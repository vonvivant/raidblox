--!strict
-- PergaminoManager: los pergaminos del Inscriptor (NPC-005).
--
--   * Regreso: te devuelve a la capital de tu bando (o a la ciudad si sos
--     neutral). Si ya estás en esa zona, te deja en su punto de llegada.
--   * Fortaleza: +10% de defensa a todo tu grupo que esté cerca, 10 minutos.
--   * Reunión: te lleva junto al líder de tu grupo, si está en la misma zona.
--
-- Los tres se usan desde la mochila, como cualquier consumible: se registran
-- en InventarioManager, que es quien gasta el ítem **solo si el pergamino hizo
-- algo**. Si el teletransporte falla, el pergamino sigue en la mochila.
--
-- Ninguno funciona en combate, ni en la Guerra, ni en una arena, ni en una
-- mazmorra: irse gratis o traer gente en medio de esos modos los rompe. Los
-- que mueven al jugador tienen un tiempo de rezo: hay que quedarse quieto y,
-- si te pegan o te movés, se corta y no se gasta nada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage.Configs.PergaminosConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local BandoManager = require(script.Parent.Parent.BandoManager)
local CombatManager = require(script.Parent.Parent.Combate.CombatManager)
local BuffManager = require(script.Parent.Parent.Combate.BuffManager)
local GrupoManager = require(script.Parent.Parent.GrupoManager)
local InventarioManager = require(script.Parent.InventarioManager)
local MazmorraManager = require(script.Parent.Parent.MazmorraManager)
local ZoneManager = require(script.Parent.Parent.ZoneManager)

type Pergamino = CFG.Pergamino

local PergaminoManager = {}

local iniciado = false
local ultimoUso: { [Player]: { [string]: number } } = {}
local rezando: { [Player]: boolean } = {}

local function avisar(player: Player, texto: string, tipo: string?)
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
	end
end

local function raizDe(player: Player): BasePart?
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

-- Motivo por el que no se puede usar, o nil si se puede.
local function porQueNo(player: Player, pergamino: Pergamino): string?
	local c = CombatManager.DeJugador(player)
	if not c or not CombatManager.EstaVivo(c) then
		return "No podés usarlo ahora."
	end
	if CombatManager.EnCombate(player) then
		return "En combate no se leen pergaminos."
	end
	if player:GetAttribute("EnGuerra") == true then
		return "No se puede durante la Guerra de Arquitectos."
	end
	if player:GetAttribute("EnArena") ~= nil then
		return "No se puede en una arena."
	end
	if MazmorraManager.EnMazmorra(player) then
		return "No se puede adentro de una mazmorra."
	end
	if rezando[player] then
		return "Ya estás leyendo un pergamino."
	end
	local mios = ultimoUso[player]
	local cuando = if mios then mios[pergamino.Id] else nil
	if not CFG.Listo(pergamino, cuando, os.clock()) then
		return `Ese pergamino se vuelve a usar en {math.ceil(CFG.Faltan(pergamino, cuando, os.clock()))} s.`
	end
	return nil
end

local function anotarUso(player: Player, pergamino: Pergamino)
	local mios = ultimoUso[player] or {}
	mios[pergamino.Id] = os.clock()
	ultimoUso[player] = mios
end

-- Quedarse quieto el tiempo del pergamino. Devuelve false si se movió, le
-- pegaron, murió o se fue: ahí no se gasta nada.
local function rezar(player: Player, pergamino: Pergamino): boolean
	if pergamino.Castea <= 0 then
		return true
	end
	local raiz = raizDe(player)
	if not raiz then
		return false
	end
	local desde = raiz.Position
	rezando[player] = true
	avisar(player, `Leyendo el {pergamino.Nombre}… quedate quieto {pergamino.Castea} s.`, "Info")
	local pasos = math.ceil(pergamino.Castea * 4)
	for _ = 1, pasos do
		task.wait(0.25)
		local c = CombatManager.DeJugador(player)
		local ahora = raizDe(player)
		if player.Parent ~= Players or not c or not CombatManager.EstaVivo(c) or not ahora then
			rezando[player] = nil
			return false
		end
		if CombatManager.EnCombate(player) then
			rezando[player] = nil
			avisar(player, "Te interrumpieron: el pergamino sigue en tu mochila.", "Aviso")
			return false
		end
		if (ahora.Position - desde).Magnitude > 6 then
			rezando[player] = nil
			avisar(player, "Te moviste: el pergamino sigue en tu mochila.", "Aviso")
			return false
		end
	end
	rezando[player] = nil
	return true
end

------------------------------------------------------------------------
-- Los tres efectos
------------------------------------------------------------------------

local function regreso(player: Player): (boolean, string?)
	local casa = CFG.Casa(BandoManager.De(player))
	if ZoneManager.ZonaActual() == casa then
		-- Ya está en casa: lo deja en el punto de llegada de la zona.
		if not ZoneManager.UbicarEnLlegada(player, casa) then
			local raiz = raizDe(player)
			local spawn = workspace:FindFirstChild("SpawnLocation")
			if raiz and spawn and spawn:IsA("BasePart") then
				raiz.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
			else
				return false, "No encontré a dónde llevarte."
			end
		end
		avisar(player, "Volviste al centro de la ciudad.", "Exito")
		return true
	end
	if not ZoneManager.Teleportar(player, casa) then
		return false, "No se pudo viajar ahora. El pergamino sigue en tu mochila."
	end
	return true
end

local function fortaleza(player: Player): (boolean, string?)
	local raiz = raizDe(player)
	if not raiz then
		return false, "No podés usarlo ahora."
	end
	local alcanzados = 0
	for _, miembro in GrupoManager.MiembrosDe(player) do
		local suya = raizDe(miembro)
		if miembro ~= player and (not suya or (suya.Position - raiz.Position).Magnitude > CFG.RadioGrupo) then
			continue
		end
		if BuffManager.Dar(miembro, CFG.BuffFortaleza) then
			alcanzados += 1
			if miembro ~= player then
				avisar(miembro, `{player.DisplayName} leyó un Pergamino de Fortaleza.`, "Exito")
			end
		end
	end
	if alcanzados == 0 then
		return false, "No alcanzó a nadie."
	end
	avisar(player, `Pergamino de Fortaleza: {alcanzados} del grupo reforzados.`, "Exito")
	return true
end

local function reunion(player: Player): (boolean, string?)
	local grupo = GrupoManager.GrupoDe(player)
	if not grupo then
		return false, "No estás en un grupo."
	end
	local lider = grupo.Lider
	if lider == player then
		return false, "Sos el líder: este pergamino lleva hacia el líder."
	end
	if lider.Parent ~= Players then
		return false, "Tu líder no está en este servidor."
	end
	local destino = raizDe(lider)
	local mia = raizDe(player)
	if not destino or not mia then
		return false, "Tu líder no está disponible ahora."
	end
	if lider:GetAttribute("EnGuerra") == true or lider:GetAttribute("EnArena") ~= nil then
		return false, "Tu líder está en un modo cerrado."
	end
	if MazmorraManager.EnMazmorra(lider) then
		return false, "Tu líder está en una mazmorra."
	end
	if CombatManager.EnCombate(lider) then
		return false, "Tu líder está en combate."
	end
	local personaje = player.Character
	if not personaje then
		return false, "No podés usarlo ahora."
	end
	local angulo = math.random() * math.pi * 2
	local corrimiento = Vector3.new(math.cos(angulo), 0, math.sin(angulo)) * CFG.DistanciaReunion
	personaje:PivotTo(CFrame.new(destino.Position + corrimiento + Vector3.new(0, 3, 0)))
	avisar(player, `Te reuniste con {lider.DisplayName}.`, "Exito")
	avisar(lider, `{player.DisplayName} se reunió con vos.`, "Info")
	return true
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function PergaminoManager.Init()
	if iniciado then
		return
	end
	iniciado = true

	for _, pergamino in CFG.Pergaminos do
		InventarioManager.RegistrarUso(pergamino.Id, function(player: Player): (boolean, string?)
			local motivo = porQueNo(player, pergamino)
			if motivo then
				return false, motivo
			end
			if not rezar(player, pergamino) then
				return false, nil -- ya se le avisó por qué se cortó
			end
			-- Después del rezo se vuelve a chequear: en esos segundos pudo
			-- entrar en combate o empezar la Guerra.
			motivo = porQueNo(player, pergamino)
			if motivo then
				return false, motivo
			end
			local ok: boolean, falla: string? = false, nil
			if pergamino.Efecto == "Regreso" then
				ok, falla = regreso(player)
			elseif pergamino.Efecto == "Fortaleza" then
				ok, falla = fortaleza(player)
			else
				ok, falla = reunion(player)
			end
			if ok then
				anotarUso(player, pergamino)
			end
			return ok, falla
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		ultimoUso[player] = nil
		rezando[player] = nil
	end)
end

return PergaminoManager
