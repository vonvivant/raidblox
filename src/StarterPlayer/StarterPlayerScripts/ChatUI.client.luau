--!strict
-- ChatUI: ventana de chat propia, que se puede mover (arrastrando la barra de
-- arriba) y agrandar o achicar (arrastrando la esquina de abajo a la derecha).
-- La de Roblox no deja ponerla donde uno quiere.
--
-- Usa TextChatService igual que el chat de Roblox: los mensajes llegan ya
-- filtrados por Roblox (MessageReceived) y se mandan por el canal general
-- (SendAsync). Los globos sobre la cabeza siguen funcionando.
-- Posición, tamaño y si está minimizada se guardan en los ajustes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local MonetizacionConfig = require(ReplicatedStorage.Configs.MonetizacionConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local MAX_MENSAJES = 80
-- A la derecha del menú lateral y debajo del marco del jugador (HUD de la Fase 7).
local POR_DEFECTO = { X = 0.11, Y = 0.17, Ancho = 0.28, Alto = 0.26 }
local LIMITES = { AnchoMin = 0.15, AnchoMax = 0.6, AltoMin = 0.12, AltoMax = 0.7 }

-- El chat de Roblox se apaga: se usa esta ventana.
task.spawn(function()
	local ventanaRoblox = TextChatService:WaitForChild("ChatWindowConfiguration", 10)
	if ventanaRoblox and ventanaRoblox:IsA("ChatWindowConfiguration") then
		ventanaRoblox.Enabled = false
	end
	local barraRoblox = TextChatService:WaitForChild("ChatInputBarConfiguration", 10)
	if barraRoblox and barraRoblox:IsA("ChatInputBarConfiguration") then
		barraRoblox.Enabled = false
	end
end)

local gui = UIKit.Gui("ChatRaidBlox", 30)
gui.IgnoreGuiInset = true

local marco = Instance.new("Frame")
marco.Name = "Chat"
marco.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
marco.BackgroundTransparency = 0.35
marco.Position = UDim2.fromScale(POR_DEFECTO.X, POR_DEFECTO.Y)
marco.Size = UDim2.fromScale(POR_DEFECTO.Ancho, POR_DEFECTO.Alto)
UIKit.Esquinas(marco, 8)
marco.Parent = gui

-- Barra para arrastrar.
local barra = Instance.new("TextButton")
barra.Name = "Barra"
barra.Text = ""
barra.AutoButtonColor = false
barra.Size = UDim2.new(1, 0, 0, 22)
barra.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
barra.BackgroundTransparency = 0.2
UIKit.Esquinas(barra, 8)
barra.Parent = marco
local titulo = UIKit.Texto(barra, "Chat  ·  arrastrá para mover", UDim2.new(1, -60, 1, -4), UDim2.fromOffset(8, 2))
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.TextColor3 = UIKit.Colores.TextoSuave
local minimizar = UIKit.Boton(barra, "—", UDim2.fromOffset(26, 18), UDim2.new(1, -30, 0, 2))

-- Mensajes.
local lista = Instance.new("ScrollingFrame")
lista.Position = UDim2.fromOffset(6, 26)
lista.Size = UDim2.new(1, -12, 1, -64)
lista.BackgroundTransparency = 1
lista.BorderSizePixel = 0
lista.ScrollBarThickness = 5
lista.AutomaticCanvasSize = Enum.AutomaticSize.Y
lista.CanvasSize = UDim2.new()
lista.Parent = marco
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = lista

-- Entrada.
local entrada = Instance.new("TextBox")
entrada.Position = UDim2.new(0, 6, 1, -34)
entrada.Size = UDim2.new(1, -12, 0, 28)
entrada.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
entrada.TextColor3 = Color3.new(1, 1, 1)
entrada.PlaceholderText = "Escribí acá (o tocá / para chatear)"
entrada.PlaceholderColor3 = UIKit.Colores.TextoSuave
entrada.Font = Enum.Font.Gotham
entrada.TextSize = 15
entrada.TextXAlignment = Enum.TextXAlignment.Left
entrada.ClearTextOnFocus = false
entrada.Text = ""
UIKit.Esquinas(entrada, 6)
local margenEntrada = Instance.new("UIPadding")
margenEntrada.PaddingLeft = UDim.new(0, 6)
margenEntrada.Parent = entrada
entrada.Parent = marco

-- Esquina para cambiar el tamaño.
local esquina = Instance.new("TextButton")
esquina.Name = "Esquina"
esquina.Text = "◢"
esquina.TextColor3 = UIKit.Colores.TextoSuave
esquina.TextSize = 14
esquina.BackgroundTransparency = 1
esquina.AnchorPoint = Vector2.new(1, 1)
esquina.Position = UDim2.fromScale(1, 1)
esquina.Size = UDim2.fromOffset(18, 18)
esquina.ZIndex = 3
esquina.Parent = marco

-- Botón para volver a mostrar cuando está minimizada.
local mostrar = UIKit.Boton(gui, "💬 Chat", UDim2.fromOffset(90, 28), UDim2.fromOffset(8, 64))
mostrar.Visible = false

------------------------------------------------------------------------
-- Mensajes
------------------------------------------------------------------------

local orden = 0
local colorVip = MonetizacionConfig.Vip.Color:ToHex()

local function escapar(t: string): string
	return (string.gsub(string.gsub(string.gsub(t, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function agregar(texto: string)
	orden += 1
	local etiqueta = Instance.new("TextLabel")
	etiqueta.BackgroundTransparency = 1
	etiqueta.Size = UDim2.new(1, -6, 0, 0)
	etiqueta.AutomaticSize = Enum.AutomaticSize.Y
	etiqueta.Font = Enum.Font.Gotham
	etiqueta.TextSize = 15
	etiqueta.TextWrapped = true
	etiqueta.RichText = true
	etiqueta.TextXAlignment = Enum.TextXAlignment.Left
	etiqueta.TextColor3 = Color3.new(1, 1, 1)
	etiqueta.TextStrokeTransparency = 0.6
	etiqueta.Text = texto
	etiqueta.LayoutOrder = orden
	etiqueta.Parent = lista
	local hijos: { TextLabel } = {}
	for _, h in lista:GetChildren() do
		if h:IsA("TextLabel") then
			table.insert(hijos, h)
		end
	end
	if #hijos > MAX_MENSAJES then
		table.sort(hijos, function(a: TextLabel, b: TextLabel): boolean
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #hijos - MAX_MENSAJES do
			hijos[i]:Destroy()
		end
	end
	task.defer(function()
		lista.CanvasPosition = Vector2.new(0, math.max(0, lista.AbsoluteCanvasSize.Y - lista.AbsoluteSize.Y))
	end)
end

TextChatService.MessageReceived:Connect(function(mensaje: TextChatMessage)
	local cuerpo = mensaje.Text -- ya filtrado por Roblox
	local fuente = mensaje.TextSource
	if not fuente then
		agregar(`<font color="#AAB4FF">{cuerpo}</font>`) -- mensajes del sistema
		return
	end
	local autor = Players:GetPlayerByUserId(fuente.UserId)
	local nombre = if autor then autor.DisplayName else fuente.Name
	local bando = autor and autor:GetAttribute("Bando")
	local color = if bando == "Rojo" then "#FF6E6E" elseif bando == "Azul" then "#7EA8FF" else "#C9A6FF"
	local vip = if autor and autor:GetAttribute("VIP") == true then `<font color="#{colorVip}">[VIP]</font> ` else ""
	agregar(`{vip}<font color="{color}"><b>{escapar(nombre)}:</b></font> {cuerpo}`)
end)

local function enviar()
	local texto = entrada.Text
	entrada.Text = ""
	if string.match(texto, "^%s*$") then
		return
	end
	local canales = TextChatService:FindFirstChild("TextChannels")
	local general = canales and canales:FindFirstChild("RBXGeneral")
	if general and general:IsA("TextChannel") then
		task.spawn(function()
			pcall(function()
				general:SendAsync(texto)
			end)
		end)
	end
end
entrada.FocusLost:Connect(function(enter: boolean)
	if enter then
		enviar()
	end
end)
ContextActionService:BindAction("ChatRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin and UserInputService:GetFocusedTextBox() == nil and marco.Visible then
		task.defer(function()
			entrada:CaptureFocus()
		end)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Slash)

------------------------------------------------------------------------
-- Mover, cambiar tamaño y guardar
------------------------------------------------------------------------

local function guardar(clave: string, valor: any)
	task.spawn(function()
		NetworkBridge.Client.Invoke("GuardarAjuste", clave, valor)
	end)
end

local function pantalla(): Vector2
	return gui.AbsoluteSize
end

local arrastre: { Tipo: string, Inicio: Vector2, Pos: Vector2, Tam: Vector2 }? = nil

local function empezar(tipo: string, input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	arrastre = {
		Tipo = tipo,
		Inicio = Vector2.new(input.Position.X, input.Position.Y),
		Pos = marco.AbsolutePosition,
		Tam = marco.AbsoluteSize,
	}
end
barra.InputBegan:Connect(function(input: InputObject)
	empezar("Mover", input)
end)
esquina.InputBegan:Connect(function(input: InputObject)
	empezar("Tamano", input)
end)

UserInputService.InputChanged:Connect(function(input: InputObject)
	local a = arrastre
	if
		not a
		or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch)
	then
		return
	end
	local p = pantalla()
	local delta = Vector2.new(input.Position.X, input.Position.Y) - a.Inicio
	if a.Tipo == "Mover" then
		local x = math.clamp((a.Pos.X + delta.X) / p.X, 0, 1 - marco.AbsoluteSize.X / p.X)
		local y = math.clamp((a.Pos.Y + delta.Y) / p.Y, 0, 1 - marco.AbsoluteSize.Y / p.Y)
		marco.Position = UDim2.fromScale(x, y)
	else
		local ancho = math.clamp((a.Tam.X + delta.X) / p.X, LIMITES.AnchoMin, LIMITES.AnchoMax)
		local alto = math.clamp((a.Tam.Y + delta.Y) / p.Y, LIMITES.AltoMin, LIMITES.AltoMax)
		marco.Size = UDim2.fromScale(ancho, alto)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	local a = arrastre
	if
		not a
		or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch)
	then
		return
	end
	arrastre = nil
	if a.Tipo == "Mover" then
		guardar("ChatX", marco.Position.X.Scale)
		guardar("ChatY", marco.Position.Y.Scale)
	else
		guardar("ChatAncho", marco.Size.X.Scale)
		guardar("ChatAlto", marco.Size.Y.Scale)
	end
end)

local function verVisible(visible: boolean)
	marco.Visible = visible
	mostrar.Visible = not visible
end
minimizar.Activated:Connect(function()
	verVisible(false)
	guardar("ChatVisible", false)
end)
mostrar.Activated:Connect(function()
	verVisible(true)
	guardar("ChatVisible", true)
end)

local function aplicarAjustes()
	local ajustes = EstadoCliente.Get("Ajustes")
	if typeof(ajustes) ~= "table" or arrastre then
		return
	end
	marco.Position = UDim2.fromScale(ajustes.ChatX or POR_DEFECTO.X, ajustes.ChatY or POR_DEFECTO.Y)
	marco.Size = UDim2.fromScale(ajustes.ChatAncho or POR_DEFECTO.Ancho, ajustes.ChatAlto or POR_DEFECTO.Alto)
	verVisible(ajustes.ChatVisible ~= false)
end
EstadoCliente.Cambio:Connect(function(campo: string)
	if campo == "Ajustes" or campo == "*" then
		aplicarAjustes()
	end
end)
aplicarAjustes()
