--!strict
-- CombatEffectsClient: efectos visuales del combate, todos locales.
--
-- * Números flotantes de daño y cura (físico blanco, mágico azul/púrpura,
--   crítico dorado con rebote, cura verde con "+", estados como ¡PARRY!).
-- * Barra de vida gigante de los RaidBlox cercanos.
-- * Anuncios globales en el chat y en pantalla.
-- * Bolsas de botín personales: solo las ve su dueño; Épico o más con haz de luz.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local jugador = Players.LocalPlayer
local playerGui = jugador:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Números flotantes
------------------------------------------------------------------------

local COLOR_FISICO = Color3.fromRGB(255, 245, 210)
local COLOR_MAGICO = Color3.fromRGB(150, 130, 255)
local COLOR_CRITICO = Color3.fromRGB(255, 205, 40)
local COLOR_CURA = Color3.fromRGB(80, 255, 110)
local COLOR_ESTADO = Color3.fromRGB(255, 170, 70)

local function flotante(modelo: Model, texto: string, color: Color3, grande: boolean)
	local ancla = modelo:FindFirstChild("Head") or modelo.PrimaryPart
	if not ancla or not ancla:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 50)
	gui.StudsOffset = Vector3.new((math.random() - 0.5) * 2.5, 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Adornee = ancla
	local etiqueta = Instance.new("TextLabel")
	etiqueta.Size = UDim2.fromScale(1, 1)
	etiqueta.BackgroundTransparency = 1
	etiqueta.Font = Enum.Font.GothamBlack
	etiqueta.TextSize = if grande then 22 else 18
	etiqueta.TextColor3 = color
	etiqueta.TextStrokeTransparency = 0.2
	etiqueta.Text = texto
	etiqueta.Parent = gui
	gui.Parent = playerGui

	if grande then
		-- Rebote del crítico.
		TweenService:Create(etiqueta, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextSize = 34,
		}):Play()
		task.delay(0.12, function()
			TweenService:Create(etiqueta, TweenInfo.new(0.15), { TextSize = 26 }):Play()
		end)
	end
	local duracion = 1.2
	TweenService:Create(gui, TweenInfo.new(duracion, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = gui.StudsOffset + Vector3.new(0, 3, 0),
	}):Play()
	TweenService:Create(
		etiqueta,
		TweenInfo.new(duracion * 0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, duracion * 0.4),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	):Play()
	task.delay(duracion + 0.05, function()
		gui:Destroy()
	end)
end

NetworkBridge.Client.OnEvent("CombateEvento", function(tipo: any, modelo: any, valor: any, extra: any)
	if typeof(modelo) ~= "Instance" or not modelo:IsA("Model") then
		return
	end
	if tipo == "Danio" and typeof(valor) == "number" then
		local critico = typeof(extra) == "table" and extra.Critico == true
		local magico = typeof(extra) == "table" and extra.Escuela == "Magico"
		local color = if critico then COLOR_CRITICO elseif magico then COLOR_MAGICO else COLOR_FISICO
		flotante(modelo, if critico then `{valor}!` else tostring(valor), color, critico)
	elseif tipo == "Cura" and typeof(valor) == "number" then
		flotante(modelo, `+{valor}`, COLOR_CURA, extra == true)
	elseif tipo == "Estado" and typeof(valor) == "string" then
		flotante(modelo, valor, COLOR_ESTADO, false)
	end
end)

------------------------------------------------------------------------
-- Barra de los RaidBlox
------------------------------------------------------------------------

local guiJefes = Instance.new("ScreenGui")
guiJefes.Name = "RaidBloxUI"
guiJefes.ResetOnSpawn = false
guiJefes.DisplayOrder = 45
guiJefes.Parent = playerGui

local contenedorJefes = Instance.new("Frame")
contenedorJefes.AnchorPoint = Vector2.new(0.5, 0)
contenedorJefes.Position = UDim2.fromScale(0.5, 0.18)
contenedorJefes.Size = UDim2.fromScale(0.5, 0.2)
contenedorJefes.BackgroundTransparency = 1
contenedorJefes.Parent = guiJefes
local listaJefes = Instance.new("UIListLayout")
listaJefes.Padding = UDim.new(0, 6)
listaJefes.Parent = contenedorJefes

type BarraJefe = { Marco: Frame, Relleno: Frame, Titulo: TextLabel, Valor: TextLabel }
local barrasJefe: { [string]: BarraJefe } = {}

local function barraJefe(id: string): BarraJefe
	local existente = barrasJefe[id]
	if existente then
		return existente
	end
	local marco = Instance.new("Frame")
	marco.Size = UDim2.new(1, 0, 0, 46)
	marco.BackgroundTransparency = 1
	local titulo = Instance.new("TextLabel")
	titulo.Size = UDim2.new(1, 0, 0, 20)
	titulo.BackgroundTransparency = 1
	titulo.Font = Enum.Font.GothamBlack
	titulo.TextScaled = true
	titulo.TextColor3 = Color3.fromRGB(255, 220, 180)
	titulo.TextStrokeTransparency = 0.3
	titulo.Parent = marco
	local fondo = Instance.new("Frame")
	fondo.Position = UDim2.fromOffset(0, 22)
	fondo.Size = UDim2.new(1, 0, 0, 22)
	fondo.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
	fondo.BorderSizePixel = 0
	fondo.Parent = marco
	local borde = Instance.new("UIStroke")
	borde.Color = Color3.fromRGB(200, 150, 60)
	borde.Thickness = 2
	borde.Parent = fondo
	local relleno = Instance.new("Frame")
	relleno.Size = UDim2.fromScale(1, 1)
	relleno.BackgroundColor3 = Color3.fromRGB(190, 40, 35)
	relleno.BorderSizePixel = 0
	relleno.Parent = fondo
	local valor = Instance.new("TextLabel")
	valor.Size = UDim2.fromScale(1, 1)
	valor.BackgroundTransparency = 1
	valor.Font = Enum.Font.GothamBold
	valor.TextScaled = true
	valor.TextColor3 = Color3.new(1, 1, 1)
	valor.TextStrokeTransparency = 0.4
	valor.ZIndex = 2
	valor.Parent = fondo
	marco.Parent = contenedorJefes
	local nueva: BarraJefe = { Marco = marco, Relleno = relleno, Titulo = titulo, Valor = valor }
	barrasJefe[id] = nueva
	return nueva
end

NetworkBridge.Client.OnEvent("RaidBloxEstado", function(estado: any)
	if typeof(estado) ~= "table" or typeof(estado.Id) ~= "string" then
		return
	end
	local id = estado.Id
	if estado.Oculto or estado.Muerto then
		local b = barrasJefe[id]
		if b then
			b.Marco:Destroy()
			barrasJefe[id] = nil
		end
		return
	end
	local vida = if typeof(estado.Vida) == "number" then estado.Vida else 0
	local maxima = if typeof(estado.VidaMax) == "number" and estado.VidaMax > 0 then estado.VidaMax else 1
	local b = barraJefe(id)
	b.Titulo.Text = `{estado.Nombre} (Nv. {estado.Nivel}){if estado.Furia then "  -  ¡FURIA!" else ""}`
	b.Relleno.BackgroundColor3 = if estado.Furia then Color3.fromRGB(255, 90, 20) else Color3.fromRGB(190, 40, 35)
	TweenService:Create(b.Relleno, TweenInfo.new(0.3), { Size = UDim2.fromScale(math.clamp(vida / maxima, 0, 1), 1) })
		:Play()
	b.Valor.Text = `{vida} / {maxima}`
end)

------------------------------------------------------------------------
-- Anuncios globales
------------------------------------------------------------------------

NetworkBridge.Client.OnEvent("AnuncioGlobal", function(texto: any, color: any)
	if typeof(texto) ~= "string" then
		return
	end
	Avisos.Mostrar(texto, "Oro")
	local hex = if typeof(color) == "Color3" then color:ToHex() else "FFD700"
	pcall(function()
		local canales = TextChatService:FindFirstChild("TextChannels")
		local general = canales and canales:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			general:DisplaySystemMessage(`<font color="#{hex}"><b>[RaidBlox]</b> {texto}</font>`)
		end
	end)
end)

------------------------------------------------------------------------
-- Bolsas de botín personales
------------------------------------------------------------------------

local bolsas: { [string]: Part } = {}
local paramsSuelo = RaycastParams.new()
paramsSuelo.FilterType = Enum.RaycastFilterType.Exclude

local function crearBolsa(id: string, posicion: Vector3, info: { [string]: any })
	local color: Color3 = if typeof(info.Color) == "Color3" then info.Color else Color3.new(1, 1, 1)
	paramsSuelo.FilterDescendantsInstances = if jugador.Character then { jugador.Character } else {}
	local suelo = Workspace:Raycast(posicion + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), paramsSuelo)
	local y = if suelo then suelo.Position.Y else posicion.Y

	local bolsa = Instance.new("Part")
	bolsa.Name = "BotinRaidBlox"
	bolsa.Shape = Enum.PartType.Ball
	bolsa.Size = Vector3.new(1.4, 1.4, 1.4)
	bolsa.Anchored = true
	bolsa.CanCollide = false
	bolsa.CanQuery = false
	bolsa.Material = Enum.Material.Fabric
	bolsa.Color = Color3.fromRGB(140, 100, 60)
	bolsa.Position = Vector3.new(posicion.X, y + 0.7, posicion.Z)

	local brillo = Instance.new("PointLight")
	brillo.Color = color
	brillo.Range = 8
	brillo.Brightness = 1.5
	brillo.Parent = bolsa

	if info.Haz then
		-- Haz de luz vertical del color de la rareza.
		local base = Instance.new("Attachment")
		base.Parent = bolsa
		local tope = Instance.new("Attachment")
		tope.Position = Vector3.new(0, 40, 0)
		tope.Parent = bolsa
		local haz = Instance.new("Beam")
		haz.Attachment0 = base
		haz.Attachment1 = tope
		haz.Color = ColorSequence.new(color)
		haz.Transparency = NumberSequence.new(0.2, 1)
		haz.LightEmission = 1
		haz.Width0 = 1.2
		haz.Width1 = 0.4
		haz.FaceCamera = true
		haz.Parent = bolsa
	end
	if info.Particulas then
		local chispas = Instance.new("ParticleEmitter")
		chispas.Color = ColorSequence.new(color)
		chispas.LightEmission = 0.8
		chispas.Rate = 12
		chispas.Lifetime = NumberRange.new(0.8, 1.4)
		chispas.Speed = NumberRange.new(1, 3)
		chispas.Size = NumberSequence.new(0.3, 0)
		chispas.Parent = bolsa
	end

	local cartel = Instance.new("BillboardGui")
	cartel.Size = UDim2.fromOffset(220, 30)
	cartel.StudsOffset = Vector3.new(0, 2, 0)
	cartel.AlwaysOnTop = true
	cartel.MaxDistance = 60
	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.Font = Enum.Font.GothamBold
	texto.TextScaled = true
	texto.TextColor3 = color
	texto.TextStrokeTransparency = 0.3
	texto.Text = `{info.Nombre} x{info.Cantidad} ({info.NombreRareza})`
	texto.Parent = cartel
	cartel.Parent = bolsa

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Recoger"
	prompt.ObjectText = tostring(info.Nombre)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function()
		NetworkBridge.Client.Fire("RecogerBotin", id)
	end)
	prompt.Parent = bolsa

	bolsa.Parent = Workspace
	bolsas[id] = bolsa
end

NetworkBridge.Client.OnEvent("BotinSoltado", function(id: any, posicion: any, info: any)
	if typeof(id) ~= "string" or typeof(posicion) ~= "Vector3" or typeof(info) ~= "table" then
		return
	end
	crearBolsa(id, posicion, info)
end)

NetworkBridge.Client.OnEvent("BotinRetirado", function(id: any)
	if typeof(id) ~= "string" then
		return
	end
	local bolsa = bolsas[id]
	if bolsa then
		bolsa:Destroy()
		bolsas[id] = nil
	end
end)
