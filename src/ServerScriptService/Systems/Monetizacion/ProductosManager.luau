--!strict
-- ProductosManager: compras repetibles (Developer Products) y cajas.
--
-- ProcessReceipt atómico e idempotente:
--   1. Si el PurchaseId ya está en el perfil -> se confirma el guardado y
--      PurchaseGranted (no se entrega dos veces).
--   2. Si no: se entrega en memoria (sin pausas) y se anota el PurchaseId.
--   3. PurchaseGranted SOLO si SaveNowAsync confirma; si no, NotProcessedYet y
--      Roblox reintenta (en este servidor ya está anotado: no se duplica).
-- Lo que no entra en la mochila va por buzón con id fijo (recibo:<id>:<n>).
--
-- Productos: Booster de 2× experiencia (1 h, se encadena), Pack de Inicio
-- (una vez), fichas de Re-roll y de Cambio de Bando, y 5 cajas aleatorias. Las
-- probabilidades de las cajas se calculan de los pesos y se muestran antes de
-- comprar; donde Roblox restringe los ítems aleatorios pagos
-- (PolicyService.ArePaidRandomItemsRestricted) no se ofrecen.
-- Modo pruebas: con Id = 0, el creador y los probadores pueden simular.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ItemRarityConfig = require(ReplicatedStorage.Configs.ItemRarityConfig)
local MonetizacionConfig = require(ReplicatedStorage.Configs.MonetizacionConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local DataManager = require(script.Parent.Parent.DataManager)
local Buzon = require(script.Parent.Parent.Buzon)
local LootManager = require(script.Parent.Parent.Combate.LootManager)
local NpcsPrueba = require(script.Parent.Parent.Pruebas.NpcsPrueba)
local Bonos = require(script.Parent.Bonos)

type Respuesta = Types.Respuesta
type ItemInstancia = Types.ItemInstancia

local CFG = MonetizacionConfig
local BANDOS: { [string]: Types.Bando } = { Rojo = "Rojo", Azul = "Azul", Violeta = "Violeta" }

local ProductosManager = {}

local restringidas: { [Player]: boolean } = {}
local precios: { [number]: number? } = {}
local ultimoUso: { [Player]: number } = {}
local azar = Random.new()
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function claveDeId(id: number): string?
	for clave, p in CFG.Productos do
		if p.Id == id and id ~= 0 then
			return clave
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Cajas
------------------------------------------------------------------------

-- Probabilidad (0-1) de cada entrada y de cada rareza, para mostrar.
local function probabilidades(caja: MonetizacionConfig.Caja)
	local total = 0
	for _, e in caja.Contenido do
		total += e.Peso
	end
	local items = {}
	for _, e in caja.Contenido do
		local def = ItemCatalog[e.ItemId]
		table.insert(items, {
			Nombre = if def then def.Nombre else e.ItemId,
			Probabilidad = e.Peso / total,
			Min = e.Min,
			Max = e.Max,
		})
	end
	local rarezas = {}
	if caja.Rarezas then
		local totalR = 0
		for _, peso in caja.Rarezas do
			totalR += peso
		end
		for rareza, peso in caja.Rarezas do
			local def = ItemRarityConfig.Rarezas[rareza :: any]
			table.insert(rarezas, { Nombre = if def then def.Nombre else rareza, Probabilidad = peso / totalR })
		end
		table.sort(rarezas, function(a: any, b: any): boolean
			return a.Probabilidad > b.Probabilidad
		end)
	end
	return { Items = items, Rarezas = rarezas, Tiradas = caja.Tiradas }
end

local function sortear<T>(lista: { T }, peso: (T) -> number): T
	local total = 0
	for _, e in lista do
		total += peso(e)
	end
	local tirada = azar:NextNumber() * total
	for _, e in lista do
		tirada -= peso(e)
		if tirada <= 0 then
			return e
		end
	end
	return lista[#lista]
end

local function abrirCaja(caja: MonetizacionConfig.Caja): { ItemInstancia }
	local salida: { ItemInstancia } = {}
	for _ = 1, caja.Tiradas do
		local e = sortear(caja.Contenido, function(x: MonetizacionConfig.EntradaCaja): number
			return x.Peso
		end)
		local rareza: string? = nil
		local pesosRareza = caja.Rarezas
		if pesosRareza then
			type Peso = { Nombre: string, Peso: number }
			local lista: { Peso } = {}
			for nombre, peso in pesosRareza do
				table.insert(lista, { Nombre = nombre, Peso = peso })
			end
			table.sort(lista, function(a: Peso, b: Peso): boolean
				return a.Nombre < b.Nombre
			end)
			rareza = sortear(lista, function(x: Peso): number
				return x.Peso
			end).Nombre
		end
		local g = LootManager.GenerarItem(e.ItemId, azar:NextInteger(e.Min, e.Max), rareza)
		if g then
			table.insert(salida, {
				Uid = HttpService:GenerateGUID(false),
				ItemId = g.ItemId,
				Cantidad = g.Cantidad,
				Rareza = g.Rareza,
				Meta = g.Meta,
			})
		end
	end
	return salida
end

------------------------------------------------------------------------
-- Entrega (sin pausas: corre dentro de ProcessReceipt antes de guardar)
------------------------------------------------------------------------

local function darItem(player: Player, item: ItemInstancia, id: string)
	if not DataManager.AgregarInstancia(player, item) then
		Buzon.EnviarItem(player.UserId, item, "Compra en la tienda", id)
	end
end

local function entregar(player: Player, clave: string, compraId: string): boolean
	local p = CFG.Productos[clave]
	if not p or not DataManager.PerfilActivo(player) then
		return false
	end
	if p.Tipo == "Booster" then
		local hasta = DataManager.ExtenderBoosterXp(player, CFG.Booster.Segundos)
		if hasta then
			Bonos.SetBoosterXp(player, hasta, CFG.Booster.Multiplicador)
		end
		avisar(player, "¡Booster de experiencia activo! 2× durante 1 hora.", "Oro")
	elseif p.Tipo == "Pack" then
		DataManager.MarcarPackInicio(player)
		if not DataManager.AddGold(player, CFG.PackInicio.Oro) then
			Buzon.EnviarOro(player.UserId, CFG.PackInicio.Oro, "Pack de Inicio", `{compraId}:oro`)
		end
		for n, e in CFG.PackInicio.Items do
			local g = LootManager.GenerarItem(e.ItemId, e.Cantidad, e.Rareza)
			if g then
				darItem(player, {
					Uid = HttpService:GenerateGUID(false),
					ItemId = g.ItemId,
					Cantidad = g.Cantidad,
					Rareza = g.Rareza,
					Meta = g.Meta,
				}, `{compraId}:{n}`)
			end
		end
		avisar(player, "¡Pack de Inicio entregado!", "Oro")
	elseif p.Tipo == "Ficha" and p.Ficha then
		DataManager.AgregarFicha(player, p.Ficha, 1)
		avisar(player, `+1 {p.Nombre}. Usala desde la Tienda.`, "Oro")
	elseif p.Tipo == "Caja" and p.Caja then
		local caja = CFG.Cajas[p.Caja]
		if not caja then
			return false
		end
		local items = abrirCaja(caja)
		for n, item in items do
			darItem(player, item, `{compraId}:{n}`)
		end
		NetworkBridge.Server.FireClient("TiendaCajaAbierta", player, caja.Nombre, items)
	else
		return false
	end
	return true
end

local function procesarRecibo(recibo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(recibo.PlayerId)
	if not player or not DataManager.PerfilActivo(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = `recibo:{recibo.PurchaseId}`
	if DataManager.ReciboYaProcesado(player, id) then
		-- Ya se entregó; se asegura que esté guardado antes de confirmar.
		return if DataManager.SaveNowAsync(player, 15)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local clave = claveDeId(recibo.ProductId)
	if not clave then
		warn(`[Productos] Producto desconocido: {recibo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not entregar(player, clave, id) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataManager.MarcarRecibo(player, id)
	if DataManager.SaveNowAsync(player, 15) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

------------------------------------------------------------------------
-- Tienda (lo que ve el cliente)
------------------------------------------------------------------------

local function precio(id: number): number?
	if id == 0 then
		return nil
	end
	if precios[id] == nil then
		local ok, info = pcall(function(): any
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
		end)
		precios[id] = if ok and typeof(info) == "table" then info.PriceInRobux else nil
	end
	return precios[id]
end

local function consultarPolitica(player: Player)
	local ok, info = pcall(function(): any
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	-- Si no se puede saber, se asume restringido (lo seguro).
	restringidas[player] = not ok or typeof(info) ~= "table" or info.ArePaidRandomItemsRestricted == true
end

local function info(player: Player): Respuesta
	if restringidas[player] == nil then
		consultarPolitica(player)
	end
	local datos = DataManager.GetData(player)
	local simular = Pruebas.Activas() and NpcsPrueba.Permitido(player)
	local lista = {}
	for clave, p in CFG.Productos do
		if p.Tipo == "Caja" and restringidas[player] then
			continue
		end
		local caja = if p.Caja then CFG.Cajas[p.Caja] else nil
		table.insert(lista, {
			Clave = clave,
			Nombre = p.Nombre,
			Descripcion = p.Descripcion,
			Orden = p.Orden,
			Tipo = p.Tipo,
			ALaVenta = p.Id ~= 0,
			Precio = precio(p.Id),
			Simulable = simular and p.Id == 0,
			Agotado = p.UnaVez == true and datos ~= nil and datos.PackInicio == true,
			Probabilidades = if caja then probabilidades(caja) else nil,
		})
	end
	return NetworkBridge.Ok({
		Productos = lista,
		CajasRestringidas = restringidas[player] == true,
		BoosterHasta = if datos then datos.BoosterXpHasta else nil,
		Ahora = os.time(),
		Fichas = { Reroll = DataManager.Fichas(player, "Reroll"), Bando = DataManager.Fichas(player, "Bando") },
		Reroll = CFG.Reroll,
	})
end

local function comprar(player: Player, clave: string): Respuesta
	local p = CFG.Productos[clave]
	if not p then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if p.Tipo == "Caja" then
		if restringidas[player] == nil then
			consultarPolitica(player)
		end
		if restringidas[player] then
			avisar(player, "Las cajas no están disponibles en tu país.", "Error")
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
	end
	local datos = DataManager.GetData(player)
	if p.UnaVez and datos and datos.PackInicio then
		avisar(player, "Ya compraste este pack.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if p.Id ~= 0 then
		MarketplaceService:PromptProductPurchase(player, p.Id)
		return NetworkBridge.Ok(nil)
	end
	if Pruebas.Activas() and NpcsPrueba.Permitido(player) then
		local ok = entregar(player, clave, `prueba:{HttpService:GenerateGUID(false)}`)
		return if ok then NetworkBridge.Ok(nil) else NetworkBridge.Fail("INTERNAL_ERROR")
	end
	avisar(player, "Todavía no está a la venta.", "Error")
	return NetworkBridge.Fail("NOT_ALLOWED")
end

-- Re-roll: nueva calidad y nuevos valores de efectos, dentro de la rareza.
local function reroll(player: Player, clave: string): Respuesta
	local item = DataManager.ItemEnRanura(player, clave)
	local def = item and ItemCatalog[item.ItemId]
	if not item or not def or def.Tipo ~= "Equipo" then
		avisar(player, "Elegí un equipo de tu mochila.", "Error")
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if not DataManager.UsarFicha(player, "Reroll") then
		avisar(player, "No tenés fichas de re-roll.", "Error")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	local rareza = ItemRarityConfig.Rarezas[item.Rareza]
	local base = if rareza then rareza.Multiplicador else 1
	local meta: Types.ItemMeta = if item.Meta then table.clone(item.Meta) else {}
	if meta.Masterpiece == true then
		base *= 1.1
	end
	meta.Mult = math.round(base * azar:NextNumber(CFG.Reroll.MinFactor, CFG.Reroll.MaxFactor) * 100) / 100
	for k in meta do
		local efecto = if string.sub(k, 1, 7) == "Efecto_" then ItemRarityConfig.Efectos[string.sub(k, 8)] else nil
		if efecto then
			meta[k] = azar:NextInteger(efecto.Min, efecto.Max)
		end
	end
	DataManager.SetMetaRanura(player, clave, meta)
	avisar(player, `{def.Nombre}: nueva calidad x{meta.Mult}.`, "Oro")
	return NetworkBridge.Ok(meta)
end

local function cambiarBando(player: Player, bando: Types.Bando): Respuesta
	if player:GetAttribute("EnGuerra") == true then
		avisar(player, "No podés cambiar de bando durante la Guerra.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local datos = DataManager.GetData(player)
	if datos and datos.Faccion == bando then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not DataManager.UsarFicha(player, "Bando") then
		avisar(player, "No tenés fichas de cambio de bando.", "Error")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	DataManager.SetFaccion(player, bando)
	avisar(player, `Ahora sos del bando {bando}.`, "Oro")
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function ProductosManager.Init()
	assert(not iniciado, "ProductosManager.Init() se llamó dos veces")
	iniciado = true

	MarketplaceService.ProcessReceipt = procesarRecibo

	DataManager.PerfilCargado:Connect(function(player: Player)
		local datos = DataManager.GetData(player)
		local hasta = datos and datos.BoosterXpHasta
		if hasta and hasta > os.time() then
			Bonos.SetBoosterXp(player, hasta, CFG.Booster.Multiplicador)
		end
		task.spawn(consultarPolitica, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		restringidas[player] = nil
		ultimoUso[player] = nil
	end)

	local function conEspera(player: Player): boolean
		local ahora = os.clock()
		if ahora - (ultimoUso[player] or -math.huge) < 1 then
			return false
		end
		ultimoUso[player] = ahora
		return true
	end

	NetworkBridge.Server.OnInvoke("TiendaProductos", function(player: Player): Respuesta
		return info(player)
	end)
	NetworkBridge.Server.OnInvoke("TiendaComprarProducto", function(player: Player, clave: unknown): Respuesta
		local c = NetworkBridge.Guard.OneOf(clave, CFG.Productos)
		if not c then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not conEspera(player) then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return comprar(player, c)
	end)
	NetworkBridge.Server.OnInvoke("TiendaUsarReroll", function(player: Player, clave: unknown): Respuesta
		local c = NetworkBridge.Guard.String(clave, 6)
		if not c then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not conEspera(player) then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return reroll(player, c)
	end)
	NetworkBridge.Server.OnInvoke("TiendaUsarBando", function(player: Player, bando: unknown): Respuesta
		local b = NetworkBridge.Guard.OneOf(bando, BANDOS)
		if not b then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not conEspera(player) then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return cambiarBando(player, BANDOS[b])
	end)
end

return ProductosManager
