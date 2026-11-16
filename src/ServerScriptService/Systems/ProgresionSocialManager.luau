--!strict
-- ProgresionSocialManager: lo que ofrecen el Tabernero (025), el Tablón de
-- Anuncios (026) y el Emisario de Facción (027). Números en
-- `Configs/ProgresionSocialConfig.luau`.
--
-- * Descanso: el Tabernero vende una habitación; mientras haya saldo, la
--   experiencia que gana el jugador rinde un 50% más (el extra sale del saldo
--   comprado, así que no es experiencia infinita).
-- * Rumores: dice si hay un jefe de mundo activo y dónde está.
-- * Reputación: se gana en la Guerra de Arquitectos y derrotando jugadores del
--   bando rival, con tope diario. El Emisario cambia honor por títulos y
--   materiales, con reputación mínima.
--
-- Las misiones diarias las maneja MisionManager; acá están sus reglas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgresionSocialConfig = require(ReplicatedStorage.Configs.ProgresionSocialConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local BandoManager = require(script.Parent.BandoManager)
local DataManager = require(script.Parent.DataManager)
local NpcManager = require(script.Parent.NpcManager)
local CombatManager = require(script.Parent.Combate.CombatManager)
local RaidBloxManager = require(script.Parent.Combate.RaidBloxManager)

type Oferta = ProgresionSocialConfig.OfertaReputacion

local CFG = ProgresionSocialConfig

local ProgresionSocialManager = {}

local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

------------------------------------------------------------------------
-- Descanso
------------------------------------------------------------------------

-- Gancho de DataManager.AddExperience: aplica y consume el descanso.
local function aplicarDescanso(player: Player, cantidad: number): number
	local datos = DataManager.GetData(player)
	local saldo = if datos then datos.Descanso or 0 else 0
	if not datos or saldo <= 0 or cantidad <= 0 then
		return cantidad
	end
	local total, usado = CFG.AplicarDescanso(cantidad, saldo)
	if usado > 0 then
		-- Mutar sincroniza la sección; no cede el hilo.
		DataManager.Mutar(player, "Social", function(d)
			d.Descanso = math.max(0, (d.Descanso or 0) - usado)
		end)
	end
	return total
end

local function descansar(player: Player): boolean
	local datos = DataManager.GetData(player)
	local d = CFG.Descanso
	if not datos then
		return false
	end
	local saldo = datos.Descanso or 0
	if saldo >= d.Maximo then
		avisar(player, "Ya estás bien descansado.")
		return false
	end
	if CombatManager.EnCombate(player) then
		avisar(player, "No podés descansar en combate.", "Error")
		return false
	end
	if not DataManager.SpendGold(player, d.Costo) then
		avisar(player, `La habitación cuesta {d.Costo} de oro.`, "Error")
		return false
	end
	local nuevo = math.min(d.Maximo, saldo + d.PorCompra)
	DataManager.Mutar(player, "Social", function(datosJugador)
		datosJugador.Descanso = nuevo
	end)
	avisar(
		player,
		`Descansaste. Tus próximos {nuevo} de experiencia rinden un {math.floor(d.Bonus * 100)}% más.`,
		"Oro"
	)
	return true
end

------------------------------------------------------------------------
-- Rumores
------------------------------------------------------------------------

local function rumores(player: Player): boolean
	local jefe, posicion = RaidBloxManager.JefeActivo()
	if jefe and posicion then
		local x, z = math.floor(posicion.X), math.floor(posicion.Z)
		avisar(player, `Dicen que {jefe} anda por la zona, cerca de ({x}, {z}).`)
	else
		avisar(player, "Por ahora no hay ningún jefe de mundo suelto. Volvé a preguntarme más tarde.")
	end
	return true
end

------------------------------------------------------------------------
-- Reputación
------------------------------------------------------------------------

function ProgresionSocialManager.Reputacion(player: Player, bando: string?): number
	local datos = DataManager.GetData(player)
	local cual = bando or BandoManager.De(player)
	local mapa = if datos then datos.Reputacion else nil
	return if mapa and typeof(mapa[cual]) == "number" then mapa[cual] else 0
end

-- Suma reputación con el bando actual del jugador, respetando el tope diario.
-- Los jugadores Violeta no tienen facción: no ganan reputación.
function ProgresionSocialManager.DarReputacion(player: Player, cantidad: number, motivo: string): number
	local datos = DataManager.GetData(player)
	local bando = BandoManager.De(player)
	if not datos or cantidad <= 0 or (bando ~= "Rojo" and bando ~= "Azul") then
		return 0
	end
	local hoy = CFG.DiaDe(os.time())
	local registro = datos.ReputacionHoy
	local usadoHoy = if registro and registro.Dia == hoy then registro.Puntos else 0
	local puede = math.min(cantidad, math.max(0, CFG.Reputacion.MaximoPorDia - usadoHoy))
	if puede <= 0 then
		return 0
	end
	local actual = ProgresionSocialManager.Reputacion(player, bando)
	local nuevo = math.min(CFG.Reputacion.Maximo, actual + puede)
	local sumado = nuevo - actual
	if sumado <= 0 then
		return 0
	end
	local antes = CFG.NivelDe(actual)
	DataManager.Mutar(player, "Social", function(d)
		local mapa: { [string]: number } = d.Reputacion or {}
		mapa[bando] = nuevo
		d.Reputacion = mapa
		d.ReputacionHoy = { Dia = hoy, Puntos = usadoHoy + sumado }
	end)
	local despues = CFG.NivelDe(nuevo)
	if despues ~= antes then
		avisar(player, `Tu bando te considera {despues}.`, "Oro")
	else
		avisar(player, `+{sumado} de reputación ({motivo}).`)
	end
	return sumado
end

local function comprarOferta(player: Player, indice: number): Types.Respuesta
	local oferta: Oferta? = CFG.Ofertas[indice]
	local datos = DataManager.GetData(player)
	if not oferta then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	local bando = BandoManager.De(player)
	if bando ~= "Rojo" and bando ~= "Azul" then
		avisar(player, "El emisario solo atiende a quienes eligieron un bando.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local reputacion = ProgresionSocialManager.Reputacion(player, bando)
	if reputacion < oferta.Reputacion then
		local nivel = CFG.NivelDe(oferta.Reputacion)
		avisar(player, `Necesitás ser {nivel} ({oferta.Reputacion} de reputación).`, "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if datos.PuntosHonor < oferta.Costo then
		avisar(player, `Cuesta {oferta.Costo} puntos de honor.`, "Error")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	-- Primero se entrega, después se cobra: entre las dos cosas no se cede el hilo.
	if oferta.Titulo then
		if not DataManager.AddTitulo(player, oferta.Titulo) then
			avisar(player, "Ya tenés ese título.")
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
	elseif oferta.ItemId then
		local ok, codigo = DataManager.AddItem(player, oferta.ItemId, oferta.Cantidad or 1, "Comun")
		if not ok then
			if codigo == "INVENTORY_FULL" then
				avisar(player, "No tenés lugar en la mochila.", "Error")
			end
			return NetworkBridge.Fail((codigo or "INTERNAL_ERROR") :: any)
		end
	else
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if not DataManager.SpendHonor(player, oferta.Costo) then
		-- No debería pasar (el honor se verificó recién).
		if oferta.ItemId then
			DataManager.RemoveItem(player, oferta.ItemId, oferta.Cantidad or 1)
		end
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	avisar(player, `{oferta.Nombre}: conseguido.`, "Oro")
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function ProgresionSocialManager.Init()
	assert(not iniciado, "ProgresionSocialManager.Init() se llamó dos veces")
	iniciado = true

	DataManager.SetBonusXp(aplicarDescanso)

	NpcManager.RegistrarAccion("Descansar", function(player: Player): boolean
		return descansar(player)
	end)
	NpcManager.RegistrarAccion("Rumores", function(player: Player): boolean
		return rumores(player)
	end)
	NpcManager.RegistrarAccion("Emisario", function(player: Player): boolean
		NetworkBridge.Server.FireClient("NpcVentana", player, "Emisario")
		return true
	end)

	-- Reputación por PvP: derrotar a un jugador del bando rival.
	CombatManager.Murio:Connect(function(c: any, asesino: any)
		local victima = c and c.Player
		local atacante = asesino and asesino.Player
		if
			victima
			and atacante
			and atacante ~= victima
			and atacante.Parent
			and BandoManager.SonRivales(atacante, victima)
		then
			ProgresionSocialManager.DarReputacion(atacante, CFG.Reputacion.PorJugadorRival, "enemigo derrotado")
		end
	end)

	NetworkBridge.Server.OnInvoke(
		"EmisarioComprar",
		function(player: Player, npcId: unknown, indice: unknown): Types.Respuesta
			local i = NetworkBridge.Guard.Integer(indice, 1, #CFG.Ofertas)
			if not i then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			-- El NPC tiene que ser un Emisario y el jugador tiene que estar al lado.
			if not NpcManager.Cerca(player, npcId, "EmisarioFaccion") then
				return NetworkBridge.Fail("NOT_ALLOWED")
			end
			return comprarOferta(player, i)
		end
	)
end

return ProgresionSocialManager
