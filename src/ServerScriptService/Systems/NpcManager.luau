--!strict
-- NpcManager: NPCs de servicio por arquetipo (NpcArquetiposConfig).
--
-- Cada NPC tiene un arquetipo (qué ofrece) y una facción (a quién atiende).
-- Regla de interacción (PuedeInteractuar):
--   * Jugador Rojo:    NPCs Rojos y Neutrales.
--   * Jugador Azul:    NPCs Azules y Neutrales.
--   * Jugador Neutral (Violeta): todos.
-- Al bando contrario el NPC lo rechaza con un mensaje hostil.
--
-- Los servicios se acoplan según lo que declare el arquetipo:
--   Vende / Compra  -> remotes NpcComprar / NpcVender
--   Estacion        -> NpcFabricar (abre las recetas; el NPC cuenta como estación)
--   Servicios       -> NpcServicio (acciones registradas con RegistrarAccion)
--   Viajes          -> NpcViajar (Guardián de Portales)
--
-- En los mapas: un Model con el tag "NpcArquetipo" y los atributos `Arquetipo`
-- y `Faccion`. En la zona de pruebas se crean los de NpcArquetiposConfig.DePrueba.
--
-- Todo se valida en el servidor en cada pedido: que el NPC exista, que el
-- jugador esté cerca, que su bando pueda hablarle, y precios del catálogo.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NpcArquetiposConfig = require(ReplicatedStorage.Configs.NpcArquetiposConfig)
local ZoneConfig = require(ReplicatedStorage.Configs.ZoneConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local Types = require(ReplicatedStorage.Shared.Types)
local BandoManager = require(script.Parent.BandoManager)
local DataManager = require(script.Parent.DataManager)
local NpcFactory = require(script.Parent.NpcFactory)
local ZoneManager = require(script.Parent.ZoneManager)
local CombatManager = require(script.Parent.Combate.CombatManager)

type Faccion = NpcArquetiposConfig.Faccion
type Arquetipo = NpcArquetiposConfig.Arquetipo
type Servicio = NpcArquetiposConfig.Servicio

type Npc = { Id: string, ArquetipoId: string, Arquetipo: Arquetipo, Faccion: Faccion, Raiz: BasePart }

-- Una acción devuelve true si se hizo (recién ahí se cobra el servicio).
export type Accion = (player: Player, npc: Npc, servicio: Servicio) -> boolean

local TAG_NPC = "NpcArquetipo"
local TAG_ESTACION = "EstacionCrafteo"
local MAX_POR_COMPRA = 99
local MAX_NO_APILABLE = 10

local NpcManager = {}

local npcs: { [string]: Npc } = {}
local acciones: { [string]: Accion } = {}
local viajesPagados: { [Player]: number } = {} -- oro cobrado por un viaje en curso
local contador = 0
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
end

-- `codigo` siempre es un CodigoError; llega como string porque el analizador
-- ensancha los literales de los retornos múltiples.
local function fallo(codigo: string?): Types.Respuesta
	return NetworkBridge.Fail((codigo or "NOT_FOUND") :: any)
end

local function raizDe(player: Player): BasePart?
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

------------------------------------------------------------------------
-- Facciones
------------------------------------------------------------------------

function NpcManager.FaccionDe(player: Player): Faccion
	local bando = BandoManager.De(player)
	return if bando == "Rojo" then "Rojo" elseif bando == "Azul" then "Azul" else "Neutral"
end

-- ¿Un jugador de `faccionJugador` puede hablar con un NPC de `faccionNpc`?
function NpcManager.Compatibles(faccionJugador: Faccion, faccionNpc: Faccion): boolean
	return faccionJugador == "Neutral" or faccionNpc == "Neutral" or faccionJugador == faccionNpc
end

function NpcManager.PuedeInteractuar(player: Player, faccionNpc: Faccion): boolean
	return NpcManager.Compatibles(NpcManager.FaccionDe(player), faccionNpc)
end

local function rechazar(player: Player, npc: Npc)
	local frases = NpcArquetiposConfig.Rechazos
	avisar(player, `{npc.Arquetipo.Nombre}: "{frases[math.random(#frases)]}"`)
end

-- Validación común de todos los pedidos: NPC existente, cerca y del bando
-- correcto. Devuelve el NPC o el código de error.
local function validar(player: Player, npcId: unknown): (Npc?, Types.CodigoError?)
	local id = NetworkBridge.Guard.String(npcId, 16)
	local npc = if id then npcs[id] else nil
	if not npc then
		return nil, "NOT_FOUND"
	end
	local raiz = raizDe(player)
	if not raiz or (raiz.Position - npc.Raiz.Position).Magnitude > NpcArquetiposConfig.DistanciaInteraccion then
		return nil, "NOT_ALLOWED"
	end
	if not NpcManager.PuedeInteractuar(player, npc.Faccion) then
		rechazar(player, npc)
		return nil, "NOT_ALLOWED"
	end
	if not DataManager.GetData(player) then
		return nil, "DATA_NOT_LOADED"
	end
	return npc, nil
end

------------------------------------------------------------------------
-- Guardián de Portales
------------------------------------------------------------------------

local function costoViaje(zona: ZoneConfig.Zona, faccionNpc: Faccion): number
	local viajes = NpcArquetiposConfig.Viajes
	local costo = viajes.CostoBase + viajes.CostoPorNivel * zona.NivelMinimo
	if faccionNpc == "Neutral" then
		costo *= viajes.FactorNeutral
	end
	return math.floor(costo)
end

-- ¿El Guardián de `faccionNpc` lleva a esa zona? Rojo: Rojas y Neutrales.
-- Azul: Azules y Neutrales. Neutral: cualquiera.
local function llevaA(faccionNpc: Faccion, zona: ZoneConfig.Zona): boolean
	return faccionNpc == "Neutral" or zona.Territorio == "Neutral" or zona.Territorio == faccionNpc
end

type Destino = { Id: string, Nombre: string, Costo: number, NivelMinimo: number, Territorio: string }

local function destinos(faccionNpc: Faccion): { Destino }
	local actual = ZoneManager.ZonaActual()
	local lista: { Destino } = {}
	for id, zona in ZoneConfig.Zonas do
		if id ~= actual and llevaA(faccionNpc, zona) then
			table.insert(lista, {
				Id = id,
				Nombre = zona.Nombre,
				Costo = costoViaje(zona, faccionNpc),
				NivelMinimo = zona.NivelMinimo,
				Territorio = zona.Territorio :: string,
			})
		end
	end
	table.sort(lista, function(a, b)
		return if a.NivelMinimo ~= b.NivelMinimo then a.NivelMinimo < b.NivelMinimo else a.Nombre < b.Nombre
	end)
	return lista
end

local function viajar(player: Player, npc: Npc, zonaId: string): Types.Respuesta
	local zona = ZoneConfig.Zonas[zonaId]
	if not npc.Arquetipo.Viajes or zonaId == ZoneManager.ZonaActual() or not llevaA(npc.Faccion, zona) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if ZoneManager.Viajando(player) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	viajesPagados[player] = nil -- un viaje anterior que ya terminó
	local costo = costoViaje(zona, npc.Faccion)
	if not DataManager.SpendGold(player, costo) then
		avisar(player, `El viaje a {zona.Nombre} cuesta {costo} de oro.`)
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	-- Se cobra antes de viajar. Si el viaje no arranca o falla después
	-- (ZoneManager.Cancelado), el oro vuelve.
	viajesPagados[player] = costo
	if not ZoneManager.Teleportar(player, zonaId) then
		if viajesPagados[player] == costo then
			viajesPagados[player] = nil
			DataManager.AddGold(player, costo)
		end
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	return NetworkBridge.Ok({ Costo = costo })
end

------------------------------------------------------------------------
-- Vendedor
------------------------------------------------------------------------

local function comprar(player: Player, npc: Npc, indice: number, cantidad: number): Types.Respuesta
	local vende = npc.Arquetipo.Vende
	local oferta = if vende then vende[indice] else nil
	if not oferta or (oferta.Solo and oferta.Solo ~= npc.Faccion) then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local def = ItemCatalog[oferta.ItemId]
	if not def then
		warn(`[Npc] {npc.ArquetipoId} vende un ítem que no existe: {oferta.ItemId}`)
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if not def.Apilable and cantidad > MAX_NO_APILABLE then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local datos = DataManager.GetData(player)
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	local total = oferta.Precio * cantidad
	local conHonor = oferta.Moneda == "Honor"
	local saldo = if conHonor then datos.PuntosHonor else datos.Oro
	if saldo < total then
		avisar(player, if conHonor then "No te alcanzan los puntos de honor." else "No te alcanza el oro.")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	-- AddItem es todo o nada; el cobro que sigue no puede fallar (no hay
	-- yields entre la verificación del saldo y el descuento).
	local ok, codigo = DataManager.AddItem(player, oferta.ItemId, cantidad, "Comun")
	if not ok then
		if codigo == "INVENTORY_FULL" then
			avisar(player, "No tenés lugar en la mochila.")
		end
		return fallo(codigo)
	end
	local cobrado = if conHonor then DataManager.SpendHonor(player, total) else DataManager.SpendGold(player, total)
	if not cobrado then
		DataManager.RemoveItem(player, oferta.ItemId, cantidad)
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	avisar(player, `Compraste {def.Nombre} x{cantidad}.`, "Oro")
	return NetworkBridge.Ok(nil)
end

local function vender(player: Player, npc: Npc, clave: string, cantidad: number): Types.Respuesta
	local compra = npc.Arquetipo.Compra
	if not compra then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local item = DataManager.ItemEnRanura(player, clave)
	if not item or item.Cantidad < cantidad then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local def = ItemCatalog[item.ItemId]
	if not def or def.PrecioVenta <= 0 or not table.find(compra.Tipos, def.Tipo) then
		avisar(player, "Eso no me interesa.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local pago = math.floor(def.PrecioVenta * compra.Factor) * cantidad
	if pago < 1 then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local quitado = DataManager.QuitarDeRanura(player, clave, cantidad)
	if not quitado then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if not DataManager.AddGold(player, pago) then
		-- Tope de oro: el ítem vuelve a la mochila (la ranura acaba de liberarse).
		DataManager.AgregarInstancia(player, quitado)
		avisar(player, "No podés llevar más oro.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	avisar(player, `Vendiste {def.Nombre} x{cantidad} por {pago} de oro.`, "Oro")
	return NetworkBridge.Ok({ Pago = pago })
end

------------------------------------------------------------------------
-- Servicios
------------------------------------------------------------------------

-- Registra qué hace un servicio (campo `Accion` del arquetipo). Otros sistemas
-- pueden sumar las suyas (por ejemplo, el Vault para el Banquero).
function NpcManager.RegistrarAccion(nombre: string, accion: Accion)
	acciones[nombre] = accion
end

local function servicio(player: Player, npc: Npc, servicioId: string): Types.Respuesta
	local elegido: Servicio? = nil
	local servicios: { Servicio } = npc.Arquetipo.Servicios or {}
	for _, s in servicios do
		if s.Id == servicioId then
			elegido = s
			break
		end
	end
	if not elegido then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local accion = if elegido.Accion then acciones[elegido.Accion] else nil
	if not accion then
		avisar(player, `{elegido.Nombre} todavía no está disponible.`, "Info")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local datos = DataManager.GetData(player)
	if not datos or datos.Oro < elegido.Costo then
		avisar(player, `{elegido.Nombre} cuesta {elegido.Costo} de oro.`)
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	-- Las acciones no ceden el hilo: entre la verificación del oro y el cobro
	-- no puede cambiar el saldo.
	if not accion(player, npc, elegido) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if elegido.Costo > 0 then
		DataManager.SpendGold(player, elegido.Costo)
	end
	return NetworkBridge.Ok(nil)
end

local function registrarAccionesBase()
	-- Afilador de Armas: mejora temporal de ataque.
	NpcManager.RegistrarAccion("Afilar", function(player: Player, npc: Npc): boolean
		local combatiente = CombatManager.DeJugador(player)
		if not combatiente or not CombatManager.EstaVivo(combatiente) then
			return false
		end
		local buff = npc.Arquetipo.Parametros.Buff
		local porcentaje = if typeof(buff) == "table" and typeof(buff.Porcentaje) == "number"
			then buff.Porcentaje
			else 10
		local duracion = if typeof(buff) == "table" and typeof(buff.Duracion) == "number" then buff.Duracion else 600
		CombatManager.AplicarEfecto(
			combatiente,
			combatiente,
			{ Tipo = "Aura", Stat = "Ataque", Porcentaje = porcentaje, Duracion = duracion },
			"NpcAfilar"
		)
		avisar(player, `Arma afilada: +{porcentaje}% de ataque por {duracion // 60} minutos.`, "Info")
		return true
	end)

	-- Subastador: abre la Casa de Subastas.
	NpcManager.RegistrarAccion("Subasta", function(player: Player): boolean
		NetworkBridge.Server.FireClient("SubastaAbrir", player)
		return true
	end)
end

------------------------------------------------------------------------
-- Alta de NPCs
------------------------------------------------------------------------

local function abrir(player: Player, npc: Npc)
	local raiz = raizDe(player)
	if not raiz or (raiz.Position - npc.Raiz.Position).Magnitude > NpcArquetiposConfig.DistanciaInteraccion then
		return
	end
	if not NpcManager.PuedeInteractuar(player, npc.Faccion) then
		rechazar(player, npc)
		return
	end
	local datos: { [string]: any } = { Posicion = npc.Raiz.Position }
	if npc.Arquetipo.Viajes then
		datos.Destinos = destinos(npc.Faccion)
	end
	NetworkBridge.Server.FireClient("NpcAbrir", player, npc.Id, npc.ArquetipoId, npc.Faccion, datos)
end

local function registrar(modelo: Model, raiz: BasePart, prompt: ProximityPrompt, arquetipoId: string, faccion: Faccion)
	local arquetipo = NpcArquetiposConfig.Arquetipos[arquetipoId]
	contador += 1
	local npc: Npc =
		{ Id = tostring(contador), ArquetipoId = arquetipoId, Arquetipo = arquetipo, Faccion = faccion, Raiz = raiz }
	npcs[npc.Id] = npc
	modelo:SetAttribute("NpcId", npc.Id)
	modelo:SetAttribute("Arquetipo", arquetipoId)
	modelo:SetAttribute("Faccion", faccion)

	-- Los artesanos cuentan como estación de su oficio (sin cartel propio).
	if arquetipo.Estacion and arquetipo.Estado ~= "Pendiente" then
		local estacion = Instance.new("Part")
		estacion.Name = "EstacionNpc"
		estacion.Anchored = true
		estacion.CanCollide = false
		estacion.CanQuery = false
		estacion.CanTouch = false
		estacion.Transparency = 1
		estacion.Size = Vector3.one
		estacion.CFrame = raiz.CFrame
		estacion:SetAttribute("Estacion", arquetipo.Estacion)
		estacion:SetAttribute("SinPrompt", true)
		estacion.Parent = modelo
		CollectionService:AddTag(estacion, TAG_ESTACION)
	end

	prompt.Triggered:Connect(function(player: Player)
		abrir(player, npc)
	end)
	modelo.Destroying:Connect(function()
		npcs[npc.Id] = nil
	end)
end

local function titulo(arquetipo: Arquetipo, faccion: Faccion): string
	return if faccion == "Neutral" then arquetipo.Nombre else `{arquetipo.Nombre} ({faccion})`
end

-- Crea un NPC del arquetipo y la facción pedidos. Devuelve el modelo, o nil si
-- el arquetipo no existe o no tiene versión de esa facción.
function NpcManager.Crear(arquetipoId: string, faccion: Faccion, posicion: Vector3, mirarA: Vector3?): Model?
	local arquetipo = NpcArquetiposConfig.Arquetipos[arquetipoId]
	if not arquetipo or not table.find(arquetipo.Facciones, faccion) then
		warn(`[Npc] No existe {arquetipoId} en versión {faccion}`)
		return nil
	end
	local raiz, prompt, modelo =
		NpcFactory.Crear(arquetipo.Nombre, titulo(arquetipo, faccion), posicion, arquetipo.Color, "Hablar", mirarA)
	local marca = Instance.new("Highlight")
	marca.Name = "MarcaFaccion"
	marca.FillTransparency = 1
	marca.OutlineColor = NpcArquetiposConfig.ColoresFaccion[faccion]
	marca.OutlineTransparency = 0.35
	marca.DepthMode = Enum.HighlightDepthMode.Occluded
	marca.Parent = modelo
	registrar(modelo, raiz, prompt, arquetipoId, faccion)
	return modelo
end

-- NPC puesto a mano en el mapa (tag "NpcArquetipo").
local function adoptar(instancia: Instance)
	if not instancia:IsA("Model") or instancia:GetAttribute("NpcId") ~= nil then
		return
	end
	local arquetipoId = instancia:GetAttribute("Arquetipo")
	local faccion = instancia:GetAttribute("Faccion")
	local arquetipo = if typeof(arquetipoId) == "string" then NpcArquetiposConfig.Arquetipos[arquetipoId] else nil
	local raiz = instancia:FindFirstChild("HumanoidRootPart") or instancia.PrimaryPart
	if
		not arquetipo
		or typeof(arquetipoId) ~= "string"
		or (faccion ~= "Rojo" and faccion ~= "Azul" and faccion ~= "Neutral")
		or not raiz
		or not raiz:IsA("BasePart")
	then
		warn(`[Npc] {instancia:GetFullName()} necesita los atributos Arquetipo y Faccion válidos y una parte raíz`)
		return
	end
	if not table.find(arquetipo.Facciones, faccion) then
		warn(`[Npc] {instancia:GetFullName()}: {arquetipoId} no tiene versión {faccion}`)
		return
	end
	local prompt = raiz:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Hablar"
	prompt.ObjectText = titulo(arquetipo, faccion)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = raiz
	registrar(instancia, raiz, prompt, arquetipoId, faccion)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function NpcManager.Init()
	assert(not iniciado, "NpcManager.Init() se llamó dos veces")
	iniciado = true

	registrarAccionesBase()

	for _, instancia in CollectionService:GetTagged(TAG_NPC) do
		adoptar(instancia)
	end
	CollectionService:GetInstanceAddedSignal(TAG_NPC):Connect(adoptar)
	if Pruebas.Activas() and next(npcs) == nil then
		for _, puesto in NpcArquetiposConfig.DePrueba do
			NpcManager.Crear(puesto.Arquetipo, puesto.Faccion, puesto.Posicion)
		end
	end

	ZoneManager.Cancelado:Connect(function(player: Player)
		local costo = viajesPagados[player]
		if costo then
			viajesPagados[player] = nil
			if DataManager.AddGold(player, costo) then
				avisar(player, `Se te devolvieron {costo} de oro del viaje.`, "Oro")
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		viajesPagados[player] = nil
	end)

	local Guard = NetworkBridge.Guard

	NetworkBridge.Server.OnInvoke(
		"NpcComprar",
		function(player: Player, npcId: unknown, indice: unknown, cantidad: unknown): Types.Respuesta
			local i = Guard.Integer(indice, 1, 50)
			local n = Guard.Integer(cantidad, 1, MAX_POR_COMPRA)
			if not i or not n then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			local npc, codigo = validar(player, npcId)
			if not npc then
				return fallo(codigo)
			end
			return comprar(player, npc, i, n)
		end
	)

	NetworkBridge.Server.OnInvoke(
		"NpcVender",
		function(player: Player, npcId: unknown, ranura: unknown, cantidad: unknown): Types.Respuesta
			local clave = Guard.String(ranura, 4)
			local n = Guard.Integer(cantidad, 1, 9999)
			if not clave or not n then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			local npc, codigo = validar(player, npcId)
			if not npc then
				return fallo(codigo)
			end
			return vender(player, npc, clave, n)
		end
	)

	NetworkBridge.Server.OnInvoke(
		"NpcServicio",
		function(player: Player, npcId: unknown, servicioId: unknown): Types.Respuesta
			local id = Guard.String(servicioId, 32)
			if not id then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			local npc, codigo = validar(player, npcId)
			if not npc then
				return fallo(codigo)
			end
			return servicio(player, npc, id)
		end
	)

	NetworkBridge.Server.OnInvoke("NpcFabricar", function(player: Player, npcId: unknown): Types.Respuesta
		local npc, codigo = validar(player, npcId)
		if not npc then
			return fallo(codigo)
		end
		local estacion = npc.Arquetipo.Estacion
		if not estacion or npc.Arquetipo.Estado == "Pendiente" then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		NetworkBridge.Server.FireClient("CrafteoAbrir", player, estacion)
		return NetworkBridge.Ok(nil)
	end)

	NetworkBridge.Server.OnInvoke(
		"NpcViajar",
		function(player: Player, npcId: unknown, zonaId: unknown): Types.Respuesta
			local zona = Guard.OneOf(zonaId, ZoneConfig.Zonas)
			if not zona then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			local npc, codigo = validar(player, npcId)
			if not npc then
				return fallo(codigo)
			end
			return viajar(player, npc, zona)
		end
	)
end

return NpcManager
