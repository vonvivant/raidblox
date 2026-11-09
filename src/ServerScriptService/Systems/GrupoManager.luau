--!strict
-- GrupoManager: grupos (party) de hasta 5 jugadores dentro de un servidor.
--
--   * Cualquiera invita a otro jugador del servidor (si invita alguien sin
--     grupo, se arma uno con él como líder). Las invitaciones vencen a los 30 s.
--   * Solo el líder invita, expulsa y pasa el liderazgo. Si el líder se va, el
--     liderazgo pasa al siguiente; un grupo de 1 se disuelve.
--   * Los clientes reciben GrupoEstado (miembros y líder). La vida de los
--     compañeros la leen del Humanoid, que ya se replica.
--
-- API para otros sistemas: MiembrosDe, MismoGrupo, GrupoDe y la señal Cambio
-- (voz de grupo, mazmorras).

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Signal = require(ReplicatedStorage.Modules.Signal)

type Respuesta = Types.Respuesta
export type Grupo = { Id: string, Lider: Player, Miembros: { Player } }

local CFG = GameConfig.Grupos

local GrupoManager = {}

-- (jugador, grupo nuevo o nil): cada vez que alguien entra, sale o cambia el líder.
GrupoManager.Cambio = Signal.new() :: Signal.Signal<Player, Grupo?>

local grupoDe: { [Player]: Grupo } = {}
-- invitado -> (quién invita -> vence en)
local invitaciones: { [Player]: { [Player]: number } } = {}
local ultimaInvitacion: { [Player]: number } = {}
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function estadoPara(grupo: Grupo): { [string]: any }
	local miembros: { { [string]: any } } = {}
	for _, m in grupo.Miembros do
		table.insert(miembros, { UserId = m.UserId, Nombre = m.DisplayName })
	end
	return { Id = grupo.Id, Lider = grupo.Lider.UserId, Miembros = miembros }
end

local function difundir(grupo: Grupo)
	local estado = estadoPara(grupo)
	for _, m in grupo.Miembros do
		NetworkBridge.Server.FireClient("GrupoEstado", m, estado)
	end
end

local function quitar(player: Player, motivo: string?)
	local grupo = grupoDe[player]
	if not grupo then
		return
	end
	grupoDe[player] = nil
	player:SetAttribute("GrupoId", nil)
	local i = table.find(grupo.Miembros, player)
	if i then
		table.remove(grupo.Miembros, i)
	end
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("GrupoEstado", player, nil)
		if motivo then
			avisar(player, motivo)
		end
	end
	GrupoManager.Cambio:Fire(player, nil)
	if #grupo.Miembros <= 1 then
		-- Un grupo de uno no tiene sentido: se disuelve.
		local ultimo = grupo.Miembros[1]
		if ultimo then
			grupoDe[ultimo] = nil
			ultimo:SetAttribute("GrupoId", nil)
			table.clear(grupo.Miembros)
			NetworkBridge.Server.FireClient("GrupoEstado", ultimo, nil)
			avisar(ultimo, "El grupo se disolvió.")
			GrupoManager.Cambio:Fire(ultimo, nil)
		end
		return
	end
	if grupo.Lider == player then
		grupo.Lider = grupo.Miembros[1]
		avisar(grupo.Lider, "Ahora sos el líder del grupo.", "Oro")
	end
	difundir(grupo)
	for _, m in grupo.Miembros do
		GrupoManager.Cambio:Fire(m, grupo)
	end
end

local function agregar(grupo: Grupo, player: Player)
	table.insert(grupo.Miembros, player)
	grupoDe[player] = grupo
	player:SetAttribute("GrupoId", grupo.Id)
	difundir(grupo)
	for _, m in grupo.Miembros do
		GrupoManager.Cambio:Fire(m, grupo)
	end
end

local function invitar(lider: Player, userId: number): Respuesta
	local invitado = Players:GetPlayerByUserId(userId)
	if not invitado or invitado == lider then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local ahora = os.clock()
	if ahora - (ultimaInvitacion[lider] or -math.huge) < CFG.EsperaEntreInvitaciones then
		return NetworkBridge.Fail("RATE_LIMITED")
	end
	ultimaInvitacion[lider] = ahora
	local grupo = grupoDe[lider]
	if grupo and grupo.Lider ~= lider then
		avisar(lider, "Solo el líder puede invitar.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if grupo and #grupo.Miembros >= CFG.MaxMiembros then
		avisar(lider, `El grupo está lleno ({CFG.MaxMiembros}).`, "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if grupoDe[invitado] then
		avisar(lider, `{invitado.DisplayName} ya está en un grupo.`, "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local deInvitado = invitaciones[invitado]
	if not deInvitado then
		deInvitado = {}
		invitaciones[invitado] = deInvitado
	end
	deInvitado[lider] = ahora + CFG.ExpiraInvitacion
	NetworkBridge.Server.FireClient("GrupoInvitacion", invitado, lider.UserId, lider.DisplayName)
	avisar(lider, `Invitaste a {invitado.DisplayName}.`)
	return NetworkBridge.Ok(nil)
end

local function responder(invitado: Player, deUserId: number, acepta: boolean): Respuesta
	local lider = Players:GetPlayerByUserId(deUserId)
	local deInvitado = invitaciones[invitado]
	local vence = lider and deInvitado and deInvitado[lider]
	if not lider or not deInvitado or not vence or os.clock() > vence then
		if deInvitado and lider then
			deInvitado[lider] = nil
		end
		avisar(invitado, "La invitación ya no es válida.", "Error")
		return NetworkBridge.Fail("NOT_FOUND")
	end
	deInvitado[lider] = nil
	if not acepta then
		avisar(lider, `{invitado.DisplayName} rechazó la invitación.`)
		return NetworkBridge.Ok(nil)
	end
	if grupoDe[invitado] then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local grupo = grupoDe[lider]
	if grupo and grupo.Lider ~= lider then
		avisar(invitado, "Quien te invitó ya no es el líder del grupo.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local g: Grupo
	if grupo then
		g = grupo
	else
		g = { Id = HttpService:GenerateGUID(false), Lider = lider, Miembros = {} }
		agregar(g, lider)
	end
	if #g.Miembros >= CFG.MaxMiembros then
		avisar(invitado, "El grupo está lleno.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	agregar(g, invitado)
	for _, m in g.Miembros do
		if m ~= invitado then
			avisar(m, `{invitado.DisplayName} se unió al grupo.`)
		end
	end
	avisar(invitado, `Te uniste al grupo de {g.Lider.DisplayName}.`, "Oro")
	return NetworkBridge.Ok(nil)
end

local function accionDeLider(lider: Player, userId: number, accion: "Expulsar" | "Lider"): Respuesta
	local grupo = grupoDe[lider]
	local objetivo = Players:GetPlayerByUserId(userId)
	if not grupo or grupo.Lider ~= lider then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not objetivo or objetivo == lider or grupoDe[objetivo] ~= grupo then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if accion == "Expulsar" then
		quitar(objetivo, "Te expulsaron del grupo.")
	else
		grupo.Lider = objetivo
		difundir(grupo)
		for _, m in grupo.Miembros do
			GrupoManager.Cambio:Fire(m, grupo)
		end
		avisar(objetivo, "Ahora sos el líder del grupo.", "Oro")
	end
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- API
------------------------------------------------------------------------

function GrupoManager.GrupoDe(player: Player): Grupo?
	return grupoDe[player]
end

-- Miembros del grupo del jugador (incluido él). Sin grupo: solo él.
function GrupoManager.MiembrosDe(player: Player): { Player }
	local grupo = grupoDe[player]
	return if grupo then table.clone(grupo.Miembros) else { player }
end

function GrupoManager.MismoGrupo(a: Player, b: Player): boolean
	local g = grupoDe[a]
	return g ~= nil and g == grupoDe[b]
end

-- Arma un grupo con estos jugadores (lo usan las mazmorras al llegar a la instancia).
function GrupoManager.Formar(lider: Player, miembros: { Player })
	for _, m in miembros do
		quitar(m, nil)
	end
	quitar(lider, nil)
	local grupo: Grupo = { Id = HttpService:GenerateGUID(false), Lider = lider, Miembros = {} }
	agregar(grupo, lider)
	for _, m in miembros do
		if m ~= lider and #grupo.Miembros < CFG.MaxMiembros then
			agregar(grupo, m)
		end
	end
end

function GrupoManager.Init()
	assert(not iniciado, "GrupoManager.Init() se llamó dos veces")
	iniciado = true

	local function usuario(valor: unknown): number?
		return NetworkBridge.Guard.Integer(valor, 1, 2 ^ 53)
	end
	NetworkBridge.Server.OnInvoke("GrupoInvitar", function(player: Player, userId: unknown): Respuesta
		local u = usuario(userId)
		return if u then invitar(player, u) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	NetworkBridge.Server.OnInvoke("GrupoResponder", function(player: Player, de: unknown, acepta: unknown): Respuesta
		local u = usuario(de)
		local a = NetworkBridge.Guard.Boolean(acepta)
		if not u or a == nil then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return responder(player, u, a)
	end)
	NetworkBridge.Server.OnInvoke("GrupoSalir", function(player: Player): Respuesta
		if not grupoDe[player] then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		quitar(player, "Saliste del grupo.")
		return NetworkBridge.Ok(nil)
	end)
	NetworkBridge.Server.OnInvoke("GrupoExpulsar", function(player: Player, userId: unknown): Respuesta
		local u = usuario(userId)
		return if u then accionDeLider(player, u, "Expulsar") else NetworkBridge.Fail("INVALID_ARGS")
	end)
	NetworkBridge.Server.OnInvoke("GrupoLider", function(player: Player, userId: unknown): Respuesta
		local u = usuario(userId)
		return if u then accionDeLider(player, u, "Lider") else NetworkBridge.Fail("INVALID_ARGS")
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		quitar(player, nil)
		invitaciones[player] = nil
		ultimaInvitacion[player] = nil
		for _, deInvitado in invitaciones do
			deInvitado[player] = nil
		end
	end)
end

return GrupoManager
