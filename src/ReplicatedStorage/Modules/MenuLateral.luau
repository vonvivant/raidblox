--!strict
-- MenuLateral: columna vertical de botones a la izquierda de la pantalla
-- (Personaje, Grupo, Hermandad, Tienda, Voz, Mira, Montura). Cada script
-- agrega su botón con un orden. Solo para el cliente.
-- Con la opción "Zurdo" la columna pasa al borde derecho.

local Players = game:GetService("Players")

local Hud = require(script.Parent.Hud)

local MenuLateral = {}

local columna: Frame? = nil

local function obtener(): Frame
	local c = columna
	if c then
		return c
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MenuRaidBlox"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 41
	local marco = Instance.new("Frame")
	marco.Name = "Columna"
	marco.AnchorPoint = Vector2.new(0, 0.5)
	marco.Position = UDim2.fromScale(0.005, 0.56)
	marco.Size = UDim2.fromScale(0.095, 0.4)
	marco.BackgroundTransparency = 1
	marco.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0.012, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = marco
	local function lado()
		marco.AnchorPoint = Vector2.new(if Hud.Zurdo then 1 else 0, 0.5)
		marco.Position = UDim2.fromScale(if Hud.Zurdo then 0.995 else 0.005, 0.56)
	end
	Hud.Cambio:Connect(lado)
	lado()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	columna = marco
	return marco
end

-- Mete el botón en la columna (le cambia tamaño y posición).
function MenuLateral.Agregar(boton: GuiButton, orden: number)
	boton.AnchorPoint = Vector2.zero
	boton.Position = UDim2.new()
	boton.Size = UDim2.new(1, 0, 0.12, 0)
	boton.LayoutOrder = orden
	local limite = boton:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = 20
	limite.Parent = boton
	boton.Parent = obtener()
end

return MenuLateral
