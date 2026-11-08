--!strict
-- ZoneManager: portales entre zonas/reinos con TeleportService.
--
-- Flujo de un portal:
--   1. El jugador toca un Part con tag "Portal" (atributo "Destino" = id de zona).
--   2. El servidor valida distancia, que no haya otro teleport en curso y el nivel mínimo.
--   3. Avisa al cliente para que muestre la pantalla de carga temática.
--   4. Fuerza un guardado (DataManager.SaveNowAsync) y teletransporta.
--   5. Si falla, reintenta con espera creciente y, si se agotan los intentos,
--      cierra la pantalla de carga y muestra un mensaje amigable.
--
-- El nivel mínimo se vuelve a validar AL LLEGAR: un cliente puede iniciar un
-- teleport por su cuenta a cualquier place de la experiencia, así que el place
-- de destino es el que tiene la última palabra.
--
-- El TeleportData lo puede tocar el cliente: solo se usa para elegir entre
-- puntos de llegada válidos del place, nunca para nada importante.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Pruebas = require(game:GetService("ReplicatedStorage").Modules.Pruebas)
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ZoneConfig = require(ReplicatedStorage.Configs.ZoneConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.DataManager)
local AntiCheat = require(script.Parent.AntiCheat)

local TAG_PORTAL = "Portal"
local ESPERA_ENTRE_PORTALES = 3 -- segundos de antirrebote por jugador
local MARGEN_DISTANCIA_PORTAL = 12 -- studs extra sobre el tamaño del portal
local LIMITE_TELEPORT = 60 -- segundos: si no se resolvió, se cancela (watchdog)
local DISTANCIA_EMPUJE = 14 -- studs que se aleja al jugador del portal tras rechazo o simulación

type Intento = {
	id: number,
	zonaId: string,
	spawnId: string?,
	portal: BasePart?,
	numero: number,
	esperandoResultado: boolean, -- hay un TeleportAsync en vuelo
}

local ZoneManager = {}

local intentos: { [Player]: Intento } = {} -- teleports en curso
local ultimoPortal: { [Player]: number } = {}
local portalesRegistrados: { [BasePart]: boolean } = {}
local contadorIntentos = 0
local iniciado = false

local function notificar(player: Player, texto: string)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, "Zona")
end

local function simulando(): boolean
	return RunService:IsStudio() and ZoneConfig.SimularEnStudio
end

-- Zona que corresponde a este place (nil si el place no está en ZoneConfig).
local function zonaDeEstePlace(): (string?, ZoneConfig.Zona?)
	for id, zona in ZoneConfig.Zonas do
		if zona.PlaceId ~= 0 and zona.PlaceId == game.PlaceId then
			return id, zona
		end
	end
	return nil, nil
end

-- Aleja al jugador del portal para que no lo vuelva a tocar en bucle.
local function alejarDelPortal(player: Player, portal: BasePart?)
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not portal or not personaje or not raiz or not raiz:IsA("BasePart") then
		return
	end
	local direccion = raiz.Position - portal.Position
	direccion = Vector3.new(direccion.X, 0, direccion.Z)
	if direccion.Magnitude < 0.1 then
		direccion = portal.CFrame.LookVector
	end
	local destino = portal.Position + direccion.Unit * DISTANCIA_EMPUJE
	AntiCheat.Gracia(player, 2)
	personaje:PivotTo(CFrame.new(destino + Vector3.new(0, 3, 0)))
end

local function cancelar(player: Player, intento: Intento, mensaje: string)
	if intentos[player] ~= intento then
		return
	end
	intentos[player] = nil
	NetworkBridge.Server.FireClient("TeleportEstado", player, "Fallo", intento.zonaId, mensaje)
end

-- Ejecuta (o reintenta) el teleport real.
local function ejecutar(player: Player, idIntento: number)
	local intento = intentos[player]
	if not intento or intento.id ~= idIntento or player.Parent ~= Players then
		return
	end
	local zona = ZoneConfig.Zonas[intento.zonaId]
	local opciones = Instance.new("TeleportOptions")
	opciones:SetTeleportData({
		ZonaDestino = intento.zonaId,
		Spawn = intento.spawnId or "",
	})
	intento.esperandoResultado = true
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(zona.PlaceId, { player }, opciones)
	end)
	if ok then
		return -- si después falla en el motor, llega por TeleportInitFailed
	end
	warn(`[ZoneManager] TeleportAsync falló para {player.Name}: {err}`)
	ZoneManager._reintentar(player, tostring(err))
end

function ZoneManager._reintentar(player: Player, motivo: string)
	local intento = intentos[player]
	if not intento or not intento.esperandoResultado then
		return -- falla vieja o ya se está reintentando
	end
	intento.esperandoResultado = false
	if intento.numero >= ZoneConfig.ReintentosTeleport then
		warn(`[ZoneManager] Teleport de {player.Name} abandonado tras {intento.numero} intentos: {motivo}`)
		cancelar(player, intento, "No pudimos llevarte a destino. Probá de nuevo en un momento.")
		return
	end
	intento.numero += 1
	NetworkBridge.Server.FireClient(
		"TeleportEstado",
		player,
		"Reintentando",
		intento.zonaId,
		`Reintentando ({intento.numero}/{ZoneConfig.ReintentosTeleport})...`
	)
	task.delay(2 ^ intento.numero, ejecutar, player, intento.id)
end

-- Simulación en Studio: muestra la pantalla de carga y ubica al jugador en un
-- punto de llegada local si existe; si no, lo aleja del portal.
local function simular(player: Player, intento: Intento)
	task.wait(2)
	if player.Parent ~= Players or intentos[player] ~= intento then
		return
	end
	intentos[player] = nil
	if not ZoneManager.UbicarEnLlegada(player, intento.spawnId) then
		alejarDelPortal(player, intento.portal)
	end
	NetworkBridge.Server.FireClient("TeleportEstado", player, "Simulado", intento.zonaId)
	notificar(player, `[Studio] Teleport simulado a {ZoneConfig.Zonas[intento.zonaId].Nombre}`)
end

------------------------------------------------------------------------
-- API pública
------------------------------------------------------------------------

-- Id de la zona de este place. En Studio devuelve "Pruebas" (área de práctica
-- con enemigos y un RaidBlox de prueba). Fuera de Studio, si el place no está en
-- ZoneConfig y ModoPruebas está activado, también "Pruebas". Si no, nil.
function ZoneManager.ZonaActual(): string?
	if RunService:IsStudio() then
		return "Pruebas"
	end
	local id = zonaDeEstePlace()
	if not id and Pruebas.Activas() then
		return "Pruebas"
	end
	return id
end

-- Pide llevar a un jugador a una zona. Devuelve false (y avisa al jugador) si
-- no se puede. Lo usan los portales y lo pueden usar NPCs o menús.
function ZoneManager.Teleportar(player: Player, zonaId: string, spawnId: string?, portal: BasePart?): boolean
	local zona = ZoneConfig.Zonas[zonaId]
	if not zona then
		warn(`[ZoneManager] Zona desconocida: {zonaId}`)
		return false
	end
	if intentos[player] then
		return false -- ya hay uno en curso
	end
	local datos = DataManager.GetData(player)
	if not datos then
		notificar(player, "Tus datos todavía están cargando. Esperá un momento.")
		return false
	end
	if datos.Nivel < zona.NivelMinimo then
		notificar(player, `Necesitás nivel {zona.NivelMinimo} para entrar a {zona.Nombre} (tenés {datos.Nivel}).`)
		alejarDelPortal(player, portal)
		return false
	end
	if zona.PlaceId == 0 and not simulando() then
		notificar(player, `{zona.Nombre} todavía no está disponible.`)
		alejarDelPortal(player, portal)
		return false
	end

	contadorIntentos += 1
	local intento: Intento = {
		id = contadorIntentos,
		zonaId = zonaId,
		spawnId = spawnId,
		portal = portal,
		numero = 1,
		esperandoResultado = false,
	}
	intentos[player] = intento
	NetworkBridge.Server.FireClient("TeleportEstado", player, "Iniciando", zonaId)

	-- Watchdog: si nada lo resolvió (ni éxito ni falla), se libera.
	task.delay(LIMITE_TELEPORT, function()
		if intentos[player] == intento then
			warn(`[ZoneManager] Teleport de {player.Name} sin respuesta; se cancela`)
			cancelar(player, intento, "El viaje tardó demasiado. Probá de nuevo.")
		end
	end)

	-- Guardado preventivo. Si no se confirma, se sigue igual: el servidor de
	-- destino espera a que este libere el session lock, así que no se pierde nada.
	if not DataManager.SaveNowAsync(player, 8) then
		warn(`[ZoneManager] Guardado previo no confirmado para {player.Name}; continúa con session lock`)
	end

	if simulando() then
		task.spawn(simular, player, intento)
	else
		task.spawn(ejecutar, player, intento.id)
	end
	return true
end

-- Ubica al jugador en un punto de llegada válido de este place.
-- Devuelve true si lo movió.
function ZoneManager.UbicarEnLlegada(player: Player, spawnId: string?): boolean
	if not spawnId or spawnId == "" then
		return false
	end
	local carpeta = Workspace:FindFirstChild(ZoneConfig.CarpetaSpawns)
	local punto = carpeta and carpeta:FindFirstChild(spawnId)
	if not punto or not punto:IsA("BasePart") then
		return false -- no existe: aparece en el spawn normal
	end
	local personaje = player.Character
	if not personaje then
		return false
	end
	AntiCheat.Gracia(player, 3)
	personaje:PivotTo(punto.CFrame + Vector3.new(0, 4, 0))
	return true
end

------------------------------------------------------------------------
-- Portales
------------------------------------------------------------------------

local function alTocarPortal(portal: BasePart, golpe: BasePart)
	local personaje = golpe:FindFirstAncestorOfClass("Model")
	local player = personaje and Players:GetPlayerFromCharacter(personaje)
	if not player or not personaje then
		return
	end
	local ahora = os.clock()
	if ahora - (ultimoPortal[player] or 0) < ESPERA_ENTRE_PORTALES then
		return
	end
	ultimoPortal[player] = ahora

	-- Distancia real (un exploit puede disparar toques a distancia).
	local raiz = personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return
	end
	local limite = portal.Size.Magnitude / 2 + MARGEN_DISTANCIA_PORTAL
	if (raiz.Position - portal.Position).Magnitude > limite then
		return
	end

	local destino = portal:GetAttribute("Destino")
	local spawn = portal:GetAttribute("Spawn")
	if typeof(destino) ~= "string" then
		warn(`[ZoneManager] Portal {portal:GetFullName()} sin atributo Destino`)
		return
	end
	ZoneManager.Teleportar(player, destino, if typeof(spawn) == "string" then spawn else nil, portal)
end

local function registrarPortal(instancia: Instance)
	if not instancia:IsA("BasePart") or portalesRegistrados[instancia] then
		return
	end
	local portal = instancia
	portalesRegistrados[portal] = true
	portal.Touched:Connect(function(golpe: BasePart)
		alTocarPortal(portal, golpe)
	end)
	portal.Destroying:Connect(function()
		portalesRegistrados[portal] = nil
	end)
end

local function crearPortalPrueba(zonaId: string, posicion: Vector3)
	local zona = ZoneConfig.Zonas[zonaId]
	local portal = Instance.new("Part")
	portal.Name = `Portal_{zonaId}`
	portal.Anchored = true
	portal.CanCollide = false
	portal.Material = Enum.Material.Neon
	portal.Color = zona.ColorTema
	portal.Transparency = 0.3
	portal.Size = Vector3.new(8, 10, 1)
	portal.Position = posicion
	portal:SetAttribute("Destino", zonaId)

	local cartel = Instance.new("BillboardGui")
	cartel.Size = UDim2.fromScale(10, 2)
	cartel.StudsOffset = Vector3.new(0, 7, 0)
	cartel.AlwaysOnTop = true
	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.TextColor3 = Color3.new(1, 1, 1)
	texto.TextStrokeTransparency = 0.3
	texto.Text = `{zona.Nombre} (Nv. {zona.NivelMinimo}+)`
	texto.Parent = cartel
	cartel.Parent = portal

	portal.Parent = Workspace
	CollectionService:AddTag(portal, TAG_PORTAL)
end

------------------------------------------------------------------------
-- Llegada
------------------------------------------------------------------------

local function esperarPersonaje(player: Player, timeout: number): Model?
	local limite = os.clock() + timeout
	while player.Parent == Players and os.clock() < limite do
		if player.Character then
			return player.Character
		end
		task.wait(0.2)
	end
	return nil
end

local function alEntrar(player: Player)
	-- 1. Nivel mínimo de ESTE place (el teleport pudo iniciarlo el cliente).
	local zonaId, zona = zonaDeEstePlace()
	if zonaId and zona and zona.NivelMinimo > 1 then
		local datos = DataManager.WaitForData(player, 60)
		if datos and datos.Nivel < zona.NivelMinimo then
			warn(`[ZoneManager] {player.Name} (nivel {datos.Nivel}) llegó a {zonaId} sin el nivel mínimo`)
			local ciudad = ZoneConfig.Zonas.CiudadPrincipal
			if ciudad and ciudad.PlaceId ~= 0 and ciudad.PlaceId ~= game.PlaceId then
				notificar(player, `Necesitás nivel {zona.NivelMinimo} para estar en {zona.Nombre}.`)
				ZoneManager.Teleportar(player, "CiudadPrincipal")
			else
				player:Kick(`Necesitás nivel {zona.NivelMinimo} para entrar a {zona.Nombre}.`)
			end
			return
		end
	end

	-- 2. ¿Llegó por teleport? Ubicarlo en el punto pedido en su primer spawn.
	local okJoin, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not okJoin or typeof(joinData) ~= "table" then
		return
	end
	local teleportData = (joinData :: any).TeleportData
	if typeof(teleportData) ~= "table" then
		return
	end
	local spawnId = teleportData.Spawn
	if typeof(spawnId) ~= "string" or #spawnId > 50 then
		return
	end
	if esperarPersonaje(player, 30) then
		task.wait() -- deja que el motor termine de ubicar el personaje
		ZoneManager.UbicarEnLlegada(player, spawnId)
	end
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function ZoneManager.Init()
	assert(not iniciado, "ZoneManager.Init() se llamó dos veces")
	iniciado = true

	if RunService:IsStudio() and ZoneConfig.CrearPortalesDePruebaEnStudio then
		if #CollectionService:GetTagged(TAG_PORTAL) == 0 then
			crearPortalPrueba("Bosque", Vector3.new(25, 5, -30))
			crearPortalPrueba("ReinoFuego", Vector3.new(-25, 5, -30))
		end
	end

	for _, portal in CollectionService:GetTagged(TAG_PORTAL) do
		registrarPortal(portal)
	end
	CollectionService:GetInstanceAddedSignal(TAG_PORTAL):Connect(registrarPortal)

	TeleportService.TeleportInitFailed:Connect(function(player: Player, resultado: Enum.TeleportResult, mensaje: string)
		if intentos[player] then
			warn(`[ZoneManager] TeleportInitFailed {player.Name}: {resultado.Name} {mensaje}`)
			ZoneManager._reintentar(player, mensaje)
		end
	end)

	Players.PlayerAdded:Connect(alEntrar)
	for _, player in Players:GetPlayers() do
		task.spawn(alEntrar, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		intentos[player] = nil
		ultimoPortal[player] = nil
	end)
end

return ZoneManager
