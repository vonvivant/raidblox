--!strict
-- UIKit: piezas básicas de interfaz compartidas por las ventanas del cliente
-- (inventario, crafteo, subastas, comercio). Todas escalan con la pantalla y
-- los botones son seleccionables con gamepad.

local Players = game:GetService("Players")

local UIKit = {}

UIKit.Colores = {
	Fondo = Color3.fromRGB(16, 16, 24),
	Panel = Color3.fromRGB(28, 28, 40),
	Boton = Color3.fromRGB(44, 44, 62),
	BotonPrimario = Color3.fromRGB(60, 120, 70),
	BotonPeligro = Color3.fromRGB(140, 50, 45),
	Texto = Color3.fromRGB(235, 235, 245),
	TextoSuave = Color3.fromRGB(170, 170, 185),
	Oro = Color3.fromRGB(255, 210, 60),
}

function UIKit.Gui(nombre: string, orden: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = nombre
	gui.ResetOnSpawn = false
	gui.DisplayOrder = orden
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function UIKit.Esquinas(padre: GuiObject, radio: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radio or 8)
	c.Parent = padre
end

-- Ventana centrada con título y botón de cerrar. Devuelve (marco, contenido).
function UIKit.Ventana(padre: Instance, titulo: string, tam: UDim2): (Frame, Frame)
	local marco = Instance.new("Frame")
	marco.AnchorPoint = Vector2.new(0.5, 0.5)
	marco.Position = UDim2.fromScale(0.5, 0.5)
	marco.Size = tam
	marco.BackgroundColor3 = UIKit.Colores.Fondo
	marco.BackgroundTransparency = 0.05
	marco.Visible = false
	marco:SetAttribute("Ventana", true) -- con una ventana abierta, el modo apuntado suelta el mouse
	UIKit.Esquinas(marco, 12)
	local proporcion = Instance.new("UISizeConstraint")
	proporcion.MinSize = Vector2.new(320, 240)
	proporcion.Parent = marco

	local etiqueta = UIKit.Texto(marco, titulo, UDim2.new(1, -60, 0, 32), UDim2.fromOffset(14, 6))
	etiqueta.TextXAlignment = Enum.TextXAlignment.Left
	etiqueta.Font = Enum.Font.GothamBlack

	local cerrar =
		UIKit.Boton(marco, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -40, 0, 6), UIKit.Colores.BotonPeligro)
	cerrar.Activated:Connect(function()
		marco.Visible = false
	end)

	local contenido = Instance.new("Frame")
	contenido.Name = "Contenido"
	contenido.Position = UDim2.fromOffset(12, 44)
	contenido.Size = UDim2.new(1, -24, 1, -56)
	contenido.BackgroundTransparency = 1
	contenido.Parent = marco

	marco.Parent = padre
	return marco, contenido
end

function UIKit.Texto(padre: Instance, texto: string, tam: UDim2, pos: UDim2?): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = tam
	t.Position = pos or UDim2.new()
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = UIKit.Colores.Texto
	t.Text = texto
	local limite = Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = 22
	limite.Parent = t
	t.Parent = padre
	return t
end

function UIKit.Boton(padre: Instance, texto: string, tam: UDim2, pos: UDim2?, color: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Size = tam
	b.Position = pos or UDim2.new()
	b.BackgroundColor3 = color or UIKit.Colores.Boton
	b.AutoButtonColor = true
	b.Selectable = true
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = UIKit.Colores.Texto
	b.Text = texto
	local limite = Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = 20
	limite.Parent = b
	local margen = Instance.new("UIPadding")
	margen.PaddingLeft = UDim.new(0, 6)
	margen.PaddingRight = UDim.new(0, 6)
	margen.PaddingTop = UDim.new(0, 3)
	margen.PaddingBottom = UDim.new(0, 3)
	margen.Parent = b
	UIKit.Esquinas(b, 6)
	b.Parent = padre
	return b
end

function UIKit.Entrada(padre: Instance, placeholder: string, tam: UDim2, pos: UDim2?): TextBox
	local caja = Instance.new("TextBox")
	caja.Size = tam
	caja.Position = pos or UDim2.new()
	caja.BackgroundColor3 = UIKit.Colores.Panel
	caja.Font = Enum.Font.Gotham
	caja.TextScaled = true
	caja.TextColor3 = UIKit.Colores.Texto
	caja.PlaceholderText = placeholder
	caja.PlaceholderColor3 = UIKit.Colores.TextoSuave
	caja.Text = ""
	caja.ClearTextOnFocus = false
	local limite = Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = 18
	limite.Parent = caja
	UIKit.Esquinas(caja, 6)
	caja.Parent = padre
	return caja
end

-- Lista vertical con scroll. Devuelve el ScrollingFrame.
function UIKit.Lista(padre: Instance, tam: UDim2, pos: UDim2?): ScrollingFrame
	local lista = Instance.new("ScrollingFrame")
	lista.Size = tam
	lista.Position = pos or UDim2.new()
	lista.BackgroundColor3 = UIKit.Colores.Panel
	lista.BackgroundTransparency = 0.3
	lista.BorderSizePixel = 0
	lista.ScrollBarThickness = 6
	lista.AutomaticCanvasSize = Enum.AutomaticSize.Y
	lista.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = lista
	local margen = Instance.new("UIPadding")
	margen.PaddingLeft = UDim.new(0, 4)
	margen.PaddingRight = UDim.new(0, 8)
	margen.PaddingTop = UDim.new(0, 4)
	margen.Parent = lista
	UIKit.Esquinas(lista, 8)
	lista.Parent = padre
	return lista
end

function UIKit.Limpiar(contenedor: Instance)
	for _, hijo in contenedor:GetChildren() do
		if hijo:IsA("GuiObject") then
			hijo:Destroy()
		end
	end
end

-- Con gamepad, pone el foco en el primer botón visible de `contenedor`, así
-- la ventana se puede usar sin mouse.
function UIKit.EnfocarPrimero(contenedor: Instance)
	if not game:GetService("UserInputService").GamepadEnabled then
		return
	end
	task.defer(function() -- espera a que la ventana termine de armarse
		local mejor: GuiObject? = nil
		for _, d in contenedor:GetDescendants() do
			if d:IsA("GuiButton") and d.Visible and d.Selectable then
				local b: GuiObject = d
				if not mejor or b.LayoutOrder < mejor.LayoutOrder then
					mejor = b
				end
			end
		end
		if mejor then
			game:GetService("GuiService").SelectedObject = mejor
		end
	end)
end

-- Botón fijo en pantalla para abrir una ventana (útil en móvil).
function UIKit.Atajo(padre: Instance, texto: string, posicion: UDim2): TextButton
	local b = UIKit.Boton(padre, texto, UDim2.fromScale(0.07, 0.045), posicion)
	b.BackgroundTransparency = 0.15
	local proporcion = Instance.new("UISizeConstraint")
	proporcion.MinSize = Vector2.new(70, 30)
	proporcion.Parent = b
	return b
end

return UIKit
