--!strict
-- MonturaChatUI: montura (tecla G o botón) y etiqueta [VIP] en el chat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local MonetizacionConfig = require(ReplicatedStorage.Configs.MonetizacionConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local MenuLateral = require(ReplicatedStorage.Modules.MenuLateral)

local jugador = Players.LocalPlayer

------------------------------------------------------------------------
-- Montura
------------------------------------------------------------------------

local boton = Instance.new("TextButton")
boton.Name = "BotonMontura"
boton.BackgroundColor3 = UIKit.Colores.Boton
boton.TextColor3 = Color3.new(1, 1, 1)
boton.Font = Enum.Font.GothamBold
boton.TextScaled = true
boton.Text = "🐴 Montar (G)"
UIKit.Esquinas(boton, 6)
MenuLateral.Agregar(boton, 7)

local function preferida(): string
	return if jugador:GetAttribute("Pase_MonturaDragon") == true then "Dragon" else "Caballo"
end

local function alternar()
	NetworkBridge.Client.Invoke("MonturaAlternar", preferida())
end

local function refrescar()
	local montura = jugador:GetAttribute("Montura")
	if typeof(montura) == "string" then
		boton.Text = "Desmontar (G)"
		boton.BackgroundColor3 = UIKit.Colores.BotonPrimario
	else
		local def = MonetizacionConfig.Monturas[preferida()]
		boton.Text = `{if preferida() == "Dragon" then "🐉" else "🐴"} {def.Nombre} (G)`
		boton.BackgroundColor3 = UIKit.Colores.Boton
	end
end
jugador:GetAttributeChangedSignal("Montura"):Connect(refrescar)
jugador:GetAttributeChangedSignal("Pase_MonturaDragon"):Connect(refrescar)
refrescar()

boton.Activated:Connect(alternar)
ContextActionService:BindAction("MonturaRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin and UserInputService:GetFocusedTextBox() == nil then
		alternar()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonL3)

------------------------------------------------------------------------
-- [VIP] dorado en el chat
------------------------------------------------------------------------

local colorVip = MonetizacionConfig.Vip.Color:ToHex()
TextChatService.OnIncomingMessage = function(mensaje: TextChatMessage): TextChatMessageProperties?
	local fuente = mensaje.TextSource
	if not fuente then
		return nil
	end
	local autor = Players:GetPlayerByUserId(fuente.UserId)
	if not autor or autor:GetAttribute("VIP") ~= true then
		return nil
	end
	local props = Instance.new("TextChatMessageProperties")
	props.PrefixText = `<font color="#{colorVip}">[VIP]</font> {mensaje.PrefixText}`
	return props
end
