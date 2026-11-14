--!strict
-- PersonalizadorManager: NPC vendedor y personalizador de armas y armaduras.
--
-- El jugador habla con el NPC, se prueba un modelo sobre su avatar (vista
-- previa local, en el cliente), le cambia material y color pieza por pieza y
-- lo compra. Este módulo es la única autoridad de la compra:
--
--   * Catálogo: los modelos de ReplicatedStorage.CustomizableItems (se leen
--     solos; los mal configurados quedan afuera con un aviso en la consola).
--   * Precio: BasePrice del modelo + un extra por pieza modificada. Lo calcula
--     el servidor; si no coincide con el que vio el jugador, no se cobra y se
--     le pide confirmar de nuevo.
--   * Entrega: un ítem real del inventario (Uid nuevo) con la personalización
--     guardada en `Meta.Pers`. Las estadísticas son las del ItemCatalog: la
--     personalización es solo estética.
--   * Una sola compra a la vez por jugador, y cada pedido lleva un id: repetir
--     el mismo pedido devuelve el mismo resultado sin cobrar ni entregar otra
--     vez (también después de reconectarse: queda guardado en el perfil).
--   * Oro e inventario están en el mismo perfil y se modifican juntos, sin
--     ceder el hilo en el medio: o pasa todo o no pasa nada.
--
-- NPCs: un Model con el tag "NpcPersonalizador" (atributo opcional `Categoria`
-- = "Armas" | "Armaduras"). En la zona de pruebas se crea uno.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AparienciaEquipoConfig = require(ReplicatedStorage.Configs.AparienciaEquipoConfig)
local Config = require(ReplicatedStorage.Configs.PersonalizadorConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Personalizador = require(ReplicatedStorage.Modules.Personalizador)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local NpcFactory = require(script.Parent.Parent.NpcFactory)

type Respuesta = Types.Respuesta
type Entrada = Personalizador.Entrada

-- Registro de una operación para diagnóstico (cobros o entregas en disputa).
export type Auditoria = {
	UserId: number,
	RequestId: string,
	Uid: string?,
	ItemId: string,
	Precio: number,
	Resultado: string, -- "OK" | "REPETIDA" | código de error
	T: number,
}

local MAX_AUDITORIA = 200
local POSICION_PRUEBA = Vector3.new(-35, 0, 62)

local PersonalizadorManager = {}

local iniciado = false
-- Sesión de tienda: con qué NPC está hablando cada jugador.
local sesiones: { [Player]: BasePart } = {}
local enCurso: { [Player]: boolean } = {}
local auditoria: { Auditoria } = {}
local avisados: { [Model]: string } = {}

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
end

------------------------------------------------------------------------
-- Catálogo
------------------------------------------------------------------------

-- Catálogo vigente. Los modelos rechazados se informan una sola vez por motivo.
local function catalogo(): { [string]: Entrada }
	return Personalizador.Catalogo(function(modelo: Model, motivo: string)
		if avisados[modelo] ~= motivo then
			avisados[modelo] = motivo
			warn(`[Personalizador] "{modelo:GetFullName()}" no se vende: {motivo}`)
		end
	end)
end

-- Nombres de las piezas de los modelos hechos por código (AparienciaEquipoConfig).
local NOMBRES_PIEZAS: { [string]: { string } } = {
	Espada = { "Mango", "Guarda", "Hoja" },
	Daga = { "Mango", "Guarda", "Hoja" },
	Baculo = { "Vara", "Orbe" },
	Casco = { "Casco", "Nasal" },
	CascoCuernos = { "Casco", "CuernoIzquierdo", "CuernoDerecho", "Cresta" },
	Corona = { "Aro", "PuntaFrente", "PuntaIzquierda", "PuntaDerecha" },
	Pechera = { "Peto", "HombreraIzquierda", "HombreraDerecha" },
	Tunica = { "Tela", "Cinturon" },
}

local function carpetaDe(nombre: string, padre: Instance): Instance
	local existente = padre:FindFirstChild(nombre)
	if existente then
		return existente
	end
	local carpeta = Instance.new("Folder")
	carpeta.Name = nombre
	carpeta.Parent = padre
	return carpeta
end

-- Mientras no haya modelos 3D propios, arma uno por cada ítem que ya se dibuja
-- con piezas simples (AparienciaEquipoConfig.Items), con el mismo aspecto. Son
-- modelos de relleno (atributo Generado = true): si en la carpeta ya hay un
-- modelo con ese ItemID, no se genera nada.
local function sembrar()
	local raiz = carpetaDe(Config.Carpeta, ReplicatedStorage)
	local armas = carpetaDe("Armas", raiz)
	local armaduras = carpetaDe("Armaduras", raiz)
	local existentes: { [string]: boolean } = {}
	for _, d in raiz:GetDescendants() do
		local id = d:GetAttribute("ItemID")
		if d:IsA("Model") and typeof(id) == "string" then
			existentes[id] = true
		end
	end
	for itemId, visual in AparienciaEquipoConfig.Items do
		local def = ItemCatalog[itemId]
		local forma = AparienciaEquipoConfig.Modelos[visual.Modelo]
		if existentes[itemId] or not def or def.Tipo ~= "Equipo" or not def.SlotEquipo or not forma then
			continue
		end
		local esArma = def.SlotEquipo == "ArmaPrincipal" or def.SlotEquipo == "ArmaSecundaria"
		local modelo = Instance.new("Model")
		modelo.Name = itemId
		modelo:SetAttribute("ItemID", itemId)
		modelo:SetAttribute("BasePrice", math.max(50, def.PrecioVenta * 4))
		modelo:SetAttribute("ItemType", if esArma then "Arma" else "Armadura")
		modelo:SetAttribute("EquipSlot", def.SlotEquipo)
		modelo:SetAttribute("Anclaje", forma.Anclaje)
		modelo:SetAttribute("Generado", true)

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.2, 0.2, 0.2)
		handle.Transparency = 1
		handle.Anchored = true
		handle.CanCollide = false
		handle.CanQuery = false
		handle.CanTouch = false
		handle.CFrame = CFrame.identity
		handle.Parent = modelo
		modelo.PrimaryPart = handle

		local origen = if forma.Empunadura then CFrame.Angles(math.rad(-90), 0, 0) else CFrame.identity
		local nombres = NOMBRES_PIEZAS[visual.Modelo] or {}
		for i, p in forma.Piezas do
			local parte = Instance.new("Part")
			parte.Name = nombres[i] or `Pieza{i}`
			parte.Size = p.Tam
			parte.Shape = p.Forma or Enum.PartType.Block
			parte.Material = if p.Tinte then visual.Material else (p.Material or Enum.Material.SmoothPlastic)
			parte.Color = if p.Tinte then visual.Color else (p.Color or visual.Color)
			parte.Anchored = true
			parte.CanCollide = false
			parte.CanQuery = false
			parte.CanTouch = false
			parte.CastShadow = false
			local rot = p.Rot or Vector3.zero
			parte.CFrame = origen * CFrame.new(p.Pos) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
			parte.Parent = modelo
		end
		modelo.Parent = if esArma then armas else armaduras
	end
end

------------------------------------------------------------------------
-- Validación de pedidos
------------------------------------------------------------------------

local function raizDe(player: Player): BasePart?
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

local function vivo(player: Player): boolean
	local personaje = player.Character
	local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")
	return humanoide ~= nil and humanoide.Health > 0
end

-- ¿El jugador sigue en una sesión de tienda válida? (habló con un NPC que
-- todavía existe y está a 15 studs o menos). No alcanza con haber tocado el
-- cartel: se revisa de nuevo en cada pedido.
local function enTienda(player: Player): boolean
	local npc = sesiones[player]
	local raiz = raizDe(player)
	if not npc or not npc:IsDescendantOf(workspace) or not raiz or not vivo(player) then
		sesiones[player] = nil
		return false
	end
	if (raiz.Position - npc.Position).Magnitude > Config.DistanciaMaxima then
		sesiones[player] = nil
		return false
	end
	return true
end

type Cotizacion = { Entrada: Entrada, Pers: Config.Personalizacion, Base: number, Extra: number, Precio: number }

-- Valida ítem y personalización y calcula el precio. Devuelve la cotización o
-- el código de error (y un texto para el jugador).
local function cotizar(player: Player, itemId: unknown, datos: unknown): (Cotizacion?, Types.CodigoError, string?)
	local id = NetworkBridge.Guard.String(itemId, 64)
	if not id then
		return nil, "INVALID_ARGS", nil
	end
	if not enTienda(player) then
		return nil, "NOT_ALLOWED", "Tenés que estar junto al vendedor."
	end
	local entrada = catalogo()[id]
	if not entrada then
		return nil, "NOT_FOUND", "Ese objeto no está a la venta."
	end
	local pers, motivo = Personalizador.Normalizar(entrada, datos)
	if not pers then
		return nil, "INVALID_ARGS", `Personalización inválida: {motivo or "?"}.`
	end
	local modificadas = Personalizador.Modificadas(pers)
	local precio = Config.Precio(entrada.Precio, modificadas)
	return { Entrada = entrada, Pers = pers, Base = entrada.Precio, Extra = precio - entrada.Precio, Precio = precio },
		"INTERNAL_ERROR",
		nil
end

local function anotar(
	player: Player,
	requestId: string,
	itemId: string,
	precio: number,
	resultado: string,
	uid: string?
)
	local registro: Auditoria = {
		UserId = player.UserId,
		RequestId = requestId,
		Uid = uid,
		ItemId = itemId,
		Precio = precio,
		Resultado = resultado,
		T = os.time(),
	}
	table.insert(auditoria, registro)
	if #auditoria > MAX_AUDITORIA then
		table.remove(auditoria, 1)
	end
	print(
		`[Personalizador] {resultado} user={player.UserId} pedido={requestId} item={itemId} precio={precio} uid={uid or "-"}`
	)
end

-- Últimas operaciones de este servidor (para diagnóstico).
function PersonalizadorManager.Auditoria(): { Auditoria }
	return table.clone(auditoria)
end

-- Guarda el pedido en el perfil y descarta los más viejos.
local function recordar(
	datos: Types.DatosJugador,
	requestId: string,
	compra: { Uid: string, ItemId: string, Precio: number, Firma: string, T: number }
)
	local mapa: { [string]: typeof(compra) } = datos.ComprasPersonalizador or {}
	mapa[requestId] = compra
	local ids: { string } = {}
	for id in mapa do
		table.insert(ids, id)
	end
	if #ids > Config.ComprasRecordadas then
		table.sort(ids, function(a: string, b: string): boolean
			return mapa[a].T < mapa[b].T
		end)
		for i = 1, #ids - Config.ComprasRecordadas do
			mapa[ids[i]] = nil
		end
	end
	datos.ComprasPersonalizador = mapa
end

local function comprar(
	player: Player,
	itemId: unknown,
	requestId: unknown,
	datosPers: unknown,
	precioVisto: unknown
): Respuesta
	if not Config.RequestIdValido(requestId) then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local pedido = requestId :: string
	local visto = NetworkBridge.Guard.Integer(precioVisto, 0, 100_000_000)
	if not visto then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local datos = DataManager.GetData(player)
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end

	local cotizacion, codigo, texto = cotizar(player, itemId, datosPers)
	if not cotizacion then
		if texto then
			avisar(player, texto)
		end
		return NetworkBridge.Fail(codigo :: any) -- siempre es un CodigoError
	end
	local entrada = cotizacion.Entrada
	local codificada = Config.Codificar(cotizacion.Pers)
	local firma = `{entrada.ItemId}|{codificada}`

	-- Reintento de un pedido ya hecho: mismo resultado, sin cobrar ni entregar.
	local previa = datos.ComprasPersonalizador and datos.ComprasPersonalizador[pedido]
	if previa then
		if previa.Firma ~= firma then
			-- Mismo id con otro contenido: no es un reintento.
			anotar(player, pedido, entrada.ItemId, cotizacion.Precio, "ID_REUSADO")
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		anotar(player, pedido, previa.ItemId, previa.Precio, "REPETIDA", previa.Uid)
		return NetworkBridge.Ok({ Estado = "Comprado", Uid = previa.Uid, Precio = previa.Precio, Repetida = true })
	end

	if datos.Nivel < entrada.Nivel then
		avisar(player, `Necesitás nivel {entrada.Nivel}.`)
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	-- El precio cambió respecto del que vio el jugador (catálogo o costos
	-- distintos): no se cobra; el cliente tiene que mostrarlo y volver a confirmar.
	if visto ~= cotizacion.Precio then
		return NetworkBridge.Ok({ Estado = "PrecioCambio", Precio = cotizacion.Precio })
	end
	if datos.Oro < cotizacion.Precio then
		avisar(player, "No te alcanza el oro.")
		anotar(player, pedido, entrada.ItemId, cotizacion.Precio, "INSUFFICIENT_FUNDS")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	if DataManager.RanurasLibres(player) < 1 then
		avisar(player, "No tenés lugar en la mochila.")
		anotar(player, pedido, entrada.ItemId, cotizacion.Precio, "INVENTORY_FULL")
		return NetworkBridge.Fail("INVENTORY_FULL")
	end

	-- A partir de acá no se cede el hilo: entrega, cobro y registro van juntos.
	local meta: Types.ItemMeta = { Origen = "NPC" }
	if codificada ~= tostring(Config.Version) then
		meta.Pers = codificada
	end
	local item: Types.ItemInstancia = {
		Uid = HttpService:GenerateGUID(false),
		ItemId = entrada.ItemId,
		Cantidad = 1,
		Rareza = "Comun",
		Meta = meta,
	}
	if not DataManager.AgregarInstancia(player, item) then
		anotar(player, pedido, entrada.ItemId, cotizacion.Precio, "INVENTORY_FULL")
		return NetworkBridge.Fail("INVENTORY_FULL")
	end
	if not DataManager.SpendGold(player, cotizacion.Precio) then
		-- No debería pasar (el saldo se verificó recién): se deshace la entrega.
		DataManager.RemoveItemByUid(player, item.Uid)
		anotar(player, pedido, entrada.ItemId, cotizacion.Precio, "INTERNAL_ERROR")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	recordar(
		datos,
		pedido,
		{ Uid = item.Uid, ItemId = entrada.ItemId, Precio = cotizacion.Precio, Firma = firma, T = os.time() }
	)
	anotar(player, pedido, entrada.ItemId, cotizacion.Precio, "OK", item.Uid)
	avisar(player, `Compraste {entrada.Nombre} por {cotizacion.Precio} de oro.`, "Oro")
	return NetworkBridge.Ok({ Estado = "Comprado", Uid = item.Uid, Precio = cotizacion.Precio })
end

------------------------------------------------------------------------
-- NPCs
------------------------------------------------------------------------

local function abrir(player: Player, raizNpc: BasePart, categoria: string?)
	local raiz = raizDe(player)
	if
		not raiz
		or not vivo(player)
		or (raiz.Position - raizNpc.Position).Magnitude > Config.DistanciaMaxima
		or not DataManager.GetData(player)
	then
		return
	end
	sesiones[player] = raizNpc
	NetworkBridge.Server.FireClient("PersonalizadorAbrir", player, raizNpc.Position, categoria)
end

local function prepararNpc(instancia: Instance)
	if not instancia:IsA("Model") then
		return
	end
	local raiz = instancia:FindFirstChild("HumanoidRootPart") or instancia.PrimaryPart
	if not raiz or not raiz:IsA("BasePart") then
		warn(`[Personalizador] El NPC {instancia:GetFullName()} necesita HumanoidRootPart o PrimaryPart`)
		return
	end
	local categoria = instancia:GetAttribute("Categoria")
	local prompt = raiz:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Probar y comprar"
	prompt.ObjectText = "Vendedor"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = raiz
	prompt.Triggered:Connect(function(player: Player)
		abrir(player, raiz, if categoria == "Armas" or categoria == "Armaduras" then categoria else nil)
	end)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function PersonalizadorManager.Init()
	assert(not iniciado, "PersonalizadorManager.Init() se llamó dos veces")
	iniciado = true

	sembrar()
	catalogo() -- valida e informa los modelos mal configurados al arrancar

	for _, npc in CollectionService:GetTagged(Config.TagNpc) do
		prepararNpc(npc)
	end
	CollectionService:GetInstanceAddedSignal(Config.TagNpc):Connect(prepararNpc)
	if Pruebas.Activas() and #CollectionService:GetTagged(Config.TagNpc) == 0 then
		local _, _, modelo = NpcFactory.Crear(
			"Maestro Personalizador",
			"Armas y armaduras a medida",
			POSICION_PRUEBA,
			Color3.fromRGB(200, 150, 60),
			"Hablar"
		)
		-- NpcFactory ya le puso un cartel; prepararNpc lo reutiliza.
		CollectionService:AddTag(modelo, Config.TagNpc)
	end

	NetworkBridge.Server.OnEvent("PersonalizadorCerrar", function(player: Player)
		sesiones[player] = nil
	end)

	NetworkBridge.Server.OnInvoke(
		"PersonalizadorPresupuesto",
		function(player: Player, itemId: unknown, datos: unknown): Respuesta
			local cotizacion, codigo = cotizar(player, itemId, datos)
			if not cotizacion then
				return NetworkBridge.Fail(codigo :: any) -- siempre es un CodigoError
			end
			return NetworkBridge.Ok({
				Base = cotizacion.Base,
				Extra = cotizacion.Extra,
				Precio = cotizacion.Precio,
				Piezas = Personalizador.Modificadas(cotizacion.Pers),
			})
		end
	)

	NetworkBridge.Server.OnInvoke(
		"PersonalizadorComprar",
		function(player: Player, itemId: unknown, requestId: unknown, datos: unknown, precioVisto: unknown): Respuesta
			-- Una compra a la vez por jugador (doble clic, pedidos simultáneos).
			if enCurso[player] then
				return NetworkBridge.Fail("RATE_LIMITED")
			end
			enCurso[player] = true
			local ok, resultado = pcall(comprar, player, itemId, requestId, datos, precioVisto)
			enCurso[player] = nil
			if not ok then
				warn(`[Personalizador] Error en la compra de {player.UserId}: {resultado}`)
				return NetworkBridge.Fail("INTERNAL_ERROR")
			end
			return resultado
		end
	)

	Players.PlayerRemoving:Connect(function(player: Player)
		sesiones[player] = nil
		enCurso[player] = nil
	end)
end

return PersonalizadorManager
