--!strict
-- DataManager: persistencia de jugadores con ProfileStore (session locking).
--
-- Reglas:
-- * Es el ÚNICO módulo que toca DataStores. El resto del juego usa esta API.
-- * Cada jugador tiene una sola sesión activa en todo el juego: si reingresa
--   rápido a otro servidor, el nuevo espera a que el viejo libere el perfil
--   (así no se duplican ítems).
-- * Si el perfil no carga, el jugador es expulsado con un mensaje. Nunca juega
--   con un perfil vacío, porque al guardar pisaría sus datos reales.
-- * ProfileStore autoguarda periódicamente y guarda todo en game:BindToClose.
-- * Cada cambio se replica al cliente por el remote DataSync, por sección.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local GuerraConfig = require(ReplicatedStorage.Configs.GuerraConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Workspace = game:GetService("Workspace")
local Signal = require(ReplicatedStorage.Modules.Signal)
local ChatarreroConfig = require(ReplicatedStorage.Configs.ChatarreroConfig)

type DatosJugador = Types.DatosJugador
type ItemInstancia = Types.ItemInstancia
type ItemMeta = Types.ItemMeta
type Rareza = Types.Rareza
type SeccionDatos = Types.SeccionDatos
type CodigoError = Types.CodigoError

------------------------------------------------------------------------
-- Interfaz de ProfileStore (solo lo que usamos). El tipo exportado por la
-- librería no incluye el parámetro Cancel de StartSessionAsync, por eso se
-- declara acá y se convierte una única vez en el require.
------------------------------------------------------------------------

-- Mensaje del buzón offline.
type MensajeOro = { Id: string, Tipo: "Oro", Cantidad: number, Motivo: string }
type MensajeItem = {
	Id: string,
	Tipo: "Item",
	ItemId: string,
	Cantidad: number,
	Rareza: Rareza,
	Meta: ItemMeta?,
	Motivo: string,
}

type Conexion = { Disconnect: (self: any) -> () }
type Perfil = {
	Data: DatosJugador,
	OnSessionEnd: { Connect: (self: any, fn: () -> ()) -> Conexion },
	OnLastSave: { Connect: (self: any, fn: (motivo: "Manual" | "External" | "Shutdown") -> ()) -> Conexion },
	OnAfterSave: { Connect: (self: any, fn: (datosGuardados: any) -> ()) -> Conexion },
	IsActive: (self: Perfil) -> boolean,
	Reconcile: (self: Perfil) -> (),
	EndSession: (self: Perfil) -> (),
	AddUserId: (self: Perfil, userId: number) -> (),
	Save: (self: Perfil) -> (),
	MessageHandler: (self: Perfil, fn: (mensaje: unknown, procesado: () -> ()) -> ()) -> (),
}
type Store = {
	StartSessionAsync: (self: Store, clave: string, params: { Cancel: () -> boolean }?) -> Perfil?,
	MessageAsync: (self: Store, clave: string, mensaje: MensajeOro | MensajeItem) -> boolean,
}
type ModuloProfileStore = {
	New: (nombre: string, plantilla: DatosJugador) -> Store,
}

local ProfileStore = (require(ServerScriptService.Packages.ProfileStore) :: any) :: ModuloProfileStore

------------------------------------------------------------------------
-- Plantilla y migraciones
------------------------------------------------------------------------

local VERSION_ACTUAL = GameConfig.Datos.VersionEsquema
local RAREZAS_VALIDAS: { [string]: Rareza } = {
	Comun = "Comun",
	Raro = "Raro",
	Epico = "Epico",
	Mistico = "Mistico",
	Unico = "Unico",
}
local MAX_ORO = 999_999_999_999

local PLANTILLA: DatosJugador = {
	Version = VERSION_ACTUAL,
	Nivel = 1,
	Experiencia = 0,
	Clase = "SinClase",
	Faccion = "Violeta",
	Estadisticas = table.clone(GameConfig.EstadisticasIniciales),
	Oro = 0,
	MonedasPremium = 0,
	Inventario = {
		MaxSlots = GameConfig.Inventario.SlotsBase,
		Slots = {},
	},
	Equipamiento = {},
	MisionesActivas = {},
	MisionesCompletadas = {},
	RecibosProcesados = {},
	MensajesProcesados = {},
	PuntosHonor = 0,
	Titulos = {},
	TituloEquipado = nil,
	SkinsEstructura = { "Ninguna" },
	SkinEstructuraEquipada = "Ninguna",
	Profesiones = {},
	KitInicialEntregado = false,
	Ajustes = {
		Genero = "Avatar",
		ChatPosicion = "Izquierda",
		ChatTamano = "Normal",
		ChatVisible = true,
	},
	Pendientes = { Subastas = {}, Compras = {} },
	MensajesSubasta = {},
	SecuenciaGuardado = 0,
}

-- MIGRACIONES[n] transforma datos de la versión n a la n+1.
-- Reconcile completa campos nuevos con valores por defecto; una migración solo
-- hace falta cuando hay que transformar datos existentes.
local MIGRACIONES: { [number]: (any) -> any } = {
	-- v1 -> v2: honor, títulos y skins de estructura (Guerra de Arquitectos).
	[1] = function(datos)
		datos.PuntosHonor = datos.PuntosHonor or 0
		datos.Titulos = datos.Titulos or {}
		datos.SkinsEstructura = datos.SkinsEstructura or { "Ninguna" }
		datos.SkinEstructuraEquipada = datos.SkinEstructuraEquipada or "Ninguna"
		return datos
	end,
	-- v2 -> v3: profesiones y kit inicial de herramientas.
	[2] = function(datos)
		datos.Profesiones = datos.Profesiones or {}
		if datos.KitInicialEntregado == nil then
			datos.KitInicialEntregado = false
		end
		return datos
	end,
	-- v3 -> v4: bandos (la facción "Ninguna" pasa a ser Violeta) y ajustes.
	[3] = function(datos)
		if datos.Faccion ~= "Rojo" and datos.Faccion ~= "Azul" then
			datos.Faccion = "Violeta"
		end
		datos.Ajustes = datos.Ajustes
			or { Genero = "Avatar", ChatPosicion = "Izquierda", ChatTamano = "Normal", ChatVisible = true }
		return datos
	end,
	-- v4 -> v5: diario de subastas y dedupe largo de mensajes de subasta.
	[4] = function(datos)
		datos.Pendientes = datos.Pendientes or { Subastas = {}, Compras = {} }
		datos.MensajesSubasta = datos.MensajesSubasta or {}
		datos.SecuenciaGuardado = datos.SecuenciaGuardado or 0
		return datos
	end,
}

local function copiaProfunda(valor: any): any
	if typeof(valor) ~= "table" then
		return valor
	end
	local copia = {}
	for k, v in valor do
		copia[k] = copiaProfunda(v)
	end
	return copia
end

local function migrar(datos: any): nil
	if typeof(datos.Version) ~= "number" then
		datos.Version = 1
	end
	if datos.Version > VERSION_ACTUAL then
		-- Datos de una versión más nueva (servidor viejo durante una actualización
		-- o tras un rollback): cargarlos y guardarlos los corrompería.
		error(`Datos en versión {datos.Version}, este servidor solo conoce hasta {VERSION_ACTUAL}`)
	end
	while datos.Version < VERSION_ACTUAL do
		local paso = MIGRACIONES[datos.Version]
		if not paso then
			error(`Falta la migración desde la versión {datos.Version}`)
		end
		paso(datos)
		datos.Version += 1
	end
	return nil
end

------------------------------------------------------------------------
-- Estado
------------------------------------------------------------------------

local DataManager = {}

-- Se dispara cuando un perfil terminó de cargar y está listo para usarse.
DataManager.PerfilCargado = Signal.new() :: Signal.Signal<Player, DatosJugador>
-- Se dispara después de cada cambio, con la sección modificada.
DataManager.DatosCambiados = Signal.new() :: Signal.Signal<Player, SeccionDatos>

local store: Store? = nil
local perfiles: { [Player]: Perfil } = {}

local function perfilActivo(player: Player): Perfil?
	local perfil = perfiles[player]
	if perfil and perfil:IsActive() then
		return perfil
	end
	return nil
end

-- Habilidades equipadas en las barras (clases con barras). Sin elección
-- guardada: las barras por defecto.
function DataManager.Barras(datos: DatosJugador): { string }
	return datos.Barras or ChatarreroConfig.BarrasPorDefecto
end

-- Valor de una sección tal como se manda al cliente.
local function valorSeccion(datos: DatosJugador, seccion: SeccionDatos): any
	if seccion == "Nivel" then
		return { Nivel = datos.Nivel, Experiencia = datos.Experiencia }
	elseif seccion == "Misiones" then
		return { Activas = datos.MisionesActivas, Completadas = datos.MisionesCompletadas }
	elseif seccion == "Oro" then
		return datos.Oro
	elseif seccion == "MonedasPremium" then
		return datos.MonedasPremium
	elseif seccion == "Estadisticas" then
		return datos.Estadisticas
	elseif seccion == "Inventario" then
		return datos.Inventario
	elseif seccion == "Profesiones" then
		return datos.Profesiones
	elseif seccion == "Clase" then
		return datos.Clase
	elseif seccion == "Faccion" then
		return datos.Faccion
	elseif seccion == "Ajustes" then
		return datos.Ajustes
	elseif seccion == "Honor" then
		return datos.PuntosHonor
	elseif seccion == "Cosmeticos" then
		return {
			Titulos = datos.Titulos,
			TituloEquipado = datos.TituloEquipado,
			SkinsEstructura = datos.SkinsEstructura,
			SkinEstructuraEquipada = datos.SkinEstructuraEquipada,
			Mascotas = datos.Mascotas or {},
			MascotaEquipada = datos.MascotaEquipada or false,
			Apariencias = datos.Apariencias or {},
			Transmog = datos.Transmog or {},
			Barras = DataManager.Barras(datos),
		}
	else
		return datos.Equipamiento
	end
end

local function notificarCambio(player: Player, datos: DatosJugador, seccion: SeccionDatos)
	NetworkBridge.Server.FireClient("DataSync", player, seccion, valorSeccion(datos, seccion))
	DataManager.DatosCambiados:Fire(player, seccion)
end

local function esEnteroPositivo(n: number): boolean
	return n == n and n >= 1 and n < math.huge and n == math.floor(n)
end

------------------------------------------------------------------------
-- Mensajes offline (buzón): oro u otros envíos a jugadores desconectados,
-- por ejemplo ventas de la Casa de Subastas. Se entregan al conectarse.
------------------------------------------------------------------------

local function procesarMensaje(player: Player, perfil: Perfil, mensaje: unknown, procesado: () -> ())
	if typeof(mensaje) ~= "table" then
		procesado() -- mensaje corrupto: se descarta para no reintentarlo siempre
		return
	end
	local m = mensaje :: { [string]: unknown }
	if typeof(m.Id) ~= "string" or typeof(m.Tipo) ~= "string" then
		procesado() -- sin Id o sin Tipo: corrupto
		return
	end
	local id = m.Id :: string
	local vistos = perfil.Data.MensajesProcesados
	-- Los envíos de la subasta pueden reintentarse días después (al volver a
	-- entrar el vendedor o el comprador): sus ids se recuerdan 30 días, no solo
	-- los últimos 100 mensajes.
	local esSubasta = string.sub(id, 1, 8) == "subasta:"

	-- Idempotencia: MessageAsync puede reintentar una escritura que sí se hizo,
	-- y el mismo mensaje llegaría dos veces.
	if table.find(vistos, id) or (esSubasta and perfil.Data.MensajesSubasta[id] ~= nil) then
		procesado()
		return
	end

	if m.Tipo == "Oro" then
		local cantidad = if typeof(m.Cantidad) == "number" then m.Cantidad :: number else 0
		if esEnteroPositivo(cantidad) then
			if perfil.Data.Oro + cantidad > MAX_ORO then
				-- No se destruye oro: queda en el buzón hasta que haya lugar.
				NetworkBridge.Server.FireClient(
					"Notificacion",
					player,
					"Tenés oro esperando en el buzón, pero llegaste al tope de oro.",
					"Error"
				)
				return
			end
			perfil.Data.Oro += cantidad
			notificarCambio(player, perfil.Data, "Oro")
			local motivo = if typeof(m.Motivo) == "string" then m.Motivo :: string else "Buzón"
			NetworkBridge.Server.FireClient("Notificacion", player, `+{cantidad} de oro ({motivo})`, "Oro")
		end
	elseif m.Tipo == "Item" then
		local itemId = m.ItemId
		local cantidad = m.Cantidad
		local rareza = m.Rareza
		if
			typeof(itemId) ~= "string"
			or not ItemCatalog[itemId :: string]
			or typeof(cantidad) ~= "number"
			or not esEnteroPositivo(cantidad :: number)
			or typeof(rareza) ~= "string"
			or not RAREZAS_VALIDAS[rareza :: string]
		then
			procesado() -- datos inválidos: se descarta
			return
		end
		local meta: ItemMeta? = nil
		if typeof(m.Meta) == "table" then
			meta = {}
			for clave, valor in m.Meta :: { [any]: any } do
				local tv = typeof(valor)
				if typeof(clave) == "string" and (tv == "string" or tv == "number" or tv == "boolean") then
					(meta :: ItemMeta)[clave] = valor
				end
			end
		end
		local ok =
			DataManager.AddItem(player, itemId :: string, cantidad :: number, RAREZAS_VALIDAS[rareza :: string], meta)
		if not ok then
			-- Inventario lleno: queda en el buzón y se reintenta al volver a entrar.
			NetworkBridge.Server.FireClient(
				"Notificacion",
				player,
				"Tenés objetos esperando en el buzón: liberá espacio y volvé a entrar para recibirlos.",
				"Error"
			)
			return
		end
		local motivo = if typeof(m.Motivo) == "string" then m.Motivo :: string else "Buzón"
		local nombre = ItemCatalog[itemId :: string].Nombre
		NetworkBridge.Server.FireClient("Notificacion", player, `Recibiste {nombre} x{cantidad} ({motivo})`, "Oro")
	else
		-- Tipo desconocido: puede venir de un servidor con una versión más nueva
		-- del juego. NO se marca como procesado; lo entregará un servidor que lo entienda.
		return
	end

	if esSubasta then
		perfil.Data.MensajesSubasta[id] = os.time()
	end
	table.insert(vistos, id)
	while #vistos > GameConfig.Datos.MaxMensajesGuardados do
		table.remove(vistos, 1)
	end
	procesado()
end

-- Envía oro al buzón de un jugador (conectado o no, en cualquier servidor).
-- `id` opcional: pasá siempre el MISMO id al reintentar un envío, así un
-- reintento de algo que en realidad sí se escribió no se entrega dos veces.
function DataManager.EnviarOroOffline(userId: number, cantidad: number, motivo: string, id: string?): boolean
	assert(store, "DataManager.Init() no se llamó")
	if not esEnteroPositivo(cantidad) then
		return false
	end
	local mensaje: MensajeOro = {
		Id = id or HttpService:GenerateGUID(false),
		Tipo = "Oro",
		Cantidad = cantidad,
		Motivo = motivo,
	}
	return store:MessageAsync(tostring(userId), mensaje)
end

-- Envía un ítem al buzón (lo usa el botín cuando el inventario está lleno).
function DataManager.EnviarItemOffline(
	userId: number,
	itemId: string,
	cantidad: number,
	rareza: Rareza,
	meta: ItemMeta?,
	motivo: string,
	id: string?
): boolean
	assert(store, "DataManager.Init() no se llamó")
	if not ItemCatalog[itemId] or not esEnteroPositivo(cantidad) then
		return false
	end
	local mensaje: MensajeItem = {
		Id = id or HttpService:GenerateGUID(false),
		Tipo = "Item",
		ItemId = itemId,
		Cantidad = cantidad,
		Rareza = rareza,
		Meta = meta,
		Motivo = motivo,
	}
	return store:MessageAsync(tostring(userId), mensaje)
end

------------------------------------------------------------------------
-- Ciclo de vida
------------------------------------------------------------------------

-- Datos completos para el cliente, sin campos internos (recibos, mensajes).
local function snapshotCliente(d: DatosJugador): { [string]: any }
	return {
		Nivel = d.Nivel,
		Experiencia = d.Experiencia,
		Clase = d.Clase,
		Faccion = d.Faccion,
		Estadisticas = d.Estadisticas,
		Oro = d.Oro,
		MonedasPremium = d.MonedasPremium,
		Inventario = d.Inventario,
		Equipamiento = d.Equipamiento,
		MisionesActivas = d.MisionesActivas,
		MisionesCompletadas = d.MisionesCompletadas,
		PuntosHonor = d.PuntosHonor,
		Titulos = d.Titulos,
		TituloEquipado = d.TituloEquipado,
		SkinsEstructura = d.SkinsEstructura,
		SkinEstructuraEquipada = d.SkinEstructuraEquipada,
		Mascotas = d.Mascotas or {},
		MascotaEquipada = d.MascotaEquipada or false,
		Apariencias = d.Apariencias or {},
		Transmog = d.Transmog or {},
		Barras = DataManager.Barras(d),
		Profesiones = d.Profesiones,
		Ajustes = d.Ajustes,
	}
end

local function alEntrarJugador(player: Player)
	assert(store, "DataManager.Init() no se llamó")
	local inicio = os.clock()
	local perfil = store:StartSessionAsync(tostring(player.UserId), {
		-- Corta si el jugador se fue o si la carga tarda demasiado (caída de
		-- DataStores): con Cancel, ProfileStore reintentaría para siempre.
		Cancel = function(): boolean
			return player.Parent ~= Players or os.clock() - inicio > GameConfig.Datos.TimeoutCarga
		end,
	})

	if perfil == nil then
		-- Falló la carga o el jugador se fue mientras esperaba.
		if player.Parent == Players then
			player:Kick("No pudimos cargar tus datos. Volvé a entrar en unos segundos.")
		end
		return
	end

	perfil:AddUserId(player.UserId) -- cumplimiento GDPR
	-- La migración trabaja sobre una copia: si falla a mitad de camino, los
	-- datos originales quedan intactos y eso es lo que se guarda al cerrar.
	local copia = copiaProfunda(perfil.Data)
	local okMigracion, errMigracion = pcall(migrar, copia)
	if not okMigracion then
		warn(`[DataManager] Migración falló para {player.UserId}: {errMigracion}`)
		perfil:EndSession()
		player:Kick("Hubo un problema actualizando tus datos. Avisá al equipo de RaidBlox.")
		return
	end
	local datos = perfil.Data :: any
	for clave in table.clone(datos) do
		datos[clave] = nil
	end
	for clave, valor in copia do
		datos[clave] = valor
	end
	perfil:Reconcile() -- completa campos nuevos de la plantilla

	perfil.OnSessionEnd:Connect(function()
		perfiles[player] = nil
	end)
	perfil.OnLastSave:Connect(function(motivo)
		-- "External": otro servidor tomó la sesión. Salidas normales y cierres no avisan.
		if motivo == "External" and player.Parent == Players then
			player:Kick("Tu sesión se abrió en otro servidor. Volvé a entrar.")
		end
	end)

	if player.Parent ~= Players then
		perfil:EndSession() -- se fue durante la carga
		return
	end

	perfiles[player] = perfil
	perfil:MessageHandler(function(mensaje: unknown, procesado: () -> ())
		procesarMensaje(player, perfil, mensaje, procesado)
	end)
	player:SetAttribute("Bando", perfil.Data.Faccion) -- visible para todos (color del nombre, PvP)
	-- Poda de los ids de mensajes de subasta de más de 30 días.
	local limiteSubasta = os.time() - 30 * 86400
	for idMensaje, cuando in perfil.Data.MensajesSubasta do
		if cuando < limiteSubasta then
			perfil.Data.MensajesSubasta[idMensaje] = nil
		end
	end
	DataManager.PerfilCargado:Fire(player, perfil.Data)
	NetworkBridge.Server.FireClient("DatosIniciales", player, snapshotCliente(perfil.Data))
end

local function alSalirJugador(player: Player)
	local perfil = perfiles[player]
	if perfil then
		perfil:EndSession() -- guarda y libera el session lock
	end
end

function DataManager.Init()
	assert(store == nil, "DataManager.Init() se llamó dos veces")
	-- Studio guarda en un store aparte: lo que se haga probando (oro del
	-- Banquero, comandos de prueba) nunca llega a los perfiles reales.
	local nombre = GameConfig.Datos.NombreStore .. (if RunService:IsStudio() then "_Studio" else "")
	store = ProfileStore.New(nombre, PLANTILLA)

	NetworkBridge.Server.OnInvoke("SolicitarDatos", function(player: Player): Types.Respuesta
		local perfil = perfilActivo(player)
		if not perfil then
			return NetworkBridge.Fail("DATA_NOT_LOADED")
		end
		return NetworkBridge.Ok(snapshotCliente(perfil.Data))
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(alEntrarJugador, player)
	end
	Players.PlayerAdded:Connect(alEntrarJugador)
	Players.PlayerRemoving:Connect(alSalirJugador)
end

------------------------------------------------------------------------
-- Lectura
------------------------------------------------------------------------

-- Datos del jugador o nil si todavía no cargaron. SOLO LECTURA: para
-- modificar, usar las funciones de esta API (validan y replican).
function DataManager.GetData(player: Player): DatosJugador?
	local perfil = perfilActivo(player)
	return if perfil then perfil.Data else nil
end

function DataManager.IsLoaded(player: Player): boolean
	return perfilActivo(player) ~= nil
end

-- Espera a que carguen los datos (o a que el jugador se vaya / timeout).
function DataManager.WaitForData(player: Player, timeout: number?): DatosJugador?
	local limite = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < limite do
		local datos = DataManager.GetData(player)
		if datos then
			return datos
		end
		task.wait(0.1)
	end
	return nil
end

-- Fuerza un guardado y ESPERA a que se escriba (hasta `timeout` segundos).
-- Devuelve true solo si el guardado terminó. Para teleports entre places no es
-- obligatorio: el servidor de destino espera a que este libere el session lock
-- (pasa al salir el jugador), así que nunca carga datos viejos.
function DataManager.SaveNowAsync(player: Player, timeout: number?): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	-- Contador de secuencia: un guardado que ya estaba en curso (y no incluye
	-- el último cambio) no cuenta como confirmación.
	perfil.Data.SecuenciaGuardado += 1
	local secuencia = perfil.Data.SecuenciaGuardado
	local guardado = false
	local conexion = perfil.OnAfterSave:Connect(function(datosGuardados: any)
		if typeof(datosGuardados) == "table" and (datosGuardados.SecuenciaGuardado or 0) >= secuencia then
			guardado = true
		end
	end)
	perfil:Save()
	local limite = os.clock() + (timeout or 10)
	while not guardado and os.clock() < limite and perfil:IsActive() do
		task.wait(0.1)
	end
	conexion:Disconnect()
	return guardado
end

------------------------------------------------------------------------
-- Oro
------------------------------------------------------------------------

function DataManager.AddGold(player: Player, cantidad: number): boolean
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) or perfil.Data.Oro + cantidad > MAX_ORO then
		return false -- todo o nada: no se pierde oro en silencio por el tope
	end
	perfil.Data.Oro += cantidad
	notificarCambio(player, perfil.Data, "Oro")
	return true
end

-- Descuenta oro solo si alcanza. Devuelve false sin tocar nada si no.
function DataManager.SpendGold(player: Player, cantidad: number): boolean
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) or perfil.Data.Oro < cantidad then
		return false
	end
	perfil.Data.Oro -= cantidad
	notificarCambio(player, perfil.Data, "Oro")
	return true
end

------------------------------------------------------------------------
-- Moneda premium: SOLO para MonetizationManager (ProcessReceipt) y gastos
-- validados por el servidor. Nunca exponer a un remote directo.
------------------------------------------------------------------------

function DataManager.AddPremium(player: Player, cantidad: number): boolean
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) or perfil.Data.MonedasPremium + cantidad > MAX_ORO then
		return false
	end
	perfil.Data.MonedasPremium += cantidad
	notificarCambio(player, perfil.Data, "MonedasPremium")
	return true
end

function DataManager.SpendPremium(player: Player, cantidad: number): boolean
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) or perfil.Data.MonedasPremium < cantidad then
		return false
	end
	perfil.Data.MonedasPremium -= cantidad
	notificarCambio(player, perfil.Data, "MonedasPremium")
	return true
end

-- Idempotencia de recibos: true si este PurchaseId ya se entregó antes.
-- Flujo correcto en ProcessReceipt (Fase 6): si ReciboYaProcesado -> PurchaseGranted.
-- Si no: entregar, MarcarRecibo y devolver PurchaseGranted SOLO si
-- SaveNowAsync(player) devuelve true; si no, NotProcessedYet (Roblox reintenta).
function DataManager.ReciboYaProcesado(player: Player, purchaseId: string): boolean
	local perfil = perfilActivo(player)
	return perfil ~= nil and table.find(perfil.Data.RecibosProcesados, purchaseId) ~= nil
end

function DataManager.MarcarRecibo(player: Player, purchaseId: string): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	local recibos = perfil.Data.RecibosProcesados
	table.insert(recibos, purchaseId)
	while #recibos > GameConfig.Datos.MaxRecibosGuardados do
		table.remove(recibos, 1)
	end
	return true
end

------------------------------------------------------------------------
-- Honor, títulos y skins de estructura
------------------------------------------------------------------------

-- Una sola fuente de verdad: las skins válidas son las definidas en GuerraConfig.Skins.
local SKINS_VALIDAS: { [string]: Types.SkinEstructura } = {}
for nombre in GuerraConfig.Skins do
	SKINS_VALIDAS[nombre] = nombre :: any
end

function DataManager.AddHonor(player: Player, cantidad: number): boolean
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) or perfil.Data.PuntosHonor + cantidad > MAX_ORO then
		return false
	end
	perfil.Data.PuntosHonor += cantidad
	notificarCambio(player, perfil.Data, "Honor")
	return true
end

-- Descuenta honor solo si alcanza. Devuelve false sin tocar nada si no.
function DataManager.SpendHonor(player: Player, cantidad: number): boolean
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) or perfil.Data.PuntosHonor < cantidad then
		return false
	end
	perfil.Data.PuntosHonor -= cantidad
	notificarCambio(player, perfil.Data, "Honor")
	return true
end

-- Otorga un título (no duplica). Devuelve true si es nuevo.
function DataManager.AddTitulo(player: Player, titulo: string): boolean
	local perfil = perfilActivo(player)
	if not perfil or titulo == "" or table.find(perfil.Data.Titulos, titulo) then
		return false
	end
	table.insert(perfil.Data.Titulos, titulo)
	notificarCambio(player, perfil.Data, "Cosmeticos")
	return true
end

-- Desbloquea una skin de estructura (la entregan el Pase de Batalla o la tienda).
function DataManager.UnlockSkinEstructura(player: Player, skin: string): boolean
	local perfil = perfilActivo(player)
	local valida = SKINS_VALIDAS[skin]
	if not perfil or not valida or table.find(perfil.Data.SkinsEstructura, valida) then
		return false
	end
	table.insert(perfil.Data.SkinsEstructura, valida)
	notificarCambio(player, perfil.Data, "Cosmeticos")
	return true
end

-- Equipa una skin ya desbloqueada.
function DataManager.SetSkinEstructura(player: Player, skin: string): boolean
	local perfil = perfilActivo(player)
	local valida = SKINS_VALIDAS[skin]
	if not perfil or not valida or not table.find(perfil.Data.SkinsEstructura, valida) then
		return false
	end
	perfil.Data.SkinEstructuraEquipada = valida :: Types.SkinEstructura
	notificarCambio(player, perfil.Data, "Cosmeticos")
	return true
end

------------------------------------------------------------------------
-- Experiencia y nivel
------------------------------------------------------------------------

function DataManager.XpParaSiguienteNivel(nivel: number): number
	local cfg = GameConfig.Progresion
	return math.floor(cfg.XpBase * nivel ^ cfg.XpExponente)
end

-- Suma XP y sube de nivel las veces que corresponda. Devuelve los niveles ganados.
function DataManager.AddExperience(player: Player, cantidad: number): number
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) then
		return 0
	end
	local d = perfil.Data
	local maximo = GameConfig.Progresion.NivelMaximo
	if d.Nivel >= maximo then
		return 0
	end

	d.Experiencia += cantidad
	local ganados = 0
	while d.Nivel < maximo do
		local necesaria = DataManager.XpParaSiguienteNivel(d.Nivel)
		if d.Experiencia < necesaria then
			break
		end
		d.Experiencia -= necesaria
		d.Nivel += 1
		ganados += 1
	end
	if d.Nivel >= maximo then
		d.Experiencia = 0
	end
	notificarCambio(player, d, "Nivel")
	return ganados
end

------------------------------------------------------------------------
-- Inventario
------------------------------------------------------------------------

local function maxStackDe(itemId: string): number
	local def = ItemCatalog[itemId]
	if not def or not def.Apilable then
		return 1
	end
	return def.MaxStack or GameConfig.Inventario.MaxStackPorDefecto
end

-- Dos instancias se pueden apilar si son el mismo ítem, misma rareza y sin metadatos.
local function apilables(a: ItemInstancia, itemId: string, rareza: Rareza): boolean
	return a.ItemId == itemId and a.Rareza == rareza and a.Meta == nil
end

local function copiarMeta(meta: ItemMeta?): ItemMeta?
	return if meta then table.clone(meta) else nil
end

-- Agrega ítems de forma atómica: primero calcula si entra todo; si no entra,
-- no agrega nada y devuelve (false, "INVENTORY_FULL").
function DataManager.AddItem(
	player: Player,
	itemId: string,
	cantidad: number,
	rareza: Rareza?,
	meta: ItemMeta?
): (boolean, CodigoError?)
	local perfil = perfilActivo(player)
	if not perfil then
		return false, "DATA_NOT_LOADED"
	end
	local def = ItemCatalog[itemId]
	if not def or not esEnteroPositivo(cantidad) then
		return false, "INVALID_ARGS"
	end

	local inv = perfil.Data.Inventario
	local rarezaFinal: Rareza = rareza or "Comun"
	local maxStack = maxStackDe(itemId)
	local seApila = def.Apilable and meta == nil

	-- 1. Calcular capacidad disponible sin modificar nada.
	local libres: { string } = {}
	local espacioEnPilas = 0
	for i = 1, inv.MaxSlots do
		local clave = tostring(i)
		local actual = inv.Slots[clave]
		if actual == nil then
			table.insert(libres, clave)
		elseif seApila and apilables(actual, itemId, rarezaFinal) then
			espacioEnPilas += math.max(0, maxStack - actual.Cantidad)
		end
	end
	local capacidad = if seApila then espacioEnPilas + #libres * maxStack else #libres
	if capacidad < cantidad then
		return false, "INVENTORY_FULL"
	end

	-- 2. Aplicar: completar pilas existentes y después usar ranuras libres.
	local restante = cantidad
	if seApila then
		for i = 1, inv.MaxSlots do
			if restante == 0 then
				break
			end
			local actual = inv.Slots[tostring(i)]
			if actual and apilables(actual, itemId, rarezaFinal) and actual.Cantidad < maxStack then
				local agregar = math.min(restante, maxStack - actual.Cantidad)
				actual.Cantidad += agregar
				restante -= agregar
			end
		end
	end
	for _, clave in libres do
		if restante == 0 then
			break
		end
		local agregar = if seApila then math.min(restante, maxStack) else 1
		inv.Slots[clave] = {
			Uid = HttpService:GenerateGUID(false),
			ItemId = itemId,
			Cantidad = agregar,
			Rareza = rarezaFinal,
			Meta = copiarMeta(meta),
		}
		restante -= agregar
	end

	notificarCambio(player, perfil.Data, "Inventario")
	return true, nil
end

-- Cantidad total de un ítem en el inventario (no cuenta lo equipado).
function DataManager.CountItem(player: Player, itemId: string): number
	local perfil = perfilActivo(player)
	if not perfil then
		return 0
	end
	-- Recorre 1..MaxSlots igual que RemoveItem, para que ambos vean lo mismo.
	local inv = perfil.Data.Inventario
	local total = 0
	for i = 1, inv.MaxSlots do
		local item = inv.Slots[tostring(i)]
		if item and item.ItemId == itemId then
			total += item.Cantidad
		end
	end
	return total
end

function DataManager.HasItem(player: Player, itemId: string, cantidad: number): boolean
	return esEnteroPositivo(cantidad) and DataManager.CountItem(player, itemId) >= cantidad
end

-- Quita `cantidad` de un ítem de forma atómica (todo o nada). Para ítems
-- únicos con metadatos (encantados, etc.) usar RemoveItemByUid.
function DataManager.RemoveItem(player: Player, itemId: string, cantidad: number): boolean
	local perfil = perfilActivo(player)
	if not perfil or not DataManager.HasItem(player, itemId, cantidad) then
		return false
	end
	local inv = perfil.Data.Inventario
	local restante = cantidad
	-- Primero las pilas sin metadatos, para no gastar un ítem encantado por error.
	for pasada = 1, 2 do
		for i = 1, inv.MaxSlots do
			if restante == 0 then
				break
			end
			local clave = tostring(i)
			local item = inv.Slots[clave]
			local sinMeta = item ~= nil and item.Meta == nil
			if item and item.ItemId == itemId and (pasada == 2 or sinMeta) then
				local quitar = math.min(restante, item.Cantidad)
				item.Cantidad -= quitar
				restante -= quitar
				if item.Cantidad <= 0 then
					inv.Slots[clave] = nil
				end
			end
		end
	end
	notificarCambio(player, perfil.Data, "Inventario")
	return true
end

-- Quita una instancia concreta. Devuelve la instancia quitada o nil.
function DataManager.RemoveItemByUid(player: Player, uid: string): ItemInstancia?
	local perfil = perfilActivo(player)
	if not perfil then
		return nil
	end
	local slots = perfil.Data.Inventario.Slots
	for clave, item in slots do
		if item.Uid == uid then
			slots[clave] = nil
			notificarCambio(player, perfil.Data, "Inventario")
			return item
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Clase y equipamiento
------------------------------------------------------------------------

-- Fija la clase. Las reglas de cuándo se permite (solo sin clase, o cambio
-- pagado) las decide quien llama.
------------------------------------------------------------------------
-- Misiones. Las reglas (nivel, previas, objetivos) las valida MisionManager;
-- estas funciones solo guardan y avisan al cliente.
------------------------------------------------------------------------

function DataManager.AceptarMision(player: Player, id: string): boolean
	local perfil = perfilActivo(player)
	if not perfil or perfil.Data.MisionesActivas[id] then
		return false
	end
	perfil.Data.MisionesActivas[id] = { AceptadaEn = os.time(), Objetivos = {} }
	notificarCambio(player, perfil.Data, "Misiones")
	return true
end

function DataManager.ProgresoMision(player: Player, id: string, objetivo: string, valor: number): boolean
	local perfil = perfilActivo(player)
	local mision = perfil and perfil.Data.MisionesActivas[id]
	if not perfil or not mision then
		return false
	end
	mision.Objetivos[objetivo] = valor
	notificarCambio(player, perfil.Data, "Misiones")
	return true
end

function DataManager.CompletarMision(player: Player, id: string): boolean
	local perfil = perfilActivo(player)
	if not perfil or not perfil.Data.MisionesActivas[id] then
		return false
	end
	perfil.Data.MisionesActivas[id] = nil
	perfil.Data.MisionesCompletadas[id] = os.time()
	notificarCambio(player, perfil.Data, "Misiones")
	return true
end

function DataManager.AbandonarMision(player: Player, id: string): boolean
	local perfil = perfilActivo(player)
	if not perfil or not perfil.Data.MisionesActivas[id] then
		return false
	end
	perfil.Data.MisionesActivas[id] = nil
	notificarCambio(player, perfil.Data, "Misiones")
	return true
end

------------------------------------------------------------------------
-- Diario de subastas (v5). Lo usa AuctionManager: se escribe en el mismo
-- bloque sin pausas en que sale el ítem o el oro, y se cierra al confirmar.
------------------------------------------------------------------------

function DataManager.RegistrarPendienteSubasta(
	player: Player,
	id: string,
	item: ItemInstancia,
	deposito: number
): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	perfil.Data.Pendientes.Subastas[id] = { Item = item, Deposito = deposito, Creado = os.time() }
	return true
end

function DataManager.RegistrarPendienteCompra(player: Player, id: string, precio: number): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	perfil.Data.Pendientes.Compras[id] = { Precio = precio, Creado = os.time() }
	return true
end

function DataManager.QuitarPendiente(player: Player, tipo: "Subastas" | "Compras", id: string)
	local perfil = perfilActivo(player)
	if perfil then
		perfil.Data.Pendientes[tipo][id] = nil
	end
end

-- Diario del banco de hermandad. Igual que el de subastas: se anota en el mismo
-- bloque sin pausas en que sale el ítem o el oro, y se guarda (SaveNowAsync)
-- antes de tocar el banco. Si el servidor se cae, al volver se reconcilia.
function DataManager.RegistrarPendienteBanco(player: Player, id: string, pendiente: Types.PendienteBanco): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	local pendientes = perfil.Data.Pendientes
	local banco: { [string]: Types.PendienteBanco } = pendientes.Banco or {}
	pendientes.Banco = banco
	banco[id] = pendiente
	return true
end

function DataManager.QuitarPendienteBanco(player: Player, id: string)
	local perfil = perfilActivo(player)
	local banco = perfil and perfil.Data.Pendientes.Banco
	if banco then
		banco[id] = nil
	end
end

function DataManager.PendientesBanco(player: Player): { [string]: Types.PendienteBanco }
	local perfil = perfilActivo(player)
	local banco = perfil and perfil.Data.Pendientes.Banco
	return if banco then table.clone(banco) else {}
end

------------------------------------------------------------------------
-- Fase 6.2: boosters, fichas y pack de inicio
------------------------------------------------------------------------

-- Suma `segundos` de booster (si ya hay uno activo, se encadena). Devuelve el nuevo fin.
function DataManager.ExtenderBoosterXp(player: Player, segundos: number): number?
	local perfil = perfilActivo(player)
	if not perfil then
		return nil
	end
	local hasta = math.max(os.time(), perfil.Data.BoosterXpHasta or 0) + segundos
	perfil.Data.BoosterXpHasta = hasta
	notificarCambio(player, perfil.Data, "Ajustes")
	return hasta
end

function DataManager.Fichas(player: Player, tipo: string): number
	local perfil = perfilActivo(player)
	local fichas = perfil and perfil.Data.Fichas
	return if fichas then fichas[tipo] or 0 else 0
end

function DataManager.AgregarFicha(player: Player, tipo: string, cantidad: number): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	local fichas: { [string]: number } = perfil.Data.Fichas or {}
	perfil.Data.Fichas = fichas
	fichas[tipo] = (fichas[tipo] or 0) + cantidad
	notificarCambio(player, perfil.Data, "Ajustes")
	return true
end

function DataManager.UsarFicha(player: Player, tipo: string): boolean
	local perfil = perfilActivo(player)
	local fichas = perfil and perfil.Data.Fichas
	if not perfil or not fichas or (fichas[tipo] or 0) < 1 then
		return false
	end
	fichas[tipo] -= 1
	notificarCambio(player, perfil.Data, "Ajustes")
	return true
end

function DataManager.MarcarPackInicio(player: Player): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	perfil.Data.PackInicio = true
	return true
end

-- Título escrito por el jugador (ya filtrado por quien llama). nil lo borra.
function DataManager.SetTituloPersonalizado(player: Player, texto: string?): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	perfil.Data.TituloPersonalizado = texto
	return true
end

-- ¿Sigue cargado el perfil del jugador? (si se fue, no hay que tocar nada más)
function DataManager.PerfilActivo(player: Player): boolean
	return perfilActivo(player) ~= nil
end

-- Cambia el bando (Violeta, Rojo o Azul). Lo usa BandoManager: este módulo no
-- decide cuándo se puede cambiar, solo lo guarda y avisa.
function DataManager.SetFaccion(player: Player, bando: Types.Bando): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	perfil.Data.Faccion = bando
	player:SetAttribute("Bando", bando)
	notificarCambio(player, perfil.Data, "Faccion")
	return true
end

local VALORES_AJUSTES: { [string]: { [any]: boolean } } = {
	Genero = { Avatar = true, Masculino = true, Femenino = true },
	ChatPosicion = { Izquierda = true, Derecha = true },
	ChatTamano = { Chico = true, Normal = true, Grande = true },
	ChatVisible = { [true] = true, [false] = true },
	CanalVoz = { Proximidad = true, Grupo = true, Hermandad = true, Zona = true },
	Zurdo = { [true] = true, [false] = true },
	TextosCombate = { [true] = true, [false] = true },
	Minimapa = { [true] = true, [false] = true },
}

-- Ajustes numéricos (fracción de la pantalla): posición y tamaño del chat.
local RANGOS_AJUSTES: { [string]: { number } } = {
	ChatX = { 0, 1 },
	ChatY = { 0, 1 },
	ChatAncho = { 0.15, 0.6 },
	ChatAlto = { 0.12, 0.7 },
	EscalaUI = { 0.75, 1.3 },
}

-- Cambia un ajuste del jugador. Valida clave y valor contra una lista cerrada
-- (o un rango, para los numéricos).
function DataManager.SetAjuste(player: Player, clave: string, valor: any): boolean
	local perfil = perfilActivo(player)
	local rango = RANGOS_AJUSTES[clave]
	if perfil and rango then
		if typeof(valor) ~= "number" or valor ~= valor then
			return false
		end
		(perfil.Data.Ajustes :: any)[clave] = math.round(math.clamp(valor, rango[1], rango[2]) * 1000) / 1000
		notificarCambio(player, perfil.Data, "Ajustes")
		return true
	end
	local permitidos = VALORES_AJUSTES[clave]
	if not perfil or not permitidos or not permitidos[valor] then
		return false
	end
	(perfil.Data.Ajustes :: any)[clave] = valor
	notificarCambio(player, perfil.Data, "Ajustes")
	return true
end

function DataManager.SetClase(player: Player, clase: Types.Clase): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	perfil.Data.Clase = clase
	notificarCambio(player, perfil.Data, "Clase")
	return true
end

local SLOTS_EQUIPO: { [string]: Types.SlotEquipo } = {
	Casco = "Casco",
	Pechera = "Pechera",
	ArmaPrincipal = "ArmaPrincipal",
	ArmaSecundaria = "ArmaSecundaria",
	Accesorio1 = "Accesorio1",
	Accesorio2 = "Accesorio2",
	Herramienta = "Herramienta",
}

-- Equipa un ítem del inventario en su slot. Si había otro equipado, pasan a
-- intercambiar lugares (el viejo queda en la ranura del nuevo).
function DataManager.EquiparItem(player: Player, uid: string): (boolean, CodigoError?)
	local perfil = perfilActivo(player)
	if not perfil then
		return false, "DATA_NOT_LOADED"
	end
	local inv = perfil.Data.Inventario
	local claveRanura: string? = nil
	local item: ItemInstancia? = nil
	for i = 1, inv.MaxSlots do
		local clave = tostring(i)
		local candidato = inv.Slots[clave]
		if candidato and candidato.Uid == uid then
			claveRanura, item = clave, candidato
			break
		end
	end
	if not claveRanura or not item then
		return false, "NOT_FOUND"
	end
	local def = ItemCatalog[item.ItemId]
	local slot = def and def.SlotEquipo
	if not def or (def.Tipo ~= "Equipo" and def.Tipo ~= "Herramienta") or not slot then
		return false, "NOT_ALLOWED"
	end
	-- Los accesorios ocupan el primer slot de accesorio libre.
	if
		slot == "Accesorio1"
		and perfil.Data.Equipamiento.Accesorio1 ~= nil
		and perfil.Data.Equipamiento.Accesorio2 == nil
	then
		slot = "Accesorio2"
	end
	local equipamiento = perfil.Data.Equipamiento :: { [string]: ItemInstancia? }
	local anterior = equipamiento[slot]
	equipamiento[slot] = item
	inv.Slots[claveRanura] = anterior :: any
	notificarCambio(player, perfil.Data, "Inventario")
	notificarCambio(player, perfil.Data, "Equipamiento")
	return true, nil
end

-- Saca el ítem de un slot y lo deja en la primera ranura libre del inventario.
function DataManager.DesequiparItem(player: Player, slot: string): (boolean, CodigoError?)
	local perfil = perfilActivo(player)
	if not perfil then
		return false, "DATA_NOT_LOADED"
	end
	if not SLOTS_EQUIPO[slot] then
		return false, "INVALID_ARGS"
	end
	local equipamiento = perfil.Data.Equipamiento :: { [string]: ItemInstancia? }
	local item = equipamiento[slot]
	if not item then
		return false, "NOT_FOUND"
	end
	local inv = perfil.Data.Inventario
	for i = 1, inv.MaxSlots do
		local clave = tostring(i)
		if inv.Slots[clave] == nil then
			inv.Slots[clave] = item
			equipamiento[slot] = nil
			notificarCambio(player, perfil.Data, "Inventario")
			notificarCambio(player, perfil.Data, "Equipamiento")
			return true, nil
		end
	end
	return false, "INVENTORY_FULL"
end

------------------------------------------------------------------------
-- Operaciones de ranuras (inventario, comercio, subastas, crafteo)
-- Todas son síncronas (sin yields): o se aplican completas o no se aplican.
------------------------------------------------------------------------

local function claveValida(inv: Types.Inventario, clave: string): boolean
	local n = tonumber(clave)
	return n ~= nil and n == math.floor(n) and n >= 1 and n <= inv.MaxSlots and tostring(n) == clave
end

function DataManager.ItemEnRanura(player: Player, clave: string): ItemInstancia?
	local perfil = perfilActivo(player)
	if not perfil or not claveValida(perfil.Data.Inventario, clave) then
		return nil
	end
	return perfil.Data.Inventario.Slots[clave]
end

-- Busca un ítem del inventario por Uid. Devuelve (clave de ranura, ítem).
function DataManager.BuscarPorUid(player: Player, uid: string): (string?, ItemInstancia?)
	local perfil = perfilActivo(player)
	if not perfil then
		return nil, nil
	end
	local inv = perfil.Data.Inventario
	for i = 1, inv.MaxSlots do
		local clave = tostring(i)
		local item = inv.Slots[clave]
		if item and item.Uid == uid then
			return clave, item
		end
	end
	return nil, nil
end

function DataManager.RanurasLibres(player: Player): number
	local perfil = perfilActivo(player)
	if not perfil then
		return 0
	end
	local inv = perfil.Data.Inventario
	local libres = 0
	for i = 1, inv.MaxSlots do
		if inv.Slots[tostring(i)] == nil then
			libres += 1
		end
	end
	return libres
end

-- Mueve, combina o intercambia el contenido de dos ranuras.
--   destino vacío            -> mueve
--   mismo ítem apilable      -> combina hasta el máximo (el resto queda en origen)
--   cualquier otro caso      -> intercambia
function DataManager.MoverRanura(player: Player, desde: string, hacia: string): (boolean, CodigoError?)
	local perfil = perfilActivo(player)
	if not perfil then
		return false, "DATA_NOT_LOADED"
	end
	local inv = perfil.Data.Inventario
	if desde == hacia or not claveValida(inv, desde) or not claveValida(inv, hacia) then
		return false, "INVALID_ARGS"
	end
	local origen = inv.Slots[desde]
	if not origen then
		return false, "NOT_FOUND"
	end
	local destino = inv.Slots[hacia]
	if destino == nil then
		inv.Slots[hacia] = origen
		inv.Slots[desde] = nil
	elseif
		destino.ItemId == origen.ItemId
		and destino.Rareza == origen.Rareza
		and destino.Meta == nil
		and origen.Meta == nil
		and maxStackDe(origen.ItemId) > 1
	then
		local espacio = maxStackDe(origen.ItemId) - destino.Cantidad
		if espacio <= 0 then
			inv.Slots[hacia], inv.Slots[desde] = origen, destino
		else
			local pasar = math.min(espacio, origen.Cantidad)
			destino.Cantidad += pasar
			origen.Cantidad -= pasar
			if origen.Cantidad <= 0 then
				inv.Slots[desde] = nil
			end
		end
	else
		inv.Slots[hacia], inv.Slots[desde] = origen, destino
	end
	notificarCambio(player, perfil.Data, "Inventario")
	return true, nil
end

-- Separa `cantidad` unidades de una pila en la primera ranura libre.
function DataManager.DividirPila(player: Player, desde: string, cantidad: number): (boolean, CodigoError?)
	local perfil = perfilActivo(player)
	if not perfil then
		return false, "DATA_NOT_LOADED"
	end
	local inv = perfil.Data.Inventario
	if not claveValida(inv, desde) or not esEnteroPositivo(cantidad) then
		return false, "INVALID_ARGS"
	end
	local origen = inv.Slots[desde]
	if not origen or origen.Cantidad <= cantidad then
		return false, "INVALID_ARGS"
	end
	for i = 1, inv.MaxSlots do
		local clave = tostring(i)
		if inv.Slots[clave] == nil then
			origen.Cantidad -= cantidad
			inv.Slots[clave] = {
				Uid = HttpService:GenerateGUID(false),
				ItemId = origen.ItemId,
				Cantidad = cantidad,
				Rareza = origen.Rareza,
				Meta = copiarMeta(origen.Meta),
			}
			notificarCambio(player, perfil.Data, "Inventario")
			return true, nil
		end
	end
	return false, "INVENTORY_FULL"
end

-- Quita `cantidad` de una ranura y devuelve lo quitado como una instancia
-- (si se quita todo, es la misma instancia con su Uid original).
function DataManager.QuitarDeRanura(player: Player, clave: string, cantidad: number): ItemInstancia?
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) then
		return nil
	end
	local inv = perfil.Data.Inventario
	if not claveValida(inv, clave) then
		return nil
	end
	local item = inv.Slots[clave]
	if not item or item.Cantidad < cantidad then
		return nil
	end
	local quitado: ItemInstancia
	if item.Cantidad == cantidad then
		inv.Slots[clave] = nil
		quitado = item
	else
		item.Cantidad -= cantidad
		quitado = {
			Uid = HttpService:GenerateGUID(false),
			ItemId = item.ItemId,
			Cantidad = cantidad,
			Rareza = item.Rareza,
			Meta = copiarMeta(item.Meta),
		}
	end
	notificarCambio(player, perfil.Data, "Inventario")
	return quitado
end

-- Agrega una instancia existente (conserva Uid y metadatos). Los apilables sin
-- metadatos se combinan con pilas existentes. Todo o nada.
function DataManager.AgregarInstancia(player: Player, item: ItemInstancia): boolean
	local perfil = perfilActivo(player)
	local def = ItemCatalog[item.ItemId]
	if not perfil or not def or not esEnteroPositivo(item.Cantidad) then
		return false
	end
	if def.Apilable and item.Meta == nil then
		local ok = DataManager.AddItem(player, item.ItemId, item.Cantidad, item.Rareza, nil)
		return ok
	end
	local inv = perfil.Data.Inventario
	for i = 1, inv.MaxSlots do
		local clave = tostring(i)
		if inv.Slots[clave] == nil then
			inv.Slots[clave] = item
			notificarCambio(player, perfil.Data, "Inventario")
			return true
		end
	end
	return false
end

-- Ranuras que haría falta para recibir estas instancias (cálculo conservador:
-- los apilables pueden necesitar menos si se combinan).
function DataManager.RanurasNecesarias(items: { ItemInstancia }): number
	local total = 0
	for _, item in items do
		local maxStack = maxStackDe(item.ItemId)
		total += if maxStack > 1 and item.Meta == nil then math.ceil(item.Cantidad / maxStack) else 1
	end
	return total
end

------------------------------------------------------------------------
-- Profesiones
------------------------------------------------------------------------

function DataManager.NivelProfesion(player: Player, profesion: string): number
	local perfil = perfilActivo(player)
	local progreso = perfil and perfil.Data.Profesiones[profesion]
	return if progreso then progreso.Nivel else 1
end

-- Suma XP de profesión. `xpPorNivel(n)` da la XP necesaria para pasar de n a n+1.
-- Devuelve los niveles ganados.
function DataManager.AddXpProfesion(
	player: Player,
	profesion: string,
	cantidad: number,
	nivelMaximo: number,
	xpPorNivel: (number) -> number
): number
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(cantidad) then
		return 0
	end
	local progreso = perfil.Data.Profesiones[profesion]
	if not progreso then
		progreso = { Nivel = 1, Xp = 0 }
		perfil.Data.Profesiones[profesion] = progreso
	end
	if progreso.Nivel >= nivelMaximo then
		return 0
	end
	progreso.Xp += cantidad
	local ganados = 0
	while progreso.Nivel < nivelMaximo and progreso.Xp >= xpPorNivel(progreso.Nivel) do
		progreso.Xp -= xpPorNivel(progreso.Nivel)
		progreso.Nivel += 1
		ganados += 1
	end
	if progreso.Nivel >= nivelMaximo then
		progreso.Xp = 0
	end
	notificarCambio(player, perfil.Data, "Profesiones")
	return ganados
end

-- Marca el kit inicial como entregado. Devuelve false si ya se había entregado.
function DataManager.MarcarKitInicial(player: Player): boolean
	local perfil = perfilActivo(player)
	if not perfil or perfil.Data.KitInicialEntregado then
		return false
	end
	perfil.Data.KitInicialEntregado = true
	return true
end

-- Cambia la cantidad de ranuras (pase de extensión de inventario).
-- Nunca reduce por debajo de una ranura ocupada.
function DataManager.SetMaxSlots(player: Player, maxSlots: number): boolean
	local perfil = perfilActivo(player)
	if not perfil or not esEnteroPositivo(maxSlots) then
		return false
	end
	local inv = perfil.Data.Inventario
	for clave in inv.Slots do
		local indice = tonumber(clave)
		if indice and indice > maxSlots then
			return false
		end
	end
	inv.MaxSlots = maxSlots
	notificarCambio(player, perfil.Data, "Inventario")
	return true
end

-- Reemplaza los metadatos de un equipo de la mochila (re-roll).
function DataManager.SetMetaRanura(player: Player, clave: string, meta: Types.ItemMeta?): boolean
	local perfil = perfilActivo(player)
	if not perfil or not claveValida(perfil.Data.Inventario, clave) then
		return false
	end
	local item = perfil.Data.Inventario.Slots[clave]
	if not item then
		return false
	end
	item.Meta = meta
	notificarCambio(player, perfil.Data, "Inventario")
	return true
end

-- Cambio directo del perfil para los sistemas de la Fase 6.3 (pase de batalla,
-- mascotas, apariencias, códigos), cuyos campos son opcionales. `cambiar` NO
-- debe pausar (sin yields): corre en el mismo bloque que el resto del cambio.
-- Devuelve false si el perfil no está activo.
-- Recarga larga de una habilidad (nil = borrarla). No se manda al cliente:
-- el combate le avisa por su lado.
function DataManager.SetCooldownLargo(player: Player, id: string, hasta: number?)
	local perfil = perfilActivo(player)
	if not perfil then
		return
	end
	local mapa: { [string]: number } = perfil.Data.CooldownsLargos or {}
	perfil.Data.CooldownsLargos = mapa
	if hasta then
		mapa[id] = hasta
	else
		mapa[id] = nil
	end
	-- Limpieza: fuera las que ya vencieron.
	local ahora = Workspace:GetServerTimeNow()
	for otro, t in mapa do
		if t <= ahora then
			mapa[otro] = nil
		end
	end
end

function DataManager.Mutar(player: Player, seccion: Types.SeccionDatos, cambiar: (Types.DatosJugador) -> ()): boolean
	local perfil = perfilActivo(player)
	if not perfil then
		return false
	end
	cambiar(perfil.Data)
	notificarCambio(player, perfil.Data, seccion)
	return true
end

return DataManager
