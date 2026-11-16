--!strict
-- AuraBando: anillo de luz en el piso alrededor de cada jugador, del color de
-- su bando (Violeta, Rojo o Azul). Lo dibuja cada cliente para TODOS los
-- jugadores (así lo ve todo el mundo sin cargar la red) y se adapta al
-- terreno: cada tramo del anillo se apoya donde pega un rayo hacia abajo
-- (rampas, escalones, terreno).
--
-- No se dibuja para jugadores muertos, lejos (más de 150 studs) ni para un
-- pícaro invisible que no seas vos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)

local jugador = Players.LocalPlayer
local COLORES = GameConfig.Bandos.Colores
local TRAMOS = 24
local RADIO = 2.8
local ANCHO = 0.32
local GROSOR = 0.06
local DISTANCIA_MAXIMA = 150

local carpeta = Instance.new("Folder")
carpeta.Name = "AurasBando"
carpeta.Parent = Workspace

local parametros = RaycastParams.new()
parametros.FilterType = Enum.RaycastFilterType.Exclude
parametros.RespectCanCollide = true

type Aura = { Modelo: Model, Tramos: { Part } }
local auras: { [Player]: Aura } = {}

local function nuevoTramo(padre: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = Vector3.new(ANCHO, GROSOR, 1)
	p.Transparency = 1
	p.Parent = padre
	return p
end

local function crearAura(otro: Player): Aura
	local modelo = Instance.new("Model")
	modelo.Name = `Aura_{otro.UserId}`
	local tramos: { Part } = {}
	for i = 1, TRAMOS do
		tramos[i] = nuevoTramo(modelo)
	end
	modelo.Parent = carpeta
	local a = { Modelo = modelo, Tramos = tramos }
	auras[otro] = a
	return a
end

local function ocultar(a: Aura)
	for _, t in a.Tramos do
		t.Transparency = 1
	end
end

local function invisible(personaje: Model): boolean
	local cabeza = personaje:FindFirstChild("Head")
	return cabeza ~= nil and cabeza:IsA("BasePart") and cabeza.Transparency >= 0.7
end

-- Lista de exclusión de los rayos: todos los personajes y las auras.
local excluir: { Instance } = { carpeta }
local function actualizarExclusion()
	table.clear(excluir)
	table.insert(excluir, carpeta)
	for _, otro in Players:GetPlayers() do
		if otro.Character then
			table.insert(excluir, otro.Character)
		end
	end
	local enemigos = Workspace:FindFirstChild("Enemigos")
	if enemigos then
		table.insert(excluir, enemigos)
	end
	parametros.FilterDescendantsInstances = excluir
end

local puntos: { Vector3? } = table.create(TRAMOS)
local normales: { Vector3 } = table.create(TRAMOS)

local function dibujar(a: Aura, raiz: BasePart, color: Color3, transparencia: number)
	local centro = raiz.Position
	-- Altura del piso bajo el personaje (para no apoyar el anillo en un techo).
	local abajo = Workspace:Raycast(centro, Vector3.new(0, -12, 0), parametros)
	if not abajo then
		ocultar(a)
		return
	end
	local alto = abajo.Position.Y
	for i = 1, TRAMOS do
		local angulo = (i - 1) / TRAMOS * math.pi * 2
		local base = Vector3.new(centro.X + math.cos(angulo) * RADIO, alto + 2.5, centro.Z + math.sin(angulo) * RADIO)
		local r = Workspace:Raycast(base, Vector3.new(0, -6, 0), parametros)
		if r then
			puntos[i] = r.Position + r.Normal * (GROSOR / 2 + 0.03)
			normales[i] = r.Normal
		else
			puntos[i] = nil
		end
	end
	for i = 1, TRAMOS do
		local siguiente = i % TRAMOS + 1
		local pa, pb = puntos[i], puntos[siguiente]
		local t = a.Tramos[i]
		if pa and pb then
			local largo = (pb - pa).Magnitude
			if largo > 0.01 and largo < RADIO * 2 then
				local arriba = (normales[i] + normales[siguiente]).Unit
				local medio = (pa + pb) / 2
				t.Size = Vector3.new(ANCHO, GROSOR, largo + 0.05)
				t.CFrame = CFrame.lookAt(medio, pb, arriba)
				t.Color = color
				t.Transparency = transparencia
				continue
			end
		end
		t.Transparency = 1
	end
end

local tiempo = 0
local acumuladoExclusion = math.huge
RunService.Heartbeat:Connect(function(dt: number)
	tiempo += dt
	acumuladoExclusion += dt
	if acumuladoExclusion > 1 then
		acumuladoExclusion = 0
		actualizarExclusion()
	end
	local camara = Workspace.CurrentCamera
	local desde = if camara then camara.CFrame.Position else Vector3.zero
	-- Late suave: entre 0.25 y 0.45 de transparencia.
	local pulso = 0.35 + 0.1 * math.sin(tiempo * 3)
	for _, otro in Players:GetPlayers() do
		local personaje = otro.Character
		local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
		local h = personaje and personaje:FindFirstChildOfClass("Humanoid")
		local a = auras[otro] or crearAura(otro)
		if
			not personaje
			or not raiz
			or not raiz:IsA("BasePart")
			or not h
			or h.Health <= 0
			or (raiz.Position - desde).Magnitude > DISTANCIA_MAXIMA
			or (otro ~= jugador and invisible(personaje))
		then
			ocultar(a)
			continue
		end
		local bando = otro:GetAttribute("Bando")
		local color = (if typeof(bando) == "string" then (COLORES :: any)[bando] else nil) or COLORES.Violeta
		dibujar(a, raiz, color, pulso)
	end
end)

Players.PlayerRemoving:Connect(function(otro: Player)
	local a = auras[otro]
	if a then
		a.Modelo:Destroy()
		auras[otro] = nil
	end
end)
