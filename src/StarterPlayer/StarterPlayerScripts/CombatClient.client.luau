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
-- Esta interfaz es la mínima para probar el combate; la definitiva llega en la Fase 7.

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
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)

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
	if not resultado then
		return nil
	end
	local modelo: Instance? = resultado.Instance
	while modelo and modelo ~= Workspace do
		if modelo:IsA("Model") and modelo:GetAttribute("Bando") ~= nil then
			return modelo
		end
		modelo = modelo.Parent
	end
	return nil
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
	NetworkBridge.Client.Fire("UsarHabilidad", indice, objetivo)
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

local function barra(padre: Instance, pos: UDim2, tam: UDim2, color: Color3): (Frame, TextLabel)
	local fondo = Instance.new("Frame")
	fondo.Position = pos
	fondo.Size = tam
	fondo.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	fondo.BorderSizePixel = 0
	fondo.Parent = padre
	local relleno = Instance.new("Frame")
	relleno.Name = "Relleno"
	relleno.Size = UDim2.fromScale(1, 1)
	relleno.BackgroundColor3 = color
	relleno.BorderSizePixel = 0
	relleno.Parent = fondo
	local texto = etiqueta(fondo, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	texto.ZIndex = 2
	return relleno, texto
end

-- Marco del jugador (vida y maná).
local marcoJugador = Instance.new("Frame")
marcoJugador.Position = UDim2.fromScale(0.01, 0.5) -- debajo del chat de Roblox
marcoJugador.Size = UDim2.fromScale(0.2, 0.08)
marcoJugador.BackgroundTransparency = 1
marcoJugador.Parent = gui
local tituloJugador = etiqueta(marcoJugador, UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0))
tituloJugador.TextXAlignment = Enum.TextXAlignment.Left
local barraVida, textoVida =
	barra(marcoJugador, UDim2.fromScale(0, 0.38), UDim2.fromScale(1, 0.3), Color3.fromRGB(60, 190, 80))
local barraMana, textoMana =
	barra(marcoJugador, UDim2.fromScale(0, 0.72), UDim2.fromScale(1, 0.26), Color3.fromRGB(60, 120, 230))

-- Marco del objetivo.
local marcoObjetivo = Instance.new("Frame")
marcoObjetivo.Position = UDim2.fromScale(0.01, 0.59)
marcoObjetivo.Size = UDim2.fromScale(0.2, 0.06)
marcoObjetivo.BackgroundTransparency = 1
marcoObjetivo.Visible = false
marcoObjetivo.Parent = gui
local tituloObjetivo = etiqueta(marcoObjetivo, UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0))
tituloObjetivo.TextXAlignment = Enum.TextXAlignment.Left
local barraObjetivo, textoObjetivo =
	barra(marcoObjetivo, UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.45), Color3.fromRGB(210, 60, 50))

-- Barra de casteo.
local marcoCasteo = Instance.new("Frame")
marcoCasteo.AnchorPoint = Vector2.new(0.5, 1)
marcoCasteo.Position = UDim2.fromScale(0.5, 0.8)
marcoCasteo.Size = UDim2.fromScale(0.25, 0.025)
marcoCasteo.BackgroundTransparency = 1
marcoCasteo.Visible = false
marcoCasteo.Parent = gui
local barraCasteo, textoCasteo =
	barra(marcoCasteo, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(230, 190, 60))

-- Barra de acción: 4 habilidades + parry.
local barraAccion = Instance.new("Frame")
barraAccion.AnchorPoint = Vector2.new(0.5, 1)
barraAccion.Position = UDim2.fromScale(0.5, 0.98)
barraAccion.Size = UDim2.fromScale(0.42, 0.11)
barraAccion.BackgroundTransparency = 1
barraAccion.Parent = gui
local disposicion = Instance.new("UIListLayout")
disposicion.FillDirection = Enum.FillDirection.Horizontal
disposicion.HorizontalAlignment = Enum.HorizontalAlignment.Center
disposicion.Padding = UDim.new(0.015, 0)
disposicion.Parent = barraAccion

type Ranura = { Boton: TextButton, Nombre: TextLabel, Tecla: TextLabel, Velo: Frame, Cuenta: TextLabel }
local ranuras: { [number]: Ranura } = {}

local function crearRanura(indice: number, tecla: string): Ranura
	local boton = Instance.new("TextButton")
	boton.Size = UDim2.fromScale(0.18, 1)
	boton.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
	boton.AutoButtonColor = true
	boton.Text = ""
	boton.LayoutOrder = if indice == 0 then 5 else indice
	local esquinas = Instance.new("UICorner")
	esquinas.CornerRadius = UDim.new(0.12, 0)
	esquinas.Parent = boton
	local borde = Instance.new("UIStroke")
	borde.Color = Color3.fromRGB(90, 90, 110)
	borde.Thickness = 1.5
	borde.Parent = boton
	local nombre = etiqueta(boton, UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.05, 0.25))
	nombre.Font = Enum.Font.GothamMedium
	local etiquetaTecla = etiqueta(boton, UDim2.fromScale(0.35, 0.25), UDim2.fromScale(0.05, 0.02), tecla)
	etiquetaTecla.TextXAlignment = Enum.TextXAlignment.Left
	etiquetaTecla.TextColor3 = Color3.fromRGB(200, 200, 120)
	local velo = Instance.new("Frame")
	velo.BackgroundColor3 = Color3.new(0, 0, 0)
	velo.BackgroundTransparency = 0.35
	velo.BorderSizePixel = 0
	velo.AnchorPoint = Vector2.new(0, 1)
	velo.Position = UDim2.fromScale(0, 1)
	velo.Size = UDim2.fromScale(1, 0)
	velo.ZIndex = 3
	velo.Parent = boton
	local cuenta = etiqueta(boton, UDim2.fromScale(0.6, 0.4), UDim2.fromScale(0.2, 0.3))
	cuenta.ZIndex = 4
	boton.Activated:Connect(function()
		if indice == 0 then
			parry()
		else
			usarHabilidad(indice)
		end
	end)
	boton.Parent = barraAccion
	return { Boton = boton, Nombre = nombre, Tecla = etiquetaTecla, Velo = velo, Cuenta = cuenta }
end

for i = 1, 4 do
	ranuras[i] = crearRanura(i, tostring(i))
end
ranuras[0] = crearRanura(0, "F")
ranuras[0].Nombre.Text = "Parry"

local function refrescarRanuras()
	local def = claseActual()
	for i = 1, 4 do
		local hab = def and def.Habilidades[i]
		ranuras[i].Nombre.Text = if hab
			then (if hab.CostoMana > 0 then `{hab.Nombre}\n{hab.CostoMana} maná` else hab.Nombre)
			else "-"
	end
end

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

local function duracionCooldown(indice: number): number
	if indice == 0 then
		return ClassConfig.CooldownParry
	end
	local def = claseActual()
	local hab = def and def.Habilidades[indice]
	return if hab then hab.Cooldown else 1
end

RunService.RenderStepped:Connect(function()
	local t = ahora()

	-- Vida y maná propios.
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
	local def = claseActual()
	local nivel = if personaje then personaje:GetAttribute("Nivel") else nil
	tituloJugador.Text = `{jugador.DisplayName} - {if def then def.Nombre else "Sin clase"} Nv. {nivel or "?"}`
	local bando = jugador:GetAttribute("Bando")
	local colorBando = if typeof(bando) == "string" then (GameConfig.Bandos.Colores :: any)[bando] else nil
	tituloJugador.TextColor3 = if colorBando then colorBando else Color3.new(1, 1, 1)

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
		local enemigo = o:GetAttribute("Bando") == "Enemigos"
		barraObjetivo.BackgroundColor3 = if enemigo then Color3.fromRGB(210, 60, 50) else Color3.fromRGB(60, 190, 80)
		tituloObjetivo.Text = `{o:GetAttribute("NombreCombate") or o.Name} Nv. {o:GetAttribute("Nivel") or "?"}`
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

	-- Cooldowns.
	for indice, ranura in ranuras do
		local listo = math.max(cooldowns[indice] or 0, if indice > 0 then gcdHasta else 0)
		local restante = listo - t
		if restante > 0 then
			local total = math.max(duracionCooldown(indice), restante)
			ranura.Velo.Size = UDim2.fromScale(1, math.clamp(restante / total, 0, 1))
			ranura.Cuenta.Text = if restante >= 1 then tostring(math.ceil(restante)) else ""
		else
			ranura.Velo.Size = UDim2.fromScale(1, 0)
			ranura.Cuenta.Text = ""
		end
	end
end)
