--!strict
-- PaseBatallaManager: pase de batalla (50 niveles, vía Gratis y Premium) y
-- códigos de creador.
--
-- * XP del pase: enemigos y jefes derrotados (a todos los que participaron),
--   misiones completadas y mazmorras ganadas. Solo jugando: no se vende.
-- * Reclamar: el servidor verifica nivel, vía (Premium = pase "PaseBatalla")
--   y que no esté reclamado; marca y entrega en el mismo bloque.
-- * Códigos: uno por cuenta; se cuenta cada uso en el DataStore "CodigosUso"
--   (para saber cuánto trae cada creador).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local PaseBatallaConfig = require(ReplicatedStorage.Configs.PaseBatallaConfig)
local RaidBloxConfig = require(ReplicatedStorage.Configs.RaidBloxConfig)
local MazmorrasConfig = require(ReplicatedStorage.Configs.MazmorrasConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local EnemyManager = require(script.Parent.Parent.Combate.EnemyManager)
local PasesManager = require(script.Parent.PasesManager)
local Recompensas = require(script.Parent.Recompensas)

type Respuesta = Types.Respuesta

local CFG = PaseBatallaConfig
local TOTAL = #CFG.Niveles
local VIAS: { [string]: string } = { Gratis = "Gratis", Premium = "Premium" }

local PaseBatallaManager = {}

local ultimo: { [Player]: number } = {}
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

type EstadoPase = { Temporada: string, Xp: number, Gratis: { [string]: boolean }, Premium: { [string]: boolean } }

-- Estado del pase en el perfil (lo crea o lo reinicia si cambió la temporada).
local function estadoDe(datos: Types.DatosJugador): EstadoPase
	local e = datos.PaseBatalla
	if e and e.Temporada == CFG.Temporada then
		return e
	end
	local nuevo: EstadoPase = { Temporada = CFG.Temporada, Xp = 0, Gratis = {}, Premium = {} }
	datos.PaseBatalla = nuevo
	return nuevo
end

local function nivelDe(xp: number): number
	return math.min(TOTAL, xp // CFG.XpPorNivel)
end

-- Suma XP de pase. Avisa si sube de nivel.
function PaseBatallaManager.SumarXp(player: Player, xp: number)
	if xp <= 0 then
		return
	end
	local antes, despues = 0, 0
	DataManager.Mutar(player, "Cosmeticos", function(d)
		local e = estadoDe(d)
		antes = nivelDe(e.Xp)
		e.Xp = math.min(e.Xp + xp, TOTAL * CFG.XpPorNivel)
		despues = nivelDe(e.Xp)
	end)
	if despues > antes then
		avisar(player, `¡Pase de batalla: nivel {despues}! Reclamá tu recompensa en la Tienda.`, "Oro")
	end
end

local function info(player: Player): Respuesta
	local datos = DataManager.GetData(player)
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	local e = datos.PaseBatalla
	local actual = if e and e.Temporada == CFG.Temporada then e else nil
	local xp = if actual then actual.Xp else 0
	local niveles = {}
	for n, par in CFG.Niveles do
		local k = tostring(n)
		table.insert(niveles, {
			Nivel = n,
			Gratis = par.Gratis.Texto,
			Premium = par.Premium.Texto,
			GratisReclamado = actual ~= nil and actual.Gratis[k] == true,
			PremiumReclamado = actual ~= nil and actual.Premium[k] == true,
		})
	end
	return NetworkBridge.Ok({
		Nombre = CFG.Nombre,
		Xp = xp,
		XpPorNivel = CFG.XpPorNivel,
		Nivel = nivelDe(xp),
		Premium = PasesManager.Tiene(player, CFG.PasePremium),
		Niveles = niveles,
	})
end

local function reclamar(player: Player, nivel: number, via: string): Respuesta
	local datos = DataManager.GetData(player)
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	if via == "Premium" and not PasesManager.Tiene(player, CFG.PasePremium) then
		avisar(player, "La vía Premium se desbloquea con el Pase de Batalla (pestaña Pases).", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local par = CFG.Niveles[nivel]
	if not par then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local ok = false
	local motivo = ""
	DataManager.Mutar(player, "Cosmeticos", function(d)
		local e = estadoDe(d)
		local marcas = if via == "Premium" then e.Premium else e.Gratis
		if nivelDe(e.Xp) < nivel then
			motivo = "Todavía no llegaste a ese nivel."
		elseif marcas[tostring(nivel)] then
			motivo = "Ya la reclamaste."
		else
			marcas[tostring(nivel)] = true
			ok = true
		end
	end)
	if not ok then
		avisar(player, motivo, "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local r = if via == "Premium" then par.Premium else par.Gratis
	Recompensas.Dar(player, r, `pase:{CFG.Temporada}:{via}:{nivel}`)
	avisar(player, `Recompensa: {r.Texto}`, "Oro")
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- Códigos de creador
------------------------------------------------------------------------

local function registrarUso(codigo: string)
	task.spawn(pcall, function()
		local store = DataStoreService:GetDataStore("CodigosUso" .. (if RunService:IsStudio() then "_Studio" else ""))
		store:UpdateAsync(codigo, function(actual: any): any
			return (if typeof(actual) == "number" then actual else 0) + 1
		end)
	end)
end

local function canjear(player: Player, texto: string): Respuesta
	local codigo = string.upper((string.gsub(texto, "%s", "")))
	local def = CFG.Codigos[codigo]
	if not def or not def.Activo then
		avisar(player, "Ese código no existe o ya venció.", "Error")
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local ok = false
	DataManager.Mutar(player, "Cosmeticos", function(d)
		local usados = d.CodigosCanjeados or {}
		d.CodigosCanjeados = usados
		if not usados[codigo] then
			usados[codigo] = os.time()
			ok = true
		end
	end)
	if not ok then
		avisar(player, "Ya canjeaste ese código.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local textos: { string } = {}
	for i, r in def.Recompensas do
		Recompensas.Dar(player, r, `codigo:{codigo}:{i}`)
		table.insert(textos, r.Texto)
	end
	registrarUso(codigo)
	avisar(player, `Código de {def.Creador}: {table.concat(textos, ", ")}`, "Oro")
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function PaseBatallaManager.Init()
	assert(not iniciado, "PaseBatallaManager.Init() se llamó dos veces")
	iniciado = true

	-- Jefes: los RaidBlox (tipo = su clave) y los de mazmorra (tipo = clave de la mazmorra).
	local jefes: { [string]: boolean } = {}
	for clave in RaidBloxConfig.Jefes do
		jefes[clave] = true
	end
	for clave in MazmorrasConfig.Mazmorras do
		jefes[clave] = true
	end
	EnemyManager.Derrotado:Connect(function(tipo: string, participantes: { Player })
		local esJefe = jefes[tipo] == true
		for _, player in participantes do
			PaseBatallaManager.SumarXp(player, if esJefe then CFG.Xp.Jefe else CFG.Xp.Enemigo)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		ultimo[player] = nil
	end)

	local function conEspera(player: Player): boolean
		local ahora = os.clock()
		if ahora - (ultimo[player] or -math.huge) < 0.5 then
			return false
		end
		ultimo[player] = ahora
		return true
	end

	NetworkBridge.Server.OnInvoke("PaseInfo", function(player: Player): Respuesta
		return info(player)
	end)
	NetworkBridge.Server.OnInvoke("PaseReclamar", function(player: Player, nivel: unknown, via: unknown): Respuesta
		local n = NetworkBridge.Guard.Integer(nivel, 1, TOTAL)
		local v = NetworkBridge.Guard.OneOf(via, VIAS)
		if not n or not v then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not conEspera(player) then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return reclamar(player, n, v)
	end)
	NetworkBridge.Server.OnInvoke("CanjearCodigo", function(player: Player, texto: unknown): Respuesta
		local t = NetworkBridge.Guard.String(texto, 30)
		if not t then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not conEspera(player) then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return canjear(player, t)
	end)
	NetworkBridge.Server.OnInvoke("EquiparSkinCastillo", function(player: Player, skin: unknown): Respuesta
		local s = NetworkBridge.Guard.String(skin, 20)
		if not s or not DataManager.SetSkinEstructura(player, s) then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		avisar(player, `Skin del castillo: {s}. La usan las etapas en las que seas quien más aportó.`, "Oro")
		return NetworkBridge.Ok(nil)
	end)
end

return PaseBatallaManager
