--!strict
-- MinimapaUI: minimapa circular y mapa del mundo (Fase 7.3). Solo visual.
--
-- * Arriba a la derecha (a la izquierda si el jugador eligió "Zurdo"), con el
--   nombre de la zona, las coordenadas y el servidor.
-- * Gira con la cámara: arriba es hacia donde mirás. La flecha central es tu
--   personaje. Marcadores: compañeros de grupo (azul; en el borde si están
--   lejos), enemigos (rojo), NPCs de misión (! disponible, ? para entregar),
--   vetas y plantas (verde), portales (violeta).
-- * Botones + y − para el zoom; M (R1 en gamepad, o el botón) abre el mapa del mundo, con el
--   norte arriba y un radio mayor.
-- * Se oculta desde el panel Personaje (ajuste "Minimapa").

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ZoneConfig = require(ReplicatedStorage.Configs.ZoneConfig)
local Hud = require(ReplicatedStorage.Modules.Hud)

local jugador = Players.LocalPlayer

local TAM = 180 -- diámetro del minimapa en píxeles (antes de escalar)
local ZOOMS = { 60, 120, 240, 480 } -- radio en studs
local RADIO_MUNDO = 900
local MAX_ENEMIGOS = 40

local COLORES = {
	Grupo = Color3.fromRGB(80, 160, 255),
	Enemigo = Color3.fromRGB(235, 70, 60),
	Nodo = Color3.fromRGB(110, 210, 110),
	Portal = Color3.fromRGB(190, 110, 255),
	Mision = Color3.fromRGB(255, 215, 60),
	MisionGris = Color3.fromRGB(190, 190, 190),
}

local gui = Instance.new("ScreenGui")
gui.Name = "MinimapaUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 39
gui.Parent = jugador:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Lienzos (minimapa y mapa grande)
------------------------------------------------------------------------

type Lienzo = {
	Marco: CanvasGroup,
	Flecha: TextLabel,
	Norte: TextLabel,
	Pool: { GuiObject },
	Usados: number,
}

local function crearLienzo(padre: Instance, tam: number): Lienzo
	local marco = Instance.new("CanvasGroup")
	marco.Size = UDim2.fromOffset(tam, tam)
	marco.BackgroundColor3 = Color3.fromRGB(18, 26, 22)
	marco.BackgroundTransparency = 0.15
	marco.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = marco
	-- Anillos de referencia.
	for _, f in { 0.5, 1 } do
		local anillo = Instance.new("Frame")
		anillo.AnchorPoint = Vector2.new(0.5, 0.5)
		anillo.Position = UDim2.fromScale(0.5, 0.5)
		anillo.Size = UDim2.fromScale(f, f)
		anillo.BackgroundTransparency = 1
		local ca = Instance.new("UICorner")
		ca.CornerRadius = UDim.new(0.5, 0)
		ca.Parent = anillo
		local borde = Instance.new("UIStroke")
		borde.Color = Color3.fromRGB(90, 120, 100)
		borde.Transparency = if f == 1 then 0 else 0.6
		borde.Thickness = if f == 1 then 3 else 1
		borde.Parent = anillo
		anillo.Parent = marco
	end
	local flecha = Instance.new("TextLabel")
	flecha.AnchorPoint = Vector2.new(0.5, 0.5)
	flecha.Position = UDim2.fromScale(0.5, 0.5)
	flecha.Size = UDim2.fromOffset(20, 20)
	flecha.BackgroundTransparency = 1
	flecha.Text = "▲"
	flecha.TextScaled = true
	flecha.Font = Enum.Font.GothamBlack
	flecha.TextColor3 = Color3.new(1, 1, 1)
	flecha.TextStrokeTransparency = 0.3
	flecha.ZIndex = 5
	flecha.Parent = marco
	local norte = Instance.new("TextLabel")
	norte.AnchorPoint = Vector2.new(0.5, 0.5)
	norte.Size = UDim2.fromOffset(16, 16)
	norte.BackgroundTransparency = 1
	norte.Text = "N"
	norte.TextScaled = true
	norte.Font = Enum.Font.GothamBlack
	norte.TextColor3 = Color3.fromRGB(255, 120, 100)
	norte.TextStrokeTransparency = 0.3
	norte.ZIndex = 6
	norte.Parent = marco
	marco.Parent = padre
	return { Marco = marco, Flecha = flecha, Norte = norte, Pool = {}, Usados = 0 }
end

-- Marcador reutilizable: un punto o un signo.
local function marcador(l: Lienzo, texto: string?): GuiObject
	l.Usados += 1
	local m = l.Pool[l.Usados]
	if not m then
		local t = Instance.new("TextLabel")
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.BorderSizePixel = 0
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextStrokeTransparency = 0.2
		t.ZIndex = 3
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = t
		t.Parent = l.Marco
		m = t
		l.Pool[l.Usados] = t
	end
	local t = m :: TextLabel
	t.Visible = true
	t.ZIndex = 3
	if texto then
		t.Text = texto
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromOffset(16, 18)
	else
		t.Text = ""
		t.BackgroundTransparency = 0
		t.Size = UDim2.fromOffset(7, 7)
	end
	return t
end

------------------------------------------------------------------------
-- Minimapa
------------------------------------------------------------------------

local contenedor = Instance.new("Frame")
contenedor.Name = "Minimapa"
contenedor.Size = UDim2.fromOffset(TAM, TAM + 52)
contenedor.BackgroundTransparency = 1
contenedor.Parent = gui
Hud.Registrar(contenedor)

local mini = crearLienzo(contenedor, TAM)

local function texto(padre: Instance, pos: UDim2, tam: UDim2, t: string?): TextLabel
	local e = Instance.new("TextLabel")
	e.Position = pos
	e.Size = tam
	e.BackgroundTransparency = 1
	e.Font = Enum.Font.GothamBold
	e.TextScaled = true
	e.TextColor3 = Color3.new(1, 1, 1)
	e.TextStrokeTransparency = 0.4
	e.Text = t or ""
	e.Parent = padre
	return e
end

local textoZona = texto(contenedor, UDim2.fromOffset(0, TAM + 2), UDim2.fromOffset(TAM, 18))
textoZona.TextColor3 = Color3.fromRGB(255, 215, 90)
local textoCoords = texto(contenedor, UDim2.fromOffset(0, TAM + 20), UDim2.fromOffset(TAM, 14))
textoCoords.Font = Enum.Font.GothamMedium
local textoServidor = texto(contenedor, UDim2.fromOffset(0, TAM + 35), UDim2.fromOffset(TAM, 13))
textoServidor.Font = Enum.Font.Gotham
textoServidor.TextColor3 = Color3.fromRGB(180, 180, 190)
textoServidor.Text = if game.JobId == "" then "Servidor local" else `Servidor {string.sub(game.JobId, 1, 6)}`

local function botonRedondo(t: string, pos: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = pos
	b.Size = UDim2.fromOffset(28, 28)
	b.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.Text = t
	b.ZIndex = 8
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	b.Parent = contenedor
	return b
end

local zoom = 2
local masZoom = botonRedondo("+", UDim2.fromOffset(TAM - 8, TAM - 40))
local menosZoom = botonRedondo("−", UDim2.fromOffset(TAM - 8, TAM - 8))
local botonMapa = botonRedondo("M", UDim2.fromOffset(8, TAM - 8))
masZoom.Activated:Connect(function()
	zoom = math.max(1, zoom - 1)
end)
menosZoom.Activated:Connect(function()
	zoom = math.min(#ZOOMS, zoom + 1)
end)

------------------------------------------------------------------------
-- Mapa del mundo
------------------------------------------------------------------------

local fondoMundo = Instance.new("Frame")
fondoMundo.Name = "MapaMundo"
fondoMundo.Size = UDim2.fromScale(1, 1)
fondoMundo.BackgroundColor3 = Color3.new(0, 0, 0)
fondoMundo.BackgroundTransparency = 0.45
fondoMundo.Visible = false
fondoMundo.ZIndex = 20
fondoMundo.Parent = gui
local mundo = crearLienzo(fondoMundo, 520)
mundo.Marco.AnchorPoint = Vector2.new(0.5, 0.5)
mundo.Marco.Position = UDim2.fromScale(0.5, 0.5)
Hud.Registrar(mundo.Marco)
local tituloMundo = texto(fondoMundo, UDim2.new(0.5, -260, 0.5, -300), UDim2.fromOffset(520, 30))
tituloMundo.TextColor3 = Color3.fromRGB(255, 215, 90)
local ayudaMundo =
	texto(fondoMundo, UDim2.new(0.5, -260, 0.5, 268), UDim2.fromOffset(520, 18), "M o tocá afuera para cerrar")
ayudaMundo.Font = Enum.Font.GothamMedium
local cerrarMundo = Instance.new("TextButton")
cerrarMundo.Size = UDim2.fromScale(1, 1)
cerrarMundo.BackgroundTransparency = 1
cerrarMundo.Text = ""
cerrarMundo.ZIndex = 0
cerrarMundo.Parent = fondoMundo

local function alternarMundo()
	fondoMundo.Visible = not fondoMundo.Visible
end
botonMapa.Activated:Connect(alternarMundo)
cerrarMundo.Activated:Connect(function()
	fondoMundo.Visible = false
end)
ContextActionService:BindAction("MapaMundoRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin and UserInputService:GetFocusedTextBox() == nil then
		alternarMundo()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonR1)

------------------------------------------------------------------------
-- Dibujo
------------------------------------------------------------------------

local function raizDe(modelo: Instance?): BasePart?
	if not modelo then
		return nil
	end
	local r = modelo:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	if modelo:IsA("Model") and modelo.PrimaryPart then
		return modelo.PrimaryPart
	end
	return if modelo:IsA("BasePart") then modelo else nil
end

-- Dibuja todo en un lienzo. `giro` = ángulo de la cámara (0 = norte arriba).
local function dibujar(l: Lienzo, centro: Vector3, radio: number, giro: number, rumbo: number)
	l.Usados = 0
	local medio = l.Marco.Size.X.Offset / 2
	local cosG, sinG = math.cos(giro), math.sin(giro)

	-- Mundo (x, z) -> pantalla. Con giro, "adelante de la cámara" queda arriba.
	local function aPantalla(pos: Vector3, fijarBorde: boolean): (UDim2?, boolean)
		local dx, dz = pos.X - centro.X, pos.Z - centro.Z
		local rx = dx * cosG - dz * sinG
		local ry = dx * sinG + dz * cosG
		local d = math.sqrt(rx * rx + ry * ry)
		local enBorde = false
		if d > radio then
			if not fijarBorde then
				return nil, false
			end
			rx, ry = rx / d * radio, ry / d * radio
			enBorde = true
		end
		local escala = (medio - 6) / radio
		return UDim2.fromOffset(medio + rx * escala, medio + ry * escala), enBorde
	end

	-- Norte en el borde.
	local norte = aPantalla(centro + Vector3.new(0, 0, -radio * 2), true)
	if norte then
		l.Norte.Position = norte
	end
	l.Flecha.Rotation = math.deg(rumbo + giro)

	-- Portales y nodos de recolección.
	for _, p in CollectionService:GetTagged("Portal") do
		local r = raizDe(p)
		local pos = r and aPantalla(r.Position, false)
		if pos then
			local m = marcador(l, "◆")
			m.Position = pos;
			(m :: TextLabel).TextColor3 = COLORES.Portal
		end
	end
	for _, n in CollectionService:GetTagged("NodoRecoleccion") do
		local r = raizDe(n)
		local pos = r and aPantalla(r.Position, false)
		if pos then
			local m = marcador(l, nil)
			m.Position = pos
			m.Size = UDim2.fromOffset(5, 5)
			m.BackgroundColor3 = COLORES.Nodo
		end
	end
	-- NPCs de misión (el signo lo pone MisionesUI).
	for _, npc in CollectionService:GetTagged("NpcMision") do
		local signo = npc:GetAttribute("MarcaMinimapa")
		local r = raizDe(npc)
		if typeof(signo) == "string" and signo ~= "" and r then
			local pos = aPantalla(r.Position, false)
			if pos then
				local m = marcador(l, signo)
				m.Position = pos;
				(m :: TextLabel).TextColor3 = if signo == "!" then COLORES.Mision else COLORES.MisionGris
			end
		end
	end
	-- Enemigos.
	local carpeta = Workspace:FindFirstChild("Enemigos")
	if carpeta then
		local n = 0
		for _, e in carpeta:GetChildren() do
			local h = e:FindFirstChildOfClass("Humanoid")
			local r = raizDe(e)
			if h and h.Health > 0 and r then
				local pos = aPantalla(r.Position, false)
				if pos then
					local m = marcador(l, nil)
					m.Position = pos
					m.BackgroundColor3 = COLORES.Enemigo
					n += 1
					if n >= MAX_ENEMIGOS then
						break
					end
				end
			end
		end
	end
	-- Compañeros de grupo (fijos en el borde si están lejos).
	local miGrupo = jugador:GetAttribute("GrupoId")
	if miGrupo ~= nil then
		for _, otro in Players:GetPlayers() do
			if otro ~= jugador and otro:GetAttribute("GrupoId") == miGrupo then
				local r = raizDe(otro.Character)
				if r then
					local pos, borde = aPantalla(r.Position, true)
					if pos then
						local m = marcador(l, nil)
						m.Position = pos
						m.Size = UDim2.fromOffset(if borde then 7 else 9, if borde then 7 else 9)
						m.BackgroundColor3 = COLORES.Grupo
						m.ZIndex = 4
					end
				end
			end
		end
	end
	for i = l.Usados + 1, #l.Pool do
		l.Pool[i].Visible = false
	end
end

local function ubicar()
	contenedor.Visible = Hud.Minimapa
	contenedor.AnchorPoint = Vector2.new(if Hud.Zurdo then 0 else 1, 0)
	contenedor.Position = if Hud.Zurdo then UDim2.fromOffset(8, 8) else UDim2.new(1, -8, 0, 8)
end
Hud.Cambio:Connect(ubicar)
ubicar()

local function actualizarZona()
	local zona = Workspace:GetAttribute("Zona")
	local def = if typeof(zona) == "string" then ZoneConfig.Zonas[zona] else nil
	local nombre = if def then def.Nombre elseif zona == "Pruebas" then "Zona de pruebas" else tostring(zona or "...")
	textoZona.Text = nombre
	tituloMundo.Text = `Mapa: {nombre}`
end
Workspace:GetAttributeChangedSignal("Zona"):Connect(actualizarZona)
actualizarZona()

task.spawn(function()
	while true do
		task.wait(0.1)
		local raiz = raizDe(jugador.Character)
		local camara = Workspace.CurrentCamera
		if not raiz or not camara then
			continue
		end
		local p = raiz.Position
		textoCoords.Text = `X {math.floor(p.X)}  ·  Z {math.floor(p.Z)}`
		-- Ángulo de la cámara y del personaje (0 = mirando al norte, -Z).
		local mira = camara.CFrame.LookVector
		local giroCamara = math.atan2(mira.X, -mira.Z)
		local frente = raiz.CFrame.LookVector
		local rumbo = math.atan2(frente.X, -frente.Z)
		if contenedor.Visible then
			dibujar(mini, p, ZOOMS[zoom], -giroCamara, rumbo)
		end
		if fondoMundo.Visible then
			dibujar(mundo, p, RADIO_MUNDO, 0, rumbo)
		end
	end
end)
