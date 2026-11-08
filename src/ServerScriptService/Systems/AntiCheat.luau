--!strict
-- AntiCheat: detección de movimiento imposible en el servidor.
--
-- El cliente simula su propio personaje, así que speedhack y vuelo no se
-- pueden impedir del todo: se detectan y se corrigen. Lo valioso (oro, ítems,
-- daño) ya está protegido porque el servidor valida distancias en cada acción.
--
-- Todo se decide con lo que el SERVIDOR observa (posiciones muestreadas y
-- raycasts). Velocidad, FloorMaterial y estado del Humanoid los reporta el
-- cliente dueño del personaje, así que un exploit puede falsearlos.
--
-- * Speedhack: cada segundo compara la distancia horizontal recorrida con la
--   velocidad permitida (+ margen por latencia). Si se pasa, rubberbanding:
--   vuelve a la última posición válida.
-- * Vuelo/levitación: si pasa más de 3 s lejos del suelo sin bajar (según las
--   posiciones observadas) y sin montura/vuelo legítimo, vuelve al último
--   punto apoyado. Tras varias infracciones seguidas, respawn forzado.
-- * Nunca banea automáticamente: solo registra.
--
-- Otros sistemas deben avisar cuando mueven al jugador a propósito:
--   AntiCheat.Gracia(player, segundos)         -- teleports, empujones, dashes
--   AntiCheat.SetVelocidadPermitida(player, n) -- monturas, buffs de velocidad
--   player:SetAttribute("Montado", true)       -- montura activa (exime del chequeo de vuelo)
--   player:SetAttribute("Volando", true)       -- vuelo legítimo (habilidad, evento)
-- Los atributos que pone el cliente no se replican al servidor, así que no los puede falsear.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local Signal = require(ReplicatedStorage.Modules.Signal)

local CFG = GameConfig.AntiCheat

type TipoInfraccion = "Velocidad" | "Vuelo"

type Estado = {
	ultimaPosValida: Vector3?,
	ultimaPosSuelo: Vector3?,
	ultimaY: number?,
	ultimaMuestra: number,
	graciaHasta: number,
	velocidadExtra: number?, -- velocidad permitida fijada por otro sistema
	tiempoEnAire: number,
	strikesVuelo: { number }, -- timestamps de infracciones recientes
	totalInfracciones: number,
	conexiones: { RBXScriptConnection },
}

local AntiCheat = {}

-- Se dispara en cada infracción detectada (para logs, Discord, panel admin).
AntiCheat.Infraccion = Signal.new() :: Signal.Signal<Player, TipoInfraccion, string>

local estados: { [Player]: Estado } = {}
local iniciado = false

-- Devuelve el estado o nil si el jugador ya no está (no crea estado huérfano).
local function estadoDe(player: Player): Estado?
	local estado = estados[player]
	if not estado and player.Parent == Players then
		estado = {
			ultimaPosValida = nil,
			ultimaPosSuelo = nil,
			ultimaY = nil,
			ultimaMuestra = os.clock(),
			graciaHasta = 0,
			velocidadExtra = nil,
			tiempoEnAire = 0,
			strikesVuelo = {},
			totalInfracciones = 0,
			conexiones = {},
		}
		estados[player] = estado
	end
	return estado
end

local function partesDelPersonaje(player: Player): (Model?, BasePart?, Humanoid?)
	local personaje = player.Character
	if not personaje then
		return nil, nil, nil
	end
	local raiz = personaje:FindFirstChild("HumanoidRootPart")
	local humanoid = personaje:FindFirstChildOfClass("Humanoid")
	if not raiz or not raiz:IsA("BasePart") or not humanoid then
		return nil, nil, nil
	end
	return personaje, raiz, humanoid
end

------------------------------------------------------------------------
-- API para otros sistemas
------------------------------------------------------------------------

-- Suspende los chequeos durante `segundos` (teleports, knockbacks, dashes).
function AntiCheat.Gracia(player: Player, segundos: number)
	local estado = estadoDe(player)
	if not estado then
		return
	end
	estado.graciaHasta = math.max(estado.graciaHasta, os.clock() + segundos)
	estado.ultimaPosValida = nil
	estado.ultimaPosSuelo = nil -- no devolverlo a un punto de antes del teleport
	estado.ultimaY = nil
	estado.tiempoEnAire = 0
end

-- Fija una velocidad máxima permitida mayor a la del Humanoid (montura +15%,
-- buffs). nil vuelve al valor normal.
function AntiCheat.SetVelocidadPermitida(player: Player, velocidad: number?)
	local estado = estadoDe(player)
	if estado then
		estado.velocidadExtra = velocidad
	end
end

------------------------------------------------------------------------
-- Correcciones
------------------------------------------------------------------------

local function registrar(player: Player, estado: Estado, tipo: TipoInfraccion, detalle: string)
	estado.totalInfracciones += 1
	warn(`[AntiCheat] {tipo} - {player.Name} ({player.UserId}): {detalle} [total {estado.totalInfracciones}]`)
	AntiCheat.Infraccion:Fire(player, tipo, detalle)
end

local function devolverA(raiz: BasePart, posicion: Vector3)
	raiz.AssemblyLinearVelocity = Vector3.zero
	-- Mantiene la orientación actual, solo corrige la posición.
	raiz.CFrame = CFrame.new(posicion) * raiz.CFrame.Rotation
end

------------------------------------------------------------------------
-- Observación del entorno (todo calculado por el servidor)
------------------------------------------------------------------------

local paramsRayo = RaycastParams.new()
paramsRayo.FilterType = Enum.RaycastFilterType.Exclude
paramsRayo.IgnoreWater = false

type Suelo = {
	altura: number, -- distancia hasta el suelo (math.huge si no hay nada cerca)
	parte: BasePart?, -- parte sobre la que está parado
}

local function observarSuelo(raiz: BasePart, personaje: Model): Suelo
	paramsRayo.FilterDescendantsInstances = { personaje }
	local alcance = CFG.AlturaMinimaSospechosa * 3
	local resultado = Workspace:Raycast(raiz.Position, Vector3.new(0, -alcance, 0), paramsRayo)
	if not resultado then
		return { altura = math.huge, parte = nil }
	end
	local parte = resultado.Instance
	return {
		altura = (raiz.Position - resultado.Position).Magnitude,
		parte = if parte:IsA("BasePart") then parte else nil,
	}
end

-- Plataformas móviles y vehículos arrastran al jugador más rápido que su WalkSpeed.
local function sobrePlataformaMovil(suelo: Suelo): boolean
	local parte = suelo.parte
	if not parte or suelo.altura > CFG.AlturaEnSuelo then
		return false
	end
	return not parte.Anchored or parte.AssemblyLinearVelocity.Magnitude > 1
end

local paramsCerca = OverlapParams.new()
paramsCerca.FilterType = Enum.RaycastFilterType.Exclude

-- Escaleras y trusses: el estado Climbing lo reporta el cliente, así que solo
-- se acepta si además hay algo sólido pegado al personaje donde trepar.
local function trepandoDeVerdad(raiz: BasePart, humanoid: Humanoid): boolean
	if humanoid:GetState() ~= Enum.HumanoidStateType.Climbing then
		return false
	end
	local personaje = raiz:FindFirstAncestorWhichIsA("Model")
	paramsCerca.FilterDescendantsInstances = if personaje then { personaje } else {}
	return #Workspace:GetPartBoundsInRadius(raiz.Position, 3, paramsCerca) > 0
end

------------------------------------------------------------------------
-- Chequeos
------------------------------------------------------------------------

local function chequearVelocidad(
	player: Player,
	estado: Estado,
	raiz: BasePart,
	humanoid: Humanoid,
	suelo: Suelo,
	dt: number
)
	local posActual = raiz.Position
	local anterior = estado.ultimaPosValida

	-- Sentado (asientos, vehículos) o sobre algo que se mueve: no se mide.
	if anterior == nil or humanoid.SeatPart ~= nil or sobrePlataformaMovil(suelo) then
		estado.ultimaPosValida = posActual
		return
	end

	-- Solo distancia horizontal: caer rápido es legítimo.
	local delta = posActual - anterior
	local distancia = Vector3.new(delta.X, 0, delta.Z).Magnitude

	-- humanoid.WalkSpeed leído en el servidor es el valor que fijó el servidor;
	-- si el exploit lo cambia en su cliente, acá no se ve.
	local velocidad = math.max(humanoid.WalkSpeed, CFG.VelocidadBase, estado.velocidadExtra or 0)
	local permitida = velocidad * dt * CFG.MultiplicadorTolerancia + CFG.ToleranciaFijaStuds

	if distancia > permitida then
		registrar(
			player,
			estado,
			"Velocidad",
			`recorrió {math.floor(distancia)} studs en {string.format("%.2f", dt)}s (máx {math.floor(permitida)})`
		)
		devolverA(raiz, anterior)
		return
	end
	estado.ultimaPosValida = posActual
end

local function chequearVuelo(
	player: Player,
	estado: Estado,
	raiz: BasePart,
	humanoid: Humanoid,
	suelo: Suelo,
	dt: number
)
	local posActual = raiz.Position
	local yAnterior = estado.ultimaY
	estado.ultimaY = posActual.Y

	-- Cerca del suelo: punto seguro para devolverlo más adelante.
	if suelo.altura <= CFG.AlturaEnSuelo then
		estado.ultimaPosSuelo = posActual
	end

	local exento = player:GetAttribute("Montado") == true
		or player:GetAttribute("Volando") == true
		or humanoid.SeatPart ~= nil
		or trepandoDeVerdad(raiz, humanoid)

	-- Cayendo según las posiciones que vio el servidor (no la velocidad reportada).
	local cayendo = yAnterior ~= nil and (yAnterior - posActual.Y) >= CFG.CaidaMinimaPorSegundo * dt
	local lejosDelSuelo = suelo.altura >= CFG.AlturaMinimaSospechosa

	if exento or cayendo or not lejosDelSuelo then
		estado.tiempoEnAire = 0
		return
	end

	estado.tiempoEnAire += dt
	if estado.tiempoEnAire < CFG.TiempoMaxEnAire then
		return
	end

	-- Infracción de vuelo.
	estado.tiempoEnAire = 0
	local ahora = os.clock()
	local recientes: { number } = {}
	for _, t in estado.strikesVuelo do
		if ahora - t < CFG.VentanaStrikes then
			table.insert(recientes, t)
		end
	end
	table.insert(recientes, ahora)
	estado.strikesVuelo = recientes

	registrar(
		player,
		estado,
		"Vuelo",
		`suspendido más de {CFG.TiempoMaxEnAire}s ({#recientes} en {CFG.VentanaStrikes}s)`
	)

	local destino = estado.ultimaPosSuelo
	if #recientes >= CFG.StrikesParaReaparecer or destino == nil then
		estado.strikesVuelo = {}
		task.spawn(player.LoadCharacterAsync, player) -- respawn forzado (CharacterAdded da gracia)
	else
		devolverA(raiz, destino)
		estado.ultimaPosValida = destino
		estado.ultimaY = destino.Y
	end
end

local function muestrear(): nil
	local ahora = os.clock()
	for _, player in Players:GetPlayers() do
		local estado = estadoDe(player)
		if not estado then
			continue
		end
		local dt = ahora - estado.ultimaMuestra
		estado.ultimaMuestra = ahora

		local personaje, raiz, humanoid = partesDelPersonaje(player)
		if not personaje or not raiz or not humanoid or humanoid.Health <= 0 then
			estado.ultimaPosValida = nil
			estado.ultimaY = nil
			continue
		end
		if ahora < estado.graciaHasta then
			estado.ultimaPosValida = raiz.Position
			estado.ultimaY = raiz.Position.Y
			continue
		end

		local suelo = observarSuelo(raiz, personaje)
		chequearVelocidad(player, estado, raiz, humanoid, suelo, dt)
		chequearVuelo(player, estado, raiz, humanoid, suelo, dt)
	end
	return nil
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

local function alEntrar(player: Player)
	local estado = estadoDe(player)
	if not estado then
		return
	end
	table.insert(
		estado.conexiones,
		player.CharacterAdded:Connect(function()
			AntiCheat.Gracia(player, CFG.GraciaTrasReaparecer)
		end)
	)
	if player.Character then
		AntiCheat.Gracia(player, CFG.GraciaTrasReaparecer)
	end
end

function AntiCheat.Init()
	assert(not iniciado, "AntiCheat.Init() se llamó dos veces")
	iniciado = true

	for _, player in Players:GetPlayers() do
		alEntrar(player)
	end
	Players.PlayerAdded:Connect(alEntrar)
	Players.PlayerRemoving:Connect(function(player: Player)
		local estado = estados[player]
		if estado then
			for _, conexion in estado.conexiones do
				conexion:Disconnect()
			end
		end
		estados[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(CFG.IntervaloMuestreo)
			local ok, err = pcall(muestrear)
			if not ok then
				warn(`[AntiCheat] Error en muestreo: {err}`)
			end
		end
	end)
end

return AntiCheat
