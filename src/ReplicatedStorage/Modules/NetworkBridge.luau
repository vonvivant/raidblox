--!strict
-- NetworkBridge: única puerta de entrada/salida de red del juego.
--
-- * El servidor crea todos los remotes (el cliente nunca los crea).
-- * Cada petición del cliente pasa por rate limiting por jugador y por remote.
-- * Las RemoteFunctions devuelven siempre una Respuesta { Success, ErrorCode, Data }
--   y cortan a los 5 segundos con ErrorCode = "TIMEOUT".
-- * Guard trae validadores para tratar todo argumento del cliente como hostil.
--
-- Uso en servidor:
--   NetworkBridge.Server.Init()
--   NetworkBridge.Server.OnEvent("UsarItem", function(player, slot) ... end)
--   NetworkBridge.Server.OnInvoke("SolicitarDatos", function(player) return NetworkBridge.Ok(datos) end)
-- Uso en cliente:
--   NetworkBridge.Client.Fire("UsarItem", 3)
--   local respuesta = NetworkBridge.Client.Invoke("SolicitarDatos")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Shared.Types)
local GameConfig = require(script.Parent.Parent.Configs.GameConfig)

type Respuesta = Types.Respuesta
type CodigoError = Types.CodigoError

type TipoRemote = "Event" | "Function"
type Definicion = {
	Tipo: TipoRemote,
	Critico: boolean, -- críticos: 10 req/s; normales: límite más bajo
	SoloServidorACliente: boolean?, -- el cliente nunca debería dispararlo
	Timeout: number?, -- RemoteFunctions lentas (DataStore): segundos; por defecto GameConfig.Red.TimeoutInvoke
}

-- Registro central de remotes. Agregar acá cada remote nuevo de las próximas fases.
local DEFINICIONES: { [string]: Definicion } = {
	-- Servidor -> cliente
	DatosIniciales = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (snapshot completo)
	DataSync = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (seccion, valor)
	Notificacion = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (texto, tipo)
	TeleportEstado = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (estado, nombreZona, mensaje?)
	GuerraEstado = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (snapshot de la partida)
	GuerraCarga = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (recursos que lleva el jugador)
	-- Cliente -> servidor
	SolicitarDatos = { Tipo = "Function", Critico = false },
	-- Fase 4: inventario
	MoverItem = { Tipo = "Event", Critico = true }, -- (desde, hacia)
	UsarItem = { Tipo = "Event", Critico = true }, -- (ranura)
	DividirPila = { Tipo = "Event", Critico = true }, -- (desde, cantidad)
	DestruirItem = { Tipo = "Function", Critico = false }, -- (ranura)
	-- Fase 4: crafteo y recolección
	CraftearIniciar = { Tipo = "Function", Critico = false }, -- (recetaId)
	CrafteoAbrir = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (estacion)
	CrafteoEstado = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (estado)
	MinijuegoRecoleccion = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (datos)
	RecoleccionGolpe = { Tipo = "Event", Critico = true }, -- (token, horaServidorVistaPorElCliente)
	-- Pruebas: NPCs de oro y materiales (solo con Pruebas.Activas())
	TiendaPruebaAbrir = { Tipo = "Event", Critico = false, SoloServidorACliente = true },
	TiendaPruebaComprar = { Tipo = "Function", Critico = false }, -- (itemId, cantidad)
	-- Fase 4: Casa de Subastas
	SubastaAbrir = { Tipo = "Event", Critico = false, SoloServidorACliente = true },
	SubastaBuscar = { Tipo = "Function", Critico = false, Timeout = 10 }, -- (texto, rareza)
	SubastaPublicar = { Tipo = "Function", Critico = false, Timeout = 25 }, -- (uid, precio)
	SubastaComprar = { Tipo = "Function", Critico = false, Timeout = 25 }, -- (id)
	SubastaCancelar = { Tipo = "Function", Critico = false, Timeout = 20 }, -- (id)
	SubastaMias = { Tipo = "Function", Critico = false, Timeout = 30 },
	-- Fase 4: comercio 1v1
	ComercioSolicitar = { Tipo = "Event", Critico = false }, -- (jugador)
	ComercioResponder = { Tipo = "Event", Critico = false }, -- (jugador, acepta)
	ComercioOfertar = { Tipo = "Event", Critico = false }, -- (uids, oro)
	ComercioBloquear = { Tipo = "Event", Critico = false },
	ComercioConfirmar = { Tipo = "Event", Critico = false },
	ComercioCancelar = { Tipo = "Event", Critico = false },
	ComercioInvitacion = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (jugador)
	ComercioEstado = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (estado)
	-- Fase 3: combate y botín
	UsarHabilidad = { Tipo = "Event", Critico = true }, -- (indice 1..4, modeloObjetivo?)
	Parry = { Tipo = "Event", Critico = true },
	RecogerBotin = { Tipo = "Event", Critico = true }, -- (idBotin)
	ElegirClase = { Tipo = "Function", Critico = false }, -- (clase)
	EquiparItem = { Tipo = "Function", Critico = false }, -- (uid)
	DesequiparItem = { Tipo = "Function", Critico = false }, -- (slot)
	CombateEvento = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (tipo, modelo, valor, extra)
	HabilidadEstado = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (estado de cooldown/casteo)
	RaidBloxEstado = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (barra del jefe)
	AnuncioGlobal = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (texto, color)
	BotinSoltado = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (id, posicion, info)
	BotinRetirado = { Tipo = "Event", Critico = false, SoloServidorACliente = true }, -- (id)
}

local NOMBRE_CARPETA = "Remotes"

local NetworkBridge = {}

------------------------------------------------------------------------
-- Respuestas estándar
------------------------------------------------------------------------

function NetworkBridge.Ok(data: any?): Respuesta
	return { Success = true, ErrorCode = nil, Data = data }
end

function NetworkBridge.Fail(codigo: CodigoError): Respuesta
	return { Success = false, ErrorCode = codigo, Data = nil }
end

------------------------------------------------------------------------
-- Guard: validación de argumentos del cliente. Devuelven el valor ya
-- tipado o nil si no es válido. Siempre validar antes de usar.
------------------------------------------------------------------------

local Guard = {}
NetworkBridge.Guard = Guard

-- Número finito (rechaza NaN, inf, -inf) dentro de [min, max].
function Guard.Number(valor: unknown, min: number, max: number): number?
	if typeof(valor) ~= "number" then
		return nil
	end
	local n = valor :: number
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	if n < min or n > max then
		return nil
	end
	return n
end

-- Entero dentro de [min, max].
function Guard.Integer(valor: unknown, min: number, max: number): number?
	local n = Guard.Number(valor, min, max)
	if n == nil or n ~= math.floor(n) then
		return nil
	end
	return n
end

-- Texto no vacío de hasta maxLargo caracteres.
function Guard.String(valor: unknown, maxLargo: number): string?
	if typeof(valor) ~= "string" then
		return nil
	end
	local s = valor :: string
	if #s == 0 or #s > maxLargo then
		return nil
	end
	return s
end

function Guard.Boolean(valor: unknown): boolean?
	if typeof(valor) ~= "boolean" then
		return nil
	end
	return valor :: boolean
end

-- Texto que tiene que ser una de las claves permitidas (ej. ids de catálogo).
function Guard.OneOf<V>(valor: unknown, permitidos: { [string]: V }): string?
	if typeof(valor) ~= "string" then
		return nil
	end
	local s = valor :: string
	if permitidos[s] == nil then
		return nil
	end
	return s
end

-- Instance de la clase indicada que sigue existiendo en el juego.
function Guard.InstanceOf(valor: unknown, clase: string): Instance?
	if typeof(valor) ~= "Instance" then
		return nil
	end
	local inst = valor :: Instance
	if not inst:IsA(clase) or not inst:IsDescendantOf(game) then
		return nil
	end
	return inst
end

------------------------------------------------------------------------
-- Ejecución con timeout
------------------------------------------------------------------------

-- Corre fn en un hilo aparte y espera como mucho `timeout` segundos.
-- Devuelve (true, resultado) si terminó bien, (false, codigo) si falló o se pasó.
-- Ojo: un handler que se pasa del tiempo sigue corriendo en segundo plano;
-- por eso los handlers tienen que volver a validar el estado antes de mutar.
local function ejecutarConTimeout<R>(timeout: number, fn: () -> R): (boolean, R | CodigoError)
	local hilo = coroutine.running()
	local listo = false -- ya hay resultado (éxito, error o timeout)
	local esperando = false -- el hilo que llamó está suspendido esperando
	local exito = false
	local valor: any = nil

	local function terminar(ok: boolean, resultado: any)
		if listo then
			return
		end
		listo = true
		exito = ok
		valor = resultado
		-- Solo se reanuda si el que llamó ya está suspendido. Si fn terminó sin
		-- ceder el control, el que llamó todavía no cedió y lee el resultado directo.
		if esperando and coroutine.status(hilo) == "suspended" then
			task.spawn(hilo)
		end
	end

	task.spawn(function()
		local ok, resultado = pcall(fn)
		if not ok then
			warn(`[NetworkBridge] Error en handler: {resultado}`)
			terminar(false, "INTERNAL_ERROR")
		else
			terminar(true, resultado)
		end
	end)

	if not listo then
		task.delay(timeout, function()
			terminar(false, "TIMEOUT")
		end)
		esperando = true
		coroutine.yield()
	end
	return exito, valor
end

local function definicionDe(nombre: string): Definicion
	local def = DEFINICIONES[nombre]
	assert(def, `[NetworkBridge] Remote no registrado: {nombre}`)
	return def
end

------------------------------------------------------------------------
-- SERVIDOR
------------------------------------------------------------------------

local Server = {}
NetworkBridge.Server = Server

type Balde = { tokens: number, ultimo: number }
local baldes: { [Player]: { [string]: Balde } } = {}
local infracciones: { [Player]: { cantidad: number, ultimoAviso: number } } = {}
local remotesServidor: { [string]: RemoteEvent | RemoteFunction } = {}
local inicializado = false

-- Token bucket: rate = tokens recuperados por segundo, burst = máximo acumulable.
local function permitir(player: Player, nombre: string, critico: boolean): boolean
	local rate = if critico then GameConfig.Red.RateCritico else GameConfig.Red.RateNormal
	local burst = if critico then GameConfig.Red.BurstCritico else GameConfig.Red.BurstNormal
	local ahora = os.clock()

	if player.Parent ~= Players then
		return false -- ya se fue: no crear estado que nunca se limpiaría
	end
	local delJugador = baldes[player]
	if not delJugador then
		delJugador = {}
		baldes[player] = delJugador
	end
	local balde = delJugador[nombre]
	if not balde then
		balde = { tokens = burst, ultimo = ahora }
		delJugador[nombre] = balde
	end

	balde.tokens = math.min(burst, balde.tokens + (ahora - balde.ultimo) * rate)
	balde.ultimo = ahora
	if balde.tokens < 1 then
		-- Registro con aviso limitado a uno cada 10s por jugador. No se banea
		-- automáticamente: el lag de móviles también dispara ráfagas.
		local reg = infracciones[player]
		if not reg then
			reg = { cantidad = 0, ultimoAviso = 0 }
			infracciones[player] = reg
		end
		reg.cantidad += 1
		if ahora - reg.ultimoAviso > 10 then
			reg.ultimoAviso = ahora
			warn(`[NetworkBridge] Rate limit: {player.Name} ({player.UserId}) en {nombre}, total {reg.cantidad}`)
		end
		return false
	end
	balde.tokens -= 1
	return true
end

function Server.Init()
	assert(RunService:IsServer(), "NetworkBridge.Server.Init solo en servidor")
	if inicializado then
		return
	end
	inicializado = true

	local carpeta = ReplicatedStorage:FindFirstChild(NOMBRE_CARPETA)
	if carpeta then
		carpeta:Destroy() -- evita remotes viejos o insertados a mano
	end
	local nueva = Instance.new("Folder")
	nueva.Name = NOMBRE_CARPETA

	for nombre, def in DEFINICIONES do
		if def.Tipo == "Event" then
			local remote = Instance.new("RemoteEvent")
			remote.Name = nombre
			remote.Parent = nueva
			remotesServidor[nombre] = remote
			if def.SoloServidorACliente then
				-- Sin un listener, los FireServer de un exploiter se acumulan en cola.
				remote.OnServerEvent:Connect(function() end)
			end
		else
			local remote = Instance.new("RemoteFunction")
			remote.Name = nombre
			remote.Parent = nueva
			remotesServidor[nombre] = remote
		end
	end
	nueva.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player: Player)
		baldes[player] = nil
		infracciones[player] = nil
	end)
end

local function remoteEventServidor(nombre: string): RemoteEvent
	local def = definicionDe(nombre)
	assert(def.Tipo == "Event", `[NetworkBridge] {nombre} no es un RemoteEvent`)
	local remote = remotesServidor[nombre]
	assert(remote and remote:IsA("RemoteEvent"), "NetworkBridge.Server.Init() no se llamó")
	return remote
end

-- Escucha un RemoteEvent. Los argumentos llegan como `unknown`: validalos con Guard.
function Server.OnEvent(nombre: string, handler: (Player, ...unknown) -> ())
	local def = definicionDe(nombre)
	local remote = remoteEventServidor(nombre)
	remote.OnServerEvent:Connect(function(player: Player, ...: unknown)
		if not permitir(player, nombre, def.Critico) then
			return
		end
		local ok, err = pcall(function(...: unknown): nil
			handler(player, ...)
			return nil
		end, ...)
		if not ok then
			warn(`[NetworkBridge] Error en {nombre} de {player.Name}: {err}`)
		end
	end)
end

-- Responde una RemoteFunction. El handler devuelve una Respuesta (usar Ok/Fail).
function Server.OnInvoke(nombre: string, handler: (Player, ...unknown) -> Respuesta)
	local def = definicionDe(nombre)
	assert(def.Tipo == "Function", `[NetworkBridge] {nombre} no es una RemoteFunction`)
	local remote = remotesServidor[nombre]
	assert(remote and remote:IsA("RemoteFunction"), "NetworkBridge.Server.Init() no se llamó")

	remote.OnServerInvoke = function(player: Player, ...: unknown): Respuesta
		if not permitir(player, nombre, def.Critico) then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		local args = table.pack(...)
		local ok, resultado = ejecutarConTimeout(def.Timeout or GameConfig.Red.TimeoutInvoke, function(): Respuesta
			return handler(player, table.unpack(args, 1, args.n))
		end)
		if ok then
			return resultado :: Respuesta
		end
		return NetworkBridge.Fail(resultado :: CodigoError)
	end
end

function Server.FireClient(nombre: string, player: Player, ...: any)
	remoteEventServidor(nombre):FireClient(player, ...)
end

function Server.FireAll(nombre: string, ...: any)
	remoteEventServidor(nombre):FireAllClients(...)
end

function Server.FireList(nombre: string, jugadores: { Player }, ...: any)
	local remote = remoteEventServidor(nombre)
	for _, player in jugadores do
		remote:FireClient(player, ...)
	end
end

------------------------------------------------------------------------
-- CLIENTE
------------------------------------------------------------------------

local Client = {}
NetworkBridge.Client = Client

local remotesCliente: { [string]: RemoteEvent | RemoteFunction } = {}

local function remoteCliente(nombre: string): RemoteEvent | RemoteFunction
	local cache = remotesCliente[nombre]
	if cache then
		return cache
	end
	definicionDe(nombre)
	local carpeta = ReplicatedStorage:WaitForChild(NOMBRE_CARPETA)
	local remote = carpeta:WaitForChild(nombre)
	assert(remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction"), `[NetworkBridge] {nombre} no es un remote`)
	local tipado = remote :: RemoteEvent | RemoteFunction
	remotesCliente[nombre] = tipado
	return tipado
end

function Client.Fire(nombre: string, ...: any)
	local remote = remoteCliente(nombre)
	assert(remote:IsA("RemoteEvent"), `[NetworkBridge] {nombre} no es un RemoteEvent`)
	remote:FireServer(...)
end

function Client.OnEvent(nombre: string, handler: (...any) -> ()): RBXScriptConnection
	local remote = remoteCliente(nombre)
	assert(remote:IsA("RemoteEvent"), `[NetworkBridge] {nombre} no es un RemoteEvent`)
	return remote.OnClientEvent:Connect(handler)
end

-- Pide algo al servidor. Nunca tira error: siempre devuelve una Respuesta.
function Client.Invoke(nombre: string, ...: any): Respuesta
	local remote = remoteCliente(nombre)
	assert(remote:IsA("RemoteFunction"), `[NetworkBridge] {nombre} no es una RemoteFunction`)
	local args = table.pack(...)
	-- Margen extra sobre el timeout del servidor para el viaje de ida y vuelta.
	local def = definicionDe(nombre)
	local ok, resultado = ejecutarConTimeout((def.Timeout or GameConfig.Red.TimeoutInvoke) + 2, function(): any
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return NetworkBridge.Fail(resultado :: CodigoError)
	end
	if typeof(resultado) ~= "table" then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	return resultado :: Respuesta
end

return NetworkBridge
