--!strict
-- NpcUI: ventana genérica de los NPCs por arquetipo (NpcArquetiposConfig).
-- El servidor la abre al hablar con un NPC; la ventana arma una sección por
-- cada servicio que tenga: viajes, fabricación, servicios, venta y compra.
-- Todo lo que se toca acá es un pedido: el servidor valida y decide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NpcArquetiposConfig = require(ReplicatedStorage.Configs.NpcArquetiposConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local ItemInfo = require(ReplicatedStorage.Modules.ItemInfo)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

type Arquetipo = NpcArquetiposConfig.Arquetipo

local DISTANCIA_CIERRE = NpcArquetiposConfig.DistanciaInteraccion + 4
local NOMBRES_ESTACION: { [string]: string } = {
	Yunque = "Yunque",
	MesaAlquimia = "Mesa de Alquimia",
	Telar = "Telar",
}

local jugador = Players.LocalPlayer
local gui = UIKit.Gui("NpcUI", 63)
local ventana, contenido = UIKit.Ventana(gui, "NPC", UDim2.fromScale(0.46, 0.66))
local tituloVentana = ventana:FindFirstChildOfClass("TextLabel")

local descripcion = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 40))
descripcion.Font = Enum.Font.Gotham
descripcion.TextColor3 = UIKit.Colores.TextoSuave
descripcion.TextXAlignment = Enum.TextXAlignment.Left
descripcion.TextWrapped = true
local saldo = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 42))
saldo.TextXAlignment = Enum.TextXAlignment.Right
saldo.TextColor3 = UIKit.Colores.Oro
local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -70), UDim2.fromOffset(0, 68))

type Sesion = { NpcId: string, Arquetipo: Arquetipo, Faccion: string, Posicion: Vector3?, Destinos: { any } }
local sesion: Sesion? = nil
local ocupado = false -- un pedido a la vez

local function oro(): number
	local v = EstadoCliente.Get("Oro")
	return if typeof(v) == "number" then v else 0
end

local function honor(): number
	local v = EstadoCliente.Get("PuntosHonor")
	return if typeof(v) == "number" then v else 0
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
-- Piezas
------------------------------------------------------------------------

local orden = 0

local function encabezado(texto: string)
	orden += 1
	local t = UIKit.Texto(lista, texto, UDim2.new(1, 0, 0, 24))
	t.LayoutOrder = orden
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = UIKit.Colores.Oro
end

local function nota(texto: string)
	orden += 1
	local t = UIKit.Texto(lista, texto, UDim2.new(1, 0, 0, 40))
	t.LayoutOrder = orden
	t.Font = Enum.Font.Gotham
	t.TextColor3 = UIKit.Colores.TextoSuave
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
end

-- Fila con título, detalle y hasta dos botones a la derecha.
local function fila(titulo: string, detalle: string, color: Color3?): Frame
	orden += 1
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 54)
	f.BackgroundColor3 = UIKit.Colores.Fondo
	f.LayoutOrder = orden
	UIKit.Esquinas(f, 6)
	local t = UIKit.Texto(f, titulo, UDim2.new(0.56, 0, 0, 24), UDim2.fromOffset(8, 4))
	t.TextXAlignment = Enum.TextXAlignment.Left
	if color then
		t.TextColor3 = color
	end
	local d = UIKit.Texto(f, detalle, UDim2.new(0.56, 0, 0, 20), UDim2.fromOffset(8, 30))
	d.Font = Enum.Font.Gotham
	d.TextColor3 = UIKit.Colores.TextoSuave
	d.TextXAlignment = Enum.TextXAlignment.Left
	f.Parent = lista
	return f
end

local function boton(f: Frame, texto: string, columna: number, activo: boolean, alTocar: () -> ())
	local b = UIKit.Boton(
		f,
		texto,
		UDim2.new(0.19, 0, 0, 36),
		UDim2.new(0.59 + 0.205 * (columna - 1), 0, 0, 9),
		if activo then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
	)
	b.Activated:Connect(alTocar)
end

------------------------------------------------------------------------
-- Secciones
------------------------------------------------------------------------

local redibujar: () -> ()

local function seccionViajes(s: Sesion)
	encabezado("Destinos")
	if #s.Destinos == 0 then
		nota("No hay destinos disponibles desde acá.")
	end
	for _, destino in s.Destinos do
		if typeof(destino) ~= "table" then
			continue
		end
		local territorio = if destino.Territorio == "Neutral" then "zona libre" else `territorio {destino.Territorio}`
		local f = fila(
			destino.Nombre,
			`Nivel {destino.NivelMinimo}  ·  {territorio}`,
			NpcArquetiposConfig.ColoresFaccion[destino.Territorio]
		)
		boton(f, `Viajar ({destino.Costo} oro)`, 1.5, oro() >= destino.Costo, function()
			if pedir("NpcViajar", s.NpcId, destino.Id) then
				ventana.Visible = false
			end
		end)
	end
end

local function seccionFabricar(s: Sesion, estacion: string)
	encabezado("Fabricación")
	local f = fila(NOMBRES_ESTACION[estacion] or estacion, "Usá mis herramientas para fabricar.")
	boton(f, "Fabricar", 1.5, true, function()
		if pedir("NpcFabricar", s.NpcId) then
			ventana.Visible = false
		end
	end)
end

local function seccionServicios(s: Sesion)
	encabezado("Servicios")
	local servicios: { NpcArquetiposConfig.Servicio } = s.Arquetipo.Servicios or {}
	for _, servicio in servicios do
		local disponible = servicio.Accion ~= nil
		local costo = if servicio.Costo > 0 then `{servicio.Costo} oro` else "Gratis"
		local f = fila(servicio.Nombre, servicio.Descripcion)
		boton(f, if disponible then costo else "Próximamente", 1.5, disponible and oro() >= servicio.Costo, function()
			if disponible and pedir("NpcServicio", s.NpcId, servicio.Id) and servicio.Accion == "Subasta" then
				ventana.Visible = false
			end
		end)
	end
end

local function seccionVenta(s: Sesion)
	encabezado("En venta")
	local ofertas: { NpcArquetiposConfig.Oferta } = s.Arquetipo.Vende or {}
	for indice, oferta in ofertas do
		local def = ItemCatalog[oferta.ItemId]
		if not def or (oferta.Solo and oferta.Solo ~= s.Faccion) then
			continue
		end
		local conHonor = oferta.Moneda == "Honor"
		local moneda = if conHonor then "honor" else "oro"
		local tengo = if conHonor then honor() else oro()
		local f = fila(def.Nombre, `{oferta.Precio} {moneda} c/u`)
		boton(f, "Comprar", 1, tengo >= oferta.Precio, function()
			pedir("NpcComprar", s.NpcId, indice, 1)
		end)
		if def.Apilable then
			boton(f, "x10", 2, tengo >= oferta.Precio * 10, function()
				pedir("NpcComprar", s.NpcId, indice, 10)
			end)
		end
	end
end

local function seccionCompra(s: Sesion, compra: { Factor: number, Tipos: { string } })
	encabezado("Vender de tu mochila")
	local inv = EstadoCliente.Get("Inventario")
	local claves: { string } = {}
	if typeof(inv) == "table" and typeof(inv.Slots) == "table" then
		for clave, item in inv.Slots do
			local def = ItemCatalog[item.ItemId]
			if def and def.PrecioVenta > 0 and table.find(compra.Tipos, def.Tipo) then
				table.insert(claves, clave)
			end
		end
	end
	table.sort(claves, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	if #claves == 0 then
		nota("No tenés nada que me interese.")
	end
	for _, clave in claves do
		local item = inv.Slots[clave]
		local def = ItemCatalog[item.ItemId]
		local precio = math.floor(def.PrecioVenta * compra.Factor)
		local f = fila(`{ItemInfo.Nombre(item)} x{item.Cantidad}`, `{precio} oro c/u`, ItemInfo.Color(item))
		boton(f, "Vender 1", 1, true, function()
			pedir("NpcVender", s.NpcId, clave, 1)
		end)
		if item.Cantidad > 1 then
			boton(f, "Todo", 2, true, function()
				pedir("NpcVender", s.NpcId, clave, item.Cantidad)
			end)
		end
	end
end

redibujar = function()
	local s = sesion
	if not s then
		return
	end
	UIKit.Limpiar(lista)
	orden = 0
	local a = s.Arquetipo
	saldo.Text = `Oro: {oro()}   ·   Honor: {honor()}`

	if a.Estado == "Pendiente" then
		encabezado("Próximamente")
		local requiere = a.Parametros.Requiere
		nota(
			if typeof(requiere) == "string"
				then `Todavía no atiendo. Falta: {requiere}.`
				else "Todavía no atiendo. Volvé más adelante."
		)
		return
	end
	if a.Estado == "Parcial" and a.Sistema then
		encabezado("Por ahora")
		nota(`Esto ya lo podés usar desde: {a.Sistema}.`)
	end
	if a.Viajes then
		seccionViajes(s)
	end
	if a.Estacion then
		seccionFabricar(s, a.Estacion)
	end
	if a.Servicios then
		seccionServicios(s)
	end
	if a.Vende then
		seccionVenta(s)
	end
	if a.Compra then
		seccionCompra(s, a.Compra)
	end
end

------------------------------------------------------------------------
-- Apertura y cierre
------------------------------------------------------------------------

NetworkBridge.Client.OnEvent("NpcAbrir", function(npcId: any, arquetipoId: any, faccion: any, datos: any)
	if typeof(npcId) ~= "string" or typeof(arquetipoId) ~= "string" or typeof(faccion) ~= "string" then
		return
	end
	local arquetipo = NpcArquetiposConfig.Arquetipos[arquetipoId]
	if not arquetipo then
		return
	end
	local extra = if typeof(datos) == "table" then datos else {}
	sesion = {
		NpcId = npcId,
		Arquetipo = arquetipo,
		Faccion = faccion,
		Posicion = if typeof(extra.Posicion) == "Vector3" then extra.Posicion else nil,
		Destinos = if typeof(extra.Destinos) == "table" then extra.Destinos else {},
	}
	if tituloVentana then
		tituloVentana.Text = if faccion == "Neutral" then arquetipo.Nombre else `{arquetipo.Nombre} ({faccion})`
		tituloVentana.TextColor3 = NpcArquetiposConfig.ColoresFaccion[faccion] or UIKit.Colores.Texto
	end
	descripcion.Text = arquetipo.Descripcion
	redibujar()
	ventana.Visible = true
	UIKit.EnfocarPrimero(ventana)
end)

EstadoCliente.Cambio:Connect(function(campo: string)
	if ventana.Visible and (campo == "Oro" or campo == "Honor" or campo == "Inventario" or campo == "*") then
		redibujar()
	end
end)

-- Si el jugador se aleja del NPC, la ventana se cierra sola.
task.spawn(function()
	while true do
		task.wait(0.5)
		local s = sesion
		if ventana.Visible and s and s.Posicion then
			local personaje = jugador.Character
			local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
			if raiz and raiz:IsA("BasePart") and (raiz.Position - s.Posicion).Magnitude > DISTANCIA_CIERRE then
				ventana.Visible = false
			end
		end
	end
end)
