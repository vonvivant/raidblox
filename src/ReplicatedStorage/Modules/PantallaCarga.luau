--!strict
-- PantallaCarga: construye la pantalla de carga temática de cada zona.
-- La usa el cliente al iniciar un teleport; se registra con
-- TeleportService:SetTeleportGui para que siga visible al llegar al otro place.

local TweenService = game:GetService("TweenService")

local ZoneConfig = require(script.Parent.Parent.Configs.ZoneConfig)

local PantallaCarga = {}

export type Pantalla = {
	Gui: ScreenGui,
	SetEstado: (texto: string) -> (),
	Ocultar: () -> (),
}

function PantallaCarga.Crear(zonaId: string): Pantalla
	local zona = ZoneConfig.Zonas[zonaId]
	local color = if zona then zona.ColorTema else Color3.fromRGB(120, 120, 140)
	local nombre = if zona then zona.Nombre else "Viajando"
	local tema = if zona then zona.Tema else ""

	local gui = Instance.new("ScreenGui")
	gui.Name = "PantallaCargaRaidBlox"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local fondo = Instance.new("Frame")
	fondo.Name = "Fondo"
	fondo.Size = UDim2.fromScale(1, 1)
	fondo.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
	fondo.BorderSizePixel = 0
	fondo.Parent = gui

	local degradado = Instance.new("UIGradient")
	degradado.Color = ColorSequence.new(Color3.fromRGB(10, 10, 16), color:Lerp(Color3.new(0, 0, 0), 0.55))
	degradado.Rotation = 90
	degradado.Parent = fondo

	local titulo = Instance.new("TextLabel")
	titulo.Name = "Titulo"
	titulo.AnchorPoint = Vector2.new(0.5, 0.5)
	titulo.Position = UDim2.fromScale(0.5, 0.42)
	titulo.Size = UDim2.fromScale(0.8, 0.1)
	titulo.BackgroundTransparency = 1
	titulo.Font = Enum.Font.GothamBlack
	titulo.TextScaled = true
	titulo.TextColor3 = color
	titulo.Text = nombre
	titulo.Parent = fondo

	local subtitulo = Instance.new("TextLabel")
	subtitulo.Name = "Tema"
	subtitulo.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitulo.Position = UDim2.fromScale(0.5, 0.52)
	subtitulo.Size = UDim2.fromScale(0.7, 0.05)
	subtitulo.BackgroundTransparency = 1
	subtitulo.Font = Enum.Font.GothamMedium
	subtitulo.TextScaled = true
	subtitulo.TextColor3 = Color3.fromRGB(220, 220, 230)
	subtitulo.Text = tema
	subtitulo.Parent = fondo

	local estado = Instance.new("TextLabel")
	estado.Name = "Estado"
	estado.AnchorPoint = Vector2.new(0.5, 0.5)
	estado.Position = UDim2.fromScale(0.5, 0.85)
	estado.Size = UDim2.fromScale(0.5, 0.035)
	estado.BackgroundTransparency = 1
	estado.Font = Enum.Font.Gotham
	estado.TextScaled = true
	estado.TextColor3 = Color3.fromRGB(170, 170, 185)
	estado.Text = "Viajando"
	estado.Parent = fondo

	-- Animación de puntos ("Viajando..."), corta sola cuando se destruye la GUI.
	local base = "Viajando"
	task.spawn(function()
		local n = 0
		while gui.Parent ~= nil or n == 0 do
			n = (n % 3) + 1
			estado.Text = base .. string.rep(".", n)
			task.wait(0.4)
		end
	end)

	local function setEstado(texto: string)
		base = texto
		estado.Text = texto
	end

	local function ocultar()
		local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, objeto in gui:GetDescendants() do
			if objeto:IsA("TextLabel") then
				TweenService:Create(objeto, info, { TextTransparency = 1 }):Play()
			elseif objeto:IsA("Frame") then
				TweenService:Create(objeto, info, { BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(0.7, function()
			gui:Destroy()
		end)
	end

	return { Gui = gui, SetEstado = setEstado, Ocultar = ocultar }
end

return PantallaCarga
