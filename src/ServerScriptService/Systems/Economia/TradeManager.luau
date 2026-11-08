--!strict
-- TradeManager: comercio directo 1v1 entre jugadores cercanos.
--
-- Flujo:
--   1. A solicita comerciar con B (a 15 studs o menos). B acepta o rechaza.
--   2. Cada uno arma su oferta (hasta 8 ítems del inventario y oro).
--      Cualquier cambio en una oferta quita los bloqueos de ambos.
--   3. "Bloquear oferta": cuando AMBOS bloquearon, empieza una espera de 3 s.
--   4. "Confirmar comercio": recién después de la espera. Cuando ambos
--      confirman, el intercambio se ejecuta.
--   5. Si se alejan a más de 15 studs, uno cancela o se desconecta, el comercio
--      se cancela y cada uno conserva lo suyo.
--
-- Los ítems nunca salen del inventario hasta el final: al confirmar se vuelve a
-- validar todo (que los ítems y el oro sigan ahí y que haya espacio) y el
-- intercambio completo se ejecuta de forma síncrona, sin pausas: o se hace todo
-- o no se hace nada. No hay ítems "en el aire" que se puedan perder o duplicar.
--
-- Cada ítem ofrecido se guarda como "foto" (ItemId, cantidad, rareza, meta). Si
-- el inventario cambia y un ítem ofrecido ya no coincide con su foto (por
-- ejemplo, se usó parte de la pila), se quitan los bloqueos de ambos: nadie
-- puede confirmar viendo una oferta distinta de la que se va a entregar.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local Buzon = require(script.Parent.Parent.Buzon)

type ItemInstancia = Types.ItemInstancia

type Oferta = { Uids: { string }, Oro: number, Fotos: { [string]: string } }
type Sesion = {
	A: Player,
	B: Player,
	Ofertas: { [Player]: Oferta },
	Bloqueado: { [Player]: boolean },
	Confirmado: { [Player]: boolean },
	ConfirmarDesde: number?, -- hora de servidor desde la que se puede confirmar
	Terminada: boolean,
	Ejecutando: boolean,
}

local CFG = GameConfig.Comercio

local TradeManager = {}

local sesiones: { [Player]: Sesion } = {}
local invitaciones: { [Player]: { De: Player, Expira: number } } = {} -- clave: invitado
local iniciado = false

local function ahora(): number
	return Workspace:GetServerTimeNow()
end

local function avisar(player: Player, texto: string, tipo: string?)
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
	end
end

local function distancia(a: Player, b: Player): number
	local ca, cb = a.Character, b.Character
	local ra = ca and ca:FindFirstChild("HumanoidRootPart")
	local rb = cb and cb:FindFirstChild("HumanoidRootPart")
	if not ra or not rb or not ra:IsA("BasePart") or not rb:IsA("BasePart") then
		return math.huge
	end
	return (ra.Position - rb.Position).Magnitude
end

local function otro(sesion: Sesion, player: Player): Player
	return if sesion.A == player then sesion.B else sesion.A
end

-- Ítems de una oferta tal como están ahora en el inventario (para mostrar).
local function itemsDeOferta(player: Player, oferta: Oferta): { ItemInstancia }
	local lista: { ItemInstancia } = {}
	for _, uid in oferta.Uids do
		local _, item = DataManager.BuscarPorUid(player, uid)
		if item then
			table.insert(lista, item)
		end
	end
	return lista
end

-- Serialización canónica (claves ordenadas): dos tablas con el mismo contenido
-- dan siempre el mismo texto, aunque se hayan copiado.
local function canonico(valor: any): string
	if typeof(valor) ~= "table" then
		return HttpService:JSONEncode(valor)
	end
	local claves: { string } = {}
	for k in valor do
		table.insert(claves, tostring(k))
	end
	table.sort(claves)
	local partes: { string } = {}
	for _, k in claves do
		local v = valor[k]
		if v == nil then
			v = valor[tonumber(k)]
		end
		table.insert(partes, `{k}={canonico(v)}`)
	end
	return "{" .. table.concat(partes, ",") .. "}"
end

-- "Foto" de un ítem: todo lo que define qué se entrega.
local function foto(item: ItemInstancia): string
	return `{item.ItemId}|{item.Cantidad}|{item.Rareza}|{canonico(item.Meta)}`
end

local function enviarEstado(sesion: Sesion)
	for _, yo in { sesion.A, sesion.B } do
		local el = otro(sesion, yo)
		NetworkBridge.Server.FireClient("ComercioEstado", yo, {
			Otro = el.DisplayName,
			Mia = { Items = itemsDeOferta(yo, sesion.Ofertas[yo]), Oro = sesion.Ofertas[yo].Oro },
			Suya = { Items = itemsDeOferta(el, sesion.Ofertas[el]), Oro = sesion.Ofertas[el].Oro },
			BloqueadoYo = sesion.Bloqueado[yo] == true,
			BloqueadoOtro = sesion.Bloqueado[el] == true,
			ConfirmadoYo = sesion.Confirmado[yo] == true,
			ConfirmadoOtro = sesion.Confirmado[el] == true,
			ConfirmarDesde = sesion.ConfirmarDesde,
		})
	end
end

local function terminar(sesion: Sesion, exito: boolean, motivo: string)
	if sesion.Terminada then
		return
	end
	sesion.Terminada = true
	for _, p in { sesion.A, sesion.B } do
		if sesiones[p] == sesion then
			sesiones[p] = nil
		end
		if p.Parent == Players then
			NetworkBridge.Server.FireClient("ComercioEstado", p, { Terminado = true, Exito = exito, Motivo = motivo })
		end
	end
end

local function quitarBloqueos(sesion: Sesion)
	table.clear(sesion.Bloqueado)
	table.clear(sesion.Confirmado)
	sesion.ConfirmarDesde = nil
end

------------------------------------------------------------------------
-- Ejecución atómica del intercambio
------------------------------------------------------------------------

local function validarOferta(player: Player, oferta: Oferta): boolean
	local datos = DataManager.GetData(player)
	if not datos or datos.Oro < oferta.Oro then
		return false
	end
	for _, uid in oferta.Uids do
		local clave, item = DataManager.BuscarPorUid(player, uid)
		if not clave or not item or foto(item) ~= oferta.Fotos[uid] then
			return false
		end
	end
	return true
end

local function ejecutar(sesion: Sesion)
	local a, b = sesion.A, sesion.B
	local oa, ob = sesion.Ofertas[a], sesion.Ofertas[b]

	if distancia(a, b) > CFG.DistanciaMaxima then
		terminar(sesion, false, "Están demasiado lejos.")
		return
	end
	if not validarOferta(a, oa) or not validarOferta(b, ob) then
		terminar(sesion, false, "Una de las ofertas cambió o ya no es válida.")
		return
	end
	local itemsA, itemsB = itemsDeOferta(a, oa), itemsDeOferta(b, ob)
	-- Espacio: lo libre más lo que libera su propia oferta.
	if DataManager.RanurasLibres(a) + #itemsA < DataManager.RanurasNecesarias(itemsB) then
		terminar(sesion, false, `{a.DisplayName} no tiene espacio en el inventario.`)
		return
	end
	if DataManager.RanurasLibres(b) + #itemsB < DataManager.RanurasNecesarias(itemsA) then
		terminar(sesion, false, `{b.DisplayName} no tiene espacio en el inventario.`)
		return
	end

	-- A partir de acá todo es síncrono: no hay yields entre quitar y entregar.
	sesion.Ejecutando = true
	local quitadosA: { ItemInstancia } = {}
	local quitadosB: { ItemInstancia } = {}
	for _, uid in oa.Uids do
		local clave, item = DataManager.BuscarPorUid(a, uid)
		local q = clave and item and DataManager.QuitarDeRanura(a, clave, item.Cantidad)
		if q then
			table.insert(quitadosA, q)
		end
	end
	for _, uid in ob.Uids do
		local clave, item = DataManager.BuscarPorUid(b, uid)
		local q = clave and item and DataManager.QuitarDeRanura(b, clave, item.Cantidad)
		if q then
			table.insert(quitadosB, q)
		end
	end
	if oa.Oro > 0 then
		DataManager.SpendGold(a, oa.Oro)
	end
	if ob.Oro > 0 then
		DataManager.SpendGold(b, ob.Oro)
	end

	local function entregar(destino: Player, items: { ItemInstancia }, oro: number)
		for _, item in items do
			if not DataManager.AgregarInstancia(destino, item) then
				-- No debería pasar (se verificó el espacio); por las dudas, al buzón
				-- (con reintentos e id fijo).
				Buzon.EnviarItem(destino.UserId, item, "Comercio")
			end
		end
		if oro > 0 then
			Buzon.DarOro(destino, oro, "Comercio")
		end
	end
	entregar(b, quitadosA, oa.Oro)
	entregar(a, quitadosB, ob.Oro)

	print(
		`[Comercio] {a.UserId} -> {b.UserId}: {#quitadosA} ítems + {oa.Oro} oro | {b.UserId} -> {a.UserId}: {#quitadosB} ítems + {ob.Oro} oro`
	)
	terminar(sesion, true, "¡Comercio completado!")
end

------------------------------------------------------------------------
-- Acciones de los jugadores
------------------------------------------------------------------------

local function solicitar(de: Player, para: Player)
	if de == para or sesiones[de] or sesiones[para] then
		avisar(de, "No se puede comerciar ahora.", "Error")
		return
	end
	if distancia(de, para) > CFG.DistanciaMaxima then
		avisar(de, "Acercate más para comerciar.", "Error")
		return
	end
	invitaciones[para] = { De = de, Expira = ahora() + CFG.ExpiraInvitacion }
	NetworkBridge.Server.FireClient("ComercioInvitacion", para, de)
	avisar(de, `Solicitud de comercio enviada a {para.DisplayName}.`)
end

local function responder(invitado: Player, de: Player, acepta: boolean)
	local invitacion = invitaciones[invitado]
	if not invitacion or invitacion.De ~= de or invitacion.Expira < ahora() then
		return
	end
	invitaciones[invitado] = nil
	if not acepta then
		avisar(de, `{invitado.DisplayName} rechazó el comercio.`)
		return
	end
	if sesiones[de] or sesiones[invitado] or de.Parent ~= Players then
		avisar(invitado, "Ese comercio ya no está disponible.", "Error")
		return
	end
	if distancia(de, invitado) > CFG.DistanciaMaxima then
		avisar(invitado, "Están demasiado lejos para comerciar.", "Error")
		return
	end
	local sesion: Sesion = {
		A = de,
		B = invitado,
		Ofertas = { [de] = { Uids = {}, Oro = 0, Fotos = {} }, [invitado] = { Uids = {}, Oro = 0, Fotos = {} } },
		Bloqueado = {},
		Confirmado = {},
		ConfirmarDesde = nil,
		Terminada = false,
		Ejecutando = false,
	}
	sesiones[de] = sesion
	sesiones[invitado] = sesion
	enviarEstado(sesion)
end

local function ofertar(player: Player, uids: unknown, oro: unknown)
	local sesion = sesiones[player]
	if not sesion then
		return
	end
	local datos = DataManager.GetData(player)
	local cantidadOro = NetworkBridge.Guard.Integer(oro, 0, if datos then datos.Oro else 0)
	if not cantidadOro or typeof(uids) ~= "table" then
		return
	end
	local lista: { string } = {}
	local fotos: { [string]: string } = {}
	for _, valor in uids :: { [any]: any } do
		local uid = NetworkBridge.Guard.String(valor, 64)
		if not uid or fotos[uid] or #lista >= CFG.MaxItemsPorLado then
			return -- oferta inválida: se ignora entera
		end
		local _, item = DataManager.BuscarPorUid(player, uid)
		if not item then
			return
		end
		fotos[uid] = foto(item)
		table.insert(lista, uid)
	end
	sesion.Ofertas[player] = { Uids = lista, Oro = cantidadOro, Fotos = fotos }
	quitarBloqueos(sesion) -- cualquier cambio obliga a volver a revisar
	enviarEstado(sesion)
end

local function bloquear(player: Player)
	local sesion = sesiones[player]
	if not sesion then
		return
	end
	sesion.Bloqueado[player] = true
	if sesion.Bloqueado[sesion.A] and sesion.Bloqueado[sesion.B] and not sesion.ConfirmarDesde then
		sesion.ConfirmarDesde = ahora() + CFG.EsperaConfirmacion
	end
	enviarEstado(sesion)
end

local function confirmar(player: Player)
	local sesion = sesiones[player]
	local desde = sesion and sesion.ConfirmarDesde
	if not sesion or not desde or ahora() < desde then
		return -- todavía no se puede confirmar
	end
	sesion.Confirmado[player] = true
	if sesion.Confirmado[sesion.A] and sesion.Confirmado[sesion.B] then
		ejecutar(sesion)
	else
		enviarEstado(sesion)
	end
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function TradeManager.Init()
	assert(not iniciado, "TradeManager.Init() se llamó dos veces")
	iniciado = true

	NetworkBridge.Server.OnEvent("ComercioSolicitar", function(player: Player, objetivo: unknown)
		local otroJugador = NetworkBridge.Guard.InstanceOf(objetivo, "Player")
		if otroJugador then
			solicitar(player, otroJugador :: Player)
		end
	end)
	NetworkBridge.Server.OnEvent("ComercioResponder", function(player: Player, de: unknown, acepta: unknown)
		local quien = NetworkBridge.Guard.InstanceOf(de, "Player")
		local si = NetworkBridge.Guard.Boolean(acepta)
		if quien and si ~= nil then
			responder(player, quien :: Player, si)
		end
	end)
	NetworkBridge.Server.OnEvent("ComercioOfertar", ofertar)
	NetworkBridge.Server.OnEvent("ComercioBloquear", bloquear)
	NetworkBridge.Server.OnEvent("ComercioConfirmar", confirmar)
	NetworkBridge.Server.OnEvent("ComercioCancelar", function(player: Player)
		local sesion = sesiones[player]
		if sesion then
			terminar(sesion, false, `{player.DisplayName} canceló el comercio.`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		invitaciones[player] = nil
		local sesion = sesiones[player]
		if sesion then
			terminar(sesion, false, `{player.DisplayName} se desconectó.`)
		end
	end)

	-- Si el inventario o el oro de alguien cambia durante el comercio y su oferta
	-- ya no coincide con lo que el otro vio, se quitan los bloqueos.
	DataManager.DatosCambiados:Connect(function(player: Player, seccion: Types.SeccionDatos)
		local sesion = sesiones[player]
		if not sesion or sesion.Terminada or sesion.Ejecutando then
			return
		end
		if seccion ~= "Inventario" and seccion ~= "Oro" then
			return
		end
		if validarOferta(player, sesion.Ofertas[player]) then
			return -- solo se movió algo de lugar: la oferta sigue igual
		end
		-- Se sacan de la oferta los ítems que cambiaron y se ajusta el oro.
		local oferta = sesion.Ofertas[player]
		local uids: { string } = {}
		for _, uid in oferta.Uids do
			local _, item = DataManager.BuscarPorUid(player, uid)
			if item and foto(item) == oferta.Fotos[uid] then
				table.insert(uids, uid)
			else
				oferta.Fotos[uid] = nil
			end
		end
		oferta.Uids = uids
		local datos = DataManager.GetData(player)
		oferta.Oro = math.min(oferta.Oro, if datos then datos.Oro else 0)
		local hayBloqueo = next(sesion.Bloqueado) ~= nil
		quitarBloqueos(sesion)
		enviarEstado(sesion)
		if hayBloqueo then
			avisar(sesion.A, "Una oferta cambió: revisen y vuelvan a bloquear.")
			avisar(sesion.B, "Una oferta cambió: revisen y vuelvan a bloquear.")
		end
	end)

	-- Vigilancia de distancia: si se alejan, se cancela.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local revisadas: { [Sesion]: boolean } = {}
			for _, sesion in sesiones do
				if not revisadas[sesion] then
					revisadas[sesion] = true
					if distancia(sesion.A, sesion.B) > CFG.DistanciaMaxima then
						terminar(sesion, false, "Se alejaron demasiado: comercio cancelado.")
					end
				end
			end
		end
	end)
end

return TradeManager
