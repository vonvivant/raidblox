--!strict
-- ParcelasUI: la ventana del Arquitecto de Viviendas (NPC-033).
--
-- Muestra los barrios y sus parcelas con su estado, y desde ahí se compra, se
-- paga el alquiler, se ponen permisos, se renombra, se fusiona y se abandona.
-- Nada se decide acá: cada botón manda un pedido y el servidor contesta con el
-- estado nuevo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage.Configs.ParcelasConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local jugador = Players.LocalPlayer
local gui = UIKit.Gui("ParcelasUI", 45)
local ventana, contenido = UIKit.Ventana(gui, "Parcelas", UDim2.fromScale(0.58, 0.7))
ventana.Visible = false

local barrioElegido: string? = nil
local parcelaElegida: string? = nil
local ultimas: { any } = {}
local pidiendo = false

local pestanas = Instance.new("Frame")
pestanas.BackgroundTransparency = 1
pestanas.Size = UDim2.new(1, 0, 0, 30)
pestanas.Parent = contenido
local filaPestanas = Instance.new("UIListLayout")
filaPestanas.FillDirection = Enum.FillDirection.Horizontal
filaPestanas.Padding = UDim.new(0, 6)
filaPestanas.Parent = pestanas

local lista = UIKit.Lista(contenido, UDim2.new(0.52, -6, 1, -40), UDim2.fromOffset(0, 36))
local panel = Instance.new("Frame")
panel.BackgroundColor3 = UIKit.Colores.Panel
panel.BackgroundTransparency = 0.25
panel.Position = UDim2.new(0.52, 6, 0, 36)
panel.Size = UDim2.new(0.48, -6, 1, -40)
UIKit.Esquinas(panel, 8)
panel.Parent = contenido

local titulo = UIKit.Texto(panel, "Elegí una parcela", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 8))
titulo.TextXAlignment = Enum.TextXAlignment.Left
local detalle = UIKit.Texto(panel, "", UDim2.new(1, -16, 0, 96), UDim2.fromOffset(8, 34))
detalle.TextXAlignment = Enum.TextXAlignment.Left
detalle.TextYAlignment = Enum.TextYAlignment.Top
detalle.TextWrapped = true
detalle.TextColor3 = UIKit.Colores.TextoSuave

local acciones = Instance.new("Frame")
acciones.BackgroundTransparency = 1
acciones.Position = UDim2.fromOffset(8, 136)
acciones.Size = UDim2.new(1, -16, 1, -144)
acciones.Parent = panel
local filaAcciones = Instance.new("UIListLayout")
filaAcciones.Padding = UDim.new(0, 6)
filaAcciones.Parent = acciones

local refrescar: () -> ()

local function pedir(accion: string, id: string, extra: any?)
	if pidiendo then
		return
	end
	pidiendo = true
	task.spawn(function()
		local respuesta = NetworkBridge.Client.Invoke("ParcelaAccion", accion, id, extra)
		pidiendo = false
		if respuesta and respuesta.Success then
			refrescar()
		end
	end)
end

local function boton(texto: string, color: Color3, alApretar: () -> ())
	local b = UIKit.Boton(acciones, texto, UDim2.new(1, 0, 0, 30), nil, color)
	b.Activated:Connect(alApretar)
end

local function fecha(hasta: number): string
	local faltan = hasta - os.time()
	if faltan <= 0 then
		return "vencido"
	end
	local dias = math.floor(faltan / 86400)
	if dias >= 1 then
		return `{dias} día(s)`
	end
	return `{math.max(1, math.floor(faltan / 3600))} h`
end

local function dibujarPanel(parcela: { [string]: any }?)
	UIKit.Limpiar(acciones)
	local filaNueva = Instance.new("UIListLayout")
	filaNueva.Padding = UDim.new(0, 6)
	filaNueva.Parent = acciones

	if not parcela then
		titulo.Text = "Elegí una parcela"
		detalle.Text =
			`El alquiler sale {CFG.AlquilerDiario} de oro por día. Podés tener hasta {CFG.MaxPorJugador} parcelas.`
		return
	end
	local id = tostring(parcela.Id)
	local barrio = CFG.Barrio(tostring(parcela.Barrio))
	titulo.Text = `{if barrio then barrio.Nombre else parcela.Barrio} #{tostring(parcela.Numero)}`

	if parcela.Estado == "Libre" then
		detalle.Text =
			`Libre.\nPrecio: {tostring(parcela.Precio)} de oro.\nIncluye {CFG.DiasAlCompar} días de alquiler.\n{if barrio
				then barrio.Descripcion
				else ""}`
		boton(`Comprar por ${tostring(parcela.Precio)}`, UIKit.Colores.BotonPrimario, function()
			pedir("Comprar", id)
		end)
		return
	end

	local lineas = {
		`Dueño: {tostring(parcela.Dueno)}`,
		if parcela.Nombre then `Nombre: {parcela.Nombre}` else "Sin nombre",
		`Alquiler: {fecha(tonumber(parcela.Hasta) or 0)}`,
	}
	if parcela.Fusion then
		table.insert(lineas, `Fusionada con: {table.concat(parcela.Fusion, ", ")}`)
	end
	if parcela.MiPermiso then
		table.insert(lineas, `Tu permiso: {parcela.MiPermiso}`)
	end
	detalle.Text = table.concat(lineas, "\n")

	if parcela.EsMia ~= true then
		return
	end

	local dias = tonumber(parcela.DiasQuePuedePagar) or 0
	if dias >= 1 then
		boton(`Pagar 1 día (${CFG.Alquiler(1)})`, UIKit.Colores.Boton, function()
			pedir("Alquiler", id, 1)
		end)
	end
	if dias >= 7 then
		boton(`Pagar 7 días (${CFG.Alquiler(7)})`, UIKit.Colores.Boton, function()
			pedir("Alquiler", id, 7)
		end)
	end

	-- Renombrar
	local entrada = UIKit.Entrada(acciones, "Nombre de la casa", UDim2.new(1, 0, 0, 28))
	boton("Renombrar", UIKit.Colores.Boton, function()
		local nombre = entrada.Text
		if #nombre > 0 then
			pedir("Renombrar", id, nombre)
		end
	end)

	-- Permisos: por nombre de alguien que esté en el servidor.
	local quien = UIKit.Entrada(acciones, "Nombre de un jugador", UDim2.new(1, 0, 0, 28))
	for _, permiso in CFG.Permisos do
		boton(`Dar permiso: {permiso.Nombre}`, UIKit.Colores.Boton, function()
			local otro = Players:FindFirstChild(quien.Text)
			if not otro or not otro:IsA("Player") then
				return
			end
			pedir("Permiso", id, { Usuario = otro.UserId, Nivel = permiso.Id })
		end)
	end
	boton("Quitar permiso", UIKit.Colores.BotonPeligro, function()
		local otro = Players:FindFirstChild(quien.Text)
		if otro and otro:IsA("Player") then
			pedir("Permiso", id, { Usuario = otro.UserId })
		end
	end)

	-- Fusionar con una vecina propia.
	for _, otra in ultimas do
		local datos: { [string]: any } = otra
		if datos.EsMia == true and CFG.Fusionables(id, tostring(datos.Id)) then
			boton(`Fusionar con #{tostring(datos.Numero)}`, UIKit.Colores.BotonPrimario, function()
				pedir("Fusionar", id, tostring(datos.Id))
			end)
		end
	end

	boton("Abandonar la parcela", UIKit.Colores.BotonPeligro, function()
		pedir("Abandonar", id)
	end)
end

local function dibujarLista()
	UIKit.Limpiar(lista)
	for _, entrada in ultimas do
		local datos: { [string]: any } = entrada
		if barrioElegido and datos.Barrio ~= barrioElegido then
			continue
		end
		local etiqueta = if datos.EsMia == true
			then "TUYA"
			elseif datos.Estado == "Libre" then `${tostring(datos.Precio)}`
			elseif datos.Estado == "Vencida" then "vencida"
			else tostring(datos.Dueno)
		local color = if datos.EsMia == true
			then UIKit.Colores.BotonPrimario
			elseif datos.Estado == "Libre" then UIKit.Colores.Boton
			else UIKit.Colores.Panel
		local fila = UIKit.Boton(lista, `#{tostring(datos.Numero)} · {etiqueta}`, UDim2.new(1, -8, 0, 28), nil, color)
		fila.Activated:Connect(function()
			parcelaElegida = tostring(datos.Id)
			dibujarPanel(datos)
		end)
	end
end

refrescar = function()
	task.spawn(function()
		local respuesta = NetworkBridge.Client.Invoke("ParcelaListar", barrioElegido)
		if not respuesta or not respuesta.Success or typeof(respuesta.Data) ~= "table" then
			return
		end
		local datos: { [string]: any } = respuesta.Data
		ultimas = if typeof(datos.Parcelas) == "table" then datos.Parcelas else {}
		dibujarLista()
		-- Mantener abierto el detalle de la que estaba mirando.
		local elegida: { [string]: any }? = nil
		for _, entrada in ultimas do
			local uno: { [string]: any } = entrada
			if tostring(uno.Id) == parcelaElegida then
				elegida = uno
			end
		end
		dibujarPanel(elegida)
	end)
end

local function armarPestanas()
	UIKit.Limpiar(pestanas)
	local fila = Instance.new("UIListLayout")
	fila.FillDirection = Enum.FillDirection.Horizontal
	fila.Padding = UDim.new(0, 6)
	fila.Parent = pestanas
	for _, barrio in CFG.Barrios do
		local b = UIKit.Boton(
			pestanas,
			barrio.Nombre,
			UDim2.fromOffset(150, 28),
			nil,
			if barrioElegido == barrio.Id then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		b.Activated:Connect(function()
			barrioElegido = barrio.Id
			parcelaElegida = nil
			armarPestanas()
			refrescar()
		end)
	end
end

NetworkBridge.Client.OnEvent("ParcelaPanel", function(abrir: any)
	if abrir ~= true then
		ventana.Visible = false
		return
	end
	if not barrioElegido then
		barrioElegido = CFG.Barrios[1].Id
	end
	armarPestanas()
	refrescar()
	ventana.Visible = true
end)

-- Mientras la ventana está abierta, el estado se actualiza solo: otro jugador
-- puede comprar una parcela en este mismo momento.
task.spawn(function()
	while true do
		task.wait(10)
		if ventana.Visible and jugador.Parent == Players then
			refrescar()
		end
	end
end)
