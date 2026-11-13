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
-- barra de acción de 8 ranuras con recarga circular: 4 habilidades, parry,
-- poción de vida (5), poción de maná (6) y montura (G).

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

local jugador = Players.LocalPlayer
local playerGui = jugador:WaitForChild("PlayerGui")

local ALCANCE_TAB = 60
local TECLAS: { Enum.KeyCode } = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
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

for i = 1, 4 do
	ContextActionService:BindAction(`HabilidadRaidBlox{i}`, function(_, estado: Enum.UserInputState)
		if estado == Enum.UserInputState.Begin then
			usarHabilidad(i)
		end
		return Enum.ContextActionResult.Sink
	end, false, TECLAS[i], BOTONES[i])
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
-- Barra de acción: 8 ranuras con recarga circular
------------------------------------------------------------------------

local TAM_RANURA = 58
local barraAccion = Instance.new("Frame")
barraAccion.Name = "BarraAccion"
barraAccion.BackgroundTransparency = 1
barraAccion.Parent = gui
Hud.Registrar(barraAccion)
local grillaAccion = Instance.new("UIGridLayout")
grillaAccion.CellSize = UDim2.fromOffset(TAM_RANURA, TAM_RANURA)
grillaAccion.CellPadding = UDim2.fromOffset(6, 6)
grillaAccion.SortOrder = Enum.SortOrder.LayoutOrder
grillaAccion.HorizontalAlignment = Enum.HorizontalAlignment.Center
grillaAccion.Parent = barraAccion

type TipoRanura = "Habilidad" | "Parry" | "Pocion" | "Montura"
type Ranura = {
	Tipo: TipoRanura,
	Indice: number,
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

local function crearRanura(orden: number, tipo: TipoRanura, indice: number, tecla: string, itemId: string?): Ranura
	local boton = Instance.new("TextButton")
	boton.Name = `Ranura{orden}`
	boton.LayoutOrder = orden
	boton.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
	boton.AutoButtonColor = true
	boton.Text = ""
	local esquinas = Instance.new("UICorner")
	esquinas.CornerRadius = UDim.new(0, 10)
	esquinas.Parent = boton
	local borde = Instance.new("UIStroke")
	borde.Color = if tipo == "Habilidad"
		then Color3.fromRGB(110, 110, 150)
		elseif tipo == "Pocion" then Color3.fromRGB(80, 140, 90)
		else Color3.fromRGB(150, 130, 80)
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

for i = 1, 4 do
	table.insert(ranuras, crearRanura(i, "Habilidad", i, tostring(i)))
end
table.insert(ranuras, crearRanura(5, "Parry", 0, "F"))
table.insert(ranuras, crearRanura(6, "Pocion", 0, "5", "PocionVida"))
table.insert(ranuras, crearRanura(7, "Pocion", 0, "6", "PocionMana"))
table.insert(ranuras, crearRanura(8, "Montura", 0, "G"))
ranuras[5].Nombre.Text = "Parry"
ranuras[6].Nombre.Text = "Poción vida"
ranuras[7].Nombre.Text = "Poción maná"
ranuras[8].Nombre.Text = "Montura"

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

-- Ubicación según dispositivo y mano.
local function ubicarHud()
	local tactil = Hud.EsTactil()
	local zurdo = Hud.Zurdo
	-- Marco del jugador: arriba, del lado contrario al minimapa.
	marcoJugador.AnchorPoint = Vector2.new(if zurdo then 1 else 0, 0)
	marcoJugador.Position = if zurdo then UDim2.new(1, -8, 0, 8) else UDim2.fromOffset(8, 8)
	-- Barra de acción: en PC y consola una fila centrada; en táctil un bloque
	-- de 4×2 del lado de la mano hábil (derecha, o izquierda si es zurdo).
	if tactil then
		local ancho = 4 * TAM_RANURA + 3 * 6
		barraAccion.Size = UDim2.fromOffset(ancho, 2 * TAM_RANURA + 6)
		barraAccion.AnchorPoint = Vector2.new(if zurdo then 0 else 1, 1)
		barraAccion.Position = if zurdo then UDim2.new(0, 12, 1, -150) else UDim2.new(1, -12, 1, -150)
	else
		barraAccion.Size = UDim2.fromOffset(8 * TAM_RANURA + 7 * 6, TAM_RANURA)
		barraAccion.AnchorPoint = Vector2.new(0.5, 1)
		barraAccion.Position = UDim2.new(0.5, 0, 1, -12)
	end
	for _, r in ranuras do
		r.Tecla.Visible = not tactil
	end
end
Hud.Cambio:Connect(ubicarHud)
ubicarHud()

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
layoutGrilla.CellSize = UDim2.fromScale(0.235, 0.47)
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

local function revisarClase()
	local clase = jugador:GetAttribute("Clase")
	if clase == "SinClase" then
		selector.Visible = true
	elseif typeof(clase) == "string" then
		selector.Visible = false
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
	ranuras[8].Boton.BackgroundColor3 = if typeof(jugador:GetAttribute("Montura")) == "string"
		then Color3.fromRGB(60, 110, 60)
		else Color3.fromRGB(28, 28, 40)
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
