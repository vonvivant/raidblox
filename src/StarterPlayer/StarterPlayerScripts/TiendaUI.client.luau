--!strict
-- TiendaUI: tienda (Fase 6). Botón "🛒 Tienda" del menú lateral.
--
-- Pestañas:
--   Pases       permanentes (6.1); con el Título Personalizado se escribe acá.
--   Productos   booster, pack de inicio, fichas y cajas (6.2). Cada caja
--               muestra sus probabilidades ANTES de comprar.
--   Mis fichas  usar fichas de re-roll (equipo de la mochila) y de bando.
-- La compra la abre el servidor; en modo pruebas lo que no tiene Id se simula.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local ItemInfo = require(ReplicatedStorage.Modules.ItemInfo)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local MenuLateral = require(ReplicatedStorage.Modules.MenuLateral)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local DORADO = Color3.fromRGB(255, 213, 74)
local VIOLETA = Color3.fromRGB(90, 70, 140)

local gui = UIKit.Gui("TiendaUI", 63)
local ventana, contenido = UIKit.Ventana(gui, "Tienda", UDim2.fromScale(0.56, 0.78))

local abrir = Instance.new("TextButton")
abrir.Name = "BotonTienda"
abrir.BackgroundColor3 = Color3.fromRGB(110, 80, 20)
abrir.TextColor3 = Color3.new(1, 1, 1)
abrir.Font = Enum.Font.GothamBold
abrir.TextScaled = true
abrir.Text = "🛒 Tienda"
UIKit.Esquinas(abrir, 6)
MenuLateral.Agregar(abrir, 4)

local barra = Instance.new("Frame")
barra.Size = UDim2.new(1, 0, 0, 34)
barra.BackgroundTransparency = 1
barra.Parent = contenido
local layoutBarra = Instance.new("UIListLayout")
layoutBarra.FillDirection = Enum.FillDirection.Horizontal
layoutBarra.Padding = UDim.new(0, 6)
layoutBarra.SortOrder = Enum.SortOrder.LayoutOrder
layoutBarra.Parent = barra

local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -42), UDim2.fromOffset(0, 42))
local vista = "Pases"
local botonesVista: { [string]: TextButton } = {}
local recargar: () -> ()

for i, nombre in { "Pases", "Productos", "Mis fichas" } do
	local b = UIKit.Boton(barra, nombre, UDim2.new(0.3, 0, 1, 0))
	b.LayoutOrder = i
	botonesVista[nombre] = b
	b.Activated:Connect(function()
		vista = nombre
		recargar()
	end)
end

local orden = 0
local function tarjeta(alto: number): Frame
	orden += 1
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, alto)
	f.BackgroundColor3 = UIKit.Colores.Fondo
	f.LayoutOrder = orden
	UIKit.Esquinas(f, 8)
	f.Parent = lista
	return f
end

local function encabezado(f: Frame, nombre: string, descripcion: string)
	local t = UIKit.Texto(f, nombre, UDim2.new(0.66, 0, 0, 24), UDim2.fromOffset(10, 6))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = DORADO
	local d = UIKit.Texto(f, descripcion, UDim2.new(0.66, 0, 0, 38), UDim2.fromOffset(10, 32))
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.TextYAlignment = Enum.TextYAlignment.Top
	d.TextWrapped = true
	d.TextColor3 = UIKit.Colores.TextoSuave
end

local function porcentaje(p: number): string
	local v = p * 100
	return if v < 1 then string.format("%.1f%%", v) else string.format("%d%%", math.floor(v + 0.5))
end

------------------------------------------------------------------------
-- Pases
------------------------------------------------------------------------

local function dibujarPases(datos: any)
	local pases = datos.Pases
	table.sort(pases, function(a: any, b: any): boolean
		return a.Orden < b.Orden
	end)
	for _, p in pases do
		local f = tarjeta(if p.Clave == "TituloPersonal" and p.Tengo then 112 else 76)
		encabezado(f, p.Nombre, p.Descripcion)
		local texto: string
		local color: Color3 = UIKit.Colores.BotonPrimario
		if p.Tengo then
			texto = if p.Simulable then "Tenés (quitar)" else "✔ Lo tenés"
			color = UIKit.Colores.Boton
		elseif p.ALaVenta then
			texto = if p.Precio then `R$ {p.Precio}` else "Comprar"
		elseif p.Simulable then
			texto = "Simular (pruebas)"
			color = VIOLETA
		else
			texto = "Próximamente"
			color = UIKit.Colores.Boton
		end
		local b = UIKit.Boton(f, texto, UDim2.new(0.3, 0, 0, 36), UDim2.new(0.68, 0, 0, 20), color)
		local clave = p.Clave
		if (not p.Tengo and (p.ALaVenta or p.Simulable)) or (p.Tengo and p.Simulable) then
			b.Activated:Connect(function()
				local r = NetworkBridge.Client.Invoke("TiendaComprarPase", clave)
				if r.Success then
					task.delay(if p.ALaVenta then 2 else 0.2, recargar)
				end
			end)
		end
		if p.Clave == "TituloPersonal" and p.Tengo then
			local caja =
				UIKit.Entrada(f, "Tu título (hasta 24 letras)", UDim2.new(0.62, 0, 0, 30), UDim2.fromOffset(10, 74))
			caja.Text = datos.Titulo or ""
			local guardar = UIKit.Boton(f, "Guardar título", UDim2.new(0.3, 0, 0, 30), UDim2.new(0.68, 0, 0, 74))
			guardar.Activated:Connect(function()
				NetworkBridge.Client.Invoke("TiendaGuardarTitulo", caja.Text)
			end)
		end
	end
end

------------------------------------------------------------------------
-- Productos y cajas
------------------------------------------------------------------------

local function dibujarProductos(datos: any)
	if datos.BoosterHasta and datos.BoosterHasta > datos.Ahora then
		local f = tarjeta(34)
		local restante = datos.BoosterHasta - datos.Ahora
		local t = UIKit.Texto(
			f,
			`⚡ Booster activo: 2× experiencia por {restante // 60} min más`,
			UDim2.new(1, -16, 1, -8),
			UDim2.fromOffset(8, 4)
		)
		t.TextColor3 = DORADO
	end
	if datos.CajasRestringidas then
		local f = tarjeta(34)
		local t = UIKit.Texto(
			f,
			"Las cajas aleatorias no están disponibles en tu país.",
			UDim2.new(1, -16, 1, -8),
			UDim2.fromOffset(8, 4)
		)
		t.TextColor3 = UIKit.Colores.TextoSuave
	end
	local productos = datos.Productos
	table.sort(productos, function(a: any, b: any): boolean
		return a.Orden < b.Orden
	end)
	for _, p in productos do
		local probs = p.Probabilidades
		local lineas = 0
		if probs then
			lineas = #probs.Items + (if #probs.Rarezas > 0 then #probs.Rarezas + 1 else 0) + 1
		end
		local f = tarjeta(76 + lineas * 17)
		encabezado(f, p.Nombre, p.Descripcion)
		local texto: string
		local color: Color3 = UIKit.Colores.BotonPrimario
		local activo = true
		if p.Agotado then
			texto = "✔ Ya lo compraste"
			color = UIKit.Colores.Boton
			activo = false
		elseif p.ALaVenta then
			texto = if p.Precio then `R$ {p.Precio}` else "Comprar"
		elseif p.Simulable then
			texto = "Simular (pruebas)"
			color = VIOLETA
		else
			texto = "Próximamente"
			color = UIKit.Colores.Boton
			activo = false
		end
		local b = UIKit.Boton(f, texto, UDim2.new(0.3, 0, 0, 36), UDim2.new(0.68, 0, 0, 20), color)
		if activo then
			local clave = p.Clave
			b.Activated:Connect(function()
				local r = NetworkBridge.Client.Invoke("TiendaComprarProducto", clave)
				if r.Success then
					task.delay(if p.ALaVenta then 3 else 0.3, recargar)
				end
			end)
		end
		if probs then
			-- Probabilidades a la vista antes de comprar.
			local y = 74
			local function linea(contenidoLinea: string, colorLinea: Color3?)
				local t = UIKit.Texto(f, contenidoLinea, UDim2.new(1, -20, 0, 16), UDim2.fromOffset(14, y))
				t.TextXAlignment = Enum.TextXAlignment.Left
				t.TextColor3 = colorLinea or UIKit.Colores.Texto
				y += 17
			end
			linea(`Probabilidades (para cada uno de los {probs.Tiradas} ítems):`, DORADO)
			for _, it in probs.Items do
				local cantidad = if it.Min == it.Max then `x{it.Min}` else `x{it.Min}-{it.Max}`
				linea(`  {it.Nombre} {cantidad}: {porcentaje(it.Probabilidad)}`)
			end
			if #probs.Rarezas > 0 then
				linea("Rareza:", DORADO)
				for _, r in probs.Rarezas do
					linea(`  {r.Nombre}: {porcentaje(r.Probabilidad)}`)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Mis fichas
------------------------------------------------------------------------

local function dibujarFichas(datos: any)
	local fichas = datos.Fichas
	local f = tarjeta(60)
	encabezado(
		f,
		`Fichas de Re-roll: {fichas.Reroll}`,
		`Calidad nueva entre x{datos.Reroll.MinFactor} y x{datos.Reroll.MaxFactor} de su rareza; los efectos se tiran de nuevo en su rango.`
	)
	local inv = EstadoCliente.Get("Inventario")
	if inv then
		for clave, item in inv.Slots do
			local def = ItemCatalog[item.ItemId]
			if not def or def.Tipo ~= "Equipo" then
				continue
			end
			local fila = tarjeta(40)
			local meta = item.Meta
			local mult = if typeof(meta) == "table" and typeof(meta.Mult) == "number" then ` (x{meta.Mult})` else ""
			local t = UIKit.Texto(fila, ItemInfo.Corto(item) .. mult, UDim2.new(0.6, 0, 1, -8), UDim2.fromOffset(10, 4))
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.TextColor3 = ItemInfo.Color(item)
			local b = UIKit.Boton(fila, "Re-roll", UDim2.new(0.3, 0, 1, -8), UDim2.new(0.68, 0, 0, 4), VIOLETA)
			local c = clave
			b.Activated:Connect(function()
				if fichas.Reroll > 0 then
					NetworkBridge.Client.Invoke("TiendaUsarReroll", c)
					task.delay(0.3, recargar)
				else
					Avisos.Mostrar("No tenés fichas de re-roll.", "Error")
				end
			end)
		end
	end
	local fb = tarjeta(84)
	encabezado(fb, `Fichas de Cambio de Bando: {fichas.Bando}`, "Elegí tu nuevo bando:")
	for i, bando in { "Rojo", "Azul", "Violeta" } do
		local b = UIKit.Boton(
			fb,
			bando,
			UDim2.new(0.3, -6, 0, 30),
			UDim2.new((i - 1) * 0.32, 10, 0, 48),
			if bando == "Rojo"
				then Color3.fromRGB(170, 50, 50)
				elseif bando == "Azul" then Color3.fromRGB(50, 80, 170)
				else Color3.fromRGB(120, 70, 170)
		)
		b.Activated:Connect(function()
			if fichas.Bando > 0 then
				NetworkBridge.Client.Invoke("TiendaUsarBando", bando)
				task.delay(0.3, recargar)
			else
				Avisos.Mostrar("No tenés fichas de cambio de bando.", "Error")
			end
		end)
	end
end

------------------------------------------------------------------------
-- Recargar
------------------------------------------------------------------------

local cargando = false
recargar = function()
	if cargando or not ventana.Visible then
		return
	end
	cargando = true
	for nombre, b in botonesVista do
		b.BackgroundColor3 = if nombre == vista then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
	end
	local r = NetworkBridge.Client.Invoke(if vista == "Pases" then "TiendaInfo" else "TiendaProductos")
	cargando = false
	UIKit.Limpiar(lista)
	orden = 0
	if not r.Success then
		Avisos.Mostrar("No se pudo abrir la tienda.", "Error")
		return
	end
	if vista == "Pases" then
		dibujarPases(r.Data)
	elseif vista == "Productos" then
		dibujarProductos(r.Data)
	else
		dibujarFichas(r.Data)
	end
end

abrir.Activated:Connect(function()
	ventana.Visible = not ventana.Visible
	if ventana.Visible then
		task.spawn(recargar)
		UIKit.EnfocarPrimero(ventana)
	end
end)

------------------------------------------------------------------------
-- Caja abierta: muestra lo que salió
------------------------------------------------------------------------

local revelado = Instance.new("Frame")
revelado.AnchorPoint = Vector2.new(0.5, 0.5)
revelado.Position = UDim2.fromScale(0.5, 0.45)
revelado.Size = UDim2.fromScale(0.34, 0.36)
revelado.BackgroundColor3 = UIKit.Colores.Fondo
revelado.Visible = false
UIKit.Esquinas(revelado, 12)
revelado.Parent = gui
local tituloRevelado = UIKit.Texto(revelado, "", UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 8))
tituloRevelado.TextColor3 = DORADO
local listaRevelado = UIKit.Lista(revelado, UDim2.new(1, -16, 1, -90), UDim2.fromOffset(8, 44))
local cerrarRevelado =
	UIKit.Boton(revelado, "¡Genial!", UDim2.new(0.4, 0, 0, 32), UDim2.new(0.3, 0, 1, -40), UIKit.Colores.BotonPrimario)
cerrarRevelado.Activated:Connect(function()
	revelado.Visible = false
end)

NetworkBridge.Client.OnEvent("TiendaCajaAbierta", function(nombre: any, items: any)
	if typeof(nombre) ~= "string" or typeof(items) ~= "table" then
		return
	end
	tituloRevelado.Text = `{nombre}: ¡te salió!`
	UIKit.Limpiar(listaRevelado)
	for i, item in items do
		local t = UIKit.Texto(listaRevelado, ItemInfo.Corto(item), UDim2.new(1, 0, 0, 26))
		t.TextColor3 = ItemInfo.Color(item)
		t.LayoutOrder = i
	end
	revelado.Visible = true
	if ventana.Visible then
		task.delay(0.3, recargar)
	end
end)
