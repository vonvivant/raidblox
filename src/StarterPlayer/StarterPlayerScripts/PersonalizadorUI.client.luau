--!strict
-- PersonalizadorUI: tienda y probador del NPC vendedor y personalizador.
--
--   Izquierda: catálogo (Armas / Armaduras, buscador).
--   Centro:    el avatar con el modelo puesto (VISTA PREVIA); se gira
--              arrastrando y se elige una pieza haciéndole clic.
--   Derecha:   piezas, materiales y color (paleta, RGB y hexadecimal).
--   Abajo:     precio (lo calcula el servidor), saldo, COMPRAR y CANCELAR.
--
-- Todo lo que se ve acá es local: el modelo de prueba es un clon que no existe
-- para el servidor, no es un ítem y no da estadísticas. La compra la decide el
-- servidor con el id del modelo y la personalización; el precio que se muestra
-- es el que él informa.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Configs.PersonalizadorConfig)
local Avisos = require(ReplicatedStorage.Modules.Avisos)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Personalizador = require(ReplicatedStorage.Modules.Personalizador)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

type Entrada = Personalizador.Entrada
type Pieza = Config.Pieza

local jugador = Players.LocalPlayer
local CAM = Config.Camara

------------------------------------------------------------------------
-- Interfaz (se arma una vez; después solo se actualiza)
------------------------------------------------------------------------

local gui = UIKit.Gui("PersonalizadorUI", 70)
local raiz = Instance.new("Frame")
raiz.Name = "ShopCustomizerUI"
raiz.Size = UDim2.fromScale(1, 1)
raiz.BackgroundTransparency = 1
raiz.Visible = false
raiz:SetAttribute("Ventana", true) -- con esto abierto, el modo apuntado suelta el mouse
raiz.Parent = gui

local function panel(pos: UDim2, tam: UDim2): Frame
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = tam
	f.BackgroundColor3 = UIKit.Colores.Fondo
	f.BackgroundTransparency = 0.08
	UIKit.Esquinas(f, 10)
	local margen = Instance.new("UIPadding")
	margen.PaddingLeft = UDim.new(0, 8)
	margen.PaddingRight = UDim.new(0, 8)
	margen.PaddingTop = UDim.new(0, 8)
	margen.PaddingBottom = UDim.new(0, 8)
	margen.Parent = f
	f.Parent = raiz
	return f
end

local function titulo(padre: Instance, texto: string, y: number): TextLabel
	local t = UIKit.Texto(padre, texto, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, y))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = UIKit.Colores.Oro
	return t
end

-- Fila de una lista: botón de ancho completo con el texto a la izquierda.
local function fila(lista: Instance, texto: string, orden: number): TextButton
	local b = UIKit.Boton(lista, texto, UDim2.new(1, 0, 0, 30))
	b.LayoutOrder = orden
	b.TextXAlignment = Enum.TextXAlignment.Left
	return b
end

-- Catálogo (izquierda)
local pCatalogo = panel(UDim2.fromScale(0.01, 0.08), UDim2.fromScale(0.22, 0.72))
titulo(pCatalogo, "Catálogo", 0)
local botonArmas = UIKit.Boton(pCatalogo, "Armas", UDim2.new(0.5, -3, 0, 30), UDim2.fromOffset(0, 26))
local botonArmaduras = UIKit.Boton(pCatalogo, "Armaduras", UDim2.new(0.5, -3, 0, 30), UDim2.new(0.5, 3, 0, 26))
local cajaBuscar = UIKit.Entrada(pCatalogo, "Buscar…", UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 60))
local listaCatalogo = UIKit.Lista(pCatalogo, UDim2.new(1, 0, 1, -94), UDim2.fromOffset(0, 94))

-- Probador (centro): zona transparente que recibe el arrastre y los clics.
local zona = Instance.new("TextButton")
zona.Name = "Probador"
zona.Position = UDim2.fromScale(0.24, 0.08)
zona.Size = UDim2.fromScale(0.5, 0.72)
zona.BackgroundTransparency = 1
zona.Text = ""
zona.AutoButtonColor = false
zona.Selectable = false
zona.Parent = raiz
local cartel = UIKit.Texto(zona, "VISTA PREVIA", UDim2.new(0.5, 0, 0, 26), UDim2.fromScale(0.25, 0))
cartel.TextColor3 = UIKit.Colores.Oro
cartel.BackgroundColor3 = UIKit.Colores.Fondo
cartel.BackgroundTransparency = 0.3
UIKit.Esquinas(cartel, 6)
local ayuda = UIKit.Texto(
	zona,
	"Arrastrá para girar  ·  tocá una pieza para elegirla",
	UDim2.new(1, 0, 0, 20),
	UDim2.new(0, 0, 0, 30)
)
ayuda.TextColor3 = UIKit.Colores.TextoSuave
local botonIzq = UIKit.Boton(zona, "⟲", UDim2.fromOffset(40, 40), UDim2.new(0, 6, 1, -46))
local botonDer = UIKit.Boton(zona, "⟳", UDim2.fromOffset(40, 40), UDim2.new(0, 52, 1, -46))
local botonMas = UIKit.Boton(zona, "+", UDim2.fromOffset(40, 40), UDim2.new(1, -92, 1, -46))
local botonMenos = UIKit.Boton(zona, "–", UDim2.fromOffset(40, 40), UDim2.new(1, -46, 1, -46))

-- Personalización (derecha)
local pEdicion = panel(UDim2.fromScale(0.75, 0.08), UDim2.fromScale(0.24, 0.72))
titulo(pEdicion, "Piezas", 0)
local listaPiezas = UIKit.Lista(pEdicion, UDim2.new(1, 0, 0.2, 0), UDim2.fromOffset(0, 24))
local tituloMaterial = titulo(pEdicion, "Material", 0)
tituloMaterial.Position = UDim2.new(0, 0, 0.2, 28)
local cajaMaterial = UIKit.Entrada(pEdicion, "Buscar material…", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0.2, 52))
local listaMateriales = UIKit.Lista(pEdicion, UDim2.new(1, 0, 0.24, 0), UDim2.new(0, 0, 0.2, 82))
local tituloColor = titulo(pEdicion, "Color", 0)
tituloColor.Position = UDim2.new(0, 0, 0.44, 86)
local muestra = Instance.new("Frame")
muestra.Size = UDim2.fromOffset(40, 22)
muestra.Position = UDim2.new(1, -40, 0.44, 86)
UIKit.Esquinas(muestra, 4)
muestra.Parent = pEdicion
local paleta = Instance.new("Frame")
paleta.Position = UDim2.new(0, 0, 0.44, 112)
paleta.Size = UDim2.new(1, 0, 0.14, 0)
paleta.BackgroundTransparency = 1
paleta.Parent = pEdicion
local grilla = Instance.new("UIGridLayout")
grilla.CellSize = UDim2.new(1 / 6, -4, 1 / 3, -4)
grilla.CellPadding = UDim2.fromOffset(4, 4)
grilla.Parent = paleta
local cajaR = UIKit.Entrada(pEdicion, "R", UDim2.new(0.2, -4, 0, 26), UDim2.new(0, 0, 0.58, 116))
local cajaG = UIKit.Entrada(pEdicion, "G", UDim2.new(0.2, -4, 0, 26), UDim2.new(0.2, 0, 0.58, 116))
local cajaB = UIKit.Entrada(pEdicion, "B", UDim2.new(0.2, -4, 0, 26), UDim2.new(0.4, 0, 0.58, 116))
local cajaHex = UIKit.Entrada(pEdicion, "#RRGGBB", UDim2.new(0.4, 0, 0, 26), UDim2.new(0.6, 0, 0.58, 116))
local botonReset = UIKit.Boton(pEdicion, "Restablecer pieza", UDim2.new(0.5, -3, 0, 28), UDim2.new(0, 0, 0.58, 148))
local botonResetTodo =
	UIKit.Boton(pEdicion, "Restablecer todo", UDim2.new(0.5, -3, 0, 28), UDim2.new(0.5, 3, 0.58, 148))
local botonATodas = UIKit.Boton(pEdicion, "Aplicar a todas", UDim2.new(0.4, -3, 0, 28), UDim2.new(0, 0, 0.58, 180))
local botonCopiar = UIKit.Boton(pEdicion, "Copiar", UDim2.new(0.3, -3, 0, 28), UDim2.new(0.4, 3, 0.58, 180))
local botonPegar = UIKit.Boton(pEdicion, "Pegar", UDim2.new(0.3, -3, 0, 28), UDim2.new(0.7, 3, 0.58, 180))

-- Compra (abajo)
local pCompra = panel(UDim2.fromScale(0.01, 0.82), UDim2.fromScale(0.98, 0.16))
local textoItem = UIKit.Texto(pCompra, "Elegí un objeto del catálogo", UDim2.fromScale(0.34, 0.5))
textoItem.TextXAlignment = Enum.TextXAlignment.Left
local textoEstado = UIKit.Texto(pCompra, "", UDim2.fromScale(0.34, 0.45), UDim2.fromScale(0, 0.55))
textoEstado.TextXAlignment = Enum.TextXAlignment.Left
textoEstado.TextColor3 = UIKit.Colores.TextoSuave
local textoPrecio = UIKit.Texto(pCompra, "", UDim2.fromScale(0.3, 0.5), UDim2.fromScale(0.35, 0))
textoPrecio.TextXAlignment = Enum.TextXAlignment.Left
local textoSaldo = UIKit.Texto(pCompra, "", UDim2.fromScale(0.3, 0.45), UDim2.fromScale(0.35, 0.55))
textoSaldo.TextXAlignment = Enum.TextXAlignment.Left
textoSaldo.TextColor3 = UIKit.Colores.Oro
local botonComprar =
	UIKit.Boton(pCompra, "COMPRAR", UDim2.new(0.16, 0, 0.8, 0), UDim2.fromScale(0.66, 0.1), UIKit.Colores.BotonPrimario)
local botonCancelar = UIKit.Boton(
	pCompra,
	"CANCELAR",
	UDim2.new(0.16, 0, 0.8, 0),
	UDim2.fromScale(0.835, 0.1),
	UIKit.Colores.BotonPeligro
)

-- Confirmación (encima de todo)
local pConfirmar = Instance.new("Frame")
pConfirmar.AnchorPoint = Vector2.new(0.5, 0.5)
pConfirmar.Position = UDim2.fromScale(0.5, 0.45)
pConfirmar.Size = UDim2.fromScale(0.36, 0.6)
pConfirmar.BackgroundColor3 = UIKit.Colores.Fondo
pConfirmar.ZIndex = 5
pConfirmar.Visible = false
UIKit.Esquinas(pConfirmar, 12)
pConfirmar.Parent = raiz
local tituloConfirmar = UIKit.Texto(pConfirmar, "Confirmar compra", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 8))
tituloConfirmar.TextColor3 = UIKit.Colores.Oro
tituloConfirmar.ZIndex = 6
local listaConfirmar = UIKit.Lista(pConfirmar, UDim2.new(1, -20, 1, -100), UDim2.fromOffset(10, 44))
listaConfirmar.ZIndex = 6
local botonSi = UIKit.Boton(
	pConfirmar,
	"Confirmar",
	UDim2.new(0.5, -15, 0, 40),
	UDim2.new(0, 10, 1, -50),
	UIKit.Colores.BotonPrimario
)
botonSi.ZIndex = 6
local botonNo = UIKit.Boton(pConfirmar, "Volver", UDim2.new(0.5, -15, 0, 40), UDim2.new(0.5, 5, 1, -50))
botonNo.ZIndex = 6

------------------------------------------------------------------------
-- Estado
------------------------------------------------------------------------

type Presupuesto = { Base: number, Extra: number, Precio: number }
type EstadoCamara = { Tipo: Enum.CameraType, Sujeto: Instance?, Fov: number, CFrame: CFrame }

local abierta = false
local sesion = 0 -- cambia en cada apertura y cierre: las respuestas viejas se descartan
local posicionNpc: Vector3? = nil
local categoria = "Armas"
local conexiones: { any } = {} -- conexiones de Roblox y de señales propias

local seleccion: Entrada? = nil
local clon: Model? = nil
local mapa: { [string]: BasePart } = {}
local resaltado: Highlight? = nil
local piezaId: string? = nil
-- Cambios por ítem (solo piezas distintas del original). Se conservan mientras
-- el probador siga abierto, aunque se cambie de ítem o de pestaña.
local cambiosPorItem: { [string]: { [string]: Pieza } } = {}
local portapapeles: Pieza? = nil

local presupuesto: Presupuesto? = nil
local cotizacion = 0 -- número de la última cotización pedida
local comprando = false
local pedidoId: string? = nil -- id del pedido de compra en curso (se reutiliza al reintentar)

local camaraOriginal: EstadoCamara? = nil
local giro = 0 -- grados alrededor del avatar
local distancia = CAM.Distancia
local mezcla = Instance.new("NumberValue") -- 0 = cámara original, 1 = cámara del probador
local tweenEntrada: Tween? = nil
local controles: any = nil
local botonesPieza: { [string]: TextButton } = {}

local function oro(): number
	local v = EstadoCliente.Get("Oro")
	return if typeof(v) == "number" then v else 0
end

local function nivel(): number
	local v = EstadoCliente.Get("Nivel")
	return if typeof(v) == "number" then v else 1
end

local function cambios(): { [string]: Pieza }
	local s = seleccion
	if not s then
		return {}
	end
	local c = cambiosPorItem[s.ItemId]
	if not c then
		c = {}
		cambiosPorItem[s.ItemId] = c
	end
	return c
end

-- Material y color actuales de una pieza (lo cambiado o lo original).
local function actual(id: string): Pieza?
	local s = seleccion
	local original = if s then s.PorId[id] else nil
	if not original then
		return nil
	end
	return cambios()[id] or { Material = original.Material, Color = original.Color }
end

------------------------------------------------------------------------
-- Vista previa
------------------------------------------------------------------------

-- Oculta (solo para este jugador) el equipo real del slot que se está probando.
local function ocultarEquipo(slot: string?)
	local personaje = jugador.Character
	local carpeta = personaje and personaje:FindFirstChild("EquipoVisible")
	if not carpeta then
		return
	end
	for _, hijo in carpeta:GetChildren() do
		local oculto = slot ~= nil and hijo:GetAttribute("Slot") == slot
		local partes: { Instance } = hijo:GetDescendants()
		table.insert(partes, hijo)
		for _, d in partes do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if oculto then 1 else 0
			end
		end
	end
end

local function quitarClon()
	if clon then
		clon:Destroy()
	end
	clon = nil
	mapa = {}
	resaltado = nil
	ocultarEquipo(nil)
end

local function resaltar()
	local parte = if piezaId then mapa[piezaId] else nil
	if resaltado then
		resaltado.Adornee = parte
		resaltado.Enabled = parte ~= nil
	end
	for id, boton in botonesPieza do
		boton.BackgroundColor3 = if id == piezaId then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
	end
end

-- Clona el modelo elegido, le aplica los cambios y lo monta sobre el avatar.
local function ponerClon()
	quitarClon()
	local s = seleccion
	local personaje = jugador.Character
	if not s or not personaje then
		return
	end
	local nuevo = s.Modelo:Clone()
	nuevo.Name = "VistaPrevia"
	nuevo:SetAttribute("VistaPrevia", true) -- objeto temporal: no es un ítem
	local nuevoMapa = Personalizador.Mapa(nuevo) -- antes de montar
	Personalizador.Aplicar(s, nuevoMapa, cambios())
	local ok, motivo = Personalizador.Montar(nuevo, personaje, s.Slot)
	if not ok then
		nuevo:Destroy()
		Avisos.Mostrar(`No se puede probar este modelo: {motivo or "?"}.`, "Error")
		return
	end
	-- Las piezas editables aceptan rayos para poder elegirlas con un clic.
	for _, parte in nuevoMapa do
		parte.CanQuery = true
	end
	local marca = Instance.new("Highlight")
	marca.FillColor = Color3.new(1, 1, 1)
	marca.FillTransparency = 0.75
	marca.OutlineColor = UIKit.Colores.Oro
	marca.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	marca.Enabled = false
	marca.Parent = nuevo
	nuevo.Parent = personaje
	clon, mapa, resaltado = nuevo, nuevoMapa, marca
	ocultarEquipo(s.Slot)
	resaltar()
end

-- Aplica al clon el estado actual de una pieza (sin rehacer nada más).
local function pintar(id: string)
	local s = seleccion
	local parte = mapa[id]
	local estado = actual(id)
	if not s or not parte or not estado then
		return
	end
	local material = Personalizador.Material(estado.Material)
	local color = Personalizador.ColorDeHex(estado.Color)
	if material then
		parte.Material = material
	end
	if color then
		parte.Color = color
	end
end

------------------------------------------------------------------------
-- Presupuesto y panel de compra
------------------------------------------------------------------------

local function cantidadCambios(): number
	local n = 0
	for _ in cambios() do
		n += 1
	end
	return n
end

local function actualizarCompra()
	local s = seleccion
	textoSaldo.Text = `Tu oro: {oro()}`
	if not s then
		textoItem.Text = "Elegí un objeto del catálogo"
		textoEstado.Text = ""
		textoPrecio.Text = ""
		botonComprar.BackgroundColor3 = UIKit.Colores.Boton
		return
	end
	local n = cantidadCambios()
	textoItem.Text = s.Nombre
	textoEstado.Text = if n > 0
		then `{n} pieza(s) modificada(s) · cambios sin comprar`
		else "Sin cambios · los cambios son solo estéticos"
	local p = presupuesto
	if p then
		textoPrecio.Text = if p.Extra > 0
			then `Base {p.Base} + personalización {p.Extra} = {p.Precio} de oro`
			else `Precio: {p.Precio} de oro`
		local puede = oro() >= p.Precio and nivel() >= s.Nivel and not comprando
		botonComprar.BackgroundColor3 = if puede then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
	else
		textoPrecio.Text = "Calculando precio…"
		botonComprar.BackgroundColor3 = UIKit.Colores.Boton
	end
end

-- Lo que se le manda al servidor: solo las piezas cambiadas.
local function paraEnviar(): { [string]: Pieza }
	local datos: { [string]: Pieza } = {}
	for id, pieza in cambios() do
		datos[id] = { Material = pieza.Material, Color = pieza.Color }
	end
	return datos
end

-- Pide el precio al servidor un momento después del último cambio (no en cada
-- movimiento del selector de color).
local function cotizar()
	local s = seleccion
	presupuesto = nil
	cotizacion += 1
	local numero, miSesion = cotizacion, sesion
	actualizarCompra()
	if not s then
		return
	end
	task.delay(0.35, function()
		if numero ~= cotizacion or miSesion ~= sesion then
			return
		end
		local r = NetworkBridge.Client.Invoke("PersonalizadorPresupuesto", s.ItemId, paraEnviar())
		if numero ~= cotizacion or miSesion ~= sesion then
			return -- hubo otro cambio o se cerró mientras tanto
		end
		if r.Success and typeof(r.Data) == "table" and typeof(r.Data.Precio) == "number" then
			presupuesto = { Base = r.Data.Base, Extra = r.Data.Extra, Precio = r.Data.Precio }
		else
			textoPrecio.Text = "No se pudo calcular el precio"
		end
		actualizarCompra()
	end)
end

------------------------------------------------------------------------
-- Edición
------------------------------------------------------------------------

local function mostrarColor()
	local estado = if piezaId then actual(piezaId) else nil
	local r, g, b = Config.DeHex(if estado then estado.Color else nil)
	if not estado or not r or not g or not b then
		cajaR.Text, cajaG.Text, cajaB.Text, cajaHex.Text = "", "", "", ""
		muestra.BackgroundColor3 = UIKit.Colores.Panel
		tituloMaterial.Text = "Material"
		return
	end
	cajaR.Text, cajaG.Text, cajaB.Text = tostring(r), tostring(g), tostring(b)
	cajaHex.Text = "#" .. estado.Color
	muestra.BackgroundColor3 = Color3.fromRGB(r, g, b)
	tituloMaterial.Text = `Material: {estado.Material}`
end

-- Cambia material o color de una pieza. Si queda igual al original, deja de
-- contar como cambio.
local function fijar(id: string, material: string?, color: string?)
	local s = seleccion
	local original = if s then s.PorId[id] else nil
	local estado = actual(id)
	if not s or not original or not estado then
		return
	end
	local nuevo: Pieza = { Material = material or estado.Material, Color = color or estado.Color }
	local c = cambios()
	if nuevo.Material == original.Material and nuevo.Color == original.Color then
		c[id] = nil
	else
		c[id] = nuevo
	end
	pintar(id)
end

local function despuesDeEditar()
	mostrarColor()
	cotizar()
end

local function elegirPieza(id: string?)
	piezaId = id
	resaltar()
	mostrarColor()
end

local function llenarPiezas()
	UIKit.Limpiar(listaPiezas)
	botonesPieza = {}
	local s = seleccion
	if not s then
		return
	end
	for i, pieza in s.Piezas do
		local b = fila(listaPiezas, pieza.Nombre, i)
		botonesPieza[pieza.Id] = b
		b.Activated:Connect(function()
			elegirPieza(pieza.Id)
		end)
	end
end

local function llenarMateriales()
	UIKit.Limpiar(listaMateriales)
	local filtro = string.lower(cajaMaterial.Text)
	for i, nombre in Personalizador.Materiales() do
		if filtro ~= "" and not string.find(string.lower(nombre), filtro, 1, true) then
			continue
		end
		local b = fila(listaMateriales, nombre, i)
		b.Activated:Connect(function()
			if piezaId then
				fijar(piezaId, nombre, nil)
				despuesDeEditar()
			end
		end)
	end
end

local function elegirColor(hex: string?)
	if piezaId and hex and Config.HexValido(hex) then
		fijar(piezaId, nil, string.upper(hex))
		despuesDeEditar()
	else
		mostrarColor() -- valor inválido: vuelve a mostrar el actual
	end
end

for i, hex in Config.Paleta do
	local r, g, b = Config.DeHex(hex)
	local celda = Instance.new("TextButton")
	celda.Text = ""
	celda.LayoutOrder = i
	celda.BackgroundColor3 = Color3.fromRGB(r or 255, g or 255, b or 255)
	UIKit.Esquinas(celda, 4)
	celda.Parent = paleta
	celda.Activated:Connect(function()
		elegirColor(hex)
	end)
end

local function desdeRgb()
	elegirColor(Config.AHex(tonumber(cajaR.Text), tonumber(cajaG.Text), tonumber(cajaB.Text)))
end
cajaR.FocusLost:Connect(desdeRgb)
cajaG.FocusLost:Connect(desdeRgb)
cajaB.FocusLost:Connect(desdeRgb)
cajaHex.FocusLost:Connect(function()
	elegirColor((string.gsub(cajaHex.Text, "[#%s]", "")))
end)
cajaMaterial:GetPropertyChangedSignal("Text"):Connect(llenarMateriales)

botonReset.Activated:Connect(function()
	if piezaId then
		cambios()[piezaId] = nil
		pintar(piezaId)
		despuesDeEditar()
	end
end)
botonResetTodo.Activated:Connect(function()
	local s = seleccion
	if s then
		cambiosPorItem[s.ItemId] = {}
		for id in mapa do
			pintar(id)
		end
		despuesDeEditar()
	end
end)
botonATodas.Activated:Connect(function()
	local s = seleccion
	local estado = if piezaId then actual(piezaId) else nil
	if s and estado then
		for _, pieza in s.Piezas do
			fijar(pieza.Id, estado.Material, estado.Color)
		end
		despuesDeEditar()
	end
end)
botonCopiar.Activated:Connect(function()
	local estado = if piezaId then actual(piezaId) else nil
	if estado then
		portapapeles = { Material = estado.Material, Color = estado.Color }
		Avisos.Mostrar("Configuración copiada. Elegí otra pieza y tocá Pegar.", "Info")
	end
end)
botonPegar.Activated:Connect(function()
	local copia = portapapeles
	if piezaId and copia then
		fijar(piezaId, copia.Material, copia.Color)
		despuesDeEditar()
	end
end)

------------------------------------------------------------------------
-- Catálogo
------------------------------------------------------------------------

local function elegirItem(entrada: Entrada?)
	seleccion = entrada
	pedidoId = nil
	ponerClon()
	llenarPiezas()
	elegirPieza(if entrada then entrada.Piezas[1].Id else nil)
	cotizar()
end

local function llenarCatalogo()
	UIKit.Limpiar(listaCatalogo)
	botonArmas.BackgroundColor3 = if categoria == "Armas" then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
	botonArmaduras.BackgroundColor3 = if categoria == "Armaduras"
		then UIKit.Colores.BotonPrimario
		else UIKit.Colores.Boton
	local tipo = Config.Subcarpetas[categoria]
	local filtro = string.lower(cajaBuscar.Text)
	local entradas: { Entrada } = {}
	for _, entrada in Personalizador.Catalogo() do
		if entrada.Tipo == tipo and (filtro == "" or string.find(string.lower(entrada.Nombre), filtro, 1, true)) then
			table.insert(entradas, entrada)
		end
	end
	table.sort(entradas, function(a: Entrada, b: Entrada): boolean
		return if a.Precio ~= b.Precio then a.Precio < b.Precio else a.Nombre < b.Nombre
	end)
	if #entradas == 0 then
		local vacio = UIKit.Texto(listaCatalogo, "No hay objetos en esta categoría.", UDim2.new(1, 0, 0, 40))
		vacio.TextColor3 = UIKit.Colores.TextoSuave
		vacio.TextWrapped = true
	end
	for i, entrada in entradas do
		local disponible = nivel() >= entrada.Nivel
		local b = fila(
			listaCatalogo,
			if disponible
				then `{entrada.Nombre} · {entrada.Precio} oro`
				else `{entrada.Nombre} · nivel {entrada.Nivel}`,
			i
		)
		if not disponible then
			b.TextColor3 = UIKit.Colores.TextoSuave
		end
		b.Activated:Connect(function()
			elegirItem(entrada)
		end)
	end
end

botonArmas.Activated:Connect(function()
	categoria = "Armas"
	llenarCatalogo()
end)
botonArmaduras.Activated:Connect(function()
	categoria = "Armaduras"
	llenarCatalogo()
end)
cajaBuscar:GetPropertyChangedSignal("Text"):Connect(llenarCatalogo)

------------------------------------------------------------------------
-- Cámara del probador
------------------------------------------------------------------------

local function raizPersonaje(): BasePart?
	local personaje = jugador.Character
	local r = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function destinoCamara(): CFrame?
	local r = raizPersonaje()
	if not r then
		return nil
	end
	local foco = r.Position + Vector3.new(0, CAM.Altura, 0)
	local direccion = CFrame.Angles(0, math.rad(giro), 0) * Vector3.new(0, 0.25, 1)
	return CFrame.lookAt(foco + direccion.Unit * distancia, foco)
end

local function acercar(delta: number)
	distancia = math.clamp(distancia + delta, CAM.DistanciaMinima, CAM.DistanciaMaxima)
end

------------------------------------------------------------------------
-- Compra
------------------------------------------------------------------------

local function linea(texto: string, orden: number, color: Color3?)
	local t = UIKit.Texto(listaConfirmar, texto, UDim2.new(1, 0, 0, 24))
	t.LayoutOrder = orden
	t.ZIndex = 6
	t.Font = Enum.Font.Gotham
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color or UIKit.Colores.Texto
end

-- Muestra exactamente qué se compra y por cuánto antes de pedirlo.
local function mostrarConfirmacion(aviso: string?)
	local s, p = seleccion, presupuesto
	if not s or not p then
		return
	end
	UIKit.Limpiar(listaConfirmar)
	local orden = 0
	local function agregar(texto: string, color: Color3?)
		orden += 1
		linea(texto, orden, color)
	end
	if aviso then
		agregar(aviso, UIKit.Colores.Oro)
	end
	agregar(`Objeto: {s.Nombre}`)
	local ids: { string } = {}
	for id in cambios() do
		table.insert(ids, id)
	end
	table.sort(ids)
	if #ids == 0 then
		agregar("Sin personalización (como el original).", UIKit.Colores.TextoSuave)
	end
	for _, id in ids do
		local pieza = cambios()[id]
		local original = s.PorId[id]
		agregar(`  · {if original then original.Nombre else id}: {pieza.Material}, #{pieza.Color}`)
	end
	agregar(`Precio final: {p.Precio} de oro`, UIKit.Colores.Oro)
	agregar(`Tu oro: {oro()}   ·   te quedan: {oro() - p.Precio}`)
	agregar("Los cambios son solo estéticos: no modifican las estadísticas.", UIKit.Colores.TextoSuave)
	if s.Nivel > 1 then
		agregar(`Requiere nivel {s.Nivel}.`, UIKit.Colores.TextoSuave)
	end
	pConfirmar.Visible = true
end

local function enviarCompra()
	local s, p = seleccion, presupuesto
	if not s or not p or comprando then
		return
	end
	comprando = true
	pConfirmar.Visible = false
	textoPrecio.Text = "Comprando…"
	-- El mismo id mientras el pedido no tenga una respuesta definitiva: si la
	-- respuesta se pierde, reintentar no compra dos veces.
	local id = pedidoId or HttpService:GenerateGUID(false)
	pedidoId = id
	local miSesion = sesion
	local r = NetworkBridge.Client.Invoke("PersonalizadorComprar", s.ItemId, id, paraEnviar(), p.Precio)
	comprando = false
	if miSesion ~= sesion then
		return -- se cerró el probador: si la compra se hizo, el ítem ya está en la mochila
	end
	local datos = r.Data
	if r.Success and typeof(datos) == "table" and datos.Estado == "Comprado" then
		pedidoId = nil
		Avisos.Mostrar(`¡{s.Nombre} comprada! Está en tu mochila.`, "Oro")
	elseif r.Success and typeof(datos) == "table" and datos.Estado == "PrecioCambio" then
		-- El servidor no cobró: hay que confirmar de nuevo con el precio real.
		pedidoId = nil
		presupuesto = { Base = s.Precio, Extra = datos.Precio - s.Precio, Precio = datos.Precio }
		mostrarConfirmacion(`El precio cambió: ahora cuesta {datos.Precio} de oro.`)
	elseif r.ErrorCode == "TIMEOUT" or r.ErrorCode == "RATE_LIMITED" then
		Avisos.Mostrar("No hubo respuesta del servidor. Tocá COMPRAR de nuevo: no se cobra dos veces.", "Error")
	else
		pedidoId = nil
		Avisos.Mostrar("No se pudo completar la compra.", "Error")
	end
	actualizarCompra()
end

botonComprar.Activated:Connect(function()
	local s, p = seleccion, presupuesto
	if not s or comprando then
		return
	end
	if not p then
		Avisos.Mostrar("Esperá a que se calcule el precio.", "Info")
	elseif nivel() < s.Nivel then
		Avisos.Mostrar(`Necesitás nivel {s.Nivel}.`, "Error")
	elseif oro() < p.Precio then
		Avisos.Mostrar("No te alcanza el oro.", "Error")
	else
		mostrarConfirmacion(nil)
	end
end)
botonSi.Activated:Connect(function()
	task.spawn(enviarCompra)
end)
botonNo.Activated:Connect(function()
	pConfirmar.Visible = false
end)

------------------------------------------------------------------------
-- Apertura, cierre y limpieza
------------------------------------------------------------------------

local function controlesDelJugador(): any
	local ok, resultado = pcall(function(): any
		local scripts = jugador:FindFirstChild("PlayerScripts")
		local modulo = scripts and scripts:FindFirstChild("PlayerModule")
		if modulo and modulo:IsA("ModuleScript") then
			return (require :: any)(modulo):GetControls()
		end
		return nil
	end)
	return if ok then resultado else nil
end

-- Cierra el probador y deja todo como estaba. Se puede llamar más de una vez.
local function cerrar()
	if not abierta then
		return
	end
	abierta = false
	sesion += 1
	for _, c in conexiones do
		c:Disconnect()
	end
	table.clear(conexiones)
	if tweenEntrada then
		tweenEntrada:Cancel()
		tweenEntrada = nil
	end
	quitarClon()
	seleccion, piezaId, presupuesto, pedidoId = nil, nil, nil, nil
	table.clear(cambiosPorItem)
	portapapeles = nil
	pConfirmar.Visible = false
	raiz.Visible = false

	local camara = Workspace.CurrentCamera
	local original = camaraOriginal
	if camara and original then
		camara.CameraType = original.Tipo
		camara.CameraSubject = original.Sujeto :: any
		camara.FieldOfView = original.Fov
	end
	camaraOriginal = nil
	if controles then
		pcall(function()
			controles:Enable()
		end)
		controles = nil
	end
	NetworkBridge.Client.Fire("PersonalizadorCerrar")
end

local function elegirConClic(posicion: Vector3)
	local camara = Workspace.CurrentCamera
	local modelo = clon
	if not camara or not modelo then
		return
	end
	local rayo = camara:ScreenPointToRay(posicion.X, posicion.Y)
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Include
	filtro.FilterDescendantsInstances = { modelo }
	local golpe = Workspace:Raycast(rayo.Origin, rayo.Direction * 100, filtro)
	if not golpe then
		return
	end
	for id, parte in mapa do
		if parte == golpe.Instance then
			elegirPieza(id)
			return
		end
	end
end

local function abrir(posicion: Vector3, categoriaNpc: string?)
	if abierta then
		cerrar()
	end
	local camara = Workspace.CurrentCamera
	local r = raizPersonaje()
	local personaje = jugador.Character
	local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")
	if not camara or not r or not humanoide or humanoide.Health <= 0 then
		return
	end
	abierta = true
	sesion += 1
	posicionNpc = posicion
	if categoriaNpc == "Armas" or categoriaNpc == "Armaduras" then
		categoria = categoriaNpc
	end
	botonArmas.Visible = categoriaNpc == nil or categoriaNpc == "Armas"
	botonArmaduras.Visible = categoriaNpc == nil or categoriaNpc == "Armaduras"

	camaraOriginal =
		{ Tipo = camara.CameraType, Sujeto = camara.CameraSubject, Fov = camara.FieldOfView, CFrame = camara.CFrame }
	-- Arranca mirando al avatar de frente.
	local frente = r.CFrame.LookVector
	giro = math.deg(math.atan2(frente.X, frente.Z))
	distancia = CAM.Distancia
	camara.CameraType = Enum.CameraType.Scriptable
	mezcla.Value = 0
	local entrada = TweenService:Create(
		mezcla,
		TweenInfo.new(CAM.Transicion, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	tweenEntrada = entrada
	entrada:Play()
	controles = controlesDelJugador()
	if controles then
		pcall(function()
			controles:Disable()
		end)
	end

	-- Arrastre para girar; un toque corto elige la pieza.
	local arrastrando: InputObject? = nil
	local ultimaX, recorrido = 0, 0
	table.insert(
		conexiones,
		zona.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				arrastrando, ultimaX, recorrido = input, input.Position.X, 0
			end
		end)
	)
	table.insert(
		conexiones,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			local activo = arrastrando
			if not activo then
				return
			end
			local esMouse = activo.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			if esMouse or input == activo then
				local dx = input.Position.X - ultimaX
				ultimaX = input.Position.X
				recorrido += math.abs(dx)
				giro -= dx * CAM.GradosPorPixel
			end
		end)
	)
	table.insert(
		conexiones,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			local activo = arrastrando
			if activo and (input == activo or input.UserInputType == activo.UserInputType) then
				arrastrando = nil
				if recorrido < 6 then
					elegirConClic(input.Position)
				end
			end
		end)
	)
	table.insert(
		conexiones,
		zona.InputChanged:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				acercar(-input.Position.Z)
			end
		end)
	)

	-- Cámara y motivos de cierre, una vez por frame mientras esté abierto.
	table.insert(
		conexiones,
		RunService.RenderStepped:Connect(function()
			local actualRaiz = raizPersonaje()
			local npc = posicionNpc
			if not actualRaiz or not npc or (actualRaiz.Position - npc).Magnitude > Config.DistanciaMaxima then
				cerrar() -- se alejó del vendedor o se quedó sin personaje
				return
			end
			local destino = destinoCamara()
			local original = camaraOriginal
			local actualCamara = Workspace.CurrentCamera
			if destino and original and actualCamara then
				actualCamara.CFrame = original.CFrame:Lerp(destino, mezcla.Value)
				actualCamara.FieldOfView = original.Fov + (CAM.CampoVision - original.Fov) * mezcla.Value
			end
		end)
	)
	table.insert(conexiones, humanoide.Died:Connect(cerrar))
	table.insert(conexiones, jugador.CharacterAdded:Connect(cerrar))
	table.insert(conexiones, jugador.CharacterRemoving:Connect(cerrar))
	table.insert(
		conexiones,
		EstadoCliente.Cambio:Connect(function(campo: string)
			if campo == "Oro" or campo == "Nivel" or campo == "*" then
				actualizarCompra()
			end
		end)
	)

	llenarCatalogo()
	llenarMateriales()
	elegirItem(nil)
	raiz.Visible = true
	UIKit.EnfocarPrimero(pCatalogo)
end

botonIzq.Activated:Connect(function()
	giro += 30
end)
botonDer.Activated:Connect(function()
	giro -= 30
end)
botonMas.Activated:Connect(function()
	acercar(-1.5)
end)
botonMenos.Activated:Connect(function()
	acercar(1.5)
end)
botonCancelar.Activated:Connect(cerrar)

NetworkBridge.Client.OnEvent("PersonalizadorAbrir", function(posicion: any, categoriaNpc: any)
	if typeof(posicion) ~= "Vector3" then
		return
	end
	local ok, err = pcall(function(): nil
		abrir(posicion, if typeof(categoriaNpc) == "string" then categoriaNpc else nil)
		return nil
	end)
	if not ok then
		warn(`[Personalizador] No se pudo abrir el probador: {err}`)
		cerrar() -- ante un error, no dejar la cámara ni los controles tomados
	end
end)
