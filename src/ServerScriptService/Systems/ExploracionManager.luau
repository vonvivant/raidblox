--!strict
-- ExploracionManager: viaje rápido por piedras de teletransporte y puntos de
-- interés del mapa (ExploracionConfig).
--
-- * Piedras: se activan una vez tocándolas (gratis) y quedan guardadas en el
--   perfil. Después, estando junto a una piedra activada, se puede viajar a
--   cualquier otra activada pagando oro. Dentro de la zona se mueve el
--   personaje; a otra zona se usa ZoneManager (que valida nivel y place).
-- * Puntos de interés: se descubren caminando cerca o los revela el Cartógrafo
--   (NPC-023). Se guardan en el perfil y el mapa del mundo los dibuja.
--
-- El cliente nunca manda posiciones: manda el id de la piedra o del punto, y el
-- servidor valida cercanía, nivel y oro.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExploracionConfig = require(ReplicatedStorage.Configs.ExploracionConfig)
local ZoneConfig = require(ReplicatedStorage.Configs.ZoneConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.DataManager)
local NpcManager = require(script.Parent.NpcManager)
local ZoneManager = require(script.Parent.ZoneManager)

type Piedra = ExploracionConfig.Piedra

local CFG = ExploracionConfig

local ExploracionManager = {}

local iniciado = false
local partesPiedra: { [string]: BasePart } = {} -- id -> parte en el mundo
local zonaActual = "Pruebas"

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
end

local function raizDe(player: Player): BasePart?
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

------------------------------------------------------------------------
-- Datos del jugador
------------------------------------------------------------------------

local function activadas(datos: Types.DatosJugador): { [string]: boolean }
	local mapa: { [string]: boolean } = {}
	local lista: { string } = datos.Waypoints or {}
	for _, id in lista do
		if CFG.Piedras[id] then
			mapa[id] = true
		end
	end
	return mapa
end

local function descubiertos(datos: Types.DatosJugador): { [string]: boolean }
	local mapa: { [string]: boolean } = {}
	local lista: { string } = datos.Interes or {}
	for _, id in lista do
		if CFG.Interes[id] then
			mapa[id] = true
		end
	end
	return mapa
end

-- Agrega un id a una lista del perfil si no estaba. Devuelve si lo agregó.
local function sumar(player: Player, seccion: "Waypoints" | "Interes", id: string): boolean
	local datos = DataManager.GetData(player)
	if not datos then
		return false
	end
	local lista: { string } = (datos :: any)[seccion] or {}
	if table.find(lista, id) then
		return false
	end
	table.insert(lista, id)
	DataManager.Mutar(player, "Exploracion", function(d)
		(d :: any)[seccion] = lista
	end)
	return true
end

-- Piedra activada más cercana al jugador (desde la que puede viajar).
local function piedraCerca(player: Player, activas: { [string]: boolean }): string?
	local raiz = raizDe(player)
	if not raiz then
		return nil
	end
	local mejor: string? = nil
	local mejorDistancia = CFG.Distancia
	for id, parte in partesPiedra do
		local d = (parte.Position - raiz.Position).Magnitude
		if activas[id] and d <= mejorDistancia then
			mejor, mejorDistancia = id, d
		end
	end
	return mejor
end

------------------------------------------------------------------------
-- Piedras
------------------------------------------------------------------------

local function abrir(player: Player, piedraId: string)
	local datos = DataManager.GetData(player)
	local piedra = CFG.Piedras[piedraId]
	local raiz = raizDe(player)
	local parte = partesPiedra[piedraId]
	if not datos or not piedra or not raiz or not parte then
		return
	end
	if (parte.Position - raiz.Position).Magnitude > CFG.Distancia then
		return
	end
	local nivel = piedra.NivelMinimo or 1
	if datos.Nivel < nivel then
		avisar(player, `La piedra no responde: necesitás nivel {nivel}.`)
		return
	end
	if sumar(player, "Waypoints", piedraId) then
		avisar(player, `Activaste {piedra.Nombre}. Ya podés viajar hasta acá.`, "Info")
	end
	local activas = activadas(DataManager.GetData(player) or datos)
	local destinos: { { Id: string, Nombre: string, Zona: string, Costo: number } } = {}
	for id in activas do
		local otra = CFG.Piedras[id]
		if otra and id ~= piedraId then
			local zona = ZoneConfig.Zonas[otra.Zona]
			table.insert(destinos, {
				Id = id,
				Nombre = otra.Nombre,
				Zona = if zona then zona.Nombre else otra.Zona,
				Costo = CFG.Costo(piedra, otra),
			})
		end
	end
	table.sort(destinos, function(a, b): boolean
		return a.Nombre < b.Nombre
	end)
	NetworkBridge.Server.FireClient("PiedraAbrir", player, piedraId, piedra.Nombre, destinos)
end

local function viajar(player: Player, destinoId: string): Types.Respuesta
	local datos = DataManager.GetData(player)
	local destino = CFG.Piedras[destinoId]
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	if not destino then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local activas = activadas(datos)
	local desdeId = piedraCerca(player, activas)
	local desde = if desdeId then CFG.Piedras[desdeId] else nil
	if not desdeId or not desde then
		avisar(player, "Tenés que estar junto a una piedra activada.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not activas[destinoId] or destinoId == desdeId then
		avisar(player, "Todavía no activaste esa piedra.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if ZoneManager.Viajando(player) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local costo = CFG.Costo(desde, destino)
	if not DataManager.SpendGold(player, costo) then
		avisar(player, `El viaje cuesta {costo} de oro.`)
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end

	if destino.Zona ~= desde.Zona then
		-- Otra zona: lo lleva ZoneManager (valida nivel y place). Si falla, devuelve el oro.
		if not ZoneManager.Teleportar(player, destino.Zona) then
			DataManager.AddGold(player, costo)
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		return NetworkBridge.Ok({ Costo = costo })
	end
	local parte = partesPiedra[destinoId]
	local raiz = raizDe(player)
	if not parte or not raiz then
		DataManager.AddGold(player, costo)
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	-- Un paso al costado de la piedra, mirando hacia ella.
	local lugar = parte.Position + Vector3.new(0, 3, 4)
	raiz.CFrame = CFrame.lookAt(lugar, Vector3.new(parte.Position.X, lugar.Y, parte.Position.Z))
	avisar(player, `Viajaste a {destino.Nombre} por {costo} de oro.`, "Oro")
	return NetworkBridge.Ok({ Costo = costo })
end

local function prepararPiedra(objeto: Instance)
	if not objeto:IsA("BasePart") then
		return
	end
	local id = objeto:GetAttribute("Piedra")
	local piedra = if typeof(id) == "string" then CFG.Piedras[id] else nil
	if not piedra or typeof(id) ~= "string" then
		warn(`[Exploracion] {objeto:GetFullName()} necesita el atributo Piedra con una clave de ExploracionConfig`)
		return
	end
	partesPiedra[id] = objeto
	local prompt = objeto:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Viaje rápido"
	prompt.ObjectText = piedra.Nombre
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CFG.Distancia - 4
	prompt.RequiresLineOfSight = false
	prompt.Parent = objeto
	prompt.Triggered:Connect(function(player: Player)
		abrir(player, id)
	end)
	objeto.Destroying:Connect(function()
		if partesPiedra[id] == objeto then
			partesPiedra[id] = nil
		end
	end)
end

-- Piedra de prueba: un obelisco con una runa flotante.
local function crearPiedra(id: string, piedra: Piedra)
	local parte = Instance.new("Part")
	parte.Name = `Piedra_{id}`
	parte.Anchored = true
	parte.Material = Enum.Material.Slate
	parte.Color = Color3.fromRGB(70, 70, 90)
	parte.Size = Vector3.new(3, 7, 3)
	parte.CFrame = CFrame.new(piedra.Posicion + Vector3.new(0, 3.5, 0))
	parte:SetAttribute("Piedra", id)

	local runa = Instance.new("PointLight")
	runa.Color = Color3.fromRGB(120, 180, 255)
	runa.Brightness = 2
	runa.Range = 16
	runa.Parent = parte

	local cartel = Instance.new("BillboardGui")
	cartel.Size = UDim2.fromOffset(170, 30)
	cartel.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	cartel.MaxDistance = 250
	cartel.LightInfluence = 0
	cartel.Parent = parte
	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.Font = Enum.Font.GothamBlack
	texto.TextScaled = true
	texto.Text = `◈ {piedra.Nombre}`
	texto.TextColor3 = Color3.fromRGB(150, 200, 255)
	texto.TextStrokeTransparency = 0.4
	texto.Parent = cartel

	parte.Parent = workspace
	CollectionService:AddTag(parte, CFG.TagPiedra)
end

------------------------------------------------------------------------
-- Puntos de interés
------------------------------------------------------------------------

local function revelar(player: Player, ids: { string }, motivo: string): number
	local nuevos = 0
	for _, id in ids do
		if sumar(player, "Interes", id) then
			nuevos += 1
		end
	end
	if nuevos > 0 then
		avisar(player, `{motivo}: {nuevos} punto(s) de interés en tu mapa.`, "Info")
	end
	return nuevos
end

-- Revisa cada tanto si el jugador pasó cerca de un punto de interés sin descubrir.
local function buscarDescubrimientos()
	local ids = CFG.InteresDe(zonaActual)
	if #ids == 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		local datos = DataManager.GetData(player)
		local raiz = raizDe(player)
		if not datos or not raiz then
			continue
		end
		local vistos = descubiertos(datos)
		for _, id in ids do
			local punto = CFG.Interes[id]
			if not vistos[id] and (punto.Posicion - raiz.Position).Magnitude <= CFG.RadioDescubrir then
				if sumar(player, "Interes", id) then
					avisar(player, `Descubriste: {punto.Nombre}.`, "Info")
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function ExploracionManager.Init(zona: string?)
	assert(not iniciado, "ExploracionManager.Init() se llamó dos veces")
	iniciado = true
	zonaActual = zona or "Pruebas"

	for _, parte in CollectionService:GetTagged(CFG.TagPiedra) do
		prepararPiedra(parte)
	end
	CollectionService:GetInstanceAddedSignal(CFG.TagPiedra):Connect(prepararPiedra)
	-- Las piedras de la zona que el mapa no trae se crean solas en pruebas.
	if Pruebas.Activas() then
		for _, id in CFG.PiedrasDe(zonaActual) do
			if not partesPiedra[id] then
				crearPiedra(id, CFG.Piedras[id])
			end
		end
	end

	-- Guardián de Piedra Teleport (NPC-024): activa la piedra más cercana.
	NpcManager.RegistrarAccion("ActivarPiedra", function(player: Player): boolean
		local raiz = raizDe(player)
		if not raiz then
			return false
		end
		local mejor: string? = nil
		local mejorDistancia = 60 -- el guardián alcanza la piedra que cuida
		for id, parte in partesPiedra do
			local d = (parte.Position - raiz.Position).Magnitude
			if d <= mejorDistancia then
				mejor, mejorDistancia = id, d
			end
		end
		local piedra = if mejor then CFG.Piedras[mejor] else nil
		if not mejor or not piedra then
			avisar(player, "No hay ninguna piedra cerca.")
			return false
		end
		if not sumar(player, "Waypoints", mejor) then
			avisar(player, `Ya tenías activada {piedra.Nombre}.`, "Info")
			return false
		end
		avisar(player, `Activaste {piedra.Nombre}.`, "Info")
		return true
	end)

	-- Cartógrafo (NPC-023): revela los puntos de interés de la zona.
	NpcManager.RegistrarAccion("RevelarPOI", function(player: Player): boolean
		local datos = DataManager.GetData(player)
		if not datos then
			return false
		end
		local vistos = descubiertos(datos)
		local faltan: { string } = {}
		for _, id in CFG.InteresDe(zonaActual) do
			if not vistos[id] then
				table.insert(faltan, id)
			end
		end
		if #faltan == 0 then
			avisar(player, "Ya conocés todo lo que tengo de esta zona.", "Info")
			return false
		end
		revelar(player, faltan, "El cartógrafo te marca la zona")
		return true
	end)
	NpcManager.RegistrarCotizacion("RevelarPOI", function(player: Player): number
		local datos = DataManager.GetData(player)
		if not datos then
			return CFG.PrecioMapa
		end
		local vistos = descubiertos(datos)
		for _, id in CFG.InteresDe(zonaActual) do
			if not vistos[id] then
				return CFG.PrecioMapa
			end
		end
		return 0 -- ya los tiene todos: el botón queda apagado
	end)

	NetworkBridge.Server.OnInvoke("PiedraViajar", function(player: Player, destino: unknown): Types.Respuesta
		local id = NetworkBridge.Guard.OneOf(destino, CFG.Piedras)
		if not id then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return viajar(player, id)
	end)

	task.spawn(function()
		while true do
			task.wait(CFG.IntervaloDescubrir)
			buscarDescubrimientos()
		end
	end)
end

return ExploracionManager
