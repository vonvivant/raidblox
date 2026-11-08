--!strict
-- Avisos: mensajes cortos en pantalla (toasts) del lado del cliente.
-- Avisos.Mostrar("Necesitás nivel 20", "Error")

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Avisos = {}

local COLORES: { [string]: Color3 } = {
	Info = Color3.fromRGB(235, 235, 245),
	Error = Color3.fromRGB(255, 110, 100),
	Oro = Color3.fromRGB(255, 215, 0),
	Zona = Color3.fromRGB(140, 210, 255),
	Guerra = Color3.fromRGB(120, 230, 160),
}

local contenedor: Frame? = nil

local function obtenerContenedor(): Frame
	if contenedor and contenedor.Parent then
		return contenedor
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "AvisosRaidBlox"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 900

	local marco = Instance.new("Frame")
	marco.Name = "Lista"
	marco.AnchorPoint = Vector2.new(0.5, 0)
	marco.Position = UDim2.fromScale(0.5, 0.16)
	marco.Size = UDim2.fromScale(0.6, 0.4)
	marco.BackgroundTransparency = 1
	marco.Parent = gui

	local lista = Instance.new("UIListLayout")
	lista.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lista.Padding = UDim.new(0, 6)
	lista.SortOrder = Enum.SortOrder.LayoutOrder
	lista.Parent = marco

	gui.Parent = playerGui
	contenedor = marco
	return marco
end

local orden = 0

function Avisos.Mostrar(texto: string, tipo: string?)
	local marco = obtenerContenedor()
	orden += 1

	local etiqueta = Instance.new("TextLabel")
	etiqueta.LayoutOrder = orden
	etiqueta.Size = UDim2.new(1, 0, 0, 34)
	etiqueta.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
	etiqueta.BackgroundTransparency = 0.25
	etiqueta.Font = Enum.Font.GothamBold
	etiqueta.TextScaled = true
	etiqueta.TextColor3 = COLORES[tipo or "Info"] or COLORES.Info
	etiqueta.Text = texto

	local esquinas = Instance.new("UICorner")
	esquinas.CornerRadius = UDim.new(0, 8)
	esquinas.Parent = etiqueta
	local margen = Instance.new("UIPadding")
	margen.PaddingLeft = UDim.new(0, 10)
	margen.PaddingRight = UDim.new(0, 10)
	margen.PaddingTop = UDim.new(0, 4)
	margen.PaddingBottom = UDim.new(0, 4)
	margen.Parent = etiqueta
	etiqueta.Parent = marco

	task.delay(4, function()
		local info = TweenInfo.new(0.5)
		TweenService:Create(etiqueta, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.6)
		etiqueta:Destroy()
	end)
end

return Avisos
