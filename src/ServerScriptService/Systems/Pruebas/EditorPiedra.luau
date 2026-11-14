--!strict
-- EditorPiedra: NPC junto al castillo azul que abre una ventana para editar la
-- piedra del castillo (material, color, reflejo, transparencia y física).
--
-- * Solo existe en modo pruebas y solo lo usan el creador y los probadores
--   (los mismos que el Banquero).
-- * Al guardar, el servidor valida los valores, los aplica a la skin "Ninguna"
--   (lo que se construya de ahora en más) y a todas las partes ya hechas con esa
--   piedra, y los guarda en el DataStore ConfigMundo: al reiniciar, siguen.
-- * Junto al NPC hay una muestra (muro y torre) para ver los cambios aunque el
--   castillo todavía no esté construido.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local GuerraConfig = require(ReplicatedStorage.Configs.GuerraConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local AspectoPiedra = require(ReplicatedStorage.Modules.AspectoPiedra)
local NpcFactory = require(script.Parent.Parent.NpcFactory)
local NpcsPrueba = require(script.Parent.NpcsPrueba)

type Valores = AspectoPiedra.Valores

local CLAVE = "PiedraCastillo"
local DISTANCIA_ABRIR = 14
local DISTANCIA_GUARDAR = 60

local EditorPiedra = {}

local original: Valores = AspectoPiedra.Desde(GuerraConfig.Skins.Ninguna.Material, GuerraConfig.Skins.Ninguna.Color)
local actual: Valores = original
local npc: BasePart? = nil
local ultimoGuardado: { [Player]: number } = {}
local iniciado = false

local function store(): DataStore
	return DataStoreService:GetDataStore("ConfigMundo" .. (if RunService:IsStudio() then "_Studio" else ""))
end

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

-- Pasa los valores a la skin "Ninguna" y a todas las partes con esa piedra.
local function aplicar(v: Valores)
	actual = v
	local skin = GuerraConfig.Skins.Ninguna
	local variante = AspectoPiedra.Variante(v.Variante)
	skin.Material = if variante then variante.BaseMaterial else AspectoPiedra.Enum(v.Material)
	skin.Variante = if variante then variante.Name else nil
	skin.Color = AspectoPiedra.Color(v)
	skin.Reflejo = v.Reflejo
	skin.Transparencia = v.Transparencia
	skin.Fisica = { Densidad = v.Densidad, Friccion = v.Friccion, Elasticidad = v.Elasticidad }
	AspectoPiedra.AplicarATodas(v, true)
end

local function distanciaA(player: Player, parte: BasePart): number
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then (raiz.Position - parte.Position).Magnitude else math.huge
end

local function guardar(player: Player, valores: unknown): Types.Respuesta
	local n = npc
	if not n or not NpcsPrueba.Permitido(player) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local ahora = os.clock()
	if ahora - (ultimoGuardado[player] or -math.huge) < 2 then
		return NetworkBridge.Fail("RATE_LIMITED")
	end
	if distanciaA(player, n) > DISTANCIA_GUARDAR then
		avisar(player, "Acercate al editor de piedra para guardar.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local v = AspectoPiedra.Validar(valores)
	if not v then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	ultimoGuardado[player] = ahora
	aplicar(v)
	local ok, err = pcall(function()
		store():UpdateAsync(CLAVE, function(): any
			return v
		end)
	end)
	if not ok then
		warn(`[EditorPiedra] No se pudo guardar: {err}`)
		avisar(player, "Se aplicó, pero no se pudo guardar (se pierde al reiniciar el servidor).", "Error")
		return NetworkBridge.Ok(nil)
	end
	avisar(player, "Piedra del castillo guardada.", "Oro")
	return NetworkBridge.Ok(nil)
end

local function crearMuestra(pos: Vector3, padre: Instance)
	local carpeta = Instance.new("Model")
	carpeta.Name = "MuestraPiedra"
	local function bloque(nombre: string, tam: Vector3, offset: Vector3)
		local p = Instance.new("Part")
		p.Name = nombre
		p.Anchored = true
		p.Size = tam
		p.CFrame = CFrame.new(pos + offset)
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		CollectionService:AddTag(p, AspectoPiedra.Etiqueta)
		p.Parent = carpeta
		AspectoPiedra.Aplicar(p, actual, true)
	end
	bloque("Muro", Vector3.new(12, 7, 2), Vector3.new(0, 3.5, 0))
	bloque("Torre", Vector3.new(4, 11, 4), Vector3.new(7.5, 5.5, 0))
	bloque("Almena1", Vector3.new(2, 1.5, 2), Vector3.new(-4.5, 7.75, 0))
	bloque("Almena2", Vector3.new(2, 1.5, 2), Vector3.new(0, 7.75, 0))
	bloque("Almena3", Vector3.new(2, 1.5, 2), Vector3.new(4.5, 7.75, 0))
	carpeta.Parent = padre
end

local function colocar()
	local mapa = Workspace:WaitForChild(GuerraConfig.NombreCarpetaMapa, 120)
	local base = mapa and mapa:WaitForChild("Base_Azul", 30)
	local centro = base and base:WaitForChild("Centro", 30)
	if not base or not centro or not centro:IsA("BasePart") then
		warn("[EditorPiedra] No se encontró el castillo azul: no se crea el NPC.")
		return
	end
	local suelo = Vector3.new(centro.Position.X, 0, centro.Position.Z)
	local posNpc = suelo + Vector3.new(30, 0, 8)
	local raiz, prompt = NpcFactory.Crear(
		"EditorPiedra",
		"Cantero (editar piedra)",
		posNpc,
		Color3.fromRGB(150, 145, 135),
		"Editar la piedra del castillo",
		suelo
	)
	npc = raiz
	crearMuestra(suelo + Vector3.new(32, 0, -6), base)
	prompt.Triggered:Connect(function(player: Player)
		if distanciaA(player, raiz) > DISTANCIA_ABRIR then
			return
		end
		if not NpcsPrueba.Permitido(player) then
			avisar(player, "El cantero solo atiende a los probadores del juego.", "Error")
			return
		end
		NetworkBridge.Server.FireClient("EditorPiedraAbrir", player, { Actual = actual, Original = original })
	end)
end

function EditorPiedra.Init()
	assert(not iniciado, "EditorPiedra.Init() se llamó dos veces")
	iniciado = true
	if not Pruebas.Activas() then
		return
	end
	NetworkBridge.Server.OnInvoke("EditorPiedraGuardar", guardar)
	Players.PlayerRemoving:Connect(function(player: Player)
		ultimoGuardado[player] = nil
	end)
	task.spawn(function()
		local ok, guardado = pcall(function(): any
			return store():GetAsync(CLAVE)
		end)
		local v = if ok then AspectoPiedra.Validar(guardado) else nil
		if v then
			aplicar(v)
		end
		colocar()
	end)
end

return EditorPiedra
