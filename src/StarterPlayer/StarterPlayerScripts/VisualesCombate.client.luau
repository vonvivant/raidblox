--!strict
-- VisualesCombate: animaciones de golpes y conjuros, proyectiles y efectos de
-- las habilidades. Todo es local y solo visual: el servidor ya resolvió el
-- daño y manda "Accion", "Casteo" y "CasteoFin" a los jugadores cercanos.
--
-- Animaciones por código: se rotan las articulaciones de los brazos y el torso
-- (Motor6D.C0) con poses clave. Funciona con R15 y R6, y se suma a la
-- animación de caminar de Roblox. Si una habilidad tiene AnimacionId en
-- VisualConfig, se reproduce esa animación subida en lugar de la de código.
--
-- Texturas: solo las partículas que vienen con Roblox (rbxasset://), así no
-- depende de recursos externos.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local VisualConfig = require(ReplicatedStorage.Configs.VisualConfig)
local EnemigosConfig = require(ReplicatedStorage.Configs.EnemigosConfig)

local jugador = Players.LocalPlayer

local TEX_CHISPAS = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FUEGO = "rbxasset://textures/particles/fire_main.dds"
local TEX_HUMO = "rbxasset://textures/particles/smoke_main.dds"

local carpeta = Instance.new("Folder")
carpeta.Name = "EfectosLocales"
carpeta.Parent = Workspace

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function grados(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function parteFx(tamano: Vector3, color: Color3, forma: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = tamano
	p.Shape = forma or Enum.PartType.Block
	return p
end

local function raizDe(modelo: Model): BasePart?
	local raiz = modelo:FindFirstChild("HumanoidRootPart") or modelo.PrimaryPart
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

local function manoDe(modelo: Model): BasePart?
	local mano = modelo:FindFirstChild("RightHand") or modelo:FindFirstChild("Right Arm")
	if mano and mano:IsA("BasePart") then
		return mano
	end
	return raizDe(modelo)
end

local function pies(modelo: Model): Vector3?
	local raiz = raizDe(modelo)
	if not raiz then
		return nil
	end
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	local alto = if humanoid then humanoid.HipHeight + raiz.Size.Y / 2 else 3
	return raiz.Position - Vector3.new(0, alto - 0.1, 0)
end

local function tween(objeto: Instance, segundos: number, props: { [string]: any }, estilo: Enum.EasingStyle?)
	TweenService
		:Create(objeto, TweenInfo.new(segundos, estilo or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
		:Play()
end

local function luz(padre: Instance, color: Color3, brillo: number, rango: number, duracion: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brillo
	l.Range = rango
	l.Parent = padre
	tween(l, duracion, { Brightness = 0 })
end

-- Emisor de partículas en un punto, que se borra solo.
local function particulas(
	posicion: Vector3,
	color: Color3,
	textura: string,
	cantidad: number,
	velocidad: NumberRange,
	vida: NumberRange,
	tamano: number,
	duracion: number?
): ParticleEmitter
	local ancla = parteFx(Vector3.new(0.2, 0.2, 0.2), color)
	ancla.Transparency = 1
	ancla.Position = posicion
	ancla.Parent = carpeta
	local e = Instance.new("ParticleEmitter")
	e.Texture = textura
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Speed = velocidad
	e.Lifetime = vida
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, tamano), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = ancla
	if duracion then
		e.Rate = cantidad / duracion
		task.delay(duracion, function()
			e.Enabled = false
		end)
		Debris:AddItem(ancla, duracion + vida.Max + 0.2)
	else
		e:Emit(cantidad)
		Debris:AddItem(ancla, vida.Max + 0.2)
	end
	return e
end

------------------------------------------------------------------------
-- Animaciones por código
------------------------------------------------------------------------

type Pose = { [string]: CFrame } -- articulación lógica -> rotación (espacio del padre)
type Paso = { Duracion: number, Pose: Pose }
type Animacion = { Pasos: { Paso }, Bucle: boolean? }

local I = CFrame.identity

local ANIMACIONES: { [string]: Animacion } = {
	Tajo = {
		Pasos = {
			{ Duracion = 0.12, Pose = { BrazoDer = grados(150, 0, 40), Torso = grados(0, 25, 0) } },
			{ Duracion = 0.1, Pose = { BrazoDer = grados(70, 0, -45), Torso = grados(0, -30, 0) } },
			{ Duracion = 0.22, Pose = {} },
		},
	},
	Zarpazo = {
		Pasos = {
			{ Duracion = 0.08, Pose = { BrazoDer = grados(80, 0, -40), Torso = grados(-10, -25, 0) } },
			{ Duracion = 0.2, Pose = {} },
		},
	},
	Golpe = {
		Pasos = {
			{
				Duracion = 0.08,
				Pose = { BrazoDer = grados(40, 0, 15), BrazoIzq = grados(80, 0, -25), Torso = grados(0, 15, 0) },
			},
			{
				Duracion = 0.08,
				Pose = { BrazoDer = grados(95, 0, -5), BrazoIzq = grados(80, 0, -25), Torso = grados(-5, -15, 0) },
			},
			{ Duracion = 0.22, Pose = {} },
		},
	},
	Estocada = {
		Pasos = {
			{ Duracion = 0.1, Pose = { BrazoDer = grados(50, 0, 20), Torso = grados(0, 20, 0) } },
			{ Duracion = 0.07, Pose = { BrazoDer = grados(95, 0, -10), Torso = grados(-10, -20, 0) } },
			{ Duracion = 0.2, Pose = {} },
		},
	},
	Pesado = {
		Pasos = {
			{
				Duracion = 0.18,
				Pose = { BrazoDer = grados(170, 0, 10), BrazoIzq = grados(170, 0, -10), Torso = grados(10, 0, 0) },
			},
			{
				Duracion = 0.1,
				Pose = { BrazoDer = grados(45, 0, -10), BrazoIzq = grados(45, 0, 10), Torso = grados(-25, 0, 0) },
			},
			{
				Duracion = 0.08,
				Pose = { BrazoDer = grados(45, 0, -10), BrazoIzq = grados(45, 0, 10), Torso = grados(-25, 0, 0) },
			},
			{ Duracion = 0.25, Pose = {} },
		},
	},
	Giro = {
		Pasos = {
			{
				Duracion = 0.08,
				Pose = { BrazoDer = grados(0, 0, 90), BrazoIzq = grados(0, 0, -90), Torso = grados(0, 0, 0) },
			},
			{
				Duracion = 0.09,
				Pose = { BrazoDer = grados(0, 0, 90), BrazoIzq = grados(0, 0, -90), Torso = grados(0, 120, 0) },
			},
			{
				Duracion = 0.09,
				Pose = { BrazoDer = grados(0, 0, 90), BrazoIzq = grados(0, 0, -90), Torso = grados(0, 240, 0) },
			},
			{
				Duracion = 0.09,
				Pose = { BrazoDer = grados(0, 0, 90), BrazoIzq = grados(0, 0, -90), Torso = grados(0, 359, 0) },
			},
			{ Duracion = 0.2, Pose = {} },
		},
	},
	Grito = {
		Pasos = {
			{
				Duracion = 0.15,
				Pose = { BrazoDer = grados(30, 0, 150), BrazoIzq = grados(30, 0, -150), Torso = grados(12, 0, 0) },
			},
			{
				Duracion = 0.3,
				Pose = { BrazoDer = grados(30, 0, 150), BrazoIzq = grados(30, 0, -150), Torso = grados(12, 0, 0) },
			},
			{ Duracion = 0.25, Pose = {} },
		},
	},
	Pisoton = {
		Pasos = {
			{
				Duracion = 0.18,
				Pose = { BrazoDer = grados(165, 0, 15), BrazoIzq = grados(165, 0, -15), Torso = grados(8, 0, 0) },
			},
			{
				Duracion = 0.1,
				Pose = { BrazoDer = grados(30, 0, 25), BrazoIzq = grados(30, 0, -25), Torso = grados(-25, 0, 0) },
			},
			{
				Duracion = 0.12,
				Pose = { BrazoDer = grados(30, 0, 25), BrazoIzq = grados(30, 0, -25), Torso = grados(-25, 0, 0) },
			},
			{ Duracion = 0.25, Pose = {} },
		},
	},
	Guardia = {
		Pasos = {
			{ Duracion = 0.1, Pose = { BrazoIzq = grados(85, 0, -35), BrazoDer = grados(20, 0, 10) } },
			{ Duracion = 0.5, Pose = { BrazoIzq = grados(85, 0, -35), BrazoDer = grados(20, 0, 10) } },
			{ Duracion = 0.2, Pose = {} },
		},
	},
	Lanzar = {
		Pasos = {
			{ Duracion = 0.1, Pose = { BrazoDer = grados(60, 0, 40), Torso = grados(0, 25, 0) } },
			{ Duracion = 0.08, Pose = { BrazoDer = grados(100, 0, -5), Torso = grados(0, -15, 0) } },
			{ Duracion = 0.12, Pose = { BrazoDer = grados(100, 0, -5), Torso = grados(0, -15, 0) } },
			{ Duracion = 0.2, Pose = {} },
		},
	},
	Bendecir = {
		Pasos = {
			{ Duracion = 0.12, Pose = { BrazoDer = grados(120, 0, -10), BrazoIzq = grados(40, 0, -10) } },
			{ Duracion = 0.3, Pose = { BrazoDer = grados(120, 0, -10), BrazoIzq = grados(40, 0, -10) } },
			{ Duracion = 0.22, Pose = {} },
		},
	},
	Disparo = {
		Pasos = {
			{
				Duracion = 0.12,
				Pose = { BrazoIzq = grados(90, 0, 15), BrazoDer = grados(90, 0, -45), Torso = grados(0, 40, 0) },
			},
			{
				Duracion = 0.08,
				Pose = { BrazoIzq = grados(90, 0, 15), BrazoDer = grados(90, 0, -45), Torso = grados(0, 40, 0) },
			},
			{
				Duracion = 0.06,
				Pose = { BrazoIzq = grados(90, 0, 15), BrazoDer = grados(75, 0, 30), Torso = grados(0, 40, 0) },
			},
			{ Duracion = 0.25, Pose = {} },
		},
	},
	Preparar = { -- el "¡!" de los enemigos: levanta el brazo antes del golpe
		Pasos = {
			{ Duracion = 0.2, Pose = { BrazoDer = grados(150, 0, 40), Torso = grados(0, 25, 0) } },
			{ Duracion = 0.6, Pose = { BrazoDer = grados(150, 0, 40), Torso = grados(0, 25, 0) } },
			{ Duracion = 0.2, Pose = {} },
		},
	},
	-- En bucle mientras castea (se cortan al terminar o cancelar).
	Conjurar = {
		Bucle = true,
		Pasos = {
			{ Duracion = 0.25, Pose = { BrazoDer = grados(70, 0, -20), BrazoIzq = grados(70, 0, 20) } },
			{ Duracion = 0.4, Pose = { BrazoDer = grados(82, 0, -14), BrazoIzq = grados(82, 0, 14) } },
			{ Duracion = 0.4, Pose = { BrazoDer = grados(70, 0, -20), BrazoIzq = grados(70, 0, 20) } },
		},
	},
	Apuntar = {
		Bucle = true,
		Pasos = {
			{
				Duracion = 0.2,
				Pose = { BrazoIzq = grados(90, 0, 15), BrazoDer = grados(90, 0, -45), Torso = grados(0, 40, 0) },
			},
			{
				Duracion = 0.6,
				Pose = { BrazoIzq = grados(92, 0, 15), BrazoDer = grados(90, 0, -48), Torso = grados(0, 40, 0) },
			},
			{
				Duracion = 0.6,
				Pose = { BrazoIzq = grados(90, 0, 15), BrazoDer = grados(90, 0, -45), Torso = grados(0, 40, 0) },
			},
		},
	},
	Rezo = {
		Bucle = true,
		Pasos = {
			{
				Duracion = 0.25,
				Pose = { BrazoDer = grados(150, 0, -20), BrazoIzq = grados(150, 0, 20), Torso = grados(8, 0, 0) },
			},
			{
				Duracion = 0.5,
				Pose = { BrazoDer = grados(158, 0, -15), BrazoIzq = grados(158, 0, 15), Torso = grados(10, 0, 0) },
			},
			{
				Duracion = 0.5,
				Pose = { BrazoDer = grados(150, 0, -20), BrazoIzq = grados(150, 0, 20), Torso = grados(8, 0, 0) },
			},
		},
	},
}

type Articulacion = { Motor: Motor6D, Original: CFrame }
type EstadoAnim = {
	Articulaciones: { [string]: Articulacion },
	Actual: Pose, -- rotación aplicada ahora (para empezar la siguiente desde acá)
	Anim: Animacion?,
	Inicio: number,
	Desde: Pose,
	Paso: number,
}

local animados: { [Model]: EstadoAnim } = {}

local function buscarMotor(modelo: Model, parte: string, nombre: string): Motor6D?
	local p = modelo:FindFirstChild(parte)
	local m = p and p:FindFirstChild(nombre)
	return if m and m:IsA("Motor6D") then m else nil
end

local function estadoDe(modelo: Model): EstadoAnim?
	local existente = animados[modelo]
	if existente then
		-- Si el cuerpo se rearmó (por ejemplo, al cambiar el género), las
		-- articulaciones viejas ya no existen: se vuelven a buscar.
		local valido = true
		for _, art in existente.Articulaciones do
			if not art.Motor.Parent then
				valido = false
				break
			end
		end
		if valido then
			return existente
		end
		animados[modelo] = nil
	end
	local motores: { [string]: Motor6D? } = {
		BrazoDer = buscarMotor(modelo, "RightUpperArm", "RightShoulder")
			or buscarMotor(modelo, "Torso", "Right Shoulder"),
		BrazoIzq = buscarMotor(modelo, "LeftUpperArm", "LeftShoulder") or buscarMotor(modelo, "Torso", "Left Shoulder"),
		Torso = buscarMotor(modelo, "UpperTorso", "Waist") or buscarMotor(modelo, "HumanoidRootPart", "RootJoint"),
	}
	local articulaciones: { [string]: Articulacion } = {}
	local alguna = false
	for nombre, motor in motores do
		if motor then
			articulaciones[nombre] = { Motor = motor, Original = motor.C0 }
			alguna = true
		end
	end
	if not alguna then
		return nil
	end
	local estado: EstadoAnim =
		{ Articulaciones = articulaciones, Actual = {}, Anim = nil, Inicio = 0, Desde = {}, Paso = 1 }
	animados[modelo] = estado
	modelo.Destroying:Connect(function()
		animados[modelo] = nil
	end)
	return estado
end

local function aplicarPose(estado: EstadoAnim, pose: Pose)
	for nombre, art in estado.Articulaciones do
		local rot = pose[nombre] or I
		if art.Motor.Parent then
			-- Rotación en el espacio del padre, con el pivote en la articulación:
			-- igual para R15 y R6.
			art.Motor.C0 = CFrame.new(art.Original.Position) * rot * art.Original.Rotation
		end
	end
	estado.Actual = pose
end

local function suavizado(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function animar(modelo: Model, nombre: string?)
	if not nombre then
		return
	end
	local anim = ANIMACIONES[nombre]
	local estado = estadoDe(modelo)
	if not anim or not estado then
		return
	end
	if not estado.Anim then
		-- En reposo el C0 es el original: se relee por si cambió la escala.
		for _, art in estado.Articulaciones do
			art.Original = art.Motor.C0
		end
		estado.Actual = {}
	end
	estado.Anim = anim
	estado.Inicio = os.clock()
	estado.Desde = estado.Actual
	estado.Paso = 1
end

local function detenerBucle(modelo: Model)
	local estado = animados[modelo]
	if estado and estado.Anim and estado.Anim.Bucle then
		estado.Anim = { Pasos = { { Duracion = 0.2, Pose = {} } } }
		estado.Inicio = os.clock()
		estado.Desde = estado.Actual
		estado.Paso = 1
	end
end

-- Animación subida (AnimacionId): se reproduce con el Animator del modelo.
local function animacionSubida(modelo: Model, id: string)
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, pista = pcall(function()
		return animator:LoadAnimation(a)
	end)
	if ok and pista then
		pista.Priority = Enum.AnimationPriority.Action
		pista:Play(0.05)
	end
end

local function lerpPose(a: Pose, b: Pose, t: number, articulaciones: { [string]: Articulacion }): Pose
	local r: Pose = {}
	for nombre in articulaciones do
		r[nombre] = (a[nombre] or I):Lerp(b[nombre] or I, t)
	end
	return r
end

RunService.RenderStepped:Connect(function()
	local ahora = os.clock()
	for modelo, estado in animados do
		local anim = estado.Anim
		if not anim then
			continue
		end
		if not modelo.Parent then
			animados[modelo] = nil
			continue
		end
		local transcurrido = ahora - estado.Inicio
		local paso = anim.Pasos[estado.Paso]
		while paso and transcurrido >= paso.Duracion do
			transcurrido -= paso.Duracion
			estado.Desde = paso.Pose
			estado.Inicio += paso.Duracion
			estado.Paso += 1
			if estado.Paso > #anim.Pasos and anim.Bucle then
				estado.Paso = 2 -- el primer paso es la entrada; se repite desde el segundo
			end
			paso = anim.Pasos[estado.Paso]
		end
		if not paso then
			aplicarPose(estado, {})
			estado.Anim = nil
			continue
		end
		aplicarPose(
			estado,
			lerpPose(estado.Desde, paso.Pose, suavizado(transcurrido / paso.Duracion), estado.Articulaciones)
		)
	end
end)

------------------------------------------------------------------------
-- Efectos
------------------------------------------------------------------------

local function estelaArma(modelo: Model, color: Color3, duracion: number)
	local mano = manoDe(modelo)
	if not mano then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, -0.3, 0)
	a0.Parent = mano
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -3.2, -0.4) -- "hoja" imaginaria que sale de la mano
	a1.Parent = mano
	local estela = Instance.new("Trail")
	estela.Attachment0 = a0
	estela.Attachment1 = a1
	estela.Color = ColorSequence.new(color)
	estela.LightEmission = 1
	estela.Lifetime = 0.18
	estela.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	estela.Parent = mano
	task.delay(duracion, function()
		estela.Enabled = false
	end)
	Debris:AddItem(estela, duracion + 0.3)
	Debris:AddItem(a0, duracion + 0.3)
	Debris:AddItem(a1, duracion + 0.3)
end

local function chispas(posicion: Vector3, color: Color3)
	particulas(posicion, color, TEX_CHISPAS, 18, NumberRange.new(12, 22), NumberRange.new(0.2, 0.4), 0.5)
	local destello = parteFx(Vector3.new(1, 1, 1), color, Enum.PartType.Ball)
	destello.Position = posicion
	destello.Transparency = 0.2
	destello.Parent = carpeta
	tween(destello, 0.15, { Size = Vector3.new(3, 3, 3), Transparency = 1 })
	Debris:AddItem(destello, 0.2)
end

local function explosion(posicion: Vector3, color: Color3, tamano: number)
	local bola = parteFx(Vector3.new(1, 1, 1), color, Enum.PartType.Ball)
	bola.Position = posicion
	bola.Transparency = 0.1
	bola.Parent = carpeta
	luz(bola, color, 6, tamano * 3, 0.4)
	tween(bola, 0.3, { Size = Vector3.one * tamano, Transparency = 1 })
	Debris:AddItem(bola, 0.4)
	particulas(posicion, color, TEX_FUEGO, 25, NumberRange.new(8, 18), NumberRange.new(0.3, 0.6), tamano * 0.5)
	particulas(
		posicion,
		Color3.fromRGB(80, 70, 70),
		TEX_HUMO,
		10,
		NumberRange.new(3, 6),
		NumberRange.new(0.6, 1),
		tamano * 0.6
	)
end

local function onda(centro: Vector3, radio: number, color: Color3)
	local anillo = parteFx(Vector3.new(0.4, 2, 2), color, Enum.PartType.Cylinder)
	anillo.CFrame = CFrame.new(centro + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	anillo.Transparency = 0.25
	anillo.Parent = carpeta
	tween(anillo, 0.35, { Size = Vector3.new(0.4, radio * 2, radio * 2), Transparency = 1 })
	Debris:AddItem(anillo, 0.4)
	particulas(centro, color, TEX_HUMO, 16, NumberRange.new(radio * 0.8, radio * 1.4), NumberRange.new(0.4, 0.7), 2)
end

local function proyectil(desde: Vector3, objetivo: Model?, destinoFijo: Vector3?, def: any, alLlegar: (Vector3) -> ())
	local estilo = def.Estilo
	local color: Color3 = def.Color
	local tamano: number = def.Tamano or 1
	local cuerpo: Part
	if estilo == "Orbe" then
		cuerpo = parteFx(Vector3.one * tamano, color, Enum.PartType.Ball)
		luz(cuerpo, color, 3, 10, 2)
		-- Chispas (o fuego) que va dejando el orbe.
		local e = Instance.new("ParticleEmitter")
		e.Texture = if color.R > 0.8 and color.G < 0.6 then TEX_FUEGO else TEX_CHISPAS
		e.Color = ColorSequence.new(color)
		e.LightEmission = 1
		e.Rate = 60
		e.Speed = NumberRange.new(0, 1)
		e.Lifetime = NumberRange.new(0.2, 0.35)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6 * tamano), NumberSequenceKeypoint.new(1, 0) })
		e.Parent = cuerpo
	elseif estilo == "Espina" then
		cuerpo = parteFx(Vector3.new(0.3, 0.3, 1.6), color)
		cuerpo.Material = Enum.Material.Wood
	else -- Flecha
		cuerpo = parteFx(Vector3.new(0.15, 0.15, 2.4), color)
		cuerpo.Material = Enum.Material.SmoothPlastic
	end
	cuerpo.Position = desde
	cuerpo.Parent = carpeta
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.15, 0)
	a0.Parent = cuerpo
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.15, 0)
	a1.Parent = cuerpo
	local estela = Instance.new("Trail")
	estela.Attachment0 = a0
	estela.Attachment1 = a1
	estela.Color = ColorSequence.new(color)
	estela.LightEmission = 1
	estela.Lifetime = 0.25
	estela.WidthScale = NumberSequence.new(tamano)
	estela.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	estela.Parent = cuerpo

	local velocidad: number = def.Velocidad
	local inicio = os.clock()
	local conexion: RBXScriptConnection
	conexion = RunService.Heartbeat:Connect(function(dt: number)
		local raiz = if objetivo then raizDe(objetivo) else nil
		local destino = if raiz then raiz.Position elseif destinoFijo then destinoFijo else nil
		if not destino or os.clock() - inicio > 3 then
			conexion:Disconnect()
			cuerpo:Destroy()
			return
		end
		local hasta = destino - cuerpo.Position
		local paso = velocidad * dt
		if hasta.Magnitude <= paso then
			conexion:Disconnect()
			cuerpo:Destroy()
			alLlegar(destino)
			return
		end
		local nueva = cuerpo.Position + hasta.Unit * paso
		cuerpo.CFrame = CFrame.lookAt(nueva, destino)
	end)
end

local function haz(desde: Model, hasta: Model, color: Color3)
	local mano, raiz = manoDe(desde), raizDe(hasta)
	if not mano or not raiz then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Parent = mano
	local a1 = Instance.new("Attachment")
	a1.Parent = raiz
	local rayo = Instance.new("Beam")
	rayo.Attachment0 = a0
	rayo.Attachment1 = a1
	rayo.Color = ColorSequence.new(color)
	rayo.LightEmission = 1
	rayo.Width0 = 0.6
	rayo.Width1 = 0.9
	rayo.FaceCamera = true
	rayo.Transparency = NumberSequence.new(0.1)
	rayo.Parent = mano
	task.delay(0.15, function()
		for i = 1, 6 do
			rayo.Transparency = NumberSequence.new(0.1 + i * 0.15)
			task.wait(0.04)
		end
	end)
	Debris:AddItem(rayo, 0.5)
	Debris:AddItem(a0, 0.5)
	Debris:AddItem(a1, 0.5)
end

local function curacion(modelo: Model, color: Color3)
	local p = pies(modelo)
	if not p then
		return
	end
	particulas(
		p + Vector3.new(0, 1, 0),
		color,
		TEX_CHISPAS,
		24,
		NumberRange.new(3, 6),
		NumberRange.new(0.6, 1),
		0.6,
		0.5
	)
	local anillo = parteFx(Vector3.new(0.2, 5, 5), color, Enum.PartType.Cylinder)
	anillo.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90))
	anillo.Transparency = 0.4
	anillo.Parent = carpeta
	tween(anillo, 0.6, { Size = Vector3.new(0.2, 7, 7), Transparency = 1 })
	Debris:AddItem(anillo, 0.7)
end

local function veneno(modelo: Model, color: Color3)
	local raiz = raizDe(modelo)
	if raiz then
		particulas(raiz.Position, color, TEX_HUMO, 30, NumberRange.new(1, 3), NumberRange.new(0.6, 1), 1.2, 1.5)
	end
end

local function hielo(modelo: Model, color: Color3)
	local p = pies(modelo)
	if not p then
		return
	end
	for i = 1, 6 do
		local angulo = i * math.pi / 3
		local cristal = parteFx(Vector3.new(0.6, 2.4, 0.6), color)
		cristal.Material = Enum.Material.Glass
		cristal.Transparency = 0.3
		cristal.CFrame = CFrame.new(p + Vector3.new(math.cos(angulo) * 1.8, 0.6, math.sin(angulo) * 1.8))
			* CFrame.Angles(math.rad(math.cos(angulo) * 25), 0, math.rad(math.sin(angulo) * 25))
		cristal.Parent = carpeta
		task.delay(0.9, function()
			tween(cristal, 0.3, { Transparency = 1, Size = Vector3.new(0.1, 0.5, 0.1) })
		end)
		Debris:AddItem(cristal, 1.3)
	end
	particulas(
		p + Vector3.new(0, 1.5, 0),
		color,
		TEX_CHISPAS,
		20,
		NumberRange.new(2, 6),
		NumberRange.new(0.4, 0.8),
		0.5
	)
end

local function raices(modelo: Model, color: Color3)
	local p = pies(modelo)
	if not p then
		return
	end
	for i = 1, 6 do
		local angulo = i * math.pi / 3 + math.random()
		local raiz = parteFx(Vector3.new(0.6, 3, 0.6), color)
		raiz.Material = Enum.Material.Wood
		local base = p + Vector3.new(math.cos(angulo) * 1.6, -1.6, math.sin(angulo) * 1.6)
		raiz.CFrame = CFrame.new(base)
			* CFrame.Angles(math.rad(-math.sin(angulo) * 20), 0, math.rad(math.cos(angulo) * 20))
		raiz.Parent = carpeta
		tween(raiz, 0.2, { CFrame = raiz.CFrame + Vector3.new(0, 2.2, 0) }, Enum.EasingStyle.Back)
		task.delay(1.4, function()
			tween(raiz, 0.3, { CFrame = raiz.CFrame - Vector3.new(0, 3, 0) })
		end)
		Debris:AddItem(raiz, 1.8)
	end
end

local function escudo(modelo: Model, color: Color3)
	local raiz = raizDe(modelo)
	if not raiz then
		return
	end
	local burbuja = parteFx(Vector3.new(4, 4, 4), color, Enum.PartType.Ball)
	burbuja.Material = Enum.Material.ForceField
	burbuja.Transparency = 0.2
	burbuja.Position = raiz.Position
	burbuja.Parent = carpeta
	tween(burbuja, 0.25, { Size = Vector3.new(8, 8, 8) }, Enum.EasingStyle.Back)
	task.delay(0.9, function()
		tween(burbuja, 0.3, { Transparency = 1 })
	end)
	Debris:AddItem(burbuja, 1.3)
end

local function meteoro(centro: Vector3, radio: number, color: Color3)
	local roca = parteFx(Vector3.new(4, 4, 4), color, Enum.PartType.Ball)
	roca.Position = centro + Vector3.new(-15, 60, -15)
	roca.Parent = carpeta
	luz(roca, color, 5, 20, 0.6)
	particulas(roca.Position, color, TEX_FUEGO, 40, NumberRange.new(1, 3), NumberRange.new(0.4, 0.7), 3, 0.45)
	tween(roca, 0.45, { Position = centro }, Enum.EasingStyle.Linear)
	task.delay(0.45, function()
		roca:Destroy()
		explosion(centro, color, radio)
		onda(centro, radio, color)
	end)
end

local function lluvia(centro: Vector3, radio: number, color: Color3)
	for _ = 1, 16 do
		task.delay(math.random() * 0.6, function()
			local angulo = math.random() * math.pi * 2
			local d = math.sqrt(math.random()) * radio
			local destino = centro + Vector3.new(math.cos(angulo) * d, 0, math.sin(angulo) * d)
			proyectil(
				destino + Vector3.new(4, 40, 4),
				nil,
				destino,
				{ Estilo = "Flecha", Color = color, Velocidad = 120 },
				function(pos)
					chispas(pos, color)
				end
			)
		end)
	end
end

local function torbellino(modelo: Model, radio: number, color: Color3)
	local raiz = raizDe(modelo)
	if not raiz then
		return
	end
	local anillo = parteFx(Vector3.new(1, radio * 2, radio * 2), color, Enum.PartType.Cylinder)
	anillo.Transparency = 0.6
	anillo.CFrame = CFrame.new(raiz.Position) * CFrame.Angles(0, 0, math.rad(90))
	anillo.Parent = carpeta
	local inicio = os.clock()
	local conexion: RBXScriptConnection
	conexion = RunService.Heartbeat:Connect(function()
		local t = os.clock() - inicio
		if t > 0.45 or not raiz.Parent then
			conexion:Disconnect()
			anillo:Destroy()
			return
		end
		anillo.CFrame = CFrame.new(raiz.Position) * CFrame.Angles(t * 25, 0, math.rad(90))
		anillo.Transparency = 0.6 + t
	end)
	particulas(
		raiz.Position,
		color,
		TEX_CHISPAS,
		30,
		NumberRange.new(radio, radio * 1.5),
		NumberRange.new(0.2, 0.35),
		0.4
	)
end

local function aura(centro: Vector3, radio: number, color: Color3)
	onda(centro, radio, color)
	particulas(
		centro + Vector3.new(0, 1, 0),
		color,
		TEX_CHISPAS,
		40,
		NumberRange.new(4, 10),
		NumberRange.new(0.6, 1),
		0.7
	)
end

local function humo(modelo: Model, color: Color3)
	local raiz = raizDe(modelo)
	if raiz then
		particulas(raiz.Position, color, TEX_HUMO, 40, NumberRange.new(2, 6), NumberRange.new(0.8, 1.4), 4)
	end
end

local function impacto(modelo: Model, def: { Estilo: string, Color: Color3 })
	local raiz = raizDe(modelo)
	if not raiz then
		return
	end
	local e = def.Estilo
	if e == "Chispas" then
		chispas(raiz.Position, def.Color)
	elseif e == "Explosion" then
		explosion(raiz.Position, def.Color, 6)
	elseif e == "Veneno" then
		veneno(modelo, def.Color)
	elseif e == "Hielo" then
		hielo(modelo, def.Color)
	elseif e == "Raices" then
		raices(modelo, def.Color)
	elseif e == "Curacion" then
		curacion(modelo, def.Color)
	elseif e == "Escudo" then
		escudo(modelo, def.Color)
	end
end

local function area(lanzador: Model, centro: Vector3, radio: number, def: { Estilo: string, Color: Color3 })
	local e = def.Estilo
	if e == "Onda" then
		onda(centro, radio, def.Color)
	elseif e == "Meteoro" then
		meteoro(centro, radio, def.Color)
	elseif e == "Lluvia" then
		lluvia(centro, radio, def.Color)
	elseif e == "Torbellino" then
		torbellino(lanzador, radio, def.Color)
	elseif e == "Aura" then
		aura(centro, radio, def.Color)
	elseif e == "Humo" then
		humo(lanzador, def.Color)
	end
end

------------------------------------------------------------------------
-- Círculo de casteo
------------------------------------------------------------------------

local circulos: { [Model]: { Parte: Part, Conexion: RBXScriptConnection } } = {}

local function terminarCasteo(modelo: Model)
	local c = circulos[modelo]
	if c then
		c.Conexion:Disconnect()
		tween(c.Parte, 0.2, { Transparency = 1 })
		Debris:AddItem(c.Parte, 0.25)
		circulos[modelo] = nil
	end
	detenerBucle(modelo)
end

local function empezarCasteo(modelo: Model, visual: VisualConfig.Visual, duracion: number)
	terminarCasteo(modelo)
	animar(modelo, visual.AnimCasteo or "Conjurar")
	local color = visual.Casteo
	if not color then
		return
	end
	local circulo = parteFx(Vector3.new(0.2, 7, 7), color, Enum.PartType.Cylinder)
	circulo.Transparency = 0.45
	circulo.Parent = carpeta
	local brillo = Instance.new("PointLight")
	brillo.Color = color
	brillo.Range = 10
	brillo.Brightness = 2
	brillo.Parent = circulo
	local inicio = os.clock()
	local conexion = RunService.Heartbeat:Connect(function()
		local p = pies(modelo)
		if not p or os.clock() - inicio > duracion + 0.5 then
			terminarCasteo(modelo)
			return
		end
		local t = os.clock() - inicio
		local escala = 0.75 + 0.25 * math.sin(t * 6)
		circulo.Size = Vector3.new(0.2, 7 * escala, 7 * escala)
		circulo.CFrame = CFrame.new(p + Vector3.new(0, 0.15, 0)) * CFrame.Angles(t * 2, 0, math.rad(90))
	end)
	circulos[modelo] = { Parte = circulo, Conexion = conexion }
	local mano = manoDe(modelo)
	if mano then
		particulas(
			mano.Position,
			color,
			TEX_CHISPAS,
			math.floor(duracion * 25),
			NumberRange.new(1, 3),
			NumberRange.new(0.3, 0.5),
			0.4,
			duracion
		)
	end
end

------------------------------------------------------------------------
-- Eventos del servidor
------------------------------------------------------------------------

local function alAccion(lanzador: Model, habilidad: string, extra: any)
	local visual = VisualConfig[habilidad]
	if not visual then
		return
	end
	terminarCasteo(lanzador)
	if visual.AnimacionId then
		animacionSubida(lanzador, visual.AnimacionId)
	else
		animar(lanzador, visual.Anim)
	end
	if visual.Arma then
		estelaArma(lanzador, visual.Arma, 0.35)
	end

	local objetivo: Model? = if typeof(extra) == "table"
			and typeof(extra.Objetivo) == "Instance"
			and extra.Objetivo:IsA("Model")
		then extra.Objetivo
		else nil
	local alcanzados: { Model } = {}
	if typeof(extra) == "table" and typeof(extra.Alcanzados) == "table" then
		for _, m in extra.Alcanzados do
			if typeof(m) == "Instance" and m:IsA("Model") then
				table.insert(alcanzados, m)
			end
		end
	end
	if #alcanzados == 0 and objetivo then
		alcanzados = { objetivo }
	end

	if visual.Haz and objetivo and objetivo ~= lanzador then
		haz(lanzador, objetivo, visual.Haz)
	end

	local function impactarTodos()
		if visual.Impacto then
			for _, m in alcanzados do
				impacto(m, visual.Impacto)
			end
		end
	end

	local def = visual.Proyectil
	if def and objetivo and objetivo ~= lanzador then
		local mano = manoDe(lanzador)
		-- Sale un instante después, cuando el brazo termina el gesto.
		task.delay(0.15, function()
			if not mano or not mano.Parent then
				return
			end
			proyectil(mano.Position, objetivo, nil, def, function()
				impactarTodos()
			end)
		end)
	else
		task.delay(if visual.Anim == "Pesado" or visual.Anim == "Pisoton" then 0.28 else 0.15, impactarTodos)
	end

	if visual.Area then
		local centro: Vector3? = if typeof(extra) == "table" and typeof(extra.Centro) == "Vector3"
			then extra.Centro
			else nil
		local radio: number = if typeof(extra) == "table" and typeof(extra.Radio) == "number" then extra.Radio else 10
		local raiz = raizDe(lanzador)
		local c = centro or (raiz and raiz.Position)
		if c then
			local demora = if visual.Anim == "Pisoton" then 0.28 else 0.12
			task.delay(demora, function()
				area(lanzador, c :: Vector3, radio, visual.Area :: any)
			end)
		end
	end
end

-- Destello blanco breve sobre quien recibe daño.
local function destello(modelo: Model)
	local h = Instance.new("Highlight")
	h.FillColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.4
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = modelo
	h.Parent = carpeta
	tween(h, 0.15, { FillTransparency = 1 })
	Debris:AddItem(h, 0.2)
end

NetworkBridge.Client.OnEvent("CombateEvento", function(tipo: any, modelo: any, valor: any, extra: any)
	if typeof(modelo) ~= "Instance" or not modelo:IsA("Model") then
		return
	end
	if tipo == "Accion" and typeof(valor) == "string" then
		alAccion(modelo, valor, extra)
	elseif tipo == "Casteo" and typeof(valor) == "string" then
		local visual = VisualConfig[valor]
		local duracion = if typeof(extra) == "table" and typeof(extra.Duracion) == "number" then extra.Duracion else 1.5
		if visual then
			empezarCasteo(modelo, visual, duracion)
		end
	elseif tipo == "CasteoFin" or (tipo == "Estado" and valor == "Aturdido") then
		terminarCasteo(modelo)
	elseif tipo == "Estado" and valor == "¡!" then
		-- Los enemigos levantan el arma antes de golpear: es la señal del parry.
		animar(modelo, "Preparar")
		local estado = animados[modelo]
		if estado and estado.Anim then
			-- Que el golpe llegue justo cuando termina el aviso.
			local primer = estado.Anim.Pasos[1]
			local espera = EnemigosConfig.AvisoAtaque
			estado.Anim = {
				Pasos = {
					{ Duracion = math.min(0.2, espera * 0.5), Pose = primer.Pose },
					{ Duracion = espera, Pose = primer.Pose },
					{ Duracion = 0.2, Pose = {} },
				},
			}
		end
	elseif tipo == "Danio" then
		destello(modelo)
	end
end)

-- Si muere el personaje propio, se limpia su estado de animación.
jugador.CharacterRemoving:Connect(function(personaje: Model)
	animados[personaje] = nil
	terminarCasteo(personaje)
end)
