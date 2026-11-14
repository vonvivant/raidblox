--!strict
-- MapaMundoUI: mapa del mundo (de la zona actual). Solo visual.
--
-- * Se abre y se cierra con la tecla M (R1 en gamepad) o con el botón "M" del
--   minimapa. Arriba a la derecha del marco hay un botón "X" para cerrarlo.
--   Empieza cerrado.
-- * Marco de pergamino con borde de metal, 70% de la pantalla, centrado.
-- * Adentro, el mapa cuadrado de la zona: la imagen de ZoneConfig.Mapas (si
--   hay) o un pergamino con cuadrícula, con el norte (-Z) arriba. Encima van
--   los portales, NPCs de misión, estaciones, élites, tu grupo y un pin con tu
--   posición y hacia dónde mirás, que se mueve en tiempo real.
--
-- Cuenta para pasar del mundo al mapa (ver `aMapa`):
--   u = (x - Centro.X) / Tamano + 0.5      v = (z - Centro.Z) / Tamano + 0.5
-- u y v van de 0 a 1 dentro del cuadrado del mapa (se recortan a ese rango) y
-- se usan directo como posición en escala del marco "Lienzo".

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ZoneConfig = require(ReplicatedStorage.Configs.ZoneConfig)
local Radar = require(ReplicatedStorage.Modules.Radar)
local EventosCliente = require(ReplicatedStorage.Modules.EventosCliente)

local jugador = Players.LocalPlayer

local PERGAMINO = Color3.fromRGB(222, 200, 155)
local TINTA = Color3.fromRGB(70, 50, 30)
local METAL = Color3.fromRGB(95, 80, 60)

type Estilo = { Color: Color3, Texto: string, Tam: number }
local ESTILOS: { [Radar.Tipo]: Estilo? } = {
	Grupo = { Color = Color3.fromRGB(40, 110, 220), Texto = "●", Tam = 18 },
	Elite = { Color = Color3.fromRGB(190, 30, 20), Texto = "◆", Tam = 22 },
	Mision = { Color = Color3.fromRGB(190, 130, 0), Texto = "!", Tam = 24 },
	Portal = { Color = Color3.fromRGB(130, 60, 200), Texto = "◈", Tam = 22 },
	Estacion = { Color = Color3.fromRGB(90, 80, 70), Texto = "■", Tam = 12 },
	Restos = { Color = Color3.fromRGB(170, 140, 0), Texto = "✦", Tam = 20 },
}

local gui = Instance.new("ScreenGui")
gui.Name = "MapaMundoUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = jugador:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Marco
------------------------------------------------------------------------

local marco = Instance.new("Frame")
marco.Name = "MarcoMapa"
marco.AnchorPoint = Vector2.new(0.5, 0.5)
marco.Position = UDim2.new(0.5, 0, 0.5, 0)
marco.Size = UDim2.fromScale(0.7, 0.7)
marco.BackgroundColor3 = PERGAMINO
marco.Visible = false
marco:SetAttribute("Ventana", true) -- con el mapa abierto, la mira suelta el mouse
local esquinas = Instance.new("UICorner")
esquinas.CornerRadius = UDim.new(0, 14)
esquinas.Parent = marco
local borde = Instance.new("UIStroke")
borde.Color = METAL
borde.Thickness = 5
borde.Parent = marco
local viejo = Instance.new("UIGradient") -- pergamino gastado: más oscuro en los bordes
viejo.Rotation = 90
viejo.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(215, 205, 190)),
	ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(205, 190, 170)),
})
viejo.Parent = marco
marco.Parent = gui

local function rotulo(padre: Instance, texto: string, tam: UDim2, pos: UDim2, fuente: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = tam
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = fuente or Enum.Font.Fondamento
	t.TextScaled = true
	t.TextColor3 = TINTA
	t.Text = texto
	t.Parent = padre
	return t
end

local titulo = rotulo(marco, "Mapa", UDim2.new(1, -120, 0, 36), UDim2.fromOffset(60, 8))
titulo.Name = "Titulo"

local cerrar = Instance.new("TextButton")
cerrar.Name = "BotonCerrar"
cerrar.AnchorPoint = Vector2.new(1, 0)
cerrar.Position = UDim2.new(1, -10, 0, 10)
cerrar.Size = UDim2.fromOffset(36, 36)
cerrar.BackgroundColor3 = Color3.fromRGB(140, 50, 40)
cerrar.TextColor3 = Color3.new(1, 1, 1)
cerrar.Font = Enum.Font.GothamBlack
cerrar.TextScaled = true
cerrar.Text = "X"
local ec = Instance.new("UICorner")
ec.CornerRadius = UDim.new(0, 8)
ec.Parent = cerrar
local bc = Instance.new("UIStroke")
bc.Color = METAL
bc.Thickness = 2
bc.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bc.Parent = cerrar
cerrar.Parent = marco

-- Lienzo: el cuadrado del mapa (siempre cuadrado, lo más grande que entre).
local zonaLienzo = Instance.new("Frame")
zonaLienzo.Position = UDim2.fromOffset(16, 52)
zonaLienzo.Size = UDim2.new(1, -32, 1, -92)
zonaLienzo.BackgroundTransparency = 1
zonaLienzo.Parent = marco

local lienzo = Instance.new("ImageLabel")
lienzo.Name = "Lienzo"
lienzo.AnchorPoint = Vector2.new(0.5, 0.5)
lienzo.Position = UDim2.fromScale(0.5, 0.5)
lienzo.Size = UDim2.fromScale(1, 1)
lienzo.BackgroundColor3 = Color3.fromRGB(205, 182, 135)
lienzo.BorderSizePixel = 0
lienzo.ClipsDescendants = true
lienzo.ScaleType = Enum.ScaleType.Stretch
local cuadrado = Instance.new("UIAspectRatioConstraint")
cuadrado.AspectRatio = 1
cuadrado.Parent = lienzo
local bl = Instance.new("UIStroke")
bl.Color = TINTA
bl.Thickness = 2
bl.Parent = lienzo
lienzo.Parent = zonaLienzo

-- Cuadrícula (se ve cuando no hay imagen).
local cuadricula = Instance.new("Frame")
cuadricula.Name = "Cuadricula"
cuadricula.Size = UDim2.fromScale(1, 1)
cuadricula.BackgroundTransparency = 1
cuadricula.Parent = lienzo
for i = 1, 7 do
	for _, vertical in { true, false } do
		local linea = Instance.new("Frame")
		linea.BackgroundColor3 = TINTA
		linea.BackgroundTransparency = if i == 4 then 0.6 else 0.85
		linea.BorderSizePixel = 0
		linea.Size = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1)
		linea.Position = if vertical then UDim2.fromScale(i / 8, 0) else UDim2.fromScale(0, i / 8)
		linea.Parent = cuadricula
	end
end
local rosa = rotulo(lienzo, "N\n▲", UDim2.fromOffset(40, 48), UDim2.new(1, -48, 0, 6), Enum.Font.GothamBlack)
rosa.ZIndex = 4

local pin = rotulo(lienzo, "▲", UDim2.fromOffset(26, 26), UDim2.fromScale(0.5, 0.5), Enum.Font.GothamBlack)
pin.Name = "Pin"
pin.AnchorPoint = Vector2.new(0.5, 0.5)
pin.TextColor3 = Color3.fromRGB(200, 30, 30)
pin.TextStrokeColor3 = Color3.new(1, 1, 1)
pin.TextStrokeTransparency = 0
pin.ZIndex = 10

local pie = rotulo(marco, "", UDim2.new(1, -32, 0, 24), UDim2.new(0, 16, 1, -34), Enum.Font.GothamMedium)
pie.Name = "Pie"

-- Marcadores reutilizables.
local pool: { TextLabel } = {}
local function marcador(i: number): TextLabel
	local existente = pool[i]
	if existente then
		return existente
	end
	local m = rotulo(lienzo, "", UDim2.fromOffset(20, 20), UDim2.new(), Enum.Font.GothamBlack)
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.TextStrokeColor3 = Color3.new(1, 1, 1)
	m.TextStrokeTransparency = 0.3
	m.ZIndex = 6
	pool[i] = m
	return m
end

------------------------------------------------------------------------
-- Mundo -> mapa
------------------------------------------------------------------------

local mapa = ZoneConfig.MapaPorDefecto

local function aMapa(pos: Vector3): (number, number, boolean)
	local u = (pos.X - mapa.Centro.X) / mapa.Tamano + 0.5
	local v = (pos.Z - mapa.Centro.Z) / mapa.Tamano + 0.5
	local dentro = u >= 0 and u <= 1 and v >= 0 and v <= 1
	return math.clamp(u, 0, 1), math.clamp(v, 0, 1), dentro
end

local function cargarZona()
	local zona = Workspace:GetAttribute("Zona")
	local id = if typeof(zona) == "string" then zona else ""
	mapa = ZoneConfig.Mapas[id] or ZoneConfig.MapaPorDefecto
	local def = ZoneConfig.Zonas[id]
	titulo.Text = `Mapa · {if def then def.Nombre elseif id == "Pruebas" then "Zona de pruebas" else id}`
	lienzo.Image = mapa.Imagen
	cuadricula.Visible = mapa.Imagen == ""
end
Workspace:GetAttributeChangedSignal("Zona"):Connect(cargarZona)
cargarZona()

------------------------------------------------------------------------
-- Abrir / cerrar
------------------------------------------------------------------------

local function alternar()
	marco.Visible = not marco.Visible
end
cerrar.Activated:Connect(function()
	marco.Visible = false
end)
EventosCliente.AlternarMapa:Connect(alternar)
ContextActionService:BindAction("MapaMundoRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin and UserInputService:GetFocusedTextBox() == nil then
		alternar()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonR1)

------------------------------------------------------------------------
-- Actualización (solo con el mapa abierto)
------------------------------------------------------------------------

local ultimaX, ultimaZ = math.huge, math.huge

RunService.RenderStepped:Connect(function()
	if not marco.Visible then
		return
	end
	local raiz = Radar.ParteDe(jugador.Character)
	if not raiz then
		return
	end
	local u, v, dentro = aMapa(raiz.Position)
	pin.Position = UDim2.fromScale(u, v)
	local frente = raiz.CFrame.LookVector
	pin.Rotation = math.deg(math.atan2(frente.X, -frente.Z))
	local px, pz = math.floor(raiz.Position.X), math.floor(raiz.Position.Z)
	if px ~= ultimaX or pz ~= ultimaZ then
		ultimaX, ultimaZ = px, pz
		pie.Text = `Tu posición: X {px} · Z {pz}{if dentro then "" else "  (fuera del mapa)"}   ·   M para cerrar`
	end

	local usados = 0
	for _, e in Radar.Entidades() do
		local esGrupo = e.Tipo == "Grupo"
		local esMision = e.Tipo == "Mision"
		local estilo = ESTILOS[e.Tipo]
		if not estilo or not e.Parte.Parent then
			continue
		end
		local eu, ev, visible = aMapa(e.Parte.Position)
		if not visible and not esGrupo then
			continue
		end
		usados += 1
		local m = marcador(usados)
		m.Visible = true
		m.Position = UDim2.fromScale(eu, ev)
		m.Size = UDim2.fromOffset(estilo.Tam, estilo.Tam)
		m.Text = if esMision and e.Texto then e.Texto else estilo.Texto
		m.TextColor3 = estilo.Color
	end
	for i = usados + 1, #pool do
		pool[i].Visible = false
	end
end)
