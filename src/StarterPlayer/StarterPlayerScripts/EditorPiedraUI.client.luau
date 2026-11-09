--!strict
-- EditorPiedraUI: ventana del cantero para editar la piedra del castillo.
--
-- Lo que movés se ve al instante (solo en tu pantalla) en el castillo y en la
-- muestra. "Guardar" lo manda al servidor, que lo aplica para todos y lo
-- guarda. Si cerrás sin guardar, vuelve a lo guardado.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local AspectoPiedra = require(ReplicatedStorage.Modules.AspectoPiedra)

type Valores = AspectoPiedra.Valores

local DORADO = Color3.fromRGB(255, 215, 90)
local PRESETS: { { string | { number } } } = {
	{ "Gris claro", { 200, 200, 205 } },
	{ "Gris", { 150, 145, 135 } },
	{ "Gris oscuro", { 75, 75, 82 } },
	{ "Arena", { 205, 180, 135 } },
	{ "Rojiza", { 150, 95, 75 } },
	{ "Verdosa", { 110, 135, 105 } },
	{ "Azulada", { 105, 120, 150 } },
	{ "Obsidiana", { 35, 30, 45 } },
}

local guardados: Valores? = nil
local original: Valores? = nil
local editando: Valores? = nil

local gui = UIKit.Gui("EditorPiedraUI", 66)
local ventana, contenido = UIKit.Ventana(gui, "Piedra del castillo", UDim2.fromScale(0.56, 0.82))

local desplazable = Instance.new("ScrollingFrame")
desplazable.Size = UDim2.new(1, 0, 1, -50)
desplazable.BackgroundTransparency = 1
desplazable.BorderSizePixel = 0
desplazable.ScrollBarThickness = 6
desplazable.AutomaticCanvasSize = Enum.AutomaticSize.Y
desplazable.CanvasSize = UDim2.new()
desplazable.Parent = contenido
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = desplazable
local margen = Instance.new("UIPadding")
margen.PaddingRight = UDim.new(0, 10)
margen.Parent = desplazable

local orden = 0
local function siguiente(): number
	orden += 1
	return orden
end

local function titulo(texto: string)
	local t = UIKit.Texto(desplazable, texto, UDim2.new(1, 0, 0, 24))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = DORADO
	t.LayoutOrder = siguiente()
end

local vistaPrevia: () -> ()

------------------------------------------------------------------------
-- Material
------------------------------------------------------------------------

titulo("Material (el dibujo de la piedra)")
local grilla = Instance.new("Frame")
grilla.Size = UDim2.new(1, 0, 0, 0)
grilla.AutomaticSize = Enum.AutomaticSize.Y
grilla.BackgroundTransparency = 1
grilla.LayoutOrder = siguiente()
grilla.Parent = desplazable
local layoutGrilla = Instance.new("UIGridLayout")
layoutGrilla.CellSize = UDim2.new(0.25, -6, 0, 30)
layoutGrilla.CellPadding = UDim2.fromOffset(6, 6)
layoutGrilla.SortOrder = Enum.SortOrder.LayoutOrder
layoutGrilla.Parent = grilla
local botonesMaterial: { [string]: TextButton } = {}
for i, par in AspectoPiedra.Materiales do
	local b = UIKit.Boton(grilla, par[2], UDim2.new())
	b.LayoutOrder = i
	botonesMaterial[par[1]] = b
	local nombre = par[1]
	b.Activated:Connect(function()
		local e = editando
		if e then
			e.Material = nombre
			e.Variante = nil
			vistaPrevia()
		end
	end)
end

-- Materiales propios (los que creaste en el Gestor de materiales de Studio).
titulo("Tus materiales (Gestor de materiales)")
local grillaPropios = Instance.new("Frame")
grillaPropios.Size = UDim2.new(1, 0, 0, 0)
grillaPropios.AutomaticSize = Enum.AutomaticSize.Y
grillaPropios.BackgroundTransparency = 1
grillaPropios.LayoutOrder = siguiente()
grillaPropios.Parent = desplazable
local layoutPropios = Instance.new("UIGridLayout")
layoutPropios.CellSize = UDim2.new(0.25, -6, 0, 30)
layoutPropios.CellPadding = UDim2.fromOffset(6, 6)
layoutPropios.SortOrder = Enum.SortOrder.LayoutOrder
layoutPropios.Parent = grillaPropios
local botonesPropios: { [string]: TextButton } = {}

local function dibujarPropios()
	UIKit.Limpiar(grillaPropios)
	table.clear(botonesPropios)
	local variantes = AspectoPiedra.Variantes()
	if #variantes == 0 then
		local t = UIKit.Texto(grillaPropios, "No hay: crealos en Studio (Gestor de materiales).", UDim2.new())
		t.TextColor3 = UIKit.Colores.TextoSuave
		return
	end
	for i, variante in variantes do
		local b = UIKit.Boton(grillaPropios, `⭐ {variante.Name}`, UDim2.new())
		b.LayoutOrder = i
		botonesPropios[variante.Name] = b
		local nombre = variante.Name
		b.Activated:Connect(function()
			local e = editando
			local v = AspectoPiedra.Variante(nombre)
			if e and v then
				e.Variante = nombre
				e.Material = v.BaseMaterial.Name
				e.Tamano = v.StudsPerTile
				vistaPrevia()
			end
		end)
	end
end

------------------------------------------------------------------------
-- Deslizadores
------------------------------------------------------------------------

type Deslizador = { Poner: (number) -> () }

local function deslizador(
	etiqueta: string,
	min: number,
	max: number,
	decimales: number,
	alCambiar: (number) -> ()
): Deslizador
	local fila = Instance.new("Frame")
	fila.Size = UDim2.new(1, 0, 0, 30)
	fila.BackgroundTransparency = 1
	fila.LayoutOrder = siguiente()
	fila.Parent = desplazable
	local t = UIKit.Texto(fila, etiqueta, UDim2.new(0.26, 0, 1, -6), UDim2.fromOffset(0, 3))
	t.TextXAlignment = Enum.TextXAlignment.Left

	local barra = Instance.new("TextButton")
	barra.Text = ""
	barra.AutoButtonColor = false
	barra.Position = UDim2.new(0.28, 0, 0.5, -5)
	barra.Size = UDim2.new(0.52, 0, 0, 10)
	barra.BackgroundColor3 = UIKit.Colores.Panel
	UIKit.Esquinas(barra, 5)
	barra.Parent = fila
	local relleno = Instance.new("Frame")
	relleno.Size = UDim2.fromScale(0, 1)
	relleno.BackgroundColor3 = DORADO
	relleno.BorderSizePixel = 0
	UIKit.Esquinas(relleno, 5)
	relleno.Parent = barra
	local perilla = Instance.new("Frame")
	perilla.AnchorPoint = Vector2.new(0.5, 0.5)
	perilla.Position = UDim2.fromScale(0, 0.5)
	perilla.Size = UDim2.fromOffset(18, 18)
	perilla.BackgroundColor3 = Color3.new(1, 1, 1)
	UIKit.Esquinas(perilla, 9)
	perilla.Parent = barra

	local caja = UIKit.Entrada(fila, "", UDim2.new(0.16, 0, 1, -4), UDim2.new(0.83, 0, 0, 2))
	local formato = `%.{decimales}f`

	local function mostrar(valor: number)
		local f = if max > min then (valor - min) / (max - min) else 0
		relleno.Size = UDim2.fromScale(f, 1)
		perilla.Position = UDim2.fromScale(f, 0.5)
		caja.Text = string.format(formato, valor)
	end
	local function fijar(valor: number)
		local factor = 10 ^ decimales
		valor = math.clamp(math.round(valor * factor) / factor, min, max)
		mostrar(valor)
		alCambiar(valor)
	end
	local function desdeX(x: number)
		local f = math.clamp((x - barra.AbsolutePosition.X) / math.max(1, barra.AbsoluteSize.X), 0, 1)
		fijar(min + f * (max - min))
	end

	local arrastrando = false
	barra.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			arrastrando = true
			desdeX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			arrastrando
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			desdeX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			arrastrando = false
		end
	end)
	caja.FocusLost:Connect(function()
		local n = tonumber(caja.Text)
		if n then
			fijar(n)
		else
			local e = editando
			if e then
				vistaPrevia()
			end
		end
	end)
	return { Poner = mostrar }
end

------------------------------------------------------------------------
-- Color
------------------------------------------------------------------------

titulo("Color")
local filaMuestra = Instance.new("Frame")
filaMuestra.Size = UDim2.new(1, 0, 0, 30)
filaMuestra.BackgroundTransparency = 1
filaMuestra.LayoutOrder = siguiente()
filaMuestra.Parent = desplazable
local muestraColor = Instance.new("Frame")
muestraColor.Size = UDim2.new(0.26, 0, 1, 0)
UIKit.Esquinas(muestraColor, 6)
muestraColor.Parent = filaMuestra
local hex = UIKit.Texto(filaMuestra, "", UDim2.new(0.3, 0, 1, -6), UDim2.new(0.28, 0, 0, 3))
hex.TextXAlignment = Enum.TextXAlignment.Left

local presets = Instance.new("Frame")
presets.Size = UDim2.new(1, 0, 0, 0)
presets.AutomaticSize = Enum.AutomaticSize.Y
presets.BackgroundTransparency = 1
presets.LayoutOrder = siguiente()
presets.Parent = desplazable
local layoutPresets = Instance.new("UIGridLayout")
layoutPresets.CellSize = UDim2.new(0.25, -6, 0, 28)
layoutPresets.CellPadding = UDim2.fromOffset(6, 6)
layoutPresets.SortOrder = Enum.SortOrder.LayoutOrder
layoutPresets.Parent = presets
for i, p in PRESETS do
	local rgb = p[2] :: { number }
	local b = UIKit.Boton(presets, p[1] :: string, UDim2.new(), nil, Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
	b.LayoutOrder = i
	b.TextStrokeTransparency = 0.3
	b.Activated:Connect(function()
		local e = editando
		if e then
			e.Color = table.clone(rgb)
			vistaPrevia()
		end
	end)
end

local deslizadores: { [string]: Deslizador } = {}
for i, canal in { "Rojo", "Verde", "Azul" } do
	deslizadores[canal] = deslizador(canal, 0, 255, 0, function(v: number)
		local e = editando
		if e then
			e.Color[i] = v
			vistaPrevia()
		end
	end)
end

------------------------------------------------------------------------
-- Superficie y física
------------------------------------------------------------------------

titulo("Superficie")
local R = AspectoPiedra.Rangos
local function numerico(clave: string, etiqueta: string, rango: { number })
	deslizadores[clave] = deslizador(etiqueta, rango[1], rango[2], 2, function(v: number)
		local e = editando
		if e then
			(e :: any)[clave] = v
			vistaPrevia()
		end
	end)
end
numerico("Tamano", "Tamaño del dibujo", R.Tamano)
numerico("Reflejo", "Brillo / metálico", R.Reflejo)
numerico("Transparencia", "Transparencia", R.Transparencia)
local nota = UIKit.Texto(
	desplazable,
	"La metalicidad y la rugosidad de verdad son texturas que solo se cambian en Studio; el brillo es lo más parecido que se puede cambiar en el juego.",
	UDim2.new(1, 0, 0, 34)
)
nota.TextColor3 = UIKit.Colores.TextoSuave
nota.TextWrapped = true
nota.LayoutOrder = siguiente()

titulo("Física (cómo se siente al caminar y chocar)")
numerico("Densidad", "Densidad", R.Densidad)
numerico("Friccion", "Fricción", R.Friccion)
numerico("Elasticidad", "Rebote", R.Elasticidad)

titulo("Código")
local codigo = UIKit.Entrada(desplazable, "", UDim2.new(1, 0, 0, 60))
codigo.TextEditable = false
codigo.TextWrapped = true
codigo.TextScaled = false
codigo.TextSize = 13
codigo.TextXAlignment = Enum.TextXAlignment.Left
codigo.TextYAlignment = Enum.TextYAlignment.Top
codigo.LayoutOrder = siguiente()

------------------------------------------------------------------------
-- Botones
------------------------------------------------------------------------

local barra = Instance.new("Frame")
barra.Position = UDim2.new(0, 0, 1, -42)
barra.Size = UDim2.new(1, 0, 0, 40)
barra.BackgroundTransparency = 1
barra.Parent = contenido
local botonGuardar = UIKit.Boton(barra, "Guardar", UDim2.new(0.32, -4, 1, 0), nil, UIKit.Colores.BotonPrimario)
local botonDeshacer = UIKit.Boton(barra, "Volver a lo guardado", UDim2.new(0.34, -4, 1, 0), UDim2.fromScale(0.33, 0))
local botonOriginal = UIKit.Boton(barra, "Valores originales", UDim2.new(0.32, -4, 1, 0), UDim2.fromScale(0.68, 0))

------------------------------------------------------------------------
-- Lógica
------------------------------------------------------------------------

local function copia(v: Valores): Valores
	local c = table.clone(v)
	c.Color = table.clone(v.Color)
	return c
end

local function refrescarControles()
	local e = editando
	if not e then
		return
	end
	for nombre, b in botonesMaterial do
		b.BackgroundColor3 = if e.Variante == nil and nombre == e.Material
			then UIKit.Colores.BotonPrimario
			else UIKit.Colores.Boton
	end
	for nombre, b in botonesPropios do
		b.BackgroundColor3 = if nombre == e.Variante then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
	end
	local color = AspectoPiedra.Color(e)
	muestraColor.BackgroundColor3 = color
	hex.Text = `#{color:ToHex():upper()}  ({e.Color[1]}, {e.Color[2]}, {e.Color[3]})`
	deslizadores.Rojo.Poner(e.Color[1])
	deslizadores.Verde.Poner(e.Color[2])
	deslizadores.Azul.Poner(e.Color[3])
	for _, clave in { "Reflejo", "Transparencia", "Densidad", "Friccion", "Elasticidad" } do
		deslizadores[clave].Poner((e :: any)[clave])
	end
	local variante = AspectoPiedra.Variante(e.Variante)
	deslizadores.Tamano.Poner(e.Tamano or (if variante then variante.StudsPerTile else 10))
	codigo.Text = AspectoPiedra.Codigo(e)
end

vistaPrevia = function()
	local e = editando
	if not e then
		return
	end
	AspectoPiedra.AplicarATodas(e, false) -- solo en tu pantalla hasta guardar
	refrescarControles()
end

local function volverALoGuardado()
	local g = guardados
	if g then
		editando = copia(g)
		vistaPrevia()
	end
end

botonGuardar.Activated:Connect(function()
	local e = editando
	if not e then
		return
	end
	botonGuardar.Text = "Guardando…"
	local r = NetworkBridge.Client.Invoke("EditorPiedraGuardar", e)
	botonGuardar.Text = "Guardar"
	if r.Success then
		guardados = copia(e)
	end
end)
botonDeshacer.Activated:Connect(volverALoGuardado)
botonOriginal.Activated:Connect(function()
	local o = original
	if o then
		editando = copia(o)
		vistaPrevia()
	end
end)

-- Cerrar sin guardar: todo vuelve a como está en el servidor.
ventana:GetPropertyChangedSignal("Visible"):Connect(function()
	if not ventana.Visible then
		local g = guardados
		if g then
			AspectoPiedra.AplicarATodas(g, false)
		end
	end
end)

NetworkBridge.Client.OnEvent("EditorPiedraAbrir", function(datos: any)
	if typeof(datos) ~= "table" then
		return
	end
	local actual = AspectoPiedra.Validar(datos.Actual)
	local orig = AspectoPiedra.Validar(datos.Original)
	if not actual or not orig then
		return
	end
	guardados = actual
	original = orig
	editando = copia(actual)
	dibujarPropios()
	ventana.Visible = true
	vistaPrevia()
	UIKit.EnfocarPrimero(ventana)
end)
