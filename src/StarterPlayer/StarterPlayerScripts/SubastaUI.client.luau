--!strict
-- SubastaUI: Casa de Subastas (buscar y comprar, vender, mis publicaciones).
-- Se abre desde el tablón de la Casa de Subastas. Todas las operaciones las
-- decide el servidor (precios, depósito, impuesto, disponibilidad).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local ItemRarityConfig = require(ReplicatedStorage.Configs.ItemRarityConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local ItemInfo = require(ReplicatedStorage.Modules.ItemInfo)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local CFG = GameConfig.Subastas

local gui = UIKit.Gui("SubastaUI", 64)
local ventana, contenido = UIKit.Ventana(gui, "Casa de Subastas", UDim2.fromScale(0.6, 0.7))

-- Pestañas
local pestanas = Instance.new("Frame")
pestanas.Size = UDim2.new(1, 0, 0, 36)
pestanas.BackgroundTransparency = 1
pestanas.Parent = contenido
local layoutPestanas = Instance.new("UIListLayout")
layoutPestanas.FillDirection = Enum.FillDirection.Horizontal
layoutPestanas.Padding = UDim.new(0, 6)
layoutPestanas.Parent = pestanas

local cuerpo = Instance.new("Frame")
cuerpo.Position = UDim2.fromOffset(0, 44)
cuerpo.Size = UDim2.new(1, 0, 1, -44)
cuerpo.BackgroundTransparency = 1
cuerpo.Parent = contenido

local vistas: { [string]: Frame } = {}
local function vista(nombre: string): Frame
	local f = Instance.new("Frame")
	f.Name = nombre
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.Parent = cuerpo
	vistas[nombre] = f
	return f
end

local function fila(
	lista: ScrollingFrame,
	orden: number,
	texto: string,
	color: Color3,
	boton: string?,
	colorBoton: Color3?
): TextButton?
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 44)
	f.BackgroundColor3 = UIKit.Colores.Fondo
	f.LayoutOrder = orden
	UIKit.Esquinas(f, 6)
	local t = UIKit.Texto(f, texto, UDim2.new(if boton then 0.72 else 0.98, 0, 1, -8), UDim2.fromOffset(8, 4))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color
	local b: TextButton? = nil
	if boton then
		b = UIKit.Boton(f, boton, UDim2.new(0.25, 0, 1, -10), UDim2.new(0.74, 0, 0, 5), colorBoton)
	end
	f.Parent = lista
	return b
end

------------------------------------------------------------------------
-- Buscar
------------------------------------------------------------------------

local vBuscar = vista("Buscar")
local caja = UIKit.Entrada(vBuscar, "Buscar por nombre…", UDim2.new(0.5, 0, 0, 34))
local rarezaFiltro: string? = nil
local botonRareza = UIKit.Boton(vBuscar, "Todas las rarezas", UDim2.new(0.25, -6, 0, 34), UDim2.new(0.5, 6, 0, 0))
local botonBuscar =
	UIKit.Boton(vBuscar, "Buscar", UDim2.new(0.25, -12, 0, 34), UDim2.new(0.75, 12, 0, 0), UIKit.Colores.BotonPrimario)
local listaBuscar = UIKit.Lista(vBuscar, UDim2.new(1, 0, 1, -44), UDim2.fromOffset(0, 44))

local ORDEN_RAREZAS = { "Comun", "Raro", "Epico", "Mistico", "Unico" }
botonRareza.Activated:Connect(function()
	local i = if rarezaFiltro then table.find(ORDEN_RAREZAS, rarezaFiltro) else 0
	local siguiente = (i or 0) + 1
	rarezaFiltro = ORDEN_RAREZAS[siguiente]
	botonRareza.Text = if rarezaFiltro then ItemRarityConfig.Rarezas[rarezaFiltro].Nombre else "Todas las rarezas"
end)

local function buscar()
	UIKit.Limpiar(listaBuscar)
	local r = NetworkBridge.Client.Invoke("SubastaBuscar", caja.Text, rarezaFiltro or "")
	if not r.Success or typeof(r.Data) ~= "table" then
		Avisos.Mostrar("No se pudo buscar en la Casa de Subastas.", "Error")
		return
	end
	if #r.Data == 0 then
		fila(listaBuscar, 1, "No hay publicaciones que coincidan.", UIKit.Colores.TextoSuave)
		return
	end
	for i, p in r.Data do
		local b = fila(
			listaBuscar,
			i,
			`{ItemInfo.Corto(p.Item)}  ·  {p.Precio} oro  ·  {p.Vendedor}`,
			ItemInfo.Color(p.Item),
			"Comprar",
			UIKit.Colores.BotonPrimario
		)
		if b then
			b.Activated:Connect(function()
				local compra = NetworkBridge.Client.Invoke("SubastaComprar", p.Id)
				if compra.Success then
					buscar()
				end
			end)
		end
	end
end
botonBuscar.Activated:Connect(buscar)
caja.FocusLost:Connect(function(enter: boolean)
	if enter then
		buscar()
	end
end)

------------------------------------------------------------------------
-- Vender
------------------------------------------------------------------------

local vVender = vista("Vender")
local ayuda = UIKit.Texto(
	vVender,
	`Elegí un objeto y su precio. Depósito: {math.floor(CFG.Deposito * 100)}% (no se devuelve). Impuesto al vender: {math.floor(
		CFG.Impuesto * 100
	)}%.`,
	UDim2.new(1, 0, 0, 30)
)
ayuda.Font = Enum.Font.Gotham
ayuda.TextColor3 = UIKit.Colores.TextoSuave
local precio = UIKit.Entrada(vVender, "Precio en oro", UDim2.new(0.3, 0, 0, 34), UDim2.fromOffset(0, 36))
local resumenVenta = UIKit.Texto(vVender, "", UDim2.new(0.68, 0, 0, 34), UDim2.new(0.32, 0, 0, 36))
resumenVenta.Font = Enum.Font.Gotham
resumenVenta.TextXAlignment = Enum.TextXAlignment.Left
local listaVender = UIKit.Lista(vVender, UDim2.new(1, 0, 1, -80), UDim2.fromOffset(0, 80))

local function actualizarResumen()
	local p = tonumber(precio.Text)
	if not p or p < CFG.PrecioMinimo then
		resumenVenta.Text = ""
		return
	end
	p = math.floor(p)
	local deposito = math.max(1, math.floor(p * CFG.Deposito))
	local neto = p - math.floor(p * CFG.Impuesto)
	resumenVenta.Text = `Depósito: {deposito} oro  ·  Si se vende recibís: {neto} oro`
end
precio:GetPropertyChangedSignal("Text"):Connect(actualizarResumen)

local function redibujarVender()
	UIKit.Limpiar(listaVender)
	local inv = EstadoCliente.Get("Inventario")
	if typeof(inv) ~= "table" then
		return
	end
	local orden = 0
	for i = 1, inv.MaxSlots do
		local item = inv.Slots[tostring(i)]
		if item then
			orden += 1
			local b = fila(
				listaVender,
				orden,
				ItemInfo.Corto(item),
				ItemInfo.Color(item),
				"Publicar",
				UIKit.Colores.BotonPrimario
			)
			if b then
				local uid = item.Uid
				b.Activated:Connect(function()
					local p = tonumber(precio.Text)
					if not p then
						Avisos.Mostrar("Escribí un precio.", "Error")
						return
					end
					NetworkBridge.Client.Invoke("SubastaPublicar", uid, math.floor(p))
				end)
			end
		end
	end
end

------------------------------------------------------------------------
-- Mis publicaciones
------------------------------------------------------------------------

local vMias = vista("Mias")
local listaMias = UIKit.Lista(vMias, UDim2.fromScale(1, 1))

local ESTADOS: { [string]: string } = {
	Activa = "Activa",
	Vendida = "Vendida",
	Cancelada = "Cancelada",
	Expirada = "Vencida (devuelta)",
}

local function redibujarMias()
	UIKit.Limpiar(listaMias)
	local r = NetworkBridge.Client.Invoke("SubastaMias")
	if not r.Success or typeof(r.Data) ~= "table" then
		Avisos.Mostrar("No se pudieron cargar tus publicaciones.", "Error")
		return
	end
	if #r.Data == 0 then
		fila(listaMias, 1, "No tenés publicaciones.", UIKit.Colores.TextoSuave)
		return
	end
	for i, p in r.Data do
		local activa = p.Estado == "Activa"
		local horas = math.max(0, math.floor((p.Expira - os.time()) / 3600))
		local texto = `{ItemInfo.Corto(p.Item)}  ·  {p.Precio} oro  ·  {ESTADOS[p.Estado] or p.Estado}{if activa
			then ` (vence en {horas} h)`
			else ""}`
		local b = fila(
			listaMias,
			i,
			texto,
			ItemInfo.Color(p.Item),
			if activa then "Cancelar" else nil,
			UIKit.Colores.BotonPeligro
		)
		if b then
			b.Activated:Connect(function()
				local c = NetworkBridge.Client.Invoke("SubastaCancelar", p.Id)
				if c.Success then
					redibujarMias()
				end
			end)
		end
	end
end

------------------------------------------------------------------------
-- Navegación
------------------------------------------------------------------------

local function mostrar(nombre: string)
	for n, f in vistas do
		f.Visible = n == nombre
	end
	if nombre == "Buscar" then
		buscar()
	elseif nombre == "Vender" then
		redibujarVender()
	elseif nombre == "Mias" then
		redibujarMias()
	end
end

for orden, par in { { "Buscar", "Comprar" }, { "Vender", "Vender" }, { "Mias", "Mis publicaciones" } } do
	local b = UIKit.Boton(pestanas, par[2], UDim2.new(0.32, 0, 1, 0))
	b.LayoutOrder = orden
	b.Activated:Connect(function()
		mostrar(par[1])
	end)
end

EstadoCliente.Cambio:Connect(function(campo: string)
	if ventana.Visible and vistas.Vender.Visible and (campo == "Inventario" or campo == "*") then
		redibujarVender()
	end
end)

NetworkBridge.Client.OnEvent("SubastaAbrir", function()
	ventana.Visible = true
	mostrar("Buscar")
	UIKit.EnfocarPrimero(ventana)
end)
