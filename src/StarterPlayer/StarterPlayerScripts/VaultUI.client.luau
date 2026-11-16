--!strict
-- VaultUI: ventana de la bóveda global.
--
-- * Izquierda: pestañas, buscador, filtros y las 30 ranuras de la pestaña.
--   Con texto en el buscador o un filtro puesto, muestra los resultados de
--   todas las pestañas.
-- * Derecha: la mochila.
-- * Un clic selecciona (y muestra el detalle); Shift + clic, doble clic o doble
--   toque pasa la pila entera al otro lado. Con un ítem de la bóveda elegido,
--   tocar otra ranura lo mueve o intercambia, y tocar otra pestaña lo manda ahí.
-- El servidor valida todo: acá solo se piden las operaciones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ItemRarityConfig = require(ReplicatedStorage.Configs.ItemRarityConfig)
local VaultConfig = require(ReplicatedStorage.Configs.VaultConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local ItemInfo = require(ReplicatedStorage.Modules.ItemInfo)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local RANURAS = VaultConfig.RanurasPorPestana
local DOBLE_CLIC = 0.35 -- segundos

local CATEGORIAS = { "Todo", "Material", "Consumible", "Equipo", "Herramienta", "Cosmetico" }
local RAREZAS: { string } = { "Todas" }
do
	local ids: { string } = {}
	for id in ItemRarityConfig.Rarezas do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return ItemRarityConfig.Rarezas[a].Orden < ItemRarityConfig.Rarezas[b].Orden
	end)
	for _, id in ids do
		table.insert(RAREZAS, id)
	end
end

local gui = UIKit.Gui("VaultUI", 64)
local ventana, contenido = UIKit.Ventana(gui, "Bóveda", UDim2.fromScale(0.82, 0.8))

------------------------------------------------------------------------
-- Estado
------------------------------------------------------------------------

type Seleccion = { Lado: "Vault" | "Mochila", Pestana: number, Ranura: string }

local disponibles = VaultConfig.PestanasIniciales
local pestanaActual = 1
local categoria = 1
local rareza = 1
local seleccion: Seleccion? = nil
local ultimoClic = { Clave = "", Momento = 0 }
local ocupado = false

local function vault(): any
	local v = EstadoCliente.Get("Vault")
	return if typeof(v) == "table" then v else nil
end

local function pestana(numero: number): any
	local v = vault()
	local p = if v and typeof(v.Pestanas) == "table" then v.Pestanas[tostring(numero)] else nil
	return if typeof(p) == "table" then p else nil
end

local function itemVault(numero: number, ranura: string): any
	local p = pestana(numero)
	return if p and typeof(p.Slots) == "table" then p.Slots[ranura] else nil
end

local function mochila(): any
	local inv = EstadoCliente.Get("Inventario")
	return if typeof(inv) == "table" and typeof(inv.Slots) == "table" then inv else nil
end

local function compradas(): number
	local v = vault()
	return if v and typeof(v.Compradas) == "number" then v.Compradas else VaultConfig.PestanasIniciales
end

local function pedir(remoto: string, ...: any): boolean
	if ocupado then
		return false
	end
	ocupado = true
	local r = NetworkBridge.Client.Invoke(remoto, ...)
	ocupado = false
	return r.Success
end

------------------------------------------------------------------------
-- Armado
------------------------------------------------------------------------

local izquierda = Instance.new("Frame")
izquierda.Size = UDim2.fromScale(0.62, 1)
izquierda.BackgroundTransparency = 1
izquierda.Parent = contenido

local derecha = Instance.new("Frame")
derecha.Size = UDim2.fromScale(0.36, 1)
derecha.Position = UDim2.fromScale(0.64, 0)
derecha.BackgroundTransparency = 1
derecha.Parent = contenido

-- Fila de pestañas
local filaPestanas = Instance.new("Frame")
filaPestanas.Size = UDim2.new(1, 0, 0, 40)
filaPestanas.BackgroundTransparency = 1
filaPestanas.Parent = izquierda
local botonesPestana: { TextButton } = {}
for i = 1, VaultConfig.MaxPestanas do
	local ancho = 1 / VaultConfig.MaxPestanas
	local b = UIKit.Boton(filaPestanas, "", UDim2.new(ancho, -4, 1, 0), UDim2.fromScale(ancho * (i - 1), 0))
	botonesPestana[i] = b
end

-- Nombre, ícono y compra
local filaNombre = Instance.new("Frame")
filaNombre.Size = UDim2.new(1, 0, 0, 32)
filaNombre.Position = UDim2.fromOffset(0, 46)
filaNombre.BackgroundTransparency = 1
filaNombre.Parent = izquierda
local botonIcono = UIKit.Boton(filaNombre, VaultConfig.Iconos[1], UDim2.new(0.1, -4, 1, 0))
local entradaNombre =
	UIKit.Entrada(filaNombre, "Nombre de la pestaña", UDim2.new(0.5, -4, 1, 0), UDim2.fromScale(0.1, 0))
local botonComprar =
	UIKit.Boton(filaNombre, "", UDim2.new(0.4, 0, 1, 0), UDim2.fromScale(0.6, 0), UIKit.Colores.BotonPrimario)

-- Buscador y filtros
local filaFiltros = Instance.new("Frame")
filaFiltros.Size = UDim2.new(1, 0, 0, 32)
filaFiltros.Position = UDim2.fromOffset(0, 84)
filaFiltros.BackgroundTransparency = 1
filaFiltros.Parent = izquierda
local buscador = UIKit.Entrada(filaFiltros, "Buscar por nombre o autor…", UDim2.new(0.5, -4, 1, 0))
local botonCategoria = UIKit.Boton(filaFiltros, "", UDim2.new(0.25, -4, 1, 0), UDim2.fromScale(0.5, 0))
local botonRareza = UIKit.Boton(filaFiltros, "", UDim2.new(0.25, 0, 1, 0), UDim2.fromScale(0.75, 0))

-- Grilla de la bóveda
local grilla = UIKit.Lista(izquierda, UDim2.new(1, 0, 1, -216), UDim2.fromOffset(0, 122))
local layoutLista = grilla:FindFirstChildOfClass("UIListLayout")
if layoutLista then
	layoutLista:Destroy()
end
local layoutGrilla = Instance.new("UIGridLayout")
layoutGrilla.CellSize = UDim2.new(1 / VaultConfig.Columnas, -6, 0, 58)
layoutGrilla.CellPadding = UDim2.fromOffset(6, 6)
layoutGrilla.SortOrder = Enum.SortOrder.LayoutOrder
layoutGrilla.Parent = grilla

-- Detalle
local detalle = Instance.new("Frame")
detalle.Size = UDim2.new(1, 0, 0, 88)
detalle.Position = UDim2.new(0, 0, 1, -88)
detalle.BackgroundColor3 = UIKit.Colores.Panel
detalle.BackgroundTransparency = 0.3
detalle.Parent = izquierda
UIKit.Esquinas(detalle, 8)
local tituloDetalle = UIKit.Texto(detalle, "", UDim2.new(0.7, -12, 0, 24), UDim2.fromOffset(8, 4))
tituloDetalle.TextXAlignment = Enum.TextXAlignment.Left
local textoDetalle = UIKit.Texto(detalle, "", UDim2.new(0.7, -12, 1, -32), UDim2.fromOffset(8, 28))
textoDetalle.TextScaled = false
textoDetalle.TextSize = 13
textoDetalle.TextWrapped = true
textoDetalle.Font = Enum.Font.Gotham
textoDetalle.TextColor3 = UIKit.Colores.TextoSuave
textoDetalle.TextXAlignment = Enum.TextXAlignment.Left
textoDetalle.TextYAlignment = Enum.TextYAlignment.Top
local botonAccion =
	UIKit.Boton(detalle, "", UDim2.new(0.3, -8, 0, 34), UDim2.new(0.7, 0, 0, 8), UIKit.Colores.BotonPrimario)
local botonUno = UIKit.Boton(detalle, "Solo 1", UDim2.new(0.3, -8, 0, 30), UDim2.new(0.7, 0, 0, 50))

-- Mochila
local tituloMochila = UIKit.Texto(derecha, "Mochila", UDim2.new(1, 0, 0, 28))
tituloMochila.TextXAlignment = Enum.TextXAlignment.Left
local ayuda =
	UIKit.Texto(derecha, "Shift + clic o doble toque: pasar la pila", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 28))
ayuda.Font = Enum.Font.Gotham
ayuda.TextColor3 = UIKit.Colores.TextoSuave
ayuda.TextXAlignment = Enum.TextXAlignment.Left
local grillaMochila = UIKit.Lista(derecha, UDim2.new(1, 0, 1, -52), UDim2.fromOffset(0, 52))
local layoutMochila = grillaMochila:FindFirstChildOfClass("UIListLayout")
if layoutMochila then
	layoutMochila:Destroy()
end
local gridMochila = Instance.new("UIGridLayout")
gridMochila.CellSize = UDim2.new(0.25, -6, 0, 58)
gridMochila.CellPadding = UDim2.fromOffset(6, 6)
gridMochila.SortOrder = Enum.SortOrder.LayoutOrder
gridMochila.Parent = grillaMochila

------------------------------------------------------------------------
-- Filtros
------------------------------------------------------------------------

local function filtrando(): boolean
	return buscador.Text ~= "" or categoria ~= 1 or rareza ~= 1
end

local function coincide(item: any): boolean
	local def = ItemCatalog[item.ItemId]
	if not def then
		return false
	end
	if categoria ~= 1 and def.Tipo ~= CATEGORIAS[categoria] then
		return false
	end
	if rareza ~= 1 and item.Rareza ~= RAREZAS[rareza] then
		return false
	end
	local texto = string.lower(buscador.Text)
	if texto == "" then
		return true
	end
	if string.find(string.lower(def.Nombre), texto, 1, true) then
		return true
	end
	local autor = if typeof(item.Meta) == "table" then item.Meta[VaultConfig.MetaAutor] else nil
	return typeof(autor) == "string" and string.find(string.lower(autor), texto, 1, true) ~= nil
end

------------------------------------------------------------------------
-- Operaciones
------------------------------------------------------------------------

local redibujar: () -> ()

local function depositar(ranura: string, cantidad: number)
	seleccion = nil
	pedir("VaultDepositar", ranura, pestanaActual, cantidad)
end

local function retirar(numero: number, ranura: string, cantidad: number)
	seleccion = nil
	pedir("VaultRetirar", numero, tonumber(ranura), cantidad)
end

-- ¿Pasar la pila entera? Shift apretado o segundo clic rápido sobre lo mismo.
local function esRapido(clave: string): boolean
	local ahora = os.clock()
	local doble = ultimoClic.Clave == clave and ahora - ultimoClic.Momento <= DOBLE_CLIC
	ultimoClic.Clave = clave
	ultimoClic.Momento = ahora
	return doble
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function alTocarVault(numero: number, ranura: string)
	local item = itemVault(numero, ranura)
	local s = seleccion
	if item and esRapido(`V{numero}:{ranura}`) then
		retirar(numero, ranura, item.Cantidad)
		return
	end
	if s and s.Lado == "Vault" and not filtrando() and (s.Pestana ~= numero or s.Ranura ~= ranura) then
		seleccion = nil
		pedir("VaultMover", s.Pestana, tonumber(s.Ranura), numero, tonumber(ranura))
		return
	end
	if s and s.Lado == "Mochila" and not item then
		local origen = mochila()
		local deMochila = if origen then origen.Slots[s.Ranura] else nil
		if deMochila then
			depositar(s.Ranura, deMochila.Cantidad)
			return
		end
	end
	seleccion = if item then { Lado = "Vault" :: "Vault", Pestana = numero, Ranura = ranura } else nil
	redibujar()
end

local function alTocarMochila(ranura: string)
	local inv = mochila()
	local item = if inv then inv.Slots[ranura] else nil
	if not item then
		return
	end
	if esRapido(`M{ranura}`) then
		depositar(ranura, item.Cantidad)
		return
	end
	seleccion = { Lado = "Mochila" :: "Mochila", Pestana = 0, Ranura = ranura }
	redibujar()
end

------------------------------------------------------------------------
-- Dibujo
------------------------------------------------------------------------

local function celda(padre: Instance, orden: number, item: any, elegido: boolean, pie: string?): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = orden
	b.BackgroundColor3 = if elegido then UIKit.Colores.Boton else UIKit.Colores.Fondo
	b.AutoButtonColor = true
	b.Selectable = true
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextWrapped = true
	b.Text = if item then ItemInfo.Corto(item) else ""
	b.TextColor3 = if item then ItemInfo.Color(item) else UIKit.Colores.TextoSuave
	local limite = Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = 13
	limite.Parent = b
	local margen = Instance.new("UIPadding")
	margen.PaddingLeft = UDim.new(0, 3)
	margen.PaddingRight = UDim.new(0, 3)
	margen.PaddingBottom = UDim.new(0, if pie then 12 else 2)
	margen.Parent = b
	UIKit.Esquinas(b, 6)
	if elegido then
		local borde = Instance.new("UIStroke")
		borde.Color = UIKit.Colores.Oro
		borde.Thickness = 2
		borde.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		borde.Parent = b
	end
	if pie then
		local t = UIKit.Texto(b, pie, UDim2.new(1, 0, 0, 11), UDim2.new(0, 0, 1, 0))
		t.Font = Enum.Font.Gotham
		t.TextColor3 = UIKit.Colores.TextoSuave
	end
	b.Parent = padre
	return b
end

local function dibujarPestanas()
	for i, b in botonesPestana do
		local p = pestana(i)
		if i <= disponibles then
			b.Text = if p and typeof(p.Icono) == "string" then p.Icono else VaultConfig.Iconos[1]
			b.BackgroundColor3 = if i == pestanaActual then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		else
			b.Text = "🔒"
			b.BackgroundColor3 = UIKit.Colores.Fondo
		end
	end
	local p = pestana(pestanaActual)
	botonIcono.Text = if p and typeof(p.Icono) == "string" then p.Icono else VaultConfig.Iconos[1]
	if not entradaNombre:IsFocused() then
		entradaNombre.Text = if p and typeof(p.Nombre) == "string" then p.Nombre else `Pestaña {pestanaActual}`
	end
	local costo = VaultConfig.CostoPestana[compradas()]
	if disponibles >= VaultConfig.MaxPestanas or not costo then
		botonComprar.Text = "Todas las pestañas"
		botonComprar.BackgroundColor3 = UIKit.Colores.Boton
	else
		botonComprar.Text = `+ Pestaña ({costo} oro)`
		botonComprar.BackgroundColor3 = UIKit.Colores.BotonPrimario
	end
	botonCategoria.Text = `Tipo: {CATEGORIAS[categoria]}`
	local r = ItemRarityConfig.Rarezas[RAREZAS[rareza]]
	botonRareza.Text = `Rareza: {if r then r.Nombre else "Todas"}`
end

local function dibujarDetalle()
	local s = seleccion
	local item: any = nil
	if s and s.Lado == "Vault" then
		item = itemVault(s.Pestana, s.Ranura)
	elseif s then
		local inv = mochila()
		item = if inv then inv.Slots[s.Ranura] else nil
	end
	if not s or not item then
		seleccion = nil
		tituloDetalle.Text = "Elegí un objeto"
		tituloDetalle.TextColor3 = UIKit.Colores.Texto
		textoDetalle.Text = ""
		botonAccion.Visible = false
		botonUno.Visible = false
		return
	end
	tituloDetalle.Text = ItemInfo.Corto(item)
	tituloDetalle.TextColor3 = ItemInfo.Color(item)
	textoDetalle.Text = string.gsub(ItemInfo.Detalle(item), "\n", "  ·  ")
	botonAccion.Visible = true
	botonAccion.Text = if s.Lado == "Vault" then "Retirar todo" else "Guardar todo"
	botonUno.Visible = item.Cantidad > 1
end

redibujar = function()
	if not ventana.Visible then
		return
	end
	dibujarPestanas()
	UIKit.Limpiar(grilla)
	local s = seleccion
	if filtrando() then
		-- Resultados de todas las pestañas desbloqueadas.
		local orden = 0
		for numero = 1, disponibles do
			for i = 1, RANURAS do
				local ranura = tostring(i)
				local item = itemVault(numero, ranura)
				if item and coincide(item) then
					orden += 1
					local elegido = s ~= nil and s.Lado == "Vault" and s.Pestana == numero and s.Ranura == ranura
					celda(grilla, orden, item, elegido, `Pestaña {numero}`).Activated:Connect(function()
						alTocarVault(numero, ranura)
					end)
				end
			end
		end
	else
		for i = 1, RANURAS do
			local ranura = tostring(i)
			local item = itemVault(pestanaActual, ranura)
			local elegido = s ~= nil and s.Lado == "Vault" and s.Pestana == pestanaActual and s.Ranura == ranura
			celda(grilla, i, item, elegido, nil).Activated:Connect(function()
				alTocarVault(pestanaActual, ranura)
			end)
		end
	end

	UIKit.Limpiar(grillaMochila)
	local inv = mochila()
	if inv then
		for clave, item in inv.Slots do
			local elegido = s ~= nil and s.Lado == "Mochila" and s.Ranura == clave
			celda(grillaMochila, tonumber(clave) or 0, item, elegido, nil).Activated:Connect(function()
				alTocarMochila(clave)
			end)
		end
	end
	dibujarDetalle()
end

------------------------------------------------------------------------
-- Controles
------------------------------------------------------------------------

for i, b in botonesPestana do
	b.Activated:Connect(function()
		if i > disponibles then
			return
		end
		local s = seleccion
		if s and s.Lado == "Vault" and s.Pestana ~= i then
			-- Con un ítem elegido, tocar otra pestaña lo manda ahí.
			seleccion = nil
			pedir("VaultMover", s.Pestana, tonumber(s.Ranura), i, 0)
			return
		end
		pestanaActual = i
		seleccion = nil
		redibujar()
	end)
end

botonComprar.Activated:Connect(function()
	if disponibles >= VaultConfig.MaxPestanas then
		return
	end
	local r = NetworkBridge.Client.Invoke("VaultExpandir")
	if r.Success and typeof(r.Data) == "table" and typeof(r.Data.Disponibles) == "number" then
		disponibles = r.Data.Disponibles
		redibujar()
	end
end)

local function guardarPersonalizacion(icono: string)
	local nombre = entradaNombre.Text
	if nombre == "" then
		nombre = `Pestaña {pestanaActual}`
	end
	pedir("VaultPersonalizar", pestanaActual, nombre, icono)
end

botonIcono.Activated:Connect(function()
	local actual = table.find(VaultConfig.Iconos, botonIcono.Text) or 0
	guardarPersonalizacion(VaultConfig.Iconos[actual % #VaultConfig.Iconos + 1])
end)

entradaNombre.FocusLost:Connect(function(enter: boolean)
	local p = pestana(pestanaActual)
	local actual = if p and typeof(p.Nombre) == "string" then p.Nombre else `Pestaña {pestanaActual}`
	if enter and entradaNombre.Text ~= actual then
		guardarPersonalizacion(botonIcono.Text)
	else
		entradaNombre.Text = actual
	end
end)

buscador:GetPropertyChangedSignal("Text"):Connect(function()
	seleccion = nil
	redibujar()
end)
botonCategoria.Activated:Connect(function()
	categoria = categoria % #CATEGORIAS + 1
	seleccion = nil
	redibujar()
end)
botonRareza.Activated:Connect(function()
	rareza = rareza % #RAREZAS + 1
	seleccion = nil
	redibujar()
end)

local function accionSeleccion(todo: boolean)
	local s = seleccion
	if not s then
		return
	end
	if s.Lado == "Vault" then
		local item = itemVault(s.Pestana, s.Ranura)
		if item then
			retirar(s.Pestana, s.Ranura, if todo then item.Cantidad else 1)
		end
	else
		local inv = mochila()
		local item = if inv then inv.Slots[s.Ranura] else nil
		if item then
			depositar(s.Ranura, if todo then item.Cantidad else 1)
		end
	end
end
botonAccion.Activated:Connect(function()
	accionSeleccion(true)
end)
botonUno.Activated:Connect(function()
	accionSeleccion(false)
end)

------------------------------------------------------------------------
-- Apertura
------------------------------------------------------------------------

NetworkBridge.Client.OnEvent("VaultAbrir", function(cantidad: any)
	disponibles = if typeof(cantidad) == "number" then cantidad else VaultConfig.PestanasIniciales
	pestanaActual = math.clamp(pestanaActual, 1, disponibles)
	seleccion = nil
	buscador.Text = ""
	categoria, rareza = 1, 1
	ventana.Visible = true
	redibujar()
	UIKit.EnfocarPrimero(ventana)
end)

EstadoCliente.Cambio:Connect(function(campo: string)
	if ventana.Visible and (campo == "Vault" or campo == "Inventario" or campo == "*") then
		redibujar()
	end
end)
