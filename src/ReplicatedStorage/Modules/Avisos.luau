--!strict
-- Avisos: mensajes cortos en pantalla (toasts) del lado del cliente.
-- Avisos.Mostrar("Necesitás nivel 20", "Error")
--
-- Estilo del HUD (Fase 7): pastillas con una franja e ícono del color del
-- tipo, debajo del centro de la pantalla. Como máximo 4 a la vez (se va el
-- más viejo) y un mismo mensaje repetido se junta en uno con "×N".

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Hud = require(script.Parent.Hud)

local Avisos = {}

local COLORES: { [string]: Color3 } = {
	Info = Color3.fromRGB(235, 235, 245),
	Error = Color3.fromRGB(255, 110, 100),
	Oro = Color3.fromRGB(255, 215, 0),
	Zona = Color3.fromRGB(140, 210, 255),
	Guerra = Color3.fromRGB(120, 230, 160),
}
local ICONOS: { [string]: string } = {
	Info = "ℹ",
	Error = "⚠",
	Oro = "★",
	Zona = "➜",
	Guerra = "⚔",
}

local MAXIMO = 4
local DURACION = 4
local ANCHO = 520

type Aviso = { Marco: Frame, Texto: TextLabel, Base: string, Veces: number, Vence: number }

local contenedor: Frame? = nil
local activos: { Aviso } = {}
local orden = 0

local function obtenerContenedor(): Frame
	local c = contenedor
	if c and c.Parent then
		return c
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "AvisosRaidBlox"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 900

	local marco = Instance.new("Frame")
	marco.Name = "Lista"
	marco.AnchorPoint = Vector2.new(0.5, 0)
	marco.Position = UDim2.fromScale(0.5, 0.6)
	marco.Size = UDim2.fromOffset(ANCHO, 0)
	marco.AutomaticSize = Enum.AutomaticSize.Y
	marco.BackgroundTransparency = 1
	marco.Parent = gui
	Hud.Registrar(marco)

	local lista = Instance.new("UIListLayout")
	lista.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lista.Padding = UDim.new(0, 6)
	lista.SortOrder = Enum.SortOrder.LayoutOrder
	lista.Parent = marco

	gui.Parent = playerGui
	contenedor = marco
	return marco
end

local function quitar(a: Aviso)
	local i = table.find(activos, a)
	if i then
		table.remove(activos, i)
	end
	local info = TweenInfo.new(0.35)
	TweenService:Create(a.Marco, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(a.Texto, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	for _, d in a.Marco:GetDescendants() do
		if d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("TextLabel") and d ~= a.Texto then
			TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		end
	end
	task.delay(0.4, function()
		a.Marco:Destroy()
	end)
end

local function programarVencimiento(a: Aviso)
	local vence = a.Vence
	task.delay(DURACION, function()
		if a.Vence == vence and table.find(activos, a) then
			quitar(a)
		end
	end)
end

function Avisos.Mostrar(texto: string, tipo: string?)
	local clase = if tipo and COLORES[tipo] then tipo else "Info"
	local color = COLORES[clase]

	-- El mismo mensaje otra vez: se suma al que ya está en pantalla.
	for _, a in activos do
		if a.Base == texto then
			a.Veces += 1
			a.Texto.Text = `{texto}  ×{a.Veces}`
			a.Vence = os.clock()
			programarVencimiento(a)
			return
		end
	end

	local lista = obtenerContenedor()
	orden += 1

	local marco = Instance.new("Frame")
	marco.LayoutOrder = orden
	marco.Size = UDim2.fromOffset(ANCHO, 0)
	marco.AutomaticSize = Enum.AutomaticSize.Y
	marco.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
	marco.BackgroundTransparency = 0.15
	local esquinas = Instance.new("UICorner")
	esquinas.CornerRadius = UDim.new(0, 10)
	esquinas.Parent = marco
	local borde = Instance.new("UIStroke")
	borde.Color = color
	borde.Transparency = 0.6
	borde.Parent = marco

	local franja = Instance.new("Frame")
	franja.Size = UDim2.new(0, 5, 1, -10)
	franja.Position = UDim2.fromOffset(6, 5)
	franja.BackgroundColor3 = color
	franja.BorderSizePixel = 0
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 3)
	c2.Parent = franja
	franja.Parent = marco

	local icono = Instance.new("TextLabel")
	icono.Size = UDim2.fromOffset(22, 22)
	icono.Position = UDim2.fromOffset(16, 6)
	icono.BackgroundTransparency = 1
	icono.Font = Enum.Font.GothamBlack
	icono.TextScaled = true
	icono.TextColor3 = color
	icono.Text = ICONOS[clase]
	icono.Parent = marco

	local etiqueta = Instance.new("TextLabel")
	etiqueta.Size = UDim2.new(1, -54, 0, 0)
	etiqueta.Position = UDim2.fromOffset(44, 0)
	etiqueta.AutomaticSize = Enum.AutomaticSize.Y
	etiqueta.BackgroundTransparency = 1
	etiqueta.Font = Enum.Font.GothamBold
	etiqueta.TextSize = 17
	etiqueta.TextWrapped = true
	etiqueta.TextXAlignment = Enum.TextXAlignment.Left
	etiqueta.TextColor3 = color
	etiqueta.TextStrokeTransparency = 0.7
	etiqueta.Text = texto
	local margen = Instance.new("UIPadding")
	margen.PaddingTop = UDim.new(0, 8)
	margen.PaddingBottom = UDim.new(0, 8)
	margen.Parent = etiqueta
	etiqueta.Parent = marco

	-- Entra con un pequeño rebote.
	local escala = Instance.new("UIScale")
	escala.Scale = 0.85
	escala.Parent = marco
	marco.Parent = lista
	TweenService:Create(escala, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	local aviso: Aviso = { Marco = marco, Texto = etiqueta, Base = texto, Veces = 1, Vence = os.clock() }
	table.insert(activos, aviso)
	while #activos > MAXIMO do
		quitar(activos[1])
	end
	programarVencimiento(aviso)
end

return Avisos
