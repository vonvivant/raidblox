--!strict
-- CombatClient: selección de objetivo y uso de habilidades en PC, móvil y consola.
--
-- Objetivo:
--   PC:      Tab (siguiente enemigo), clic sobre un enemigo o aliado, clic en el vacío para limpiar.
--   Móvil:   tocar un enemigo o aliado (tocar el vacío limpia).
--   Consola: R2 / L2 para pasar al siguiente / anterior enemigo.
-- Habilidades:
--   PC:      1 2 3 4 y F (parry).
--   Consola: X Y B y flecha arriba; L1 (parry).
--   Móvil:   tocar los botones de la barra de acción.
--
-- El cliente solo pide; el servidor valida rango, maná, cooldown y estado.
-- HUD (Fase 7): marco del jugador (retrato, nivel, vida, maná, XP), marco del
-- objetivo (vida y buffs/debuffs con cuenta regresiva), barra de casteo y
-- barra de acción con recarga circular: las habilidades (4, o 4 barras de 4
-- para el Chatarrero), parry, poción de vida (5), de maná (6) y montura (G).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local EventosCliente = require(game:GetService("ReplicatedStorage").Modules.EventosCliente)
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClassConfig = require(ReplicatedStorage.Configs.ClassConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Avisos = require(ReplicatedStorage.Modules.Avisos)
local Apuntado = require(ReplicatedStorage.Modules.Apuntado)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local Hud = require(ReplicatedStorage.Modules.Hud)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local ChatarreroConfig = require(ReplicatedStorage.Configs.ChatarreroConfig)
local CollectionService = game:GetService("CollectionService")

local jugador = Players.LocalPlayer
local playerGui = jugador:WaitForChild("PlayerGui")

local ALCANCE_TAB = 60
local BOTONES: { Enum.KeyCode } =
	{ Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonB, Enum.KeyCode.DPadUp }

------------------------------------------------------------------------
-- Estado local (solo para mostrar)
------------------------------------------------------------------------

local objetivo: Model? = nil
local relacionObjetivo: "Enemigo" | "Aliado" | "Neutral" = "Enemigo"
local cooldowns: { [number]: number } = {} -- índice -> listo en (tiempo de servidor); 0 = parry
local gcdHasta = 0
local casteo: { Hasta: number, Nombre: string, Inicio: number }? = nil

local function ahora(): number
	return Workspace:GetServerTimeNow()
end

local function claseActual(): ClassConfig.DefinicionClase?
	local clase = jugador:GetAttribute("Clase")
	return if typeof(clase) == "string" then ClassConfig.Clases[clase] else nil
end

local function combatienteVivo(modelo: Model?): boolean
	if not modelo or not modelo.Parent then
		return false
	end
	local h = modelo:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and modelo:GetAttribute("Bando") ~= nil
end

------------------------------------------------------------------------
-- Indicador de objetivo
------------------------------------------------------------------------

local resaltado = Instance.new("Highlight")
resaltado.Name = "ObjetivoRaidBlox"
resaltado.FillTransparency = 0.85
resaltado.OutlineTransparency = 0
resaltado.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

local flecha = Instance.new("BillboardGui")
flecha.Name = "FlechaObjetivo"
flecha.Size = UDim2.fromOffset(40, 40)
flecha.StudsOffset = Vector3.new(0, 3.5, 0)
flecha.AlwaysOnTop = true
local icono = Instance.new("TextLabel")
icono.Size = UDim2.fromScale(1, 1)
icono.BackgroundTransparency = 1
icono.Text = "▼"
icono.TextScaled = true
icono.Font = Enum.Font.GothamBlack
icono.Parent = flecha

local function seleccionar(modelo: Model?)
	if modelo and not combatienteVivo(modelo) then
		modelo = nil
	end
	objetivo = modelo
	if modelo then
		local enemigo = modelo:GetAttribute("Bando") == "Enemigos"
		relacionObjetivo = if enemigo then "Enemigo" else "Aliado"
		-- Un jugador es enemigo si es de otro bando (y no es Violeta); con un
		-- Violeta de por medio es neutral (no se pueden atacar).
		local otro = Players:GetPlayerFromCharacter(modelo)
		if otro then
			local suyo, mio = otro:GetAttribute("Bando"), jugador:GetAttribute("Bando")
			enemigo = suyo ~= "Violeta" and suyo ~= mio
			relacionObjetivo = if suyo == mio
				then "Aliado"
				elseif suyo == "Violeta" or mio == "Violeta" then "Neutral"
				else "Enemigo"
		end
		local color = if enemigo then Color3.fromRGB(255, 70, 60) else Color3.fromRGB(90, 230, 120)
		resaltado.OutlineColor = color
		resaltado.FillColor = color
		resaltado.Adornee = modelo
		resaltado.Parent = playerGui
		local cabeza = modelo:FindFirstChild("Head") or modelo.PrimaryPart
		if cabeza and cabeza:IsA("BasePart") then
			flecha.Adornee = cabeza
			flecha.Parent = playerGui
		else
			flecha.Parent = nil
		end
		icono.TextColor3 = color
	else
		-- Sacarlos del árbol alcanza para que dejen de verse.
		resaltado.Parent = nil
		flecha.Parent = nil
	end
end

-- Enemigos vivos cercanos, ordenados por distancia.
local function enemigosCercanos(): { Model }
	local personaje = jugador.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return {}
	end
	local lista: { { modelo: Model, d: number } } = {}
	local carpeta = Workspace:FindFirstChild("Enemigos")
	for _, modelo in if carpeta then carpeta:GetChildren() else {} do
		if modelo:IsA("Model") and combatienteVivo(modelo) then
			local otra = modelo:FindFirstChild("HumanoidRootPart")
			if otra and otra:IsA("BasePart") then
				local d = (otra.Position - raiz.Position).Magnitude
				if d <= ALCANCE_TAB then
					table.insert(lista, { modelo = modelo, d = d })
				end
			end
		end
	end
	-- Jugadores de otro bando (el Violeta es intocable). Si vale el PvP en ese
	-- lugar lo decide el servidor al atacar.
	local miBando = jugador:GetAttribute("Bando")
	for _, otro in Players:GetPlayers() do
		local bando = otro:GetAttribute("Bando")
		local personajeOtro = otro.Character
		if
			otro ~= jugador
			and personajeOtro
			and typeof(bando) == "string"
			and bando ~= "Violeta"
			and bando ~= miBando
			and combatienteVivo(personajeOtro)
		then
			local otra = personajeOtro:FindFirstChild("HumanoidRootPart")
			if otra and otra:IsA("BasePart") then
				local d = (otra.Position - raiz.Position).Magnitude
				if d <= ALCANCE_TAB then
					table.insert(lista, { modelo = personajeOtro, d = d })
				end
			end
		end
	end
	table.sort(lista, function(a, b)
		return a.d < b.d
	end)
	local resultado: { Model } = {}
	for _, e in lista do
		table.insert(resultado, e.modelo)
	end
	return resultado
end

local function ciclar(paso: number)
	local lista = enemigosCercanos()
	if #lista == 0 then
		seleccionar(nil)
		return
	end
	local actual = if objetivo then table.find(lista, objetivo) else nil
	local siguiente = if actual then ((actual - 1 + paso) % #lista) + 1 else 1
	seleccionar(lista[siguiente])
end

-- Busca un combatiente bajo una posición de pantalla.
local function combatienteEnPantalla(posicion: Vector2): Model?
	local camara = Workspace.CurrentCamera
	if not camara then
		return nil
	end
	local rayo = camara:ViewportPointToRay(posicion.X, posicion.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if jugador.Character then { jugador.Character } else {}
	local resultado = Workspace:Raycast(rayo.Origin, rayo.Direction * 300, params)
	if resultado then
		local modelo: Instance? = resultado.Instance
		while modelo and modelo ~= Workspace do
			if modelo:IsA("Model") and modelo:GetAttribute("Bando") ~= nil then
				return modelo
			end
			modelo = modelo.Parent
		end
	end
	-- El rayo no tocó a nadie (personajes chicos o lejanos): se elige el
	-- combatiente vivo más cercano al punto tocado en pantalla, hasta 60 px.
	local mejor: Model? = nil
	local mejorDistancia = 60
	for _, modelo in enemigosCercanos() do
		local cabeza = modelo:FindFirstChild("Head") or modelo:FindFirstChild("HumanoidRootPart")
		if cabeza and cabeza:IsA("BasePart") then
			local punto, visible = camara:WorldToViewportPoint(cabeza.Position)
			if visible then
				local d = (Vector2.new(punto.X, punto.Y) - posicion).Magnitude
				if d < mejorDistancia then
					mejor, mejorDistancia = modelo, d
				end
			end
		end
	end
	return mejor
end

------------------------------------------------------------------------
-- Acciones
------------------------------------------------------------------------

local function usarHabilidad(indice: number)
	local def = claseActual()
	if not def then
		Avisos.Mostrar("Primero elegí una clase.", "Error")
		return
	end
	local hab = def.Habilidades[indice]
	if not hab then
		return
	end
	-- Modo apuntado: va el punto bajo la mira y el servidor decide a quién le pega.
	local punto = if Apuntado.Activo then Apuntado.Punto() else nil
	NetworkBridge.Client.Fire("UsarHabilidad", indice, if punto then nil else objetivo, punto)
end

local function parry()
	NetworkBridge.Client.Fire("Parry")
end

ContextActionService:BindAction("ParryRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin then
		parry()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)
ContextActionService:BindAction("ObjetivoSiguiente", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin then
		ciclar(1)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Tab, Enum.KeyCode.ButtonR2)
ContextActionService:BindAction("ObjetivoAnterior", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin then
		ciclar(-1)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonL2)

UserInputService.InputBegan:Connect(function(input: InputObject, procesado: boolean)
	if procesado then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and Apuntado.Activo and not Apuntado.Libre then
		usarHabilidad(1) -- con la mira, clic izquierdo = ataque básico
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Clic sobre un combatiente lo selecciona; clic en el vacío limpia el objetivo.
		seleccionar(combatienteEnPantalla(Vector2.new(input.Position.X, input.Position.Y)))
	end
end)

UserInputService.TouchTapInWorld:Connect(function(posicion: Vector2, procesadoPorUI: boolean)
	if procesadoPorUI then
		return
	end
	seleccionar(combatienteEnPantalla(posicion))
end)

-- Tab es la tecla clásica del tab-targeting, pero Roblox la usa para la lista de
-- jugadores: se oculta esa lista para que Tab solo cambie de objetivo.
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

------------------------------------------------------------------------
-- Interfaz
------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "CombateUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = playerGui

local function etiqueta(padre: Instance, tam: UDim2, pos: UDim2, texto: string?): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = tam
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.5
	t.Text = texto or ""
	t.Parent = padre
	return t
end

-- HUD (Fase 7). Diseñado en píxeles para 1280×720; cada bloque lleva un
-- UIScale (módulo Hud) que lo adapta a la pantalla y al tamaño elegido.

local COLOR_PANEL = Color3.fromRGB(14, 14, 22)
local COLOR_VIDA = Color3.fromRGB(60, 190, 80)
local COLOR_MANA = Color3.fromRGB(60, 120, 230)
local COLOR_XP = Color3.fromRGB(150, 80, 220)
local COLOR_ENEMIGO = Color3.fromRGB(210, 60, 50)
local COLOR_NEUTRAL = Color3.fromRGB(225, 190, 50)

local function panel(padre: Instance, tam: Vector2, nombre: string): Frame
	local f = Instance.new("Frame")
	f.Name = nombre
	f.Size = UDim2.fromOffset(tam.X, tam.Y)
	f.BackgroundColor3 = COLOR_PANEL
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = f
	local borde = Instance.new("UIStroke")
	borde.Color = Color3.fromRGB(70, 70, 95)
	borde.Thickness = 1
	borde.Parent = f
	f.Parent = padre
	Hud.Registrar(f)
	return f
end

local function barraPx(padre: Instance, pos: Vector2, tam: Vector2, color: Color3): (Frame, TextLabel, Frame)
	local fondo = Instance.new("Frame")
	fondo.Position = UDim2.fromOffset(pos.X, pos.Y)
	fondo.Size = UDim2.fromOffset(tam.X, tam.Y)
	fondo.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	fondo.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = fondo
	fondo.Parent = padre
	local relleno = Instance.new("Frame")
	relleno.Name = "Relleno"
	relleno.Size = UDim2.fromScale(1, 1)
	relleno.BackgroundColor3 = color
	relleno.BorderSizePixel = 0
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 4)
	c2.Parent = relleno
	relleno.Parent = fondo
	local texto = etiqueta(fondo, UDim2.fromScale(1, 0.9), UDim2.fromScale(0, 0.05))
	texto.ZIndex = 2
	return relleno, texto, fondo
end

------------------------------------------------------------------------
-- Marco del jugador (arriba a la izquierda; a la derecha si es zurdo)
------------------------------------------------------------------------

local marcoJugador = panel(gui, Vector2.new(310, 98), "MarcoJugador")
local retrato = Instance.new("ImageLabel")
retrato.Size = UDim2.fromOffset(78, 78)
retrato.Position = UDim2.fromOffset(10, 10)
retrato.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
retrato.Image = `rbxthumb://type=AvatarHeadShot&id={jugador.UserId}&w=150&h=150`
local redondo = Instance.new("UICorner")
redondo.CornerRadius = UDim.new(0.5, 0)
redondo.Parent = retrato
local bordeRetrato = Instance.new("UIStroke")
bordeRetrato.Thickness = 2
bordeRetrato.Parent = retrato
retrato.Parent = marcoJugador
local insignia = Instance.new("Frame")
insignia.AnchorPoint = Vector2.new(0.5, 0.5)
insignia.Position = UDim2.fromOffset(49, 88)
insignia.Size = UDim2.fromOffset(46, 18)
insignia.BackgroundColor3 = Color3.fromRGB(40, 30, 10)
local c3 = Instance.new("UICorner")
c3.CornerRadius = UDim.new(0, 6)
c3.Parent = insignia
insignia.ZIndex = 3
insignia.Parent = marcoJugador
local textoNivel = etiqueta(insignia, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
textoNivel.ZIndex = 4
textoNivel.TextColor3 = Color3.fromRGB(255, 215, 90)

local tituloJugador = etiqueta(marcoJugador, UDim2.fromOffset(206, 20), UDim2.fromOffset(98, 6))
tituloJugador.TextXAlignment = Enum.TextXAlignment.Left
local barraVida, textoVida = barraPx(marcoJugador, Vector2.new(98, 30), Vector2.new(202, 20), COLOR_VIDA)
local barraMana, textoMana = barraPx(marcoJugador, Vector2.new(98, 54), Vector2.new(202, 16), COLOR_MANA)
local barraXp, textoXp = barraPx(marcoJugador, Vector2.new(98, 74), Vector2.new(202, 14), COLOR_XP)

------------------------------------------------------------------------
-- Marco del objetivo (arriba al centro) con buffs y debuffs
------------------------------------------------------------------------

local marcoObjetivo = panel(gui, Vector2.new(340, 84), "MarcoObjetivo")
marcoObjetivo.AnchorPoint = Vector2.new(0.5, 0)
marcoObjetivo.Position = UDim2.new(0.5, 0, 0, 8)
marcoObjetivo.Visible = false
local tituloObjetivo = etiqueta(marcoObjetivo, UDim2.fromOffset(320, 20), UDim2.fromOffset(10, 4))
local barraObjetivo, textoObjetivo = barraPx(marcoObjetivo, Vector2.new(10, 28), Vector2.new(320, 22), COLOR_ENEMIGO)
local filaEfectos = Instance.new("Frame")
filaEfectos.Position = UDim2.fromOffset(10, 56)
filaEfectos.Size = UDim2.fromOffset(320, 22)
filaEfectos.BackgroundTransparency = 1
filaEfectos.Parent = marcoObjetivo
local layoutEfectos = Instance.new("UIListLayout")
layoutEfectos.FillDirection = Enum.FillDirection.Horizontal
layoutEfectos.HorizontalAlignment = Enum.HorizontalAlignment.Center
layoutEfectos.Padding = UDim.new(0, 4)
layoutEfectos.Parent = filaEfectos

type Chip = { Hasta: number, Nombre: string, Texto: TextLabel, Marco: Frame }
local chips: { Chip } = {}
local efectosMostrados = ""

local function dibujarEfectos(texto: string)
	efectosMostrados = texto
	for _, h in filaEfectos:GetChildren() do
		if h:IsA("GuiObject") then
			h:Destroy()
		end
	end
	table.clear(chips)
	if texto == "" then
		return
	end
	for _, parte in string.split(texto, ";") do
		local campos = string.split(parte, "|")
		local hasta = tonumber(campos[2])
		if #campos < 3 or not hasta then
			continue
		end
		local bueno = campos[3] == "B"
		local chip = Instance.new("Frame")
		chip.Size = UDim2.fromOffset(76, 20)
		chip.BackgroundColor3 = if bueno then Color3.fromRGB(25, 70, 35) else Color3.fromRGB(80, 25, 25)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 5)
		c.Parent = chip
		local borde = Instance.new("UIStroke")
		borde.Color = if bueno then COLOR_VIDA else COLOR_ENEMIGO
		borde.Parent = chip
		local t = etiqueta(chip, UDim2.new(1, -4, 1, -2), UDim2.fromOffset(2, 1))
		t.Font = Enum.Font.GothamMedium
		chip.Parent = filaEfectos
		table.insert(chips, { Hasta = hasta, Nombre = campos[1], Texto = t, Marco = chip })
		if #chips >= 4 then
			break
		end
	end
end

------------------------------------------------------------------------
-- Barra de casteo
------------------------------------------------------------------------

local marcoCasteo = panel(gui, Vector2.new(300, 22), "Casteo")
marcoCasteo.AnchorPoint = Vector2.new(0.5, 1)
marcoCasteo.Position = UDim2.new(0.5, 0, 1, -100)
marcoCasteo.Visible = false
local barraCasteo, textoCasteo =
	barraPx(marcoCasteo, Vector2.new(3, 3), Vector2.new(294, 16), Color3.fromRGB(230, 190, 60))

------------------------------------------------------------------------
-- Barra de acción con recarga circular.
--   * Clases comunes: 4 habilidades (1 2 3 4).
--   * Clases con barras (Chatarrero): 4 barras de 4 botones, una por
--     categoría de recarga: I = 1 2 3 4, II = Z X C V, III = 7 8 9 0,
--     IV = Y U H J. El botón "⚙ Habilidades" elige cuáles van en cada barra.
--   * Siempre al final: parry (F), pociones (5, 6) y montura (G).
------------------------------------------------------------------------

local TECLAS_BARRAS: { { Enum.KeyCode } } = {
	{ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four },
	{ Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V },
	{ Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero },
	{ Enum.KeyCode.Y, Enum.KeyCode.U, Enum.KeyCode.H, Enum.KeyCode.J },
}
local NOMBRES_TECLAS: { { string } } = {
	{ "1", "2", "3", "4" },
	{ "Z", "X", "C", "V" },
	{ "7", "8", "9", "0" },
	{ "Y", "U", "H", "J" },
}
local COLORES_BARRA: { Color3 } = {
	Color3.fromRGB(110, 110, 150),
	Color3.fromRGB(80, 150, 255),
	Color3.fromRGB(180, 90, 255),
	Color3.fromRGB(255, 170, 40),
}

local barraAccion = Instance.new("Frame")
barraAccion.Name = "BarraAccion"
barraAccion.BackgroundTransparency = 1
barraAccion.Parent = gui
Hud.Registrar(barraAccion)

type TipoRanura = "Habilidad" | "Parry" | "Pocion" | "Montura"
type Ranura = {
	Tipo: TipoRanura,
	Indice: number, -- índice en las habilidades de la clase
	Barra: number, -- 1..4 (habilidades)
	Pos: number, -- 1..4 dentro de la barra
	ItemId: string?,
	Boton: TextButton,
	Nombre: TextLabel,
	Tecla: TextLabel,
	Costo: TextLabel,
	Cuenta: TextLabel,
	Derecha: UIGradient,
	Izquierda: UIGradient,
	Velo: Frame,
}
local ranuras: { Ranura } = {}
local ranuraMontura: Ranura? = nil
local tamRanura = 58
local conBarras = false
local pocionLista = 0

-- Velo circular de recarga: dos mitades recortadas, cada una con un círculo
-- y un UIGradient de corte duro que gira (sin imágenes externas).
local function veloCircular(boton: GuiObject): (Frame, UIGradient, UIGradient)
	local velo = Instance.new("Frame")
	velo.Name = "Recarga"
	velo.Size = UDim2.fromScale(1, 1)
	velo.BackgroundTransparency = 1
	velo.ZIndex = 3
	velo.Parent = boton
	local function mitad(derecha: boolean): UIGradient
		local recorte = Instance.new("Frame")
		recorte.BackgroundTransparency = 1
		recorte.ClipsDescendants = true
		recorte.Size = UDim2.fromScale(0.5, 1)
		recorte.Position = UDim2.fromScale(if derecha then 0.5 else 0, 0)
		recorte.ZIndex = 3
		recorte.Parent = velo
		local circulo = Instance.new("Frame")
		circulo.Size = UDim2.fromScale(2, 1)
		circulo.Position = UDim2.fromScale(if derecha then -1 else 0, 0)
		circulo.BackgroundColor3 = Color3.new(0, 0, 0)
		circulo.BorderSizePixel = 0
		circulo.ZIndex = 3
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = circulo
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.499, 0.3),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = circulo
		circulo.Parent = recorte
		return g
	end
	return velo, mitad(true), mitad(false)
end

-- p = fracción que falta (1 = recién usada). Barre en sentido horario desde arriba.
local function fijarRecarga(r: Ranura, p: number)
	if p <= 0 then
		r.Velo.Visible = false
		return
	end
	r.Velo.Visible = true
	local grados = math.clamp(p, 0, 1) * 360
	r.Derecha.Rotation = math.min(grados, 180)
	r.Izquierda.Rotation = 180 + math.clamp(grados - 180, 0, 180)
end

local usarRanura: (Ranura) -> ()

local function crearRanura(
	orden: number,
	tipo: TipoRanura,
	indice: number,
	tecla: string,
	colorBorde: Color3,
	itemId: string?
): Ranura
	local boton = Instance.new("TextButton")
	boton.Name = `Ranura{orden}`
	boton.LayoutOrder = orden
	boton.Size = UDim2.fromOffset(tamRanura, tamRanura)
	boton.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
	boton.AutoButtonColor = true
	boton.Text = ""
	local esquinas = Instance.new("UICorner")
	esquinas.CornerRadius = UDim.new(0, 10)
	esquinas.Parent = boton
	local borde = Instance.new("UIStroke")
	borde.Color = colorBorde
	borde.Thickness = 1.5
	borde.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	borde.Parent = boton
	local nombre = etiqueta(boton, UDim2.fromScale(0.92, 0.42), UDim2.fromScale(0.04, 0.27))
	nombre.Font = Enum.Font.GothamMedium
	nombre.TextWrapped = true
	local etiquetaTecla = etiqueta(boton, UDim2.fromScale(0.45, 0.26), UDim2.fromScale(0.05, 0.02), tecla)
	etiquetaTecla.TextXAlignment = Enum.TextXAlignment.Left
	etiquetaTecla.TextColor3 = Color3.fromRGB(230, 220, 130)
	etiquetaTecla.ZIndex = 5
	local costo = etiqueta(boton, UDim2.fromScale(0.9, 0.24), UDim2.fromScale(0.05, 0.74))
	costo.TextXAlignment = Enum.TextXAlignment.Right
	costo.TextColor3 = Color3.fromRGB(120, 170, 255)
	costo.ZIndex = 5
	local velo, derecha, izquierda = veloCircular(boton)
	local cuenta = etiqueta(boton, UDim2.fromScale(0.7, 0.5), UDim2.fromScale(0.15, 0.25))
	cuenta.ZIndex = 6
	cuenta.TextColor3 = Color3.fromRGB(255, 255, 255)
	boton.Parent = barraAccion
	local r: Ranura = {
		Tipo = tipo,
		Indice = indice,
		Barra = 0,
		Pos = 0,
		ItemId = itemId,
		Boton = boton,
		Nombre = nombre,
		Tecla = etiquetaTecla,
		Costo = costo,
		Cuenta = cuenta,
		Derecha = derecha,
		Izquierda = izquierda,
		Velo = velo,
	}
	boton.Activated:Connect(function()
		usarRanura(r)
	end)
	velo.Visible = false
	return r
end

local function usarPocion(itemId: string)
	local inv = EstadoCliente.Get("Inventario")
	if typeof(inv) ~= "table" then
		return
	end
	local mejor: number? = nil
	for clave, item in inv.Slots do
		local n = tonumber(clave)
		if n and item.ItemId == itemId and (not mejor or n < mejor) then
			mejor = n
		end
	end
	if not mejor then
		Avisos.Mostrar("No tenés esa poción.", "Error")
		return
	end
	if ahora() < pocionLista then
		return
	end
	NetworkBridge.Client.Fire("UsarItem", mejor)
	pocionLista = ahora() + GameConfig.Consumibles.CooldownPociones
end

usarRanura = function(r: Ranura)
	if r.Tipo == "Habilidad" then
		usarHabilidad(r.Indice)
	elseif r.Tipo == "Parry" then
		parry()
	elseif r.Tipo == "Pocion" and r.ItemId then
		usarPocion(r.ItemId)
	elseif r.Tipo == "Montura" then
		local dragon = jugador:GetAttribute("Pase_MonturaDragon") == true
		NetworkBridge.Client.Invoke("MonturaAlternar", if dragon then "Dragon" else "Caballo")
	end
end

-- Teclas de las 4 barras (la I también con los botones del gamepad).
for b = 1, 4 do
	for p = 1, 4 do
		local botonGamepad = if b == 1 then BOTONES[p] else nil
		local function alPulsar(_: string, estado: Enum.UserInputState): Enum.ContextActionResult
			if estado ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() ~= nil then
				return Enum.ContextActionResult.Pass
			end
			for _, r in ranuras do
				if r.Tipo == "Habilidad" and r.Barra == b and r.Pos == p then
					usarRanura(r)
					return Enum.ContextActionResult.Sink
				end
			end
			return Enum.ContextActionResult.Pass
		end
		if botonGamepad then
			ContextActionService:BindAction(
				`HabilidadRaidBlox{b}_{p}`,
				alPulsar,
				false,
				TECLAS_BARRAS[b][p],
				botonGamepad
			)
		else
			ContextActionService:BindAction(`HabilidadRaidBlox{b}_{p}`, alPulsar, false, TECLAS_BARRAS[b][p])
		end
	end
end

ContextActionService:BindAction("PocionVidaRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin then
		usarPocion("PocionVida")
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Five, Enum.KeyCode.DPadLeft)
ContextActionService:BindAction("PocionManaRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin then
		usarPocion("PocionMana")
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Six, Enum.KeyCode.DPadRight)

local function cantidadItem(itemId: string): number
	local inv = EstadoCliente.Get("Inventario")
	local total = 0
	if typeof(inv) == "table" then
		for _, item in inv.Slots do
			if item.ItemId == itemId then
				total += item.Cantidad
			end
		end
	end
	return total
end

local function refrescarRanuras()
	local def = claseActual()
	for _, r in ranuras do
		if r.Tipo == "Habilidad" then
			local hab = def and def.Habilidades[r.Indice]
			r.Nombre.Text = if hab then hab.Nombre else "-"
			r.Costo.Text = if hab and hab.CostoMana > 0 then tostring(hab.CostoMana) else ""
		elseif r.Tipo == "Pocion" and r.ItemId then
			local n = cantidadItem(r.ItemId)
			r.Costo.Text = `x{n}`
			r.Costo.TextColor3 = Color3.fromRGB(220, 220, 220)
			r.Boton.BackgroundTransparency = if n > 0 then 0 else 0.5
		end
	end
end
EstadoCliente.Cambio:Connect(function(campo: string)
	if campo == "Inventario" or campo == "*" then
		refrescarRanuras()
	end
end)

-- Botón para elegir las habilidades de las barras (solo clases con barras).
local botonBarras = Instance.new("TextButton")
botonBarras.Name = "ElegirHabilidades"
botonBarras.Size = UDim2.fromOffset(150, 24)
botonBarras.BackgroundColor3 = Color3.fromRGB(40, 40, 58)
botonBarras.TextColor3 = Color3.fromRGB(255, 215, 90)
botonBarras.Font = Enum.Font.GothamBold
botonBarras.TextSize = 14
botonBarras.Text = "⚙ Habilidades (K)"
botonBarras.Visible = false
local esquinasBarras = Instance.new("UICorner")
esquinasBarras.CornerRadius = UDim.new(0, 8)
esquinasBarras.Parent = botonBarras
botonBarras.Parent = gui
Hud.Registrar(botonBarras)

local ESPACIO = 5

-- Ubicación según dispositivo y mano.
local function ubicarHud()
	local tactil = Hud.EsTactil()
	local zurdo = Hud.Zurdo
	-- Marco del jugador: arriba, del lado contrario al minimapa.
	marcoJugador.AnchorPoint = Vector2.new(if zurdo then 1 else 0, 0)
	marcoJugador.Position = if zurdo then UDim2.new(1, -8, 0, 8) else UDim2.fromOffset(8, 8)

	local viejo = barraAccion:FindFirstChildWhichIsA("UILayout")
	if viejo then
		viejo:Destroy()
	end
	local separadores = 0
	for _, hijo in barraAccion:GetChildren() do
		if hijo.Name == "Separador" and hijo:IsA("GuiObject") then
			hijo.Visible = not tactil
			separadores += 1
		end
	end
	local n = #ranuras
	if tactil then
		-- Bloque de 4 columnas del lado de la mano hábil.
		local grilla = Instance.new("UIGridLayout")
		grilla.CellSize = UDim2.fromOffset(tamRanura, tamRanura)
		grilla.CellPadding = UDim2.fromOffset(ESPACIO, ESPACIO)
		grilla.SortOrder = Enum.SortOrder.LayoutOrder
		grilla.FillDirectionMaxCells = 4
		grilla.Parent = barraAccion
		local filas = math.ceil(n / 4)
		barraAccion.Size = UDim2.fromOffset(4 * tamRanura + 3 * ESPACIO, filas * tamRanura + (filas - 1) * ESPACIO)
		barraAccion.AnchorPoint = Vector2.new(if zurdo then 0 else 1, 1)
		barraAccion.Position = if zurdo then UDim2.new(0, 12, 1, -150) else UDim2.new(1, -12, 1, -150)
	else
		-- Una fila centrada, con un espacio entre barra y barra.
		local fila = Instance.new("UIListLayout")
		fila.FillDirection = Enum.FillDirection.Horizontal
		fila.Padding = UDim.new(0, ESPACIO)
		fila.SortOrder = Enum.SortOrder.LayoutOrder
		fila.VerticalAlignment = Enum.VerticalAlignment.Bottom
		fila.Parent = barraAccion
		local ancho = n * tamRanura + (n + separadores - 1) * ESPACIO + separadores * 6
		barraAccion.Size = UDim2.fromOffset(ancho, tamRanura)
		barraAccion.AnchorPoint = Vector2.new(0.5, 1)
		barraAccion.Position = UDim2.new(0.5, 0, 1, -12)
	end
	for _, r in ranuras do
		r.Tecla.Visible = not tactil
	end
	botonBarras.Visible = conBarras
	botonBarras.AnchorPoint = barraAccion.AnchorPoint
	botonBarras.Position = barraAccion.Position - UDim2.fromOffset(0, barraAccion.Size.Y.Offset + 8)
end

-- Arma las ranuras según la clase y las habilidades equipadas.
local function armarBarra()
	for _, hijo in barraAccion:GetChildren() do
		if hijo:IsA("GuiObject") then
			hijo:Destroy()
		end
	end
	table.clear(ranuras)
	local def = claseActual()
	conBarras = def ~= nil and def.Barras ~= nil
	tamRanura = if conBarras then 46 else 58
	local orden = 0
	local function separador()
		orden += 1
		local s = Instance.new("Frame")
		s.Name = "Separador"
		s.Size = UDim2.fromOffset(6, tamRanura)
		s.BackgroundTransparency = 1
		s.LayoutOrder = orden
		s.Parent = barraAccion
	end
	if def and conBarras then
		local equipadas = EstadoCliente.Get("Barras")
		local lista: { string } = if typeof(equipadas) == "table" then equipadas else ChatarreroConfig.BarrasPorDefecto
		for b = 1, def.Barras or 4 do
			local pos = 0
			-- En el orden del catálogo de la clase.
			for indice, hab in def.Habilidades do
				if hab.Categoria == b and table.find(lista, hab.Id) and pos < 4 then
					pos += 1
					orden += 1
					local calidad = if hab.Calidad then ChatarreroConfig.Calidades[hab.Calidad] else nil
					local r = crearRanura(
						orden,
						"Habilidad",
						indice,
						NOMBRES_TECLAS[b][pos],
						if calidad then calidad.Color else COLORES_BARRA[b]
					)
					r.Barra, r.Pos = b, pos
					table.insert(ranuras, r)
				end
			end
			-- Lugares vacíos, para que cada barra siempre tenga sus 4 botones.
			while pos < 4 do
				pos += 1
				orden += 1
				local r = crearRanura(orden, "Habilidad", 0, NOMBRES_TECLAS[b][pos], COLORES_BARRA[b])
				r.Barra, r.Pos = b, pos
				r.Boton.BackgroundTransparency = 0.6
				table.insert(ranuras, r)
			end
			separador()
		end
	else
		for i = 1, 4 do
			orden += 1
			local r = crearRanura(orden, "Habilidad", i, tostring(i), COLORES_BARRA[1])
			r.Barra, r.Pos = 1, i
			table.insert(ranuras, r)
		end
	end
	local utilidad = Color3.fromRGB(150, 130, 80)
	local verde = Color3.fromRGB(80, 140, 90)
	local function extra(tipo: TipoRanura, tecla: string, nombre: string, color: Color3, itemId: string?): Ranura
		orden += 1
		local r = crearRanura(orden, tipo, 0, tecla, color, itemId)
		r.Nombre.Text = nombre
		table.insert(ranuras, r)
		return r
	end
	extra("Parry", "F", "Parry", utilidad)
	extra("Pocion", "5", "Poción vida", verde, "PocionVida")
	extra("Pocion", "6", "Poción maná", verde, "PocionMana")
	ranuraMontura = extra("Montura", "G", "Montura", utilidad)
	refrescarRanuras()
	ubicarHud()
end
Hud.Cambio:Connect(ubicarHud)

------------------------------------------------------------------------
-- Ventana "Habilidades": elegir 4 por barra (clases con barras)
------------------------------------------------------------------------

local guiHabilidades = UIKit.Gui("HabilidadesUI", 64)
local ventanaHab, contenidoHab = UIKit.Ventana(guiHabilidades, "Habilidades", UDim2.fromScale(0.6, 0.84))
local listaHab = UIKit.Lista(contenidoHab, UDim2.fromScale(1, 1))

local function formatoRecarga(s: number): string
	return if s >= 60 then `{s // 60} min` else `{s} s`
end

local function dibujarHabilidades()
	UIKit.Limpiar(listaHab)
	local def = claseActual()
	if not def or not def.Barras then
		return
	end
	local equipadas = EstadoCliente.Get("Barras")
	local lista: { string } = if typeof(equipadas) == "table" then equipadas else ChatarreroConfig.BarrasPorDefecto
	local recurso = def.Recurso or "Maná"
	local orden = 0
	for b = 1, def.Barras do
		local puestas = 0
		for _, hab in def.Habilidades do
			if hab.Categoria == b and table.find(lista, hab.Id) then
				puestas += 1
			end
		end
		orden += 1
		local cat = ChatarreroConfig.Categorias[b]
		local titulo = UIKit.Texto(
			listaHab,
			`Barra {if cat then cat.Nombre else tostring(b)}  ·  recarga {if cat then cat.Recarga else "?"}  ·  {puestas}/4  ·  teclas {table.concat(
				NOMBRES_TECLAS[b],
				" "
			)}`,
			UDim2.new(1, 0, 0, 24)
		)
		titulo.TextXAlignment = Enum.TextXAlignment.Left
		titulo.TextColor3 = COLORES_BARRA[b]
		titulo.LayoutOrder = orden
		for _, hab in def.Habilidades do
			if hab.Categoria ~= b then
				continue
			end
			orden += 1
			local puesta = table.find(lista, hab.Id) ~= nil
			local fila = Instance.new("Frame")
			fila.Size = UDim2.new(1, 0, 0, 58)
			fila.BackgroundColor3 = UIKit.Colores.Fondo
			fila.BackgroundTransparency = if puesta then 0 else 0.35
			fila.LayoutOrder = orden
			UIKit.Esquinas(fila, 8)
			fila.Parent = listaHab
			local calidad = if hab.Calidad then ChatarreroConfig.Calidades[hab.Calidad] else nil
			local nombre = UIKit.Texto(
				fila,
				`{hab.Numero or ""}. {hab.Nombre}{if calidad then `  ({calidad.Nombre})` else ""}`,
				UDim2.new(0.5, 0, 0, 20),
				UDim2.fromOffset(10, 4)
			)
			nombre.TextXAlignment = Enum.TextXAlignment.Left
			nombre.TextColor3 = if calidad then calidad.Color else UIKit.Colores.Texto
			local datos = UIKit.Texto(
				fila,
				`{formatoRecarga(hab.Cooldown)}  ·  {hab.CostoMana} {recurso}`,
				UDim2.new(0.26, 0, 0, 18),
				UDim2.new(0.5, 10, 0, 5)
			)
			datos.TextXAlignment = Enum.TextXAlignment.Left
			datos.Font = Enum.Font.GothamMedium
			datos.TextColor3 = UIKit.Colores.TextoSuave
			local desc = UIKit.Texto(fila, hab.Descripcion, UDim2.new(0.78, -10, 0, 30), UDim2.fromOffset(10, 25))
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextYAlignment = Enum.TextYAlignment.Top
			desc.TextWrapped = true
			desc.Font = Enum.Font.Gotham
			desc.TextColor3 = UIKit.Colores.TextoSuave
			local boton = UIKit.Boton(
				fila,
				if puesta then "✔ Quitar" else "Equipar",
				UDim2.new(0.2, -10, 0, 34),
				UDim2.new(0.8, 0, 0, 12),
				if puesta then UIKit.Colores.Boton else UIKit.Colores.BotonPrimario
			)
			local id = hab.Id
			boton.Activated:Connect(function()
				NetworkBridge.Client.Invoke("BarraAlternar", id)
			end)
		end
	end
end

local function alternarVentanaHabilidades()
	if not conBarras then
		return
	end
	ventanaHab.Visible = not ventanaHab.Visible
	if ventanaHab.Visible then
		dibujarHabilidades()
	end
end
botonBarras.Activated:Connect(alternarVentanaHabilidades)
ContextActionService:BindAction("HabilidadesRaidBlox", function(_, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin and UserInputService:GetFocusedTextBox() == nil and conBarras then
		alternarVentanaHabilidades()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.K)

EstadoCliente.Cambio:Connect(function(campo: string)
	if (campo == "Cosmeticos" or campo == "*") and conBarras then
		armarBarra()
		if ventanaHab.Visible then
			dibujarHabilidades()
		end
	end
end)

------------------------------------------------------------------------
-- Olfato de Chatarrero: resalta metales y restos cercanos por un rato
------------------------------------------------------------------------

NetworkBridge.Client.OnEvent("ChatarreroOlfato", function(segundos: any, radio: any)
	local personaje = jugador.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if typeof(segundos) ~= "number" or typeof(radio) ~= "number" or not raiz or not raiz:IsA("BasePart") then
		return
	end
	local candidatos: { { Objeto: Instance, D: number, Resto: boolean } } = {}
	local function sumar(objeto: Instance, resto: boolean)
		local pos: Vector3? = if objeto:IsA("BasePart")
			then objeto.Position
			elseif objeto:IsA("Model") then objeto:GetPivot().Position
			else nil
		if pos then
			local d = (pos - raiz.Position).Magnitude
			if d <= radio then
				table.insert(candidatos, { Objeto = objeto, D = d, Resto = resto })
			end
		end
	end
	for _, nodo in CollectionService:GetTagged("NodoRecoleccion") do
		local recurso = nodo:GetAttribute("Nodo")
		-- Solo vetas de metal (los nodos de mineral).
		if typeof(recurso) == "string" and string.find(string.lower(recurso), "mineral") then
			sumar(nodo, false)
		end
	end
	for _, resto in CollectionService:GetTagged("RestosSpoil") do
		sumar(resto, true)
	end
	table.sort(candidatos, function(a, b)
		return a.D < b.D
	end)
	local encontrados = math.min(#candidatos, 20) -- Roblox dibuja pocos Highlights a la vez
	for i = 1, encontrados do
		local c = candidatos[i]
		local brillo = Instance.new("Highlight")
		brillo.Adornee = c.Objeto
		brillo.FillColor = if c.Resto then Color3.fromRGB(190, 230, 60) else Color3.fromRGB(255, 200, 60)
		brillo.OutlineColor = Color3.fromRGB(255, 240, 150)
		brillo.FillTransparency = 0.5
		brillo.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		brillo.Parent = playerGui
		task.delay(segundos, function()
			brillo:Destroy()
		end)
	end
	Avisos.Mostrar(
		if encontrados > 0 then `Olfato: {encontrados} hallazgos cerca.` else "Olfato: no hay metales ni restos cerca.",
		"Info"
	)
end)

-- Selector de clase.
local selector = Instance.new("Frame")
selector.AnchorPoint = Vector2.new(0.5, 0.5)
selector.Position = UDim2.fromScale(0.5, 0.5)
selector.Size = UDim2.fromScale(0.6, 0.62)
selector.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
selector.BackgroundTransparency = 0.1
selector.Visible = false
selector.ZIndex = 10
selector.Parent = gui
local esquinasSelector = Instance.new("UICorner")
esquinasSelector.CornerRadius = UDim.new(0.03, 0)
esquinasSelector.Parent = selector
local tituloSelector = etiqueta(selector, UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.02), "Elegí tu clase")
tituloSelector.ZIndex = 11
local grilla = Instance.new("Frame")
grilla.Position = UDim2.fromScale(0.03, 0.12)
grilla.Size = UDim2.fromScale(0.94, 0.85)
grilla.BackgroundTransparency = 1
grilla.ZIndex = 11
grilla.Parent = selector
local layoutGrilla = Instance.new("UIGridLayout")
layoutGrilla.CellSize = UDim2.fromScale(0.188, 0.47) -- 5 columnas: 9 clases
layoutGrilla.CellPadding = UDim2.fromScale(0.015, 0.03)
layoutGrilla.SortOrder = Enum.SortOrder.LayoutOrder
layoutGrilla.Parent = grilla

for orden, id in ClassConfig.Orden do
	local def = ClassConfig.Clases[id]
	local boton = Instance.new("TextButton")
	boton.LayoutOrder = orden
	boton.BackgroundColor3 = Color3.fromRGB(34, 34, 48)
	boton.Text = ""
	boton.ZIndex = 12
	local esquinas = Instance.new("UICorner")
	esquinas.CornerRadius = UDim.new(0.06, 0)
	esquinas.Parent = boton
	local nombre = etiqueta(boton, UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.05), def.Nombre)
	nombre.ZIndex = 13
	local rol = etiqueta(boton, UDim2.fromScale(0.9, 0.12), UDim2.fromScale(0.05, 0.27), def.Rol)
	rol.ZIndex = 13
	rol.TextColor3 = Color3.fromRGB(230, 200, 110)
	local descripcion = etiqueta(boton, UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.05, 0.43), def.Descripcion)
	descripcion.ZIndex = 13
	descripcion.Font = Enum.Font.Gotham
	descripcion.TextWrapped = true
	boton.Activated:Connect(function()
		local respuesta = NetworkBridge.Client.Invoke("ElegirClase", id)
		if respuesta.Success then
			selector.Visible = false
			Avisos.Mostrar(`Ahora sos {def.Nombre}.`, "Oro")
		else
			Avisos.Mostrar(`No se pudo elegir la clase ({respuesta.ErrorCode}).`, "Error")
		end
	end)
	boton.Parent = grilla
end

-- El panel Personaje abre el selector (en pruebas se puede cambiar libremente;
-- fuera de pruebas el servidor solo deja elegir la primera vez).
EventosCliente.AbrirSelectorClase:Connect(function()
	selector.Visible = not selector.Visible
end)

local claseMostrada: any = false

local function revisarClase()
	local clase = jugador:GetAttribute("Clase")
	if clase == "SinClase" then
		selector.Visible = true
	elseif typeof(clase) == "string" then
		selector.Visible = false
	end
	-- Otra clase: otras habilidades y otras recargas (el servidor reenvía las largas).
	if clase ~= claseMostrada then
		claseMostrada = clase
		table.clear(cooldowns)
		ventanaHab.Visible = false
		armarBarra()
	end
	refrescarRanuras()
end
jugador:GetAttributeChangedSignal("Clase"):Connect(revisarClase)
revisarClase()

------------------------------------------------------------------------
-- Estado del servidor
------------------------------------------------------------------------

NetworkBridge.Client.OnEvent("HabilidadEstado", function(estado: any)
	if typeof(estado) ~= "table" then
		return
	end
	if estado.Cancelado then
		casteo = nil
		return
	end
	local indice = estado.Indice
	if typeof(indice) ~= "number" then
		return
	end
	if typeof(estado.CasteoHasta) == "number" then
		casteo = {
			Hasta = estado.CasteoHasta,
			Nombre = if typeof(estado.Nombre) == "string" then estado.Nombre else "",
			Inicio = ahora(),
		}
		return
	end
	casteo = nil
	if typeof(estado.ListoEn) == "number" then
		cooldowns[indice] = estado.ListoEn
	end
	if typeof(estado.GcdHasta) == "number" then
		gcdHasta = estado.GcdHasta
	end
end)

------------------------------------------------------------------------
-- Actualización por frame
------------------------------------------------------------------------

local function duracionCooldown(r: Ranura): number
	if r.Tipo == "Parry" then
		return ClassConfig.CooldownParry
	elseif r.Tipo == "Pocion" then
		return GameConfig.Consumibles.CooldownPociones
	end
	local def = claseActual()
	local hab = def and def.Habilidades[r.Indice]
	return if hab then hab.Cooldown else 1
end

local function listoEn(r: Ranura): number
	if r.Tipo == "Habilidad" then
		return math.max(cooldowns[r.Indice] or 0, gcdHasta)
	elseif r.Tipo == "Parry" then
		return cooldowns[0] or 0
	elseif r.Tipo == "Pocion" then
		return pocionLista
	end
	return 0
end

local function formatoSegundos(s: number): string
	return if s >= 60 then `{math.ceil(s / 60)}m` elseif s >= 1 then tostring(math.ceil(s)) else ""
end

RunService.RenderStepped:Connect(function()
	local t = ahora()

	-- Vida, maná y experiencia propios.
	local personaje = jugador.Character
	local h = personaje and personaje:FindFirstChildOfClass("Humanoid")
	if h and h.MaxHealth > 0 then
		barraVida.Size = UDim2.fromScale(math.clamp(h.Health / h.MaxHealth, 0, 1), 1)
		textoVida.Text = `{math.floor(h.Health)} / {math.floor(h.MaxHealth)}`
	end
	local mana = jugador:GetAttribute("Mana")
	local manaMax = jugador:GetAttribute("ManaMax")
	if typeof(mana) == "number" and typeof(manaMax) == "number" and manaMax > 0 then
		barraMana.Size = UDim2.fromScale(math.clamp(mana / manaMax, 0, 1), 1)
		textoMana.Text = `{mana} / {manaMax}`
	end
	local nivel = EstadoCliente.Get("Nivel")
	local xp = EstadoCliente.Get("Experiencia")
	if typeof(nivel) == "number" and typeof(xp) == "number" then
		local cfg = GameConfig.Progresion
		if nivel >= cfg.NivelMaximo then
			barraXp.Size = UDim2.fromScale(1, 1)
			textoXp.Text = "Nivel máximo"
		else
			local necesaria = math.floor(cfg.XpBase * nivel ^ cfg.XpExponente)
			barraXp.Size = UDim2.fromScale(math.clamp(xp / math.max(1, necesaria), 0, 1), 1)
			textoXp.Text = `{xp} / {necesaria} XP`
		end
		textoNivel.Text = tostring(nivel)
	end
	local def = claseActual()
	barraMana.BackgroundColor3 = if def and def.ColorRecurso then def.ColorRecurso else COLOR_MANA
	tituloJugador.Text = `{jugador.DisplayName} · {if def then def.Nombre else "Sin clase"}`
	local bando = jugador:GetAttribute("Bando")
	local colorBando = if typeof(bando) == "string" then (GameConfig.Bandos.Colores :: any)[bando] else nil
	bordeRetrato.Color = if colorBando then colorBando else Color3.new(1, 1, 1)

	-- Objetivo.
	if objetivo and not combatienteVivo(objetivo) then
		seleccionar(nil)
	end
	local o = objetivo
	marcoObjetivo.Visible = o ~= nil
	if o then
		local ho = o:FindFirstChildOfClass("Humanoid")
		if ho and ho.MaxHealth > 0 then
			barraObjetivo.Size = UDim2.fromScale(math.clamp(ho.Health / ho.MaxHealth, 0, 1), 1)
			textoObjetivo.Text = `{math.floor(ho.Health)} / {math.floor(ho.MaxHealth)}`
		end
		barraObjetivo.BackgroundColor3 = if relacionObjetivo == "Enemigo"
			then COLOR_ENEMIGO
			elseif relacionObjetivo == "Neutral" then COLOR_NEUTRAL
			else COLOR_VIDA
		tituloObjetivo.Text = `{o:GetAttribute("NombreCombate") or o.Name}  ·  Nv. {o:GetAttribute("Nivel") or "?"}`
		local efectos = o:GetAttribute("Efectos")
		local texto = if typeof(efectos) == "string" then efectos else ""
		if texto ~= efectosMostrados then
			dibujarEfectos(texto)
		end
		for _, chip in chips do
			local resta = chip.Hasta - t
			chip.Texto.Text = if resta > 0 then `{chip.Nombre} {formatoSegundos(resta)}` else chip.Nombre
			chip.Marco.Visible = resta > 0
		end
	elseif efectosMostrados ~= "" then
		dibujarEfectos("")
	end

	-- Casteo.
	local c = casteo
	if c and t < c.Hasta then
		marcoCasteo.Visible = true
		local total = math.max(0.01, c.Hasta - c.Inicio)
		barraCasteo.Size = UDim2.fromScale(math.clamp((t - c.Inicio) / total, 0, 1), 1)
		textoCasteo.Text = c.Nombre
	else
		marcoCasteo.Visible = false
	end

	-- Recargas (barrido circular + segundos).
	for _, r in ranuras do
		local restante = listoEn(r) - t
		if restante > 0 then
			local total = math.max(duracionCooldown(r), restante)
			fijarRecarga(r, restante / total)
			r.Cuenta.Text = formatoSegundos(restante)
		else
			fijarRecarga(r, 0)
			r.Cuenta.Text = ""
		end
	end
	-- La montura se marca mientras estás montado.
	local rm = ranuraMontura
	if rm then
		rm.Boton.BackgroundColor3 = if typeof(jugador:GetAttribute("Montura")) == "string"
			then Color3.fromRGB(60, 110, 60)
			else Color3.fromRGB(28, 28, 40)
	end
end)

-- Con la mira, el marco de objetivo muestra al combatiente que tengas en la mira
-- (se mantiene el último hasta que apuntes a otro).
task.spawn(function()
	while true do
		task.wait(0.15)
		if Apuntado.Activo and not Apuntado.Libre then
			local modelo = Apuntado.ModeloEnMira()
			if modelo and modelo ~= jugador.Character and modelo ~= objetivo and combatienteVivo(modelo) then
				seleccionar(modelo)
			end
		end
	end
end)
