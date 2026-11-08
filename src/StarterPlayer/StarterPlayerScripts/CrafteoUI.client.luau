--!strict
-- CrafteoUI: ventana de recetas de cada estación y minijuego de recolección.
--
-- * Al activar una estación, el servidor abre la ventana con sus recetas. Cada
--   receta muestra materiales (tenés/necesitás) y el nivel requerido.
-- * Minijuego de recolección: una barra se llena y hay que golpear dentro de la
--   zona verde con E, A (gamepad), clic o el botón "¡Golpear!". El servidor
--   valida el momento con su propio reloj.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ProfesionesConfig = require(ReplicatedStorage.Configs.ProfesionesConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local gui = UIKit.Gui("CrafteoUI", 62)

local function ahora(): number
	return Workspace:GetServerTimeNow()
end

------------------------------------------------------------------------
-- Ventana de crafteo
------------------------------------------------------------------------

local ventana, contenido = UIKit.Ventana(gui, "Fabricar", UDim2.fromScale(0.45, 0.6))
local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -44))
local progresoFondo = Instance.new("Frame")
progresoFondo.Position = UDim2.new(0, 0, 1, -36)
progresoFondo.Size = UDim2.new(1, 0, 0, 30)
progresoFondo.BackgroundColor3 = UIKit.Colores.Panel
progresoFondo.Visible = false
progresoFondo.Parent = contenido
UIKit.Esquinas(progresoFondo, 6)
local progresoBarra = Instance.new("Frame")
progresoBarra.Size = UDim2.fromScale(0, 1)
progresoBarra.BackgroundColor3 = Color3.fromRGB(230, 190, 60)
progresoBarra.Parent = progresoFondo
UIKit.Esquinas(progresoBarra, 6)
local progresoTexto = UIKit.Texto(progresoFondo, "", UDim2.fromScale(1, 1))
progresoTexto.ZIndex = 2

local estacionActual: string? = nil
local trabajo: { Nombre: string, Inicio: number, Fin: number }? = nil

local NOMBRES_ESTACION: { [string]: string } = {
	Yunque = "Yunque",
	MesaAlquimia = "Mesa de Alquimia",
	Telar = "Telar",
}

local function cantidadEnInventario(itemId: string): number
	local inv = EstadoCliente.Get("Inventario")
	if typeof(inv) ~= "table" then
		return 0
	end
	local total = 0
	for _, item in inv.Slots do
		if item.ItemId == itemId then
			total += item.Cantidad
		end
	end
	return total
end

local function nivelProfesion(id: string): number
	local profesiones = EstadoCliente.Get("Profesiones")
	local p = if typeof(profesiones) == "table" then profesiones[id] else nil
	return if typeof(p) == "table" then p.Nivel else 1
end

local function redibujarRecetas()
	local estacion = estacionActual
	if not estacion then
		return
	end
	UIKit.Limpiar(lista)
	local ids: { string } = {}
	for id, receta in ProfesionesConfig.Recetas do
		if receta.Estacion == estacion then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local ra, rb = ProfesionesConfig.Recetas[a], ProfesionesConfig.Recetas[b]
		return if ra.NivelRequerido == rb.NivelRequerido
			then ra.Nombre < rb.Nombre
			else ra.NivelRequerido < rb.NivelRequerido
	end)
	for orden, id in ids do
		local receta = ProfesionesConfig.Recetas[id]
		local fila = Instance.new("Frame")
		fila.Size = UDim2.new(1, 0, 0, 64)
		fila.BackgroundColor3 = UIKit.Colores.Fondo
		fila.LayoutOrder = orden
		UIKit.Esquinas(fila, 6)

		local nivel = nivelProfesion(receta.Profesion)
		local profesion = ProfesionesConfig.Profesiones[receta.Profesion].Nombre
		local titulo = UIKit.Texto(
			fila,
			`{receta.Nombre} x{receta.Resultado.Cantidad}  ·  {profesion} {receta.NivelRequerido}`,
			UDim2.new(0.68, 0, 0, 26),
			UDim2.fromOffset(8, 4)
		)
		titulo.TextXAlignment = Enum.TextXAlignment.Left
		titulo.TextColor3 = if nivel >= receta.NivelRequerido then UIKit.Colores.Texto else Color3.fromRGB(220, 100, 90)

		local puede = nivel >= receta.NivelRequerido
		local partes: { string } = {}
		for itemId, cantidad in receta.Materiales do
			local tengo = cantidadEnInventario(itemId)
			if tengo < cantidad then
				puede = false
			end
			local def = ItemCatalog[itemId]
			table.insert(partes, `{if def then def.Nombre else itemId} {tengo}/{cantidad}`)
		end
		local materiales =
			UIKit.Texto(fila, table.concat(partes, "  ·  "), UDim2.new(0.68, 0, 0, 22), UDim2.fromOffset(8, 34))
		materiales.Font = Enum.Font.Gotham
		materiales.TextColor3 = UIKit.Colores.TextoSuave
		materiales.TextXAlignment = Enum.TextXAlignment.Left

		local boton = UIKit.Boton(
			fila,
			`Fabricar ({receta.Tiempo}s)`,
			UDim2.new(0.28, 0, 0, 40),
			UDim2.new(0.7, 0, 0, 12),
			if puede then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		boton.Activated:Connect(function()
			if trabajo then
				Avisos.Mostrar("Ya estás fabricando algo.", "Error")
				return
			end
			local r = NetworkBridge.Client.Invoke("CraftearIniciar", id)
			if r.Success and typeof(r.Data) == "table" then
				trabajo = { Nombre = r.Data.Nombre, Inicio = ahora(), Fin = r.Data.Fin }
			end
		end)
		fila.Parent = lista
	end
end

NetworkBridge.Client.OnEvent("CrafteoAbrir", function(estacion: any)
	if typeof(estacion) ~= "string" or not NOMBRES_ESTACION[estacion] then
		return
	end
	estacionActual = estacion
	local titulo = ventana:FindFirstChildOfClass("TextLabel")
	if titulo then
		titulo.Text = NOMBRES_ESTACION[estacion]
	end
	redibujarRecetas()
	ventana.Visible = true
	UIKit.EnfocarPrimero(ventana)
end)

NetworkBridge.Client.OnEvent("CrafteoEstado", function(estado: any)
	if typeof(estado) ~= "table" then
		return
	end
	if estado.Terminado or estado.Cancelado then
		trabajo = nil
	end
end)

EstadoCliente.Cambio:Connect(function(campo: string)
	if ventana.Visible and (campo == "Inventario" or campo == "Profesiones" or campo == "*") then
		redibujarRecetas()
	end
end)

------------------------------------------------------------------------
-- Minijuego de recolección
------------------------------------------------------------------------

local minijuego = Instance.new("Frame")
minijuego.AnchorPoint = Vector2.new(0.5, 0.5)
minijuego.Position = UDim2.fromScale(0.5, 0.68)
minijuego.Size = UDim2.fromScale(0.36, 0.13)
minijuego.BackgroundColor3 = UIKit.Colores.Fondo
minijuego.BackgroundTransparency = 0.1
minijuego.Visible = false
minijuego.Parent = gui
UIKit.Esquinas(minijuego, 10)
local tituloMJ = UIKit.Texto(minijuego, "", UDim2.new(1, -16, 0.3, 0), UDim2.fromOffset(8, 4))
local barraMJ = Instance.new("Frame")
barraMJ.Position = UDim2.new(0, 10, 0.38, 0)
barraMJ.Size = UDim2.new(0.7, -10, 0.36, 0)
barraMJ.BackgroundColor3 = UIKit.Colores.Panel
barraMJ.ClipsDescendants = true
barraMJ.Parent = minijuego
UIKit.Esquinas(barraMJ, 6)
local zonaMJ = Instance.new("Frame")
zonaMJ.BackgroundColor3 = Color3.fromRGB(70, 200, 90)
zonaMJ.Size = UDim2.fromScale(0.15, 1)
zonaMJ.Parent = barraMJ
local marcadorMJ = Instance.new("Frame")
marcadorMJ.BackgroundColor3 = Color3.new(1, 1, 1)
marcadorMJ.Size = UDim2.new(0, 4, 1, 0)
marcadorMJ.ZIndex = 3
marcadorMJ.Parent = barraMJ
local botonMJ = UIKit.Boton(
	minijuego,
	"¡Golpear!",
	UDim2.new(0.28, -10, 0.5, 0),
	UDim2.new(0.72, 0, 0.3, 0),
	UIKit.Colores.BotonPrimario
)

type Minijuego = { Token: string, Inicio: number, ZonaInicio: number, ZonaFin: number, Fin: number }
local actual: Minijuego? = nil
local golpeLigado = false

local function golpear()
	local mj = actual
	if not mj then
		return
	end
	actual = nil
	NetworkBridge.Client.Fire("RecoleccionGolpe", mj.Token, Workspace:GetServerTimeNow())
	task.delay(0.3, function()
		if not actual then
			minijuego.Visible = false
		end
	end)
end

botonMJ.Activated:Connect(golpear)

NetworkBridge.Client.OnEvent("MinijuegoRecoleccion", function(datos: any)
	if typeof(datos) ~= "table" or typeof(datos.Token) ~= "string" then
		return
	end
	local duracion = datos.Fin - datos.Inicio
	if typeof(duracion) ~= "number" or duracion <= 0 then
		return
	end
	actual = {
		Token = datos.Token,
		Inicio = datos.Inicio,
		ZonaInicio = datos.ZonaInicio,
		ZonaFin = datos.ZonaFin,
		Fin = datos.Fin,
	}
	tituloMJ.Text = `{datos.Nombre}: golpeá en la zona verde`
	zonaMJ.Position = UDim2.fromScale((datos.ZonaInicio - datos.Inicio) / duracion, 0)
	zonaMJ.Size = UDim2.fromScale((datos.ZonaFin - datos.ZonaInicio) / duracion, 1)
	minijuego.Visible = true
	golpeLigado = true
	ContextActionService:BindActionAtPriority("GolpeRecoleccion", function(_, estado: Enum.UserInputState)
		if estado == Enum.UserInputState.Begin and actual then
			golpear()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.E, Enum.KeyCode.ButtonA)
end)

RunService.RenderStepped:Connect(function()
	local t = ahora()
	-- Barra de crafteo.
	local tr = trabajo
	if tr and t < tr.Fin then
		progresoFondo.Visible = true
		progresoBarra.Size = UDim2.fromScale(math.clamp((t - tr.Inicio) / math.max(0.01, tr.Fin - tr.Inicio), 0, 1), 1)
		progresoTexto.Text = `Fabricando {tr.Nombre}...`
	else
		progresoFondo.Visible = false
	end
	-- Minijuego.
	local mj = actual
	if mj then
		local fraccion = (t - mj.Inicio) / (mj.Fin - mj.Inicio)
		marcadorMJ.Position = UDim2.new(math.clamp(fraccion, 0, 1), -2, 0, 0)
		if t > mj.Fin + 0.5 then
			actual = nil
			minijuego.Visible = false
		end
	end
	if not actual and golpeLigado then
		golpeLigado = false
		ContextActionService:UnbindAction("GolpeRecoleccion")
	end
end)
