--!strict
-- MinimapaUI: minimapa circular (radar HUD). Solo visual.
--
-- Método: radar 2D por coordenadas (no ViewportFrame). Un ViewportFrame
-- tendría que clonar el mapa y redibujarlo en 3D; el radar solo mueve unos
-- pocos puntos de interfaz, y con muchos jugadores cuesta casi lo mismo.
--
-- * Arriba a la derecha (a la izquierda con el ajuste "Zurdo"), con marco
--   metálico y máscara circular: el disco es un CanvasGroup con UICorner al
--   máximo, que sí recorta lo que se sale del círculo (ClipsDescendants solo
--   no recorta esquinas redondeadas).
-- * Gira con la cámara: arriba es hacia donde mirás. La flecha del centro es
--   tu personaje. Puntos (ver Modules/Radar): grupo (azul; en el borde si
--   están lejos), enemigos (rojo), élites y jefes (rombo rojo grande), NPCs de
--   misión (! y ?), recursos (cuadrado amarillo), restos del Spoil (✦
--   amarillo), portales (violeta).
-- * Se actualiza en cada frame (RenderStepped). Botones + y − cambian la
--   distancia que cubre; "M" abre el mapa del mundo.
-- * Debajo: zona, coordenadas y servidor. Se oculta desde el panel Personaje.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ZoneConfig = require(ReplicatedStorage.Configs.ZoneConfig)
local Hud = require(ReplicatedStorage.Modules.Hud)
local Radar = require(ReplicatedStorage.Modules.Radar)
local EventosCliente = require(ReplicatedStorage.Modules.EventosCliente)

local jugador = Players.LocalPlayer

local TAM = 180 -- diámetro del disco en píxeles (antes de escalar)
local MARCO = 8 -- grosor del marco metálico
local ZOOMS = { 60, 120, 240, 480 } -- radio en studs

type Estilo = { Color: Color3, Tam: number, Texto: string?, Borde: boolean?, Z: number }
local ESTILOS: { [Radar.Tipo]: Estilo } = {
	Grupo = { Color = Color3.fromRGB(80, 160, 255), Tam = 9, Borde = true, Z = 6 },
	Enemigo = { Color = Color3.fromRGB(235, 70, 60), Tam = 6, Z = 4 },
	Elite = { Color = Color3.fromRGB(255, 60, 40), Tam = 18, Texto = "◆", Z = 5 },
	Mision = { Color = Color3.fromRGB(255, 215, 60), Tam = 18, Z = 5 },
	Recurso = { Color = Color3.fromRGB(255, 205, 50), Tam = 5, Z = 2 },
	Restos = { Color = Color3.fromRGB(255, 225, 60), Tam = 17, Texto = "✦", Z = 5 },
	Portal = { Color = Color3.fromRGB(190, 110, 255), Tam = 15, Texto = "◈", Z = 3 },
	Estacion = { Color = Color3.fromRGB(200, 200, 210), Tam = 4, Z = 1 },
}

local gui = Instance.new("ScreenGui")
gui.Name = "MinimapaUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 39
gui.Parent = jugador:WaitForChild("PlayerGui")

local contenedor = Instance.new("Frame")
contenedor.Name = "Minimapa"
contenedor.Size = UDim2.fromOffset(TAM + MARCO * 2, TAM + MARCO * 2 + 52)
contenedor.BackgroundTransparency = 1
contenedor.Parent = gui
Hud.Registrar(contenedor)

------------------------------------------------------------------------
-- Marco metálico
------------------------------------------------------------------------

local marco = Instance.new("Frame")
marco.Name = "Marco"
marco.Size = UDim2.fromOffset(TAM + MARCO * 2, TAM + MARCO * 2)
marco.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
marco.BorderSizePixel = 0
local redondo = Instance.new("UICorner")
redondo.CornerRadius = UDim.new(0.5, 0)
redondo.Parent = marco
local metal = Instance.new("UIGradient")
metal.Rotation = 50
metal.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 240, 225)),
	ColorSequenceKeypoint.new(0.3, Color3.fromRGB(120, 105, 80)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(225, 205, 150)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(85, 75, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 175, 140)),
})
metal.Parent = marco
local filo = Instance.new("UIStroke")
filo.Color = Color3.fromRGB(35, 30, 25)
filo.Thickness = 2
filo.Parent = marco
marco.Parent = contenedor

-- Remaches en los cuatro puntos cardinales.
for _, pos in { Vector2.new(0.5, 0), Vector2.new(1, 0.5), Vector2.new(0.5, 1), Vector2.new(0, 0.5) } do
	local remache = Instance.new("Frame")
	remache.AnchorPoint = Vector2.new(0.5, 0.5)
	remache.Size = UDim2.fromOffset(9, 9)
	local total = TAM + MARCO * 2
	remache.Position = UDim2.fromOffset(pos.X * total + (0.5 - pos.X) * MARCO, pos.Y * total + (0.5 - pos.Y) * MARCO)
	remache.BackgroundColor3 = Color3.fromRGB(70, 60, 45)
	remache.ZIndex = 9
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = remache
	local b = Instance.new("UIStroke")
	b.Color = Color3.fromRGB(235, 220, 170)
	b.Parent = remache
	remache.Parent = contenedor
end

------------------------------------------------------------------------
-- Disco (máscara circular)
------------------------------------------------------------------------

local disco = Instance.new("CanvasGroup")
disco.Name = "Disco"
disco.Position = UDim2.fromOffset(MARCO, MARCO)
disco.Size = UDim2.fromOffset(TAM, TAM)
disco.BackgroundColor3 = Color3.fromRGB(18, 26, 22)
disco.BorderSizePixel = 0
disco.ZIndex = 2
local mascara = Instance.new("UICorner")
mascara.CornerRadius = UDim.new(0.5, 0)
mascara.Parent = disco
disco.Parent = contenedor

local anillo = Instance.new("Frame")
anillo.AnchorPoint = Vector2.new(0.5, 0.5)
anillo.Position = UDim2.fromScale(0.5, 0.5)
anillo.Size = UDim2.fromScale(0.5, 0.5)
anillo.BackgroundTransparency = 1
local ca = Instance.new("UICorner")
ca.CornerRadius = UDim.new(0.5, 0)
ca.Parent = anillo
local ba = Instance.new("UIStroke")
ba.Color = Color3.fromRGB(90, 120, 100)
ba.Transparency = 0.6
ba.Parent = anillo
anillo.Parent = disco

local function simbolo(texto: string, tam: number, color: Color3, z: number): TextLabel
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Size = UDim2.fromOffset(tam, tam)
	t.BackgroundTransparency = 1
	t.Text = texto
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.ZIndex = z
	t.Parent = disco
	return t
end

local flecha = simbolo("▲", 20, Color3.new(1, 1, 1), 8)
local norte = simbolo("N", 16, Color3.fromRGB(255, 120, 100), 7)

-- Puntos reutilizables.
type Punto = { Marco: TextLabel, Redondo: UICorner, Borde: UIStroke }
local pool: { Punto } = {}
local function punto(i: number): Punto
	local existente = pool[i]
	if existente then
		return existente
	end
	local p = Instance.new("TextLabel")
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.BorderSizePixel = 0
	p.Font = Enum.Font.GothamBlack
	p.TextScaled = true
	p.TextStrokeTransparency = 0.2
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = p
	local b = Instance.new("UIStroke")
	b.Color = Color3.new(1, 1, 1)
	b.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	b.Parent = p
	p.Parent = disco
	local nuevo: Punto = { Marco = p, Redondo = c, Borde = b }
	pool[i] = nuevo
	return nuevo
end

------------------------------------------------------------------------
-- Textos y botones
------------------------------------------------------------------------

local function texto(y: number, alto: number, fuente: Enum.Font, color: Color3): TextLabel
	local e = Instance.new("TextLabel")
	e.Position = UDim2.fromOffset(0, TAM + MARCO * 2 + y)
	e.Size = UDim2.fromOffset(TAM + MARCO * 2, alto)
	e.BackgroundTransparency = 1
	e.Font = fuente
	e.TextScaled = true
	e.TextColor3 = color
	e.TextStrokeTransparency = 0.4
	e.Parent = contenedor
	return e
end

local textoZona = texto(2, 18, Enum.Font.GothamBold, Color3.fromRGB(255, 215, 90))
local textoCoords = texto(20, 14, Enum.Font.GothamMedium, Color3.new(1, 1, 1))
local textoServidor = texto(35, 13, Enum.Font.Gotham, Color3.fromRGB(180, 180, 190))
textoServidor.Text = if game.JobId == "" then "Servidor local" else `Servidor {string.sub(game.JobId, 1, 6)}`

local function botonRedondo(t: string, pos: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = pos
	b.Size = UDim2.fromOffset(28, 28)
	b.BackgroundColor3 = Color3.fromRGB(45, 40, 32)
	b.TextColor3 = Color3.fromRGB(245, 230, 190)
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.Text = t
	b.ZIndex = 10
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	local borde = Instance.new("UIStroke")
	borde.Color = Color3.fromRGB(215, 195, 140)
	borde.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	borde.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	b.Parent = contenedor
	return b
end

local lado = TAM + MARCO * 2
local zoom = 2
local masZoom = botonRedondo("+", UDim2.fromOffset(lado - 10, lado - 44))
local menosZoom = botonRedondo("−", UDim2.fromOffset(lado - 10, lado - 12))
local botonMapa = botonRedondo("M", UDim2.fromOffset(10, lado - 12))
masZoom.Activated:Connect(function()
	zoom = math.max(1, zoom - 1) -- acercar: menos studs en el mismo círculo
end)
menosZoom.Activated:Connect(function()
	zoom = math.min(#ZOOMS, zoom + 1)
end)
botonMapa.Activated:Connect(function()
	EventosCliente.AlternarMapa:Fire()
end)

------------------------------------------------------------------------
-- Dibujo por frame
------------------------------------------------------------------------

local MEDIO = TAM / 2
local GRIS = Color3.fromRGB(190, 190, 190)

RunService.RenderStepped:Connect(function()
	if not contenedor.Visible then
		return
	end
	local raiz = Radar.ParteDe(jugador.Character)
	local camara = Workspace.CurrentCamera
	if not raiz or not camara then
		return
	end
	local centro = raiz.Position
	local radio = ZOOMS[zoom]
	local escala = (MEDIO - 6) / radio -- píxeles por stud

	-- Giro: lo que la cámara tiene adelante queda arriba.
	local mira = camara.CFrame.LookVector
	local giro = -math.atan2(mira.X, -mira.Z)
	local cosG, sinG = math.cos(giro), math.sin(giro)
	local frente = raiz.CFrame.LookVector
	flecha.Rotation = math.deg(math.atan2(frente.X, -frente.Z) + giro)
	norte.Position = UDim2.fromOffset(MEDIO + sinG * (MEDIO - 10), MEDIO - cosG * (MEDIO - 10))

	-- Mundo (x, z) -> píxeles del disco, relativo al jugador: la diferencia en
	-- studs (dx, dz) se rota por el ángulo de la cámara y se multiplica por
	-- `escala`. El +Z del mundo queda hacia abajo.
	local usados = 0
	for _, e in Radar.Entidades() do
		local parte = e.Parte
		if not parte.Parent then
			continue
		end
		local dx, dz = parte.Position.X - centro.X, parte.Position.Z - centro.Z
		local rx = dx * cosG - dz * sinG
		local ry = dx * sinG + dz * cosG
		local d = math.sqrt(rx * rx + ry * ry)
		local estilo = ESTILOS[e.Tipo]
		local enBorde = false
		if d > radio then
			if e.Tipo ~= "Grupo" then
				continue -- fuera del radar (el grupo se queda pegado al borde)
			end
			rx, ry = rx / d * radio, ry / d * radio
			enBorde = true
		end
		usados += 1
		local p = punto(usados)
		local signo: string? = if e.Tipo == "Mision" then e.Texto else estilo.Texto
		local tam = if enBorde then estilo.Tam - 2 else estilo.Tam
		local m = p.Marco
		m.Visible = true
		m.Position = UDim2.fromOffset(MEDIO + rx * escala, MEDIO + ry * escala)
		m.Size = UDim2.fromOffset(tam, tam)
		m.ZIndex = estilo.Z
		if signo then
			m.Text = signo
			m.TextColor3 = if e.Tipo == "Mision" and signo ~= "!" then GRIS else estilo.Color
			m.BackgroundTransparency = 1
		else
			m.Text = ""
			m.BackgroundColor3 = estilo.Color
			m.BackgroundTransparency = 0
		end
		-- Los recursos son cuadrados; el resto, redondos.
		p.Redondo.CornerRadius = UDim.new(if e.Tipo == "Recurso" then 0.15 else 0.5, 0)
		p.Borde.Enabled = estilo.Borde == true and signo == nil
	end
	for i = usados + 1, #pool do
		pool[i].Marco.Visible = false
	end

	textoCoords.Text = `X {math.floor(centro.X)}  ·  Z {math.floor(centro.Z)}`
end)

local function ubicar()
	contenedor.Visible = Hud.Minimapa
	contenedor.AnchorPoint = Vector2.new(if Hud.Zurdo then 0 else 1, 0)
	contenedor.Position = if Hud.Zurdo then UDim2.fromOffset(8, 8) else UDim2.new(1, -8, 0, 8)
end
Hud.Cambio:Connect(ubicar)
ubicar()

local function actualizarZona()
	local zona = Workspace:GetAttribute("Zona")
	local def = if typeof(zona) == "string" then ZoneConfig.Zonas[zona] else nil
	textoZona.Text = if def then def.Nombre elseif zona == "Pruebas" then "Zona de pruebas" else tostring(zona or "...")
end
Workspace:GetAttributeChangedSignal("Zona"):Connect(actualizarZona)
actualizarZona()
