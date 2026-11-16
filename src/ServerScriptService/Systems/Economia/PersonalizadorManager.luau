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
-- Retoque: el Tintorero y el propio Maestro Personalizador también dejan
-- cambiar un ítem que ya es tuyo, cobrando por pieza que cambia. El Tintorero
-- solo permite colores (el material queda como está).
--
-- NPCs: un Model con el tag "NpcPersonalizador" (atributo opcional `Categoria`
-- = "Armas" | "Armaduras", y `Solo` = "Color" para el Tintorero). En la zona de
-- pruebas se crea uno.

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
local StencilsConfig = require(ReplicatedStorage.Configs.StencilsConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local NpcFactory = require(script.Parent.Parent.NpcFactory)
local NpcManager = require(script.Parent.Parent.NpcManager)

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
local TAG_RADAR = "NpcServicio" -- lo dibuja el minimapa y el mapa del mundo
local POSICION_PRUEBA = Vector3.new(-35, 0, 62)

local PersonalizadorManager = {}

local iniciado = false
-- Sesión de tienda: con qué NPC está hablando cada jugador.
local sesiones: { [Player]: BasePart } = {}
local enCurso: { [Player]: boolean } = {}
-- Qué permite el NPC con el que está hablando (el Tintorero, solo color).
-- Qué permite el NPC con el que está hablando: "Color" (Tintorero),
-- "Stencil" (Grabador) o nil (todo, el Maestro Personalizador).
local restriccion: { [Player]: string? } = {}
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
-- Libros de stencils que el jugador tiene desbloqueados.
local function librosDe(player: Player): { string }
	local datos = DataManager.GetData(player)
	if not datos then
		return {}
	end
	local lista: { string } = (datos :: any).Stencils or {}
	return lista
end

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
	local pers, motivo = Personalizador.Normalizar(entrada, datos, librosDe(player))
	if not pers then
		return nil, "INVALID_ARGS", `Personalización inválida: {motivo or "?"}.`
	end
	local modificadas = Personalizador.Modificadas(pers)
	local precio = Config.Precio(entrada.Precio, modificadas)
		+ StencilsConfig.Costo(Config.CuantosStencils(pers))
		+ StencilsConfig.CostoRelieves(Config.CuantosRelieves(pers))
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
-- Retoque de un ítem que ya es del jugador
------------------------------------------------------------------------

type Retoque = {
	Clave: string, -- ranura del inventario
	Item: Types.ItemInstancia,
	Entrada: Entrada,
	Antes: Config.Personalizacion,
	Pers: Config.Personalizacion,
	Cambiadas: number,
	Precio: number,
}

-- Valida el ítem y la personalización nueva, y calcula qué cambia y cuánto sale.
local function cotizarRetoque(player: Player, uid: unknown, datosPers: unknown): (Retoque?, Types.CodigoError, string?)
	local id = NetworkBridge.Guard.String(uid, 64)
	if not id then
		return nil, "INVALID_ARGS", nil
	end
	if not enTienda(player) then
		return nil, "NOT_ALLOWED", "Tenés que estar junto al vendedor."
	end
	local clave, item = DataManager.BuscarPorUid(player, id)
	if not clave or not item then
		return nil, "NOT_FOUND", "Ese objeto ya no está en tu mochila."
	end
	local entrada = catalogo()[item.ItemId]
	if not entrada then
		return nil, "NOT_FOUND", "Ese objeto no se puede personalizar."
	end
	local antes: Config.Personalizacion = Config.Decodificar(if item.Meta then item.Meta.Pers else nil) or {}
	local pers, motivo = Personalizador.Normalizar(entrada, datosPers, librosDe(player))
	if not pers then
		return nil, "INVALID_ARGS", `Personalización inválida: {motivo or "?"}.`
	end
	-- El Tintorero solo cambia colores: cada pieza tiene que conservar el
	-- material que tiene hoy.
	if restriccion[player] == "Color" then
		for piezaId, pieza in pers do
			local original = entrada.PorId[piezaId]
			local actual = antes[piezaId]
			local material = if actual then actual.Material else (if original then original.Material else nil)
			if material and pieza.Material ~= material then
				return nil, "NOT_ALLOWED", "El tintorero solo cambia colores, no materiales."
			end
		end
		local nueva: Config.Personalizacion = pers
		for piezaId, pieza in antes do
			local original = entrada.PorId[piezaId]
			-- Quitar una pieza que tenía otro material también es cambiarlo.
			if nueva[piezaId] == nil and original and pieza.Material ~= original.Material then
				return nil, "NOT_ALLOWED", "El tintorero solo cambia colores, no materiales."
			end
		end
	end
	-- El Grabador solo pone y saca calcomanías: material y color quedan como
	-- están. Así no hace falta explicarle al jugador por qué le cambió el
	-- color de una pieza que solo quería grabar.
	if restriccion[player] == "Stencil" then
		local function comoEsta(piezaId: string): (string?, string?)
			local actual = antes[piezaId]
			if actual then
				return actual.Material, actual.Color
			end
			local original = entrada.PorId[piezaId]
			return if original then original.Material else nil, if original then original.Color else nil
		end
		for piezaId, pieza in pers do
			local material, color = comoEsta(piezaId)
			if (material and pieza.Material ~= material) or (color and pieza.Color ~= color) then
				return nil, "NOT_ALLOWED", "El grabador solo pone calcomanías, no cambia material ni color."
			end
		end
		for piezaId, pieza in antes do
			if pers[piezaId] ~= nil then
				continue
			end
			local original = entrada.PorId[piezaId]
			-- Sacar una pieza retocada volvería material y color al original.
			if original and (pieza.Material ~= original.Material or pieza.Color ~= original.Color) then
				return nil, "NOT_ALLOWED", "El grabador solo pone calcomanías, no cambia material ni color."
			end
		end
	end

	local cambiadas = Config.Diferencias(antes, pers)
	return {
		Clave = clave,
		Item = item,
		Entrada = entrada,
		Antes = antes,
		Pers = pers,
		Cambiadas = cambiadas,
		-- Los stencils nuevos se pagan aparte de las piezas retocadas.
		Precio = Config.PrecioRetoque(cambiadas) + StencilsConfig.Costo(
			math.max(0, Config.CuantosStencils(pers) - Config.CuantosStencils(antes))
		) + StencilsConfig.CostoRelieves(math.max(0, Config.CuantosRelieves(pers) - Config.CuantosRelieves(antes))),
	},
		"INTERNAL_ERROR",
		nil
end

local function retocar(
	player: Player,
	uid: unknown,
	requestId: unknown,
	datosPers: unknown,
	precioVisto: unknown
): Respuesta
	if not Config.RequestIdValido(requestId) then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local pedido = requestId :: string
	local visto = NetworkBridge.Guard.Integer(precioVisto, 0, 100_000_000)
	local datos = DataManager.GetData(player)
	if not visto then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	local cotizacion, codigo, texto = cotizarRetoque(player, uid, datosPers)
	if not cotizacion then
		if texto then
			avisar(player, texto)
		end
		return NetworkBridge.Fail(codigo :: any)
	end
	local codificada = Config.Codificar(cotizacion.Pers)
	local firma = `retoque|{cotizacion.Item.Uid}|{codificada}`

	-- Reintento del mismo pedido: no se cobra ni se aplica otra vez.
	local previa = datos.ComprasPersonalizador and datos.ComprasPersonalizador[pedido]
	if previa then
		if previa.Firma ~= firma then
			anotar(player, pedido, cotizacion.Item.ItemId, cotizacion.Precio, "ID_REUSADO")
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		anotar(player, pedido, previa.ItemId, previa.Precio, "REPETIDA", previa.Uid)
		return NetworkBridge.Ok({ Estado = "Retocado", Uid = previa.Uid, Precio = previa.Precio, Repetida = true })
	end

	if cotizacion.Cambiadas == 0 then
		avisar(player, "No cambiaste nada.", "Info")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if visto ~= cotizacion.Precio then
		return NetworkBridge.Ok({ Estado = "PrecioCambio", Precio = cotizacion.Precio })
	end
	if datos.Oro < cotizacion.Precio then
		avisar(player, "No te alcanza el oro.")
		anotar(player, pedido, cotizacion.Item.ItemId, cotizacion.Precio, "INSUFFICIENT_FUNDS")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end

	-- Desde acá no se cede el hilo: cobro, cambio del ítem y registro juntos.
	if not DataManager.SpendGold(player, cotizacion.Precio) then
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	local meta: Types.ItemMeta = if cotizacion.Item.Meta then table.clone(cotizacion.Item.Meta) else {}
	if codificada == tostring(Config.Version) then
		(meta :: any).Pers = nil -- volvió a ser igual al modelo original
	else
		meta.Pers = codificada
	end
	if not DataManager.SetMetaRanura(player, cotizacion.Clave, if next(meta) == nil then nil else meta) then
		DataManager.AddGold(player, cotizacion.Precio)
		anotar(player, pedido, cotizacion.Item.ItemId, cotizacion.Precio, "INTERNAL_ERROR")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	recordar(datos, pedido, {
		Uid = cotizacion.Item.Uid,
		ItemId = cotizacion.Item.ItemId,
		Precio = cotizacion.Precio,
		Firma = firma,
		T = os.time(),
	})
	anotar(player, pedido, cotizacion.Item.ItemId, cotizacion.Precio, "RETOQUE", cotizacion.Item.Uid)
	avisar(player, `{cotizacion.Entrada.Nombre}: {cotizacion.Cambiadas} pieza(s) cambiada(s).`, "Oro")
	return NetworkBridge.Ok({ Estado = "Retocado", Uid = cotizacion.Item.Uid, Precio = cotizacion.Precio })
end

------------------------------------------------------------------------
-- NPCs
------------------------------------------------------------------------

local function abrir(player: Player, raizNpc: BasePart, categoria: string?, solo: string?)
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
	restriccion[player] = solo
	NetworkBridge.Server.FireClient("PersonalizadorAbrir", player, raizNpc.Position, categoria, solo)
end

-- El Maestro Personalizador no es uno de los 39 del catálogo (salió del pedido
-- del vendedor 3D), así que no le toca número: lleva la etiqueta "A MEDIDA"
-- con el mismo cartel que usan los demás, para que se vea igual de lejos.
local function etiquetar(modelo: Model)
	local raiz = modelo.PrimaryPart or modelo:FindFirstChild("HumanoidRootPart")
	if raiz and raiz:IsA("BasePart") and not modelo:FindFirstChild("NumeroNpc") then
		NpcManager.PonerEtiqueta(modelo, raiz, "A MEDIDA", Color3.fromRGB(240, 190, 90))
	end
end

local function prepararNpc(instancia: Instance)
	if not instancia:IsA("Model") then
		return
	end
	-- Los del catálogo ya traen su número; a los demás se les pone la etiqueta.
	if instancia:GetAttribute("Arquetipo") == nil then
		etiquetar(instancia)
	end
	local raiz = instancia:FindFirstChild("HumanoidRootPart") or instancia.PrimaryPart
	if not raiz or not raiz:IsA("BasePart") then
		warn(`[Personalizador] El NPC {instancia:GetFullName()} necesita HumanoidRootPart o PrimaryPart`)
		return
	end
	CollectionService:AddTag(raiz, TAG_RADAR)
	local humanoide = instancia:FindFirstChildOfClass("Humanoid")
	if humanoide then
		humanoide.NameDisplayDistance = 250
	end
	local categoria = instancia:GetAttribute("Categoria")
	local solo = instancia:GetAttribute("Solo")
	local prompt = raiz:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Probar y comprar"
	prompt.ObjectText = "Vendedor"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = raiz
	prompt.Triggered:Connect(function(player: Player)
		abrir(
			player,
			raiz,
			if categoria == "Armas" or categoria == "Armaduras" then categoria else nil,
			if solo == "Color" then "Color" else nil
		)
	end)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

-- El catálogo de modelos personalizables, para los sistemas que trabajan
-- sobre ítems ya comprados (el NPC Cosméticos).
function PersonalizadorManager.Catalogo(): { [string]: Personalizador.Entrada }
	return catalogo()
end

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
		print(
			`[Personalizador] Vendedor de prueba en {POSICION_PRUEBA}.`
				.. ` Para ir: game.ServerStorage.RaidBloxDebug:Invoke("Ir", "Personalizador")`
		)
	end

	-- Inscriptor (NPC-005): graba calcomanías en un ítem que ya tenés.
	NpcManager.RegistrarAccion("Grabar", function(player: Player, npc: any): boolean
		local raiz = if typeof(npc) == "table" then npc.Raiz else nil
		if not raiz or not raiz:IsA("BasePart") then
			return false
		end
		abrir(player, raiz, nil, "Stencil")
		return true
	end)

	-- Tintorero (NPC-031): abre el probador en modo retoque (solo colores).
	NpcManager.RegistrarAccion("Tintar", function(player: Player, npc: any): boolean
		local raiz = if typeof(npc) == "table" then npc.Raiz else nil
		if not raiz or not raiz:IsA("BasePart") then
			return false
		end
		abrir(player, raiz, nil, "Color")
		return true -- abrir() ya valida distancia y estado; si no abre, no cobra nada
	end)

	NetworkBridge.Server.OnEvent("PersonalizadorCerrar", function(player: Player)
		sesiones[player] = nil
		restriccion[player] = nil
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
		"PersonalizadorRetocar",
		function(player: Player, uid: unknown, requestId: unknown, datos: unknown, precioVisto: unknown): Respuesta
			if enCurso[player] then
				return NetworkBridge.Fail("RATE_LIMITED")
			end
			enCurso[player] = true
			local ok, resultado = pcall(retocar, player, uid, requestId, datos, precioVisto)
			enCurso[player] = nil
			if not ok then
				warn(`[Personalizador] Error en el retoque de {player.UserId}: {resultado}`)
				return NetworkBridge.Fail("INTERNAL_ERROR")
			end
			return resultado
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
		restriccion[player] = nil
	end)
end

return PersonalizadorManager
