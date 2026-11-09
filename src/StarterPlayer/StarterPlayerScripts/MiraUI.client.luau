--!strict
-- MiraUI: modo apuntado con mira en el centro de la pantalla.
--
-- * Es optativo: arranca en el modo de siempre (objetivo con Tab o clic). El
--   botón "🎯 Mira" o la tecla Q (clic en el stick derecho) lo prenden y apagan.
-- * Apuntado: cámara sobre el hombro, el mouse queda fijo en el centro y el
--   personaje mira hacia donde mira la cámara. Clic izquierdo = ataque básico.
-- * El mouse se suelta solo al abrir una ventana o escribir, y mientras
--   tengas apretado Alt o Ctrl.
-- * La mira se pone roja sobre un enemigo y muestra una X al pegar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Apuntado = require(ReplicatedStorage.Modules.Apuntado)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local jugador = Players.LocalPlayer
local ajustesJuego = UserSettings():GetService("UserGameSettings")
local DESPLAZAMIENTO = Vector3.new(1.7, 0.5, 0) -- cámara sobre el hombro derecho
local BLANCO = Color3.new(1, 1, 1)
local ROJO = Color3.fromRGB(255, 70, 60)
local VERDE = Color3.fromRGB(90, 230, 120)

------------------------------------------------------------------------
-- Mira
------------------------------------------------------------------------

local gui = UIKit.Gui("MiraUI", 45)
gui.IgnoreGuiInset = true

local mira = Instance.new("Frame")
mira.AnchorPoint = Vector2.new(0.5, 0.5)
mira.Position = UDim2.fromScale(0.5, 0.5)
mira.Size = UDim2.fromOffset(28, 28)
mira.BackgroundTransparency = 1
mira.Visible = false
mira.Parent = gui

local trazos: { Frame } = {}
local function trazo(pos: UDim2, tam: UDim2)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = tam
	f.BackgroundColor3 = BLANCO
	f.BorderSizePixel = 0
	local borde = Instance.new("UIStroke")
	borde.Thickness = 1
	borde.Transparency = 0.4
	borde.Parent = f
	f.Parent = mira
	table.insert(trazos, f)
end
trazo(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(3, 3)) -- punto
trazo(UDim2.new(0.5, 0, 0, 4), UDim2.fromOffset(2, 7)) -- arriba
trazo(UDim2.new(0.5, 0, 1, -4), UDim2.fromOffset(2, 7)) -- abajo
trazo(UDim2.new(0, 4, 0.5, 0), UDim2.fromOffset(7, 2)) -- izquierda
trazo(UDim2.new(1, -4, 0.5, 0), UDim2.fromOffset(7, 2)) -- derecha

-- X de impacto
local impacto = Instance.new("Frame")
impacto.AnchorPoint = Vector2.new(0.5, 0.5)
impacto.Position = UDim2.fromScale(0.5, 0.5)
impacto.Size = UDim2.fromOffset(26, 26)
impacto.BackgroundTransparency = 1
impacto.Visible = false
impacto.Parent = gui
for _, angulo in { 45, -45 } do
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.new(1, 0, 0, 2)
	f.Rotation = angulo
	f.BackgroundColor3 = ROJO
	f.BorderSizePixel = 0
	f.Parent = impacto
end

local ayuda = UIKit.Texto(gui, "", UDim2.fromOffset(320, 18), UDim2.new(0.5, -160, 1, -26))
ayuda.TextTransparency = 0.35

-- Botón para prender y apagar la mira (con la mira puesta, se toca con Alt o Ctrl apretado).
local boton = Instance.new("TextButton")
boton.Name = "BotonMira"
boton.Position = UDim2.fromScale(0.38, 0.455)
boton.Size = UDim2.fromScale(0.08, 0.038)
boton.BackgroundColor3 = UIKit.Colores.Boton
boton.TextColor3 = Color3.new(1, 1, 1)
boton.Font = Enum.Font.GothamBold
boton.TextScaled = true
boton.Text = "🎯 Mira: NO"
UIKit.Esquinas(boton, 6)
boton.Parent = gui

local function colorMira(color: Color3)
	for _, t in trazos do
		t.BackgroundColor3 = color
	end
end

------------------------------------------------------------------------
-- Cuándo se suelta el mouse
------------------------------------------------------------------------

-- Ventanas de UIKit (llevan el atributo Ventana) y la selección de clase.
local ventanas: { GuiObject } = {}
local function registrar(d: Instance)
	if d:IsA("GuiObject") and d:GetAttribute("Ventana") == true then
		table.insert(ventanas, d)
	end
end
local playerGui = jugador:WaitForChild("PlayerGui")
for _, d in playerGui:GetDescendants() do
	registrar(d)
end
playerGui.DescendantAdded:Connect(registrar)

local function hayVentanaAbierta(): boolean
	for i = #ventanas, 1, -1 do
		local v = ventanas[i]
		if not v.Parent then
			table.remove(ventanas, i)
		elseif v.Visible then
			local pantalla = v:FindFirstAncestorOfClass("ScreenGui")
			if pantalla and pantalla.Enabled then
				return true
			end
		end
	end
	return false
end

local function debeSoltarse(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		or UserInputService:GetFocusedTextBox() ~= nil
		or hayVentanaAbierta()
end

------------------------------------------------------------------------
-- Cámara y personaje
------------------------------------------------------------------------

local function humanoide(): Humanoid?
	local p = jugador.Character
	return p and p:FindFirstChildOfClass("Humanoid")
end

local function aplicarModo()
	local activo = Apuntado.Activo
	local h = humanoide()
	if h then
		h.CameraOffset = if activo then DESPLAZAMIENTO else Vector3.zero
	end
	if not activo then
		mira.Visible = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		ajustesJuego.RotationType = Enum.RotationType.MovementRelative
	end
	ayuda.Text = if activo then "Q: volver al modo de siempre   ·   Alt o Ctrl: soltar el mouse" else ""
	boton.Text = if activo then "🎯 Mira: SÍ" else "🎯 Mira: NO"
	boton.BackgroundColor3 = if activo then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
end

RunService:BindToRenderStep("MiraRaidBlox", Enum.RenderPriority.Camera.Value + 1, function()
	if not Apuntado.Activo then
		return
	end
	local libre = debeSoltarse()
	Apuntado.Libre = libre
	mira.Visible = not libre
	if libre then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		ajustesJuego.RotationType = Enum.RotationType.MovementRelative
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		ajustesJuego.RotationType = Enum.RotationType.CameraRelative
	end
end)

jugador.CharacterAdded:Connect(function(personaje: Model)
	personaje:WaitForChild("Humanoid", 10)
	aplicarModo()
end)

------------------------------------------------------------------------
-- Color de la mira y marca de impacto
------------------------------------------------------------------------

local acumulado = 0
RunService.Heartbeat:Connect(function(dt: number)
	acumulado += dt
	if acumulado < 0.08 or not mira.Visible then
		return
	end
	acumulado = 0
	local modelo = Apuntado.ModeloEnMira()
	local h = modelo and modelo:FindFirstChildOfClass("Humanoid")
	if not modelo or not h or h.Health <= 0 or modelo:GetAttribute("Bando") == nil then
		colorMira(BLANCO)
		return
	end
	local otro = Players:GetPlayerFromCharacter(modelo)
	local enemigo = modelo:GetAttribute("Bando") == "Enemigos"
	if otro then
		local suyo, mio = otro:GetAttribute("Bando"), jugador:GetAttribute("Bando")
		enemigo = suyo ~= "Violeta" and suyo ~= mio
	end
	colorMira(if enemigo then ROJO else VERDE)
end)

local marca = 0
NetworkBridge.Client.OnEvent("CombateEvento", function(tipo: any, modelo: any, _valor: any, extra: any)
	if tipo ~= "Accion" or modelo ~= jugador.Character or not Apuntado.Activo then
		return
	end
	if typeof(extra) ~= "table" or typeof(extra.Alcanzados) ~= "table" or #extra.Alcanzados == 0 then
		return
	end
	if extra.Alcanzados[1] == modelo then
		return -- habilidades sobre uno mismo
	end
	marca += 1
	local esta = marca
	impacto.Visible = true
	task.delay(0.15, function()
		if marca == esta then
			impacto.Visible = false
		end
	end)
end)

------------------------------------------------------------------------
-- Alternar
------------------------------------------------------------------------

local function alternar()
	Apuntado.SetActivo(not Apuntado.Activo)
	aplicarModo()
	Avisos.Mostrar(
		if Apuntado.Activo
			then "Modo apuntado: la habilidad pega donde apunta la mira."
			else "Modo objetivo: elegí con Tab o clic.",
		"Info"
	)
end

boton.Activated:Connect(alternar)

ContextActionService:BindAction("MiraRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin and UserInputService:GetFocusedTextBox() == nil then
		alternar()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonR3)

-- Arranca en el modo de siempre: la mira es optativa.
Apuntado.SetActivo(false)
aplicarModo()
