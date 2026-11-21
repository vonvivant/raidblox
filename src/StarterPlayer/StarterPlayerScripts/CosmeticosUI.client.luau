--!strict
-- CosmeticosUI: la ventana del NPC Cosméticos (#30).
--
-- Se abre con una **cámara mirando a tu personaje** y dos paneles a los
-- costados, dejando el medio libre: lo que ves en el centro es lo que se va a
-- aplicar.
--
--   * Izquierda: los slots visibles y, debajo, las piezas del objeto elegido.
--   * Derecha: las cuatro pestañas (Visual, Colores, Decals, Marcas) y abajo
--     los botones de aplicar, deshacer y cerrar.
--
-- La vista previa se dibuja sobre el modelo que ya lleva el personaje
-- (`EquipoVisible/<slot>`), con el mismo código que usa el equipo de verdad:
-- `Personalizador.Aplicar`. Nada se guarda hasta que se aprieta Aplicar, y el
-- servidor revalida todo igual.
--
-- La pestaña Visual aplica en el momento, porque cambiar de visual es gratis.
-- Lo único que cuesta es **deshacer**, y el precio se muestra en el botón.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AparienciaEquipoConfig = require(ReplicatedStorage.Configs.AparienciaEquipoConfig)
local CFG = require(ReplicatedStorage.Configs.CosmeticosConfig)
local MonetizacionConfig = require(ReplicatedStorage.Configs.MonetizacionConfig)
local PersonalizadorConfig = require(ReplicatedStorage.Configs.PersonalizadorConfig)
local StencilsConfig = require(ReplicatedStorage.Configs.StencilsConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Personalizador = require(ReplicatedStorage.Modules.Personalizador)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

type Pieza = PersonalizadorConfig.Pieza
type Personalizacion = PersonalizadorConfig.Personalizacion

local jugador = Players.LocalPlayer
local camara = Workspace.CurrentCamera
local gui = UIKit.Gui("CosmeticosUI", 47)

------------------------------------------------------------------------
-- Estado
------------------------------------------------------------------------

local abierto = false
local estado: { [string]: any } = {}
local slotElegido: string? = nil
local piezaElegida: string? = nil
local pestana: string = "Visual"
local grupoDecals: string = StencilsConfig.Grupos[1].Id
-- Cambios sin aplicar, por slot.
local pendientes: { [string]: Personalizacion } = {}
-- Cámara
local anguloCamara = math.rad(CFG.Camara.AnguloInicial)
local distanciaCamara = CFG.Camara.Distancia
local arrastrando = false
local camaraAntes: Enum.CameraType? = nil

------------------------------------------------------------------------
-- Paneles
------------------------------------------------------------------------

local izquierda = Instance.new("Frame")
izquierda.AnchorPoint = Vector2.new(0, 0.5)
izquierda.Position = UDim2.fromScale(0.015, 0.5)
izquierda.Size = UDim2.fromScale(0.2, 0.78)
izquierda.BackgroundColor3 = UIKit.Colores.Fondo
izquierda.BackgroundTransparency = 0.12
izquierda.Visible = false
UIKit.Esquinas(izquierda, 10)
izquierda.Parent = gui

local tituloIzq = UIKit.Texto(izquierda, "Tu equipo", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 8))
tituloIzq.TextColor3 = UIKit.Colores.Oro
tituloIzq.TextXAlignment = Enum.TextXAlignment.Left
local listaSlots = UIKit.Lista(izquierda, UDim2.new(1, -16, 0.4, -40), UDim2.fromOffset(8, 36))
local tituloPiezas = UIKit.Texto(izquierda, "Piezas", UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0.4, 4))
tituloPiezas.TextColor3 = UIKit.Colores.Oro
tituloPiezas.TextXAlignment = Enum.TextXAlignment.Left
local listaPiezas = UIKit.Lista(izquierda, UDim2.new(1, -16, 0.6, -40), UDim2.new(0, 8, 0.4, 30))

local derecha = Instance.new("Frame")
derecha.AnchorPoint = Vector2.new(1, 0.5)
derecha.Position = UDim2.fromScale(0.985, 0.5)
derecha.Size = UDim2.fromScale(0.26, 0.78)
derecha.BackgroundColor3 = UIKit.Colores.Fondo
derecha.BackgroundTransparency = 0.12
derecha.Visible = false
UIKit.Esquinas(derecha, 10)
derecha.Parent = gui

local filaPestanas = Instance.new("Frame")
filaPestanas.BackgroundTransparency = 1
filaPestanas.Position = UDim2.fromOffset(8, 8)
filaPestanas.Size = UDim2.new(1, -16, 0, 28)
filaPestanas.Parent = derecha
local gridPestanas = Instance.new("UIGridLayout")
gridPestanas.CellSize = UDim2.new(0.25, -4, 1, 0)
gridPestanas.CellPadding = UDim2.fromOffset(5, 0)
gridPestanas.Parent = filaPestanas

local ayuda = UIKit.Texto(derecha, "", UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 42))
ayuda.TextWrapped = true
ayuda.TextXAlignment = Enum.TextXAlignment.Left
ayuda.TextColor3 = UIKit.Colores.TextoSuave

local filaGrupos = Instance.new("Frame")
filaGrupos.BackgroundTransparency = 1
filaGrupos.Position = UDim2.fromOffset(8, 86)
filaGrupos.Size = UDim2.new(1, -16, 0, 26)
filaGrupos.Visible = false
filaGrupos.Parent = derecha
local gridGrupos = Instance.new("UIGridLayout")
gridGrupos.CellSize = UDim2.new(0.25, -4, 1, 0)
gridGrupos.CellPadding = UDim2.fromOffset(5, 0)
gridGrupos.Parent = filaGrupos

local lista = UIKit.Lista(derecha, UDim2.new(1, -16, 1, -214), UDim2.fromOffset(8, 118))

local botonAplicar =
	UIKit.Boton(derecha, "Aplicar", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 1, -92), UIKit.Colores.BotonPrimario)
local botonDeshacer = UIKit.Boton(derecha, "Deshacer", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 1, -58))
local botonCerrar =
	UIKit.Boton(derecha, "Cerrar", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -26), UIKit.Colores.BotonPeligro)

------------------------------------------------------------------------
-- Datos del estado
------------------------------------------------------------------------

local function datosSlot(slot: string?): { [string]: any }?
	if not slot then
		return nil
	end
	for _, uno in estado.Slots or {} do
		local d: { [string]: any } = uno
		if d.Slot == slot then
			return d
		end
	end
	return nil
end

-- La personalización guardada del slot (lo que el servidor tiene hoy).
local function guardada(slot: string): Personalizacion
	local d = datosSlot(slot)
	return PersonalizadorConfig.Decodificar(if d then d.Pers else nil) or {}
end

-- La personalización que se está mirando: lo pendiente, o lo guardado.
local function actual(slot: string): Personalizacion
	local p = pendientes[slot]
	if p then
		return p
	end
	return guardada(slot)
end

local function infoPieza(slot: string, piezaId: string): { [string]: any }?
	local d = datosSlot(slot)
	for _, pieza in (if d then d.Piezas else {}) or {} do
		local p: { [string]: any } = pieza
		if p.Id == piezaId then
			return p
		end
	end
	return nil
end

-- Estado visible de una pieza: lo pendiente, lo guardado, o su original.
local function estadoPieza(slot: string, piezaId: string): Pieza?
	local puesta = actual(slot)[piezaId]
	if puesta then
		return puesta
	end
	local info = infoPieza(slot, piezaId)
	if not info then
		return nil
	end
	return { Material = info.Material, Color = info.Color }
end

------------------------------------------------------------------------
-- Vista previa sobre el modelo que ya lleva el personaje
------------------------------------------------------------------------

local function modeloDe(slot: string): Model?
	local personaje = jugador.Character
	local carpeta = personaje and personaje:FindFirstChild("EquipoVisible")
	local modelo = carpeta and carpeta:FindFirstChild(slot)
	return if modelo and modelo:IsA("Model") then modelo else nil
end

-- Entrada falsa con lo que `Personalizador.Aplicar` necesita saber del objeto:
-- el original de cada pieza, para poder volver atrás pieza por pieza.
local function entradaDe(slot: string): Personalizador.Entrada?
	local d = datosSlot(slot)
	if not d or not d.Editable then
		return nil
	end
	local porId: { [string]: any } = {}
	for _, pieza in d.Piezas or {} do
		local p: { [string]: any } = pieza
		porId[p.Id] = { Id = p.Id, Nombre = p.Nombre, Material = p.Material, Color = p.Color, EsMesh = p.EsMesh }
	end
	return {
		ItemId = d.ItemId,
		Nombre = d.Nombre or "",
		Precio = 0,
		Piezas = {},
		PorId = porId :: any,
		Modelo = nil :: any,
	} :: any
end

local function repintar(slot: string)
	local modelo = modeloDe(slot)
	local entrada = entradaDe(slot)
	if not modelo or not entrada then
		return
	end
	Personalizador.Aplicar(entrada, Personalizador.Mapa(modelo), actual(slot))
end

local function repintarTodo()
	for _, uno in estado.Slots or {} do
		local d: { [string]: any } = uno
		if d.Editable then
			repintar(d.Slot)
		end
	end
end

------------------------------------------------------------------------
-- Cámara
------------------------------------------------------------------------

local function tomarCamara()
	if camaraAntes == nil then
		camaraAntes = camara.CameraType
	end
	camara.CameraType = Enum.CameraType.Scriptable
end

local function devolverCamara()
	if camaraAntes ~= nil then
		camara.CameraType = camaraAntes
		camaraAntes = nil
	end
end

local function moverCamara()
	local personaje = jugador.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return
	end
	local foco = raiz.Position + Vector3.new(0, CFG.Camara.Altura, 0)
	local desde = foco
		+ Vector3.new(math.cos(anguloCamara) * distanciaCamara, 1.5, math.sin(anguloCamara) * distanciaCamara)
	camara.CFrame = CFrame.lookAt(desde, foco)
end

------------------------------------------------------------------------
-- Dibujado de las listas
------------------------------------------------------------------------

local dibujar: () -> ()

local function elegirSlot(slot: string)
	slotElegido = slot
	piezaElegida = nil
	dibujar()
end

local function aplicarPendiente()
	local slot = slotElegido
	if not slot or pestana == "Visual" then
		return
	end
	local pendiente = pendientes[slot]
	if not pendiente then
		return
	end
	task.spawn(function()
		local respuesta = NetworkBridge.Client.Invoke("CosmeticosAplicar", pestana, slot, pendiente)
		if respuesta and respuesta.Success then
			pendientes[slot] = nil
		end
		local nuevo = NetworkBridge.Client.Invoke("CosmeticosEstado")
		if nuevo and nuevo.Success and typeof(nuevo.Data) == "table" then
			estado = nuevo.Data
		end
		repintarTodo()
		dibujar()
	end)
end

local function deshacer()
	local slot = slotElegido
	if not slot then
		return
	end
	task.spawn(function()
		local respuesta = NetworkBridge.Client.Invoke("CosmeticosDeshacer", slot)
		if respuesta and respuesta.Success then
			pendientes[slot] = nil
		end
		local nuevo = NetworkBridge.Client.Invoke("CosmeticosEstado")
		if nuevo and nuevo.Success and typeof(nuevo.Data) == "table" then
			estado = nuevo.Data
		end
		repintarTodo()
		dibujar()
	end)
end

-- Guarda un cambio en la pieza elegida y lo muestra al instante.
local function cambiarPieza(cambio: (Pieza) -> Pieza)
	local slot, piezaId = slotElegido, piezaElegida
	if not slot or not piezaId then
		return
	end
	local base = estadoPieza(slot, piezaId)
	if not base then
		return
	end
	local copia: Pieza =
		{ Material = base.Material, Color = base.Color, Stencil = base.Stencil, Relieve = base.Relieve }
	local nueva = cambio(copia)
	local pendiente = pendientes[slot] or table.clone(actual(slot))
	pendiente[piezaId] = nueva
	pendientes[slot] = pendiente
	repintar(slot)
	dibujar()
end

local function dibujarVisual()
	local slot = slotElegido
	if not slot then
		ayuda.Text = "Elegí un slot de la izquierda."
		return
	end
	ayuda.Text =
		"Cambia el aspecto sin tocar las estadísticas. Cambiar entre las que tenés es gratis; las premium se compran con Robux."
	local desbloqueadas: { string } = estado.Apariencias or {}
	local transmog: { [string]: string } = estado.Transmog or {}

	local sin = UIKit.Boton(
		lista,
		"Sin visual (la del objeto)",
		UDim2.new(1, -8, 0, 28),
		nil,
		if transmog[slot] == nil then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
	)
	sin.Activated:Connect(function()
		task.spawn(function()
			NetworkBridge.Client.Invoke("CosmeticosAplicar", "Visual", slot, "")
			local nuevo = NetworkBridge.Client.Invoke("CosmeticosEstado")
			if nuevo and nuevo.Success and typeof(nuevo.Data) == "table" then
				estado = nuevo.Data
			end
			dibujar()
		end)
	end)

	-- Qué skin premium corresponde a cada apariencia, para ofrecer la compra.
	local productoDe: { [string]: { Clave: string, Producto: any } } = {}
	for clave, producto in MonetizacionConfig.Productos do
		if producto.Tipo == "Skin" and producto.Apariencia then
			productoDe[producto.Apariencia] = { Clave = clave, Producto = producto }
		end
	end

	local hay = 0
	for id, apariencia in AparienciaEquipoConfig.Apariencias do
		if apariencia.Slot ~= slot then
			continue
		end
		local tengo = table.find(desbloqueadas, id) ~= nil
		hay += 1
		local premium = productoDe[id]
		-- Premium sin comprar: el botón ofrece la compra en Robux. Si el
		-- producto todavía no tiene id (falta crearlo), se avisa y no se
		-- puede tocar, igual que los decals sin arte.
		if premium and not tengo then
			local sinId = premium.Producto.Id == 0
			local texto = if sinId
				then `{apariencia.Nombre} (próximamente)`
				else `{apariencia.Nombre} · comprar con Robux`
			local boton = UIKit.Boton(
				lista,
				texto,
				UDim2.new(1, -8, 0, 28),
				nil,
				if sinId then UIKit.Colores.Panel else UIKit.Colores.Oro
			)
			boton.AutoButtonColor = not sinId
			boton.Activated:Connect(function()
				if sinId then
					return
				end
				task.spawn(function()
					NetworkBridge.Client.Invoke("TiendaComprarProducto", premium.Clave)
				end)
			end)
			continue
		end
		local texto = if tengo
			then apariencia.Nombre
			elseif premium then `{apariencia.Nombre} (premium)`
			else `{apariencia.Nombre} (bloqueada)`
		local color = if transmog[slot] == id
			then UIKit.Colores.BotonPrimario
			elseif tengo then UIKit.Colores.Boton
			else UIKit.Colores.Panel
		local boton = UIKit.Boton(lista, texto, UDim2.new(1, -8, 0, 28), nil, color)
		boton.AutoButtonColor = tengo
		boton.Activated:Connect(function()
			if not tengo then
				return
			end
			task.spawn(function()
				NetworkBridge.Client.Invoke("CosmeticosAplicar", "Visual", slot, id)
				local nuevo = NetworkBridge.Client.Invoke("CosmeticosEstado")
				if nuevo and nuevo.Success and typeof(nuevo.Data) == "table" then
					estado = nuevo.Data
				end
				dibujar()
			end)
		end)
	end
	if hay == 0 then
		local aviso = UIKit.Texto(lista, "Todavía no hay visuales para este slot.", UDim2.new(1, -8, 0, 40))
		aviso.TextColor3 = UIKit.Colores.TextoSuave
		aviso.TextWrapped = true
	end
end

local function dibujarColores()
	local slot, piezaId = slotElegido, piezaElegida
	if not slot or not piezaId then
		ayuda.Text = "Elegí una pieza de la izquierda para pintarla."
		return
	end
	ayuda.Text = `Pieza "{piezaId}". Elegí un color: se ve en el momento y se guarda al aplicar.`
	for _, hex in PersonalizadorConfig.Paleta do
		local color = Personalizador.ColorDeHex(hex)
		if not color then
			continue
		end
		local boton = UIKit.Boton(lista, "", UDim2.new(1, -8, 0, 24), nil, color)
		boton.Activated:Connect(function()
			cambiarPieza(function(pieza: Pieza): Pieza
				pieza.Color = string.upper(hex)
				return pieza
			end)
		end)
	end
end

local function dibujarDecals()
	local slot, piezaId = slotElegido, piezaElegida
	filaGrupos.Visible = true
	UIKit.Limpiar(filaGrupos)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.25, -4, 1, 0)
	grid.CellPadding = UDim2.fromOffset(5, 0)
	grid.Parent = filaGrupos
	for _, grupo in StencilsConfig.Grupos do
		local boton = UIKit.Boton(
			filaGrupos,
			grupo.Nombre,
			UDim2.new(0.25, -4, 1, 0),
			nil,
			if grupoDecals == grupo.Id then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		boton.Activated:Connect(function()
			grupoDecals = grupo.Id
			dibujar()
		end)
	end

	if not slot or not piezaId then
		ayuda.Text = "Elegí una pieza de la izquierda y después el decal."
		return
	end
	local libros: { string } = estado.Libros or {}
	local puesto = estadoPieza(slot, piezaId)
	local ahora = if puesto and puesto.Stencil then puesto.Stencil.Id else "ninguno"
	ayuda.Text = `Pieza "{piezaId}" · decal actual: {ahora}. Los decals se desbloquean con los libros del Inscriptor.`

	local sin = UIKit.Boton(lista, "Sin decal", UDim2.new(1, -8, 0, 26), nil, UIKit.Colores.Boton)
	sin.Activated:Connect(function()
		cambiarPieza(function(pieza: Pieza): Pieza
			pieza.Stencil = nil
			return pieza
		end)
	end)
	for _, decal in StencilsConfig.DelGrupo(grupoDecals) do
		local permitido = StencilsConfig.Permitido(decal.Id, libros, Pruebas.Activas())
		local falta = if table.find(libros, decal.Libro) == nil
			then " (falta el libro)"
			elseif not StencilsConfig.Disponible(decal, Pruebas.Activas()) then " (falta el arte)"
			else ""
		local boton = UIKit.Boton(
			lista,
			`{decal.Nombre}{falta}`,
			UDim2.new(1, -8, 0, 26),
			nil,
			if ahora == decal.Id then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		boton.AutoButtonColor = permitido
		boton.Activated:Connect(function()
			if not permitido then
				return
			end
			cambiarPieza(function(pieza: Pieza): Pieza
				pieza.Stencil = {
					Id = decal.Id,
					Escala = StencilsConfig.AcomodarEscala(60),
					Opacidad = StencilsConfig.AcomodarOpacidad(100),
				}
				return pieza
			end)
		end)
	end
end

local function dibujarMarcas()
	local slot, piezaId = slotElegido, piezaElegida
	if not slot or not piezaId then
		ayuda.Text = "Elegí una pieza de la izquierda para grabarla."
		return
	end
	local info = infoPieza(slot, piezaId)
	if info and info.EsMesh ~= true then
		ayuda.Text = `La pieza "{piezaId}" no acepta marcas: el relieve solo funciona en piezas que son mallas.`
		return
	end
	local libros: { string } = estado.Libros or {}
	local puesto = estadoPieza(slot, piezaId)
	ayuda.Text =
		`Pieza "{piezaId}" · marca actual: {if puesto and puesto.Relieve then puesto.Relieve else "ninguna"}. La marca reemplaza el aspecto del material.`

	local sin = UIKit.Boton(lista, "Sin marca", UDim2.new(1, -8, 0, 26), nil, UIKit.Colores.Boton)
	sin.Activated:Connect(function()
		cambiarPieza(function(pieza: Pieza): Pieza
			pieza.Relieve = nil
			return pieza
		end)
	end)
	for _, relieve in StencilsConfig.Relieves do
		local permitido = StencilsConfig.RelievePermitido(relieve.Id, libros)
		local falta = if table.find(libros, relieve.Libro) == nil
			then " (falta el libro)"
			elseif not StencilsConfig.RelieveDisponible(relieve) then " (falta el arte)"
			else ""
		local boton = UIKit.Boton(
			lista,
			`{relieve.Nombre}{falta}`,
			UDim2.new(1, -8, 0, 26),
			nil,
			if puesto and puesto.Relieve == relieve.Id then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		boton.AutoButtonColor = permitido
		boton.Activated:Connect(function()
			if not permitido then
				return
			end
			cambiarPieza(function(pieza: Pieza): Pieza
				pieza.Relieve = relieve.Id
				return pieza
			end)
		end)
	end
end

dibujar = function()
	-- Pestañas
	UIKit.Limpiar(filaPestanas)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.25, -4, 1, 0)
	grid.CellPadding = UDim2.fromOffset(5, 0)
	grid.Parent = filaPestanas
	for _, nombre in CFG.Pestanas do
		local boton = UIKit.Boton(
			filaPestanas,
			CFG.NombrePestana[nombre],
			UDim2.new(0.25, -4, 1, 0),
			nil,
			if pestana == nombre then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		boton.Activated:Connect(function()
			pestana = nombre
			dibujar()
		end)
	end

	-- Slots
	UIKit.Limpiar(listaSlots)
	for _, uno in estado.Slots or {} do
		local d: { [string]: any } = uno
		local texto = if d.Nombre
			then `{d.Slot}: {d.Nombre}`
			elseif d.ItemId then `{d.Slot}: {d.ItemId}`
			else `{d.Slot}: vacío`
		local boton = UIKit.Boton(
			listaSlots,
			texto,
			UDim2.new(1, -8, 0, 26),
			nil,
			if slotElegido == d.Slot then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		boton.Activated:Connect(function()
			elegirSlot(d.Slot)
		end)
	end

	-- Piezas del slot elegido
	UIKit.Limpiar(listaPiezas)
	local d = datosSlot(slotElegido)
	if d and d.Editable then
		for _, pieza in d.Piezas or {} do
			local p: { [string]: any } = pieza
			local boton = UIKit.Boton(
				listaPiezas,
				p.Nombre or p.Id,
				UDim2.new(1, -8, 0, 24),
				nil,
				if piezaElegida == p.Id then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
			)
			boton.Activated:Connect(function()
				piezaElegida = p.Id
				dibujar()
			end)
		end
	elseif d then
		local aviso = UIKit.Texto(listaPiezas, "Este objeto no tiene piezas editables.", UDim2.new(1, -8, 0, 40))
		aviso.TextColor3 = UIKit.Colores.TextoSuave
		aviso.TextWrapped = true
	end

	-- Contenido de la pestaña
	UIKit.Limpiar(lista)
	filaGrupos.Visible = false
	if pestana == "Visual" then
		dibujarVisual()
	elseif pestana == "Colores" then
		dibujarColores()
	elseif pestana == "Decals" then
		dibujarDecals()
	else
		dibujarMarcas()
	end

	-- Botones de abajo
	local hayPendiente = slotElegido ~= nil and pendientes[slotElegido] ~= nil
	botonAplicar.Visible = pestana ~= "Visual"
	botonAplicar.Text = if hayPendiente then "Aplicar los cambios" else "Sin cambios por aplicar"
	botonAplicar.AutoButtonColor = hayPendiente
	botonAplicar.BackgroundColor3 = if hayPendiente then UIKit.Colores.BotonPrimario else UIKit.Colores.Panel
	local puedeDeshacer = d ~= nil and d.HayAnterior == true
	botonDeshacer.Visible = puedeDeshacer
	botonDeshacer.Text = `Deshacer ({CFG.TextoDeshacer(estado.Deshechos or 0)})`
end

------------------------------------------------------------------------
-- Abrir y cerrar
------------------------------------------------------------------------

local function cerrar()
	if not abierto then
		return
	end
	abierto = false
	izquierda.Visible = false
	derecha.Visible = false
	-- Lo pendiente se descarta: se vuelve a lo que el servidor tiene guardado.
	table.clear(pendientes)
	repintarTodo()
	devolverCamara()
	NetworkBridge.Client.Fire("CosmeticosCerrar")
end

local function abrir(nuevo: { [string]: any })
	estado = nuevo
	table.clear(pendientes)
	pestana = "Visual"
	piezaElegida = nil
	slotElegido = nil
	for _, uno in estado.Slots or {} do
		local d: { [string]: any } = uno
		if slotElegido == nil and d.ItemId then
			slotElegido = d.Slot
		end
	end
	abierto = true
	izquierda.Visible = true
	derecha.Visible = true
	anguloCamara = math.rad(CFG.Camara.AnguloInicial)
	distanciaCamara = CFG.Camara.Distancia
	tomarCamara()
	dibujar()
end

botonAplicar.Activated:Connect(aplicarPendiente)
botonDeshacer.Activated:Connect(deshacer)
botonCerrar.Activated:Connect(cerrar)

NetworkBridge.Client.OnEvent("CosmeticosAbrir", function(nuevo: any)
	if typeof(nuevo) ~= "table" then
		cerrar()
		return
	end
	abrir(nuevo)
end)

------------------------------------------------------------------------
-- Entrada: girar y acercar la cámara
------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(entrada: InputObject, tomado: boolean)
	if not abierto or tomado then
		return
	end
	if entrada.UserInputType == Enum.UserInputType.MouseButton1 then
		arrastrando = true
	elseif entrada.KeyCode == Enum.KeyCode.Escape then
		cerrar()
	end
end)

UserInputService.InputEnded:Connect(function(entrada: InputObject)
	if entrada.UserInputType == Enum.UserInputType.MouseButton1 then
		arrastrando = false
	end
end)

UserInputService.InputChanged:Connect(function(entrada: InputObject, tomado: boolean)
	if not abierto or tomado then
		return
	end
	if entrada.UserInputType == Enum.UserInputType.MouseMovement and arrastrando then
		anguloCamara += entrada.Delta.X * 0.01 * CFG.Camara.VelocidadGiro
	elseif entrada.UserInputType == Enum.UserInputType.MouseWheel then
		distanciaCamara =
			math.clamp(distanciaCamara - entrada.Position.Z, CFG.Camara.DistanciaMin, CFG.Camara.DistanciaMax)
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	if not abierto then
		return
	end
	if not arrastrando then
		anguloCamara += dt * 0.15 -- gira solo, despacio, para ver todo el objeto
	end
	moverCamara()
end)

-- Si el personaje muere o reaparece, se cierra: el modelo que se estaba
-- mirando ya no existe.
jugador.CharacterRemoving:Connect(cerrar)
