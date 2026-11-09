--!strict
-- ArenaGuerra: mapa y planos holográficos de la Guerra de Arquitectos.
--
-- Convención del mapa (si lo armás a mano en Studio):
--   Workspace.GuerraArquitectos
--     Base_Azul / Base_Rojo (Folder o Model)
--       Centro    (Part anclada)  -> origen del castillo
--       Deposito  (Part)          -> donde se entregan recursos
--       Spawn     (SpawnLocation) -> aparición del equipo
--       Plano     (Folder, opcional) -> Parts con atributo Etapa = 1..5.
--                                       Si no existe, el castillo se genera solo.
--     Recursos (Folder) -> Parts con atributo Recurso = "Madera" | "Piedra" | "Hierro"
-- Si la carpeta no existe y se está probando en Studio, se genera una arena completa.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuerraConfig = require(ReplicatedStorage.Configs.GuerraConfig)

export type Base = {
	EquipoId: string,
	Centro: BasePart,
	Deposito: BasePart,
	Spawn: SpawnLocation,
	PartesPorEtapa: { [number]: { BasePart } },
	-- Partes con color de equipo (bandera): no adoptan la skin.
	ColorEquipo: { [BasePart]: boolean },
}

export type Mapa = {
	Carpeta: Instance,
	Bases: { [string]: Base },
	Nodos: { BasePart },
}

local ArenaGuerra = {}

local CENTRO_ARENA = Vector3.new(0, 0, 220)
local SEPARACION_BASES = 95

------------------------------------------------------------------------
-- Utilidades de construcción
------------------------------------------------------------------------

local function parte(props: {
	Nombre: string,
	Tamano: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Padre: Instance,
	Forma: Enum.PartType?,
}): Part
	local p = Instance.new("Part")
	p.Name = props.Nombre
	p.Anchored = true
	p.Size = props.Tamano
	p.CFrame = props.CFrame
	p.Color = props.Color or Color3.fromRGB(160, 160, 160)
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Forma then
		p.Shape = props.Forma
	end
	p.Parent = props.Padre
	return p
end

local function cartel(adorno: BasePart, texto: string, alto: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(8, 1.6)
	gui.StudsOffset = Vector3.new(0, alto, 0)
	gui.MaxDistance = 120
	local etiqueta = Instance.new("TextLabel")
	etiqueta.Size = UDim2.fromScale(1, 1)
	etiqueta.BackgroundTransparency = 1
	etiqueta.TextScaled = true
	etiqueta.Font = Enum.Font.GothamBold
	etiqueta.TextColor3 = Color3.new(1, 1, 1)
	etiqueta.TextStrokeTransparency = 0.3
	etiqueta.Text = texto
	etiqueta.Parent = gui
	gui.Parent = adorno
end

-- Piezas del castillo por etapa, relativas al Centro (40x40 studs).
type Pieza = { Nombre: string, Tamano: Vector3, Offset: Vector3, ColorEquipo: boolean? }
local PIEZAS: { [number]: { Pieza } } = {
	[1] = { -- Fundación
		{ Nombre = "Losa", Tamano = Vector3.new(40, 2, 40), Offset = Vector3.new(0, 1, 0) },
	},
	[2] = { -- Muros
		{ Nombre = "MuroNorte", Tamano = Vector3.new(40, 12, 2), Offset = Vector3.new(0, 8, -19) },
		{ Nombre = "MuroSurIzq", Tamano = Vector3.new(16, 12, 2), Offset = Vector3.new(-12, 8, 19) },
		{ Nombre = "MuroSurDer", Tamano = Vector3.new(16, 12, 2), Offset = Vector3.new(12, 8, 19) },
		{ Nombre = "MuroEste", Tamano = Vector3.new(2, 12, 36), Offset = Vector3.new(19, 8, 0) },
		{ Nombre = "MuroOeste", Tamano = Vector3.new(2, 12, 36), Offset = Vector3.new(-19, 8, 0) },
	},
	[3] = { -- Torres
		{ Nombre = "TorreNE", Tamano = Vector3.new(7, 20, 7), Offset = Vector3.new(19, 12, -19) },
		{ Nombre = "TorreNO", Tamano = Vector3.new(7, 20, 7), Offset = Vector3.new(-19, 12, -19) },
		{ Nombre = "TorreSE", Tamano = Vector3.new(7, 20, 7), Offset = Vector3.new(19, 12, 19) },
		{ Nombre = "TorreSO", Tamano = Vector3.new(7, 20, 7), Offset = Vector3.new(-19, 12, 19) },
	},
	[4] = { -- Gran Salón
		{ Nombre = "Salon", Tamano = Vector3.new(16, 10, 16), Offset = Vector3.new(0, 7, -4) },
		{ Nombre = "Techo", Tamano = Vector3.new(18, 2, 18), Offset = Vector3.new(0, 13, -4) },
	},
	[5] = { -- Estandarte
		{ Nombre = "Mastil", Tamano = Vector3.new(1, 16, 1), Offset = Vector3.new(0, 22, -4) },
		{
			Nombre = "Bandera",
			Tamano = Vector3.new(6, 4, 0.3),
			Offset = Vector3.new(3.5, 28, -4),
			ColorEquipo = true,
		},
	},
}

local function generarPlano(centro: BasePart, carpeta: Instance, colorEquipo: Color3)
	local plano = Instance.new("Folder")
	plano.Name = "Plano"
	for etapa, piezas in PIEZAS do
		for _, pieza in piezas do
			local p = parte({
				Nombre = `{etapa}_{pieza.Nombre}`,
				Tamano = pieza.Tamano,
				CFrame = centro.CFrame * CFrame.new(pieza.Offset),
				Padre = plano,
				Color = if pieza.ColorEquipo then colorEquipo else nil,
			})
			p:SetAttribute("Etapa", etapa)
			if pieza.ColorEquipo then
				p:SetAttribute("ColorEquipo", true)
			end
		end
	end
	plano.Parent = carpeta
end

local function prompt(padre: BasePart, accion: string, objeto: string, duracion: number)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = accion
	pp.ObjectText = objeto
	pp.HoldDuration = duracion
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.Parent = padre
end

------------------------------------------------------------------------
-- Arena de prueba
------------------------------------------------------------------------

local function generarArena(): Folder
	local raiz = Instance.new("Folder")
	raiz.Name = GuerraConfig.NombreCarpetaMapa

	parte({
		Nombre = "Suelo",
		Tamano = Vector3.new(300, 1, 160),
		CFrame = CFrame.new(CENTRO_ARENA + Vector3.new(0, -0.4, 0)),
		Color = Color3.fromRGB(95, 140, 75),
		Material = Enum.Material.Grass,
		Padre = raiz,
	})

	for i, equipo in GuerraConfig.Equipos do
		local lado = if i == 1 then -1 else 1
		local base = Instance.new("Folder")
		base.Name = `Base_{equipo.Id}`
		local origen = CENTRO_ARENA + Vector3.new(lado * SEPARACION_BASES, 0, 0)

		local centro = parte({
			Nombre = "Centro",
			Tamano = Vector3.new(44, 0.2, 44),
			CFrame = CFrame.new(origen + Vector3.new(0, 0.1, 0)),
			Color = equipo.Color.Color,
			Material = Enum.Material.Concrete,
			Padre = base,
		})
		centro.Transparency = 0.6
		centro.CanCollide = false

		local deposito = parte({
			Nombre = "Deposito",
			Tamano = Vector3.new(6, 4, 4),
			CFrame = CFrame.new(origen + Vector3.new(-lado * 28, 2, 0)),
			Color = Color3.fromRGB(120, 85, 50),
			Material = Enum.Material.WoodPlanks,
			Padre = base,
		})
		cartel(deposito, `Depósito {equipo.Nombre}`, 4)

		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.CFrame = CFrame.new(origen + Vector3.new(-lado * 36, 0.5, 12))
		spawn.Neutral = false
		spawn.TeamColor = equipo.Color
		spawn.BrickColor = equipo.Color
		spawn.Duration = 0
		spawn.Parent = base

		generarPlano(centro, base, equipo.Color.Color)
		base.Parent = raiz
	end

	-- Nodos de recursos en la franja central, en posiciones fijas.
	local recursos = Instance.new("Folder")
	recursos.Name = "Recursos"
	local disposicion: { { recurso: string, x: number, z: number } } = {
		{ recurso = "Madera", x = -40, z = -45 },
		{ recurso = "Madera", x = -15, z = -55 },
		{ recurso = "Madera", x = 15, z = -55 },
		{ recurso = "Madera", x = 40, z = -45 },
		{ recurso = "Madera", x = -30, z = 45 },
		{ recurso = "Madera", x = 30, z = 45 },
		{ recurso = "Piedra", x = -25, z = -20 },
		{ recurso = "Piedra", x = 25, z = -20 },
		{ recurso = "Piedra", x = 0, z = 0 },
		{ recurso = "Piedra", x = -25, z = 20 },
		{ recurso = "Piedra", x = 25, z = 20 },
		{ recurso = "Hierro", x = 0, z = -30 },
		{ recurso = "Hierro", x = 0, z = 30 },
		{ recurso = "Hierro", x = 0, z = 60 },
	}
	for i, d in disposicion do
		local pos = CENTRO_ARENA + Vector3.new(d.x, 0, d.z)
		local nodo: Part
		if d.recurso == "Madera" then
			nodo = parte({
				Nombre = `Arbol{i}`,
				Tamano = Vector3.new(10, 3, 3),
				CFrame = CFrame.new(pos + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(105, 70, 40),
				Material = Enum.Material.Wood,
				Forma = Enum.PartType.Cylinder,
				Padre = recursos,
			})
		elseif d.recurso == "Piedra" then
			nodo = parte({
				Nombre = `Roca{i}`,
				Tamano = Vector3.new(6, 5, 6),
				CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0)),
				Color = Color3.fromRGB(125, 125, 130),
				Material = Enum.Material.Rock,
				Padre = recursos,
			})
		else
			nodo = parte({
				Nombre = `Veta{i}`,
				Tamano = Vector3.new(4, 4, 4),
				CFrame = CFrame.new(pos + Vector3.new(0, 2, 0)) * CFrame.Angles(0.4, 0.6, 0),
				Color = Color3.fromRGB(150, 110, 90),
				Material = Enum.Material.CrackedLava,
				Padre = recursos,
			})
		end
		nodo:SetAttribute("Recurso", d.recurso)
	end
	recursos.Parent = raiz

	raiz.Parent = Workspace
	return raiz
end

------------------------------------------------------------------------
-- Lectura del mapa
------------------------------------------------------------------------

local function leerBase(carpetaBase: Instance, equipoId: string, colorEquipo: Color3): Base?
	local centro = carpetaBase:FindFirstChild("Centro")
	local deposito = carpetaBase:FindFirstChild("Deposito")
	local spawn = carpetaBase:FindFirstChild("Spawn")
	if not (centro and centro:IsA("BasePart")) or not (deposito and deposito:IsA("BasePart")) then
		warn(`[ArenaGuerra] {carpetaBase:GetFullName()} necesita Centro y Deposito (Parts)`)
		return nil
	end
	if not (spawn and spawn:IsA("SpawnLocation")) then
		warn(`[ArenaGuerra] {carpetaBase:GetFullName()} necesita un SpawnLocation llamado Spawn`)
		return nil
	end
	if not carpetaBase:FindFirstChild("Plano") then
		generarPlano(centro, carpetaBase, colorEquipo)
	end

	local porEtapa: { [number]: { BasePart } } = {}
	local colorEq: { [BasePart]: boolean } = {}
	for _, objeto in (carpetaBase:FindFirstChild("Plano") :: Instance):GetDescendants() do
		local etapa = objeto:GetAttribute("Etapa")
		if objeto:IsA("BasePart") and typeof(etapa) == "number" then
			local lista = porEtapa[etapa]
			if not lista then
				lista = {}
				porEtapa[etapa] = lista
			end
			table.insert(lista, objeto)
			if objeto:GetAttribute("ColorEquipo") == true then
				colorEq[objeto] = true
			end
		end
	end

	if not deposito:FindFirstChildOfClass("ProximityPrompt") then
		prompt(deposito, "Depositar", "Recursos", 0)
	end

	return {
		EquipoId = equipoId,
		Centro = centro,
		Deposito = deposito,
		Spawn = spawn,
		PartesPorEtapa = porEtapa,
		ColorEquipo = colorEq,
	}
end

-- Encuentra el mapa (o genera la arena de prueba si `generarSiFalta`).
function ArenaGuerra.Obtener(generarSiFalta: boolean): Mapa?
	local carpeta = Workspace:FindFirstChild(GuerraConfig.NombreCarpetaMapa)
	if not carpeta then
		if not generarSiFalta then
			return nil
		end
		carpeta = generarArena()
	end
	assert(carpeta, "No se pudo obtener la carpeta del mapa")

	local bases: { [string]: Base } = {}
	for _, equipo in GuerraConfig.Equipos do
		local carpetaBase = carpeta:FindFirstChild(`Base_{equipo.Id}`)
		local base = carpetaBase and leerBase(carpetaBase, equipo.Id, equipo.Color.Color)
		if not base then
			warn(`[ArenaGuerra] Falta o está incompleta Base_{equipo.Id}`)
			return nil
		end
		bases[equipo.Id] = base
	end

	local nodos: { BasePart } = {}
	local carpetaRecursos = carpeta:FindFirstChild("Recursos")
	if carpetaRecursos then
		for _, objeto in carpetaRecursos:GetDescendants() do
			local recurso = objeto:GetAttribute("Recurso")
			if objeto:IsA("BasePart") and typeof(recurso) == "string" and GuerraConfig.Recursos[recurso :: any] then
				local def = GuerraConfig.Recursos[recurso :: any]
				local pp = objeto:FindFirstChildOfClass("ProximityPrompt")
				if not pp then
					prompt(objeto, "Recolectar", def.Nombre, def.Duracion)
				else
					-- Prompts puestos a mano: se fuerza la configuración que valida el servidor.
					pp.HoldDuration = def.Duracion
					pp.MaxActivationDistance = 10
				end
				table.insert(nodos, objeto)
			end
		end
	end

	return { Carpeta = carpeta, Bases = bases, Nodos = nodos }
end

------------------------------------------------------------------------
-- Aspecto del plano
------------------------------------------------------------------------

-- Holograma: la etapa en curso se ve marcada, las siguientes muy tenues.
function ArenaGuerra.MostrarPlano(base: Base, etapaActual: number)
	for etapa, partes in base.PartesPorEtapa do
		for _, p in partes do
			if etapa < etapaActual then
				continue -- ya construida
			end
			p.Material = Enum.Material.ForceField
			p.Color = if base.ColorEquipo[p] then p.Color else GuerraConfig.ColorHolograma
			p.Transparency = if etapa == etapaActual then 0.2 else 0.85
			p.CanCollide = false
			p.CanQuery = false
			p.CastShadow = false
		end
	end
end

-- Personajes (Models con Humanoid) que ocupan el espacio de una etapa.
-- Se usa para sacarlos antes de volver sólidas las piezas.
function ArenaGuerra.PersonajesDentro(base: Base, etapa: number): { Model }
	local encontrados: { Model } = {}
	local vistos: { [Model]: boolean } = {}
	local params = OverlapParams.new()
	local partes: { BasePart } = base.PartesPorEtapa[etapa] or {}
	for _, p in partes do
		for _, otra in Workspace:GetPartBoundsInBox(p.CFrame, p.Size + Vector3.new(2, 2, 2), params) do
			local modelo = otra:FindFirstAncestorOfClass("Model")
			if modelo and not vistos[modelo] and modelo:FindFirstChildOfClass("Humanoid") then
				vistos[modelo] = true
				table.insert(encontrados, modelo)
			end
		end
	end
	return encontrados
end

-- Convierte una etapa en estructura sólida con el aspecto de la skin indicada.
function ArenaGuerra.Construir(base: Base, etapa: number, skin: string, colorEquipo: Color3)
	local aspecto = GuerraConfig.Skins[skin] or GuerraConfig.Skins.Ninguna
	local partes: { BasePart } = base.PartesPorEtapa[etapa] or {}
	for _, p in partes do
		p.Transparency = 0
		p.Reflectance = 0
		CollectionService:RemoveTag(p, "PiedraCastillo")
		if base.ColorEquipo[p] then
			p.Material = Enum.Material.Fabric
			p.Color = colorEquipo
		else
			p.Material = aspecto.Material
			p.Color = aspecto.Color
			p.Reflectance = aspecto.Reflejo or 0
			p.Transparency = aspecto.Transparencia or 0
			local fisica = aspecto.Fisica
			if fisica then
				p.CustomPhysicalProperties =
					PhysicalProperties.new(fisica.Densidad, fisica.Friccion, fisica.Elasticidad)
			else
				(p :: any).CustomPhysicalProperties = nil
			end
			if skin == "Ninguna" or not GuerraConfig.Skins[skin] then
				-- La piedra base del castillo: la edita el NPC editor (EditorPiedra).
				CollectionService:AddTag(p, "PiedraCastillo")
			end
		end
		p.CanCollide = true
		p.CanQuery = true
		p.CastShadow = true

		-- Ráfaga de partículas en cada pieza.
		local emisor = Instance.new("ParticleEmitter")
		emisor.Color = ColorSequence.new(aspecto.Color, Color3.new(1, 1, 1))
		emisor.LightEmission = 0.6
		emisor.Lifetime = NumberRange.new(0.6, 1.2)
		emisor.Speed = NumberRange.new(6, 14)
		emisor.SpreadAngle = Vector2.new(180, 180)
		emisor.Size = NumberSequence.new(0.8, 0)
		emisor.Rate = 0
		emisor.Parent = p
		emisor:Emit(25)
		task.delay(2, function()
			emisor:Destroy()
		end)
	end

	if GuerraConfig.SonidoEtapa ~= "" then
		local sonido = Instance.new("Sound")
		sonido.SoundId = GuerraConfig.SonidoEtapa
		sonido.Volume = 1
		sonido.RollOffMaxDistance = 300
		sonido.Parent = base.Centro
		sonido:Play()
		sonido.Ended:Once(function()
			sonido:Destroy()
		end)
	end
end

return ArenaGuerra
