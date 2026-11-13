--!strict
-- InventarioUI: mochila, equipamiento y detalles de ítems.
--
-- Abrir/cerrar: tecla I, cruceta abajo del gamepad (B cierra) o el botón "Mochila".
-- PC:      arrastrar y soltar entre ranuras (mover, combinar o intercambiar) y
--          hacia los slots de equipo; clic abre el menú de acciones.
-- Móvil:   tocar una ranura abre el menú contextual (Usar, Equipar, Dividir,
--          Mover, Destruir). "Mover" espera el toque en la ranura destino.
-- Consola: navegar con el stick/cruceta (selección de Roblox) y A abre el menú.
--
-- Todas las acciones se piden al servidor; la interfaz se redibuja cuando llega
-- el cambio por EstadoCliente.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ProfesionesConfig = require(ReplicatedStorage.Configs.ProfesionesConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local MenuLateral = require(ReplicatedStorage.Modules.MenuLateral)
local ItemInfo = require(ReplicatedStorage.Modules.ItemInfo)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local jugador = Players.LocalPlayer
local playerGui = jugador:WaitForChild("PlayerGui")

local SLOTS_EQUIPO =
	{ "Casco", "Pechera", "ArmaPrincipal", "ArmaSecundaria", "Accesorio1", "Accesorio2", "Herramienta" }
local NOMBRES_SLOT: { [string]: string } = {
	Casco = "Casco",
	Pechera = "Pechera",
	ArmaPrincipal = "Arma",
	ArmaSecundaria = "Secundaria",
	Accesorio1 = "Accesorio 1",
	Accesorio2 = "Accesorio 2",
	Herramienta = "Herramienta",
}

------------------------------------------------------------------------
-- Ventana
------------------------------------------------------------------------

local gui = UIKit.Gui("InventarioUI", 60)
local ventana, contenido = UIKit.Ventana(gui, "Mochila", UDim2.fromScale(0.62, 0.7))

local panelEquipo = Instance.new("Frame")
panelEquipo.Size = UDim2.fromScale(0.22, 1)
panelEquipo.BackgroundTransparency = 1
panelEquipo.Parent = contenido
local layoutEquipo = Instance.new("UIListLayout")
layoutEquipo.Padding = UDim.new(0, 4)
layoutEquipo.SortOrder = Enum.SortOrder.LayoutOrder
layoutEquipo.Parent = panelEquipo

local grilla = UIKit.Lista(contenido, UDim2.fromScale(0.46, 0.9), UDim2.fromScale(0.235, 0))
local layoutLista = grilla:FindFirstChildOfClass("UIListLayout")
if layoutLista then
	layoutLista:Destroy()
end
local layoutGrilla = Instance.new("UIGridLayout")
layoutGrilla.CellSize = UDim2.new(0.18, 0, 0, 58)
layoutGrilla.CellPadding = UDim2.new(0.015, 0, 0, 5)
layoutGrilla.SortOrder = Enum.SortOrder.LayoutOrder
layoutGrilla.Parent = grilla

local pie = UIKit.Texto(contenido, "", UDim2.fromScale(0.46, 0.08), UDim2.fromScale(0.235, 0.92))
pie.TextColor3 = UIKit.Colores.Oro
pie.TextXAlignment = Enum.TextXAlignment.Left

local panelDetalle = Instance.new("Frame")
panelDetalle.Size = UDim2.fromScale(0.29, 1)
panelDetalle.Position = UDim2.fromScale(0.71, 0)
panelDetalle.BackgroundColor3 = UIKit.Colores.Panel
panelDetalle.BackgroundTransparency = 0.3
panelDetalle.Parent = contenido
UIKit.Esquinas(panelDetalle, 8)
local tituloDetalle =
	UIKit.Texto(panelDetalle, "Seleccioná un objeto", UDim2.new(1, -12, 0, 30), UDim2.fromOffset(6, 6))
local textoDetalle = UIKit.Texto(panelDetalle, "", UDim2.new(1, -12, 0.5, -40), UDim2.fromOffset(6, 40))
textoDetalle.TextScaled = false
textoDetalle.TextSize = 15
textoDetalle.TextWrapped = true
textoDetalle.Font = Enum.Font.Gotham
textoDetalle.TextXAlignment = Enum.TextXAlignment.Left
textoDetalle.TextYAlignment = Enum.TextYAlignment.Top
local textoProfesiones = UIKit.Texto(panelDetalle, "", UDim2.new(1, -12, 0.45, -10), UDim2.new(0, 6, 0.55, 0))
textoProfesiones.TextScaled = false
textoProfesiones.TextSize = 14
textoProfesiones.TextWrapped = true
textoProfesiones.Font = Enum.Font.Gotham
textoProfesiones.TextColor3 = UIKit.Colores.TextoSuave
textoProfesiones.TextXAlignment = Enum.TextXAlignment.Left
textoProfesiones.TextYAlignment = Enum.TextYAlignment.Top

-- Botón en el menú lateral (antes flotaba a la derecha y lo tapaban el
-- seguimiento de misiones y, en táctil, la barra de acción).
local atajo = Instance.new("TextButton")
atajo.Name = "BotonMochila"
atajo.BackgroundColor3 = UIKit.Colores.Boton
atajo.TextColor3 = Color3.new(1, 1, 1)
atajo.Font = Enum.Font.GothamBold
atajo.TextScaled = true
atajo.Text = "🎒 Mochila (I)"
UIKit.Esquinas(atajo, 6)
MenuLateral.Agregar(atajo, 8)

------------------------------------------------------------------------
-- Menú contextual
------------------------------------------------------------------------

local menu = Instance.new("Frame")
menu.Size = UDim2.fromOffset(170, 10)
menu.AutomaticSize = Enum.AutomaticSize.Y
menu.BackgroundColor3 = UIKit.Colores.Fondo
menu.Visible = false
menu.ZIndex = 20
UIKit.Esquinas(menu, 8)
local layoutMenu = Instance.new("UIListLayout")
layoutMenu.Padding = UDim.new(0, 4)
layoutMenu.Parent = menu
local margenMenu = Instance.new("UIPadding")
margenMenu.PaddingTop = UDim.new(0, 6)
margenMenu.PaddingBottom = UDim.new(0, 6)
margenMenu.PaddingLeft = UDim.new(0, 6)
margenMenu.PaddingRight = UDim.new(0, 6)
margenMenu.Parent = menu
menu.Parent = gui

type Accion = { Texto: string, Color: Color3?, Fn: () -> () }

local origenMenu: GuiObject? = nil -- botón que abrió el menú (para devolverle el foco)

-- Con mouse/táctil el menú aparece donde se tocó; con gamepad (o si no hay
-- posición) aparece junto al botón.
local function posicionMenu(boton: GuiObject, input: InputObject?): Vector2
	local esPuntero = input ~= nil
		and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
		and (input.Position.X ~= 0 or input.Position.Y ~= 0)
	if esPuntero and input then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return boton.AbsolutePosition + Vector2.new(boton.AbsoluteSize.X, 0)
end

local function abrirMenu(posicion: Vector2, acciones: { Accion }, origen: GuiObject?)
	UIKit.Limpiar(menu)
	if origen then
		origenMenu = origen
	end
	local conGamepad = GuiService.SelectedObject ~= nil
	local primero: GuiObject? = nil
	for i, accion in acciones do
		local b = UIKit.Boton(menu, accion.Texto, UDim2.new(1, 0, 0, 32), nil, accion.Color)
		b.LayoutOrder = i
		b.ZIndex = 21
		b.Activated:Connect(function()
			menu.Visible = false
			accion.Fn()
			-- Con gamepad, el foco vuelve al botón de origen (si la acción no abrió otro menú).
			local volver = origenMenu
			if conGamepad and not menu.Visible and volver and volver:IsDescendantOf(gui) and volver.Visible then
				GuiService.SelectedObject = volver
			end
		end)
		primero = primero or b
	end
	local pantalla = gui.AbsoluteSize
	menu.Position =
		UDim2.fromOffset(math.min(posicion.X, pantalla.X - 180), math.min(posicion.Y, pantalla.Y - 40 * #acciones - 20))
	menu.Visible = true
	if GuiService.SelectedObject ~= nil and primero then
		GuiService.SelectedObject = primero -- con gamepad, el foco pasa al menú
	end
end

------------------------------------------------------------------------
-- Estado local
------------------------------------------------------------------------

local seleccion: { Tipo: "Ranura" | "Equipo", Clave: string }? = nil
local modoMover: string? = nil -- ranura origen esperando destino (táctil/gamepad)
local botonesRanura: { [string]: TextButton } = {}
local botonesEquipo: { [string]: TextButton } = {}

local function inventario(): { MaxSlots: number, Slots: { [string]: any } }?
	local inv = EstadoCliente.Get("Inventario")
	return if typeof(inv) == "table" then inv else nil
end

local function itemEnRanura(clave: string): any
	local inv = inventario()
	return if inv then inv.Slots[clave] else nil
end

local function itemEquipado(slot: string): any
	local eq = EstadoCliente.Get("Equipamiento")
	return if typeof(eq) == "table" then eq[slot] else nil
end

local function mostrarDetalle(item: any)
	if typeof(item) ~= "table" then
		tituloDetalle.Text = "Seleccioná un objeto"
		tituloDetalle.TextColor3 = UIKit.Colores.Texto
		textoDetalle.Text = ""
		return
	end
	tituloDetalle.Text = ItemInfo.Corto(item)
	tituloDetalle.TextColor3 = ItemInfo.Color(item)
	textoDetalle.Text = ItemInfo.Detalle(item)
end

------------------------------------------------------------------------
-- Acciones (todas las valida el servidor)
------------------------------------------------------------------------

local function mover(desde: string, hacia: string)
	if desde ~= hacia then
		NetworkBridge.Client.Fire("MoverItem", tonumber(desde), tonumber(hacia))
	end
end

local function equipar(clave: string)
	local item = itemEnRanura(clave)
	if not item then
		return
	end
	local r = NetworkBridge.Client.Invoke("EquiparItem", item.Uid)
	if not r.Success then
		Avisos.Mostrar("No se pudo equipar.", "Error")
	end
end

local function desequipar(slot: string)
	local r = NetworkBridge.Client.Invoke("DesequiparItem", slot)
	if not r.Success then
		Avisos.Mostrar(
			if r.ErrorCode == "INVENTORY_FULL" then "No hay espacio en la mochila." else "No se pudo desequipar.",
			"Error"
		)
	end
end

local function accionesRanura(clave: string): { Accion }
	local item = itemEnRanura(clave)
	local def = item and ItemCatalog[item.ItemId]
	local acciones: { Accion } = {}
	if not item or not def then
		return acciones
	end
	if def.Tipo == "Consumible" then
		table.insert(acciones, {
			Texto = "Usar",
			Fn = function()
				NetworkBridge.Client.Fire("UsarItem", tonumber(clave))
			end,
		})
	end
	if def.SlotEquipo then
		table.insert(acciones, {
			Texto = "Equipar",
			Color = UIKit.Colores.BotonPrimario,
			Fn = function()
				equipar(clave)
			end,
		})
	end
	if item.Cantidad > 1 then
		table.insert(acciones, {
			Texto = `Dividir ({item.Cantidad // 2})`,
			Fn = function()
				NetworkBridge.Client.Fire("DividirPila", tonumber(clave), item.Cantidad // 2)
			end,
		})
	end
	table.insert(acciones, {
		Texto = "Mover…",
		Fn = function()
			modoMover = clave
			Avisos.Mostrar("Elegí la ranura de destino.", "Info")
		end,
	})
	table.insert(acciones, {
		Texto = "Destruir",
		Color = UIKit.Colores.BotonPeligro,
		Fn = function()
			-- Segunda confirmación para evitar accidentes.
			abrirMenu(menu.AbsolutePosition, {
				{
					Texto = `¿Destruir {ItemInfo.Nombre(item)}?`,
					Color = UIKit.Colores.BotonPeligro,
					Fn = function()
						NetworkBridge.Client.Invoke("DestruirItem", tonumber(clave))
					end,
				},
				{ Texto = "Cancelar", Fn = function() end },
			})
		end,
	})
	return acciones
end

------------------------------------------------------------------------
-- Arrastrar y soltar (PC)
------------------------------------------------------------------------

local fantasma = UIKit.Texto(gui, "", UDim2.fromOffset(150, 30))
fantasma.Visible = false
fantasma.ZIndex = 30
fantasma.BackgroundTransparency = 0.2
fantasma.BackgroundColor3 = UIKit.Colores.Panel

type Arrastre = { Tipo: "Ranura" | "Equipo", Clave: string, Inicio: Vector2, Activo: boolean }
local arrastre: Arrastre? = nil
local ignorarActivadoHasta = 0

local function destinoBajoMouse(posicion: Vector2): (string?, string?)
	for _, objeto in playerGui:GetGuiObjectsAtPosition(posicion.X, posicion.Y) do
		local ranura = objeto:GetAttribute("Ranura")
		if typeof(ranura) == "string" then
			return "Ranura", ranura
		end
		local slot = objeto:GetAttribute("SlotEquipo")
		if typeof(slot) == "string" then
			return "Equipo", slot
		end
	end
	return nil, nil
end

local function empezarArrastre(tipo: "Ranura" | "Equipo", clave: string, input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	arrastre = { Tipo = tipo, Clave = clave, Inicio = Vector2.new(input.Position.X, input.Position.Y), Activo = false }
end

RunService.RenderStepped:Connect(function()
	local a = arrastre
	if not a then
		return
	end
	local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	if not a.Activo and (mouse - a.Inicio).Magnitude > 8 then
		local item = if a.Tipo == "Ranura" then itemEnRanura(a.Clave) else itemEquipado(a.Clave)
		if not item then
			arrastre = nil
			return
		end
		a.Activo = true
		fantasma.Text = ItemInfo.Corto(item)
		fantasma.TextColor3 = ItemInfo.Color(item)
		fantasma.Visible = true
	end
	if a.Activo then
		fantasma.Position = UDim2.fromOffset(mouse.X + 10, mouse.Y + 10)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	local a = arrastre
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not a then
		return
	end
	arrastre = nil
	fantasma.Visible = false
	if not a.Activo then
		return -- fue un clic: lo maneja Activated
	end
	ignorarActivadoHasta = os.clock() + 0.2
	local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local tipo, clave = destinoBajoMouse(mouse)
	if not tipo or not clave then
		return
	end
	if a.Tipo == "Ranura" and tipo == "Ranura" then
		mover(a.Clave, clave)
	elseif a.Tipo == "Ranura" and tipo == "Equipo" then
		equipar(a.Clave)
	elseif a.Tipo == "Equipo" and tipo == "Ranura" then
		desequipar(a.Clave)
	end
end)

------------------------------------------------------------------------
-- Construcción de ranuras
------------------------------------------------------------------------

local function estiloRanura(boton: TextButton, item: any, vacio: string)
	local borde = boton:FindFirstChildOfClass("UIStroke")
	if typeof(item) == "table" then
		boton.Text = ItemInfo.Corto(item)
		boton.TextColor3 = ItemInfo.Color(item)
		if borde then
			borde.Color = ItemInfo.Color(item)
			borde.Thickness = if ItemInfo.EsMasterpiece(item) then 3 else 1.5
		end
	else
		boton.Text = vacio
		boton.TextColor3 = UIKit.Colores.TextoSuave
		if borde then
			borde.Color = Color3.fromRGB(70, 70, 90)
			borde.Thickness = 1
		end
	end
end

local function nuevoBoton(padre: Instance): TextButton
	local b = UIKit.Boton(padre, "", UDim2.new(1, 0, 0, 44))
	b.TextWrapped = true
	local borde = Instance.new("UIStroke")
	borde.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	borde.Parent = b
	return b
end

local function botonRanura(clave: string, orden: number): TextButton
	local existente = botonesRanura[clave]
	if existente then
		return existente
	end
	local b = nuevoBoton(grilla)
	b.LayoutOrder = orden
	b:SetAttribute("Ranura", clave)
	b.InputBegan:Connect(function(input: InputObject)
		empezarArrastre("Ranura", clave, input)
	end)
	b.MouseEnter:Connect(function()
		mostrarDetalle(itemEnRanura(clave))
	end)
	b.SelectionGained:Connect(function()
		mostrarDetalle(itemEnRanura(clave))
	end)
	b.Activated:Connect(function(input: InputObject?)
		if os.clock() < ignorarActivadoHasta then
			return
		end
		if modoMover then
			local origen = modoMover
			modoMover = nil
			mover(origen, clave)
			return
		end
		seleccion = { Tipo = "Ranura", Clave = clave }
		mostrarDetalle(itemEnRanura(clave))
		local acciones = accionesRanura(clave)
		if #acciones > 0 then
			abrirMenu(posicionMenu(b, input), acciones, b)
		end
	end)
	botonesRanura[clave] = b
	return b
end

for i, slot in SLOTS_EQUIPO do
	local b = nuevoBoton(panelEquipo)
	b.LayoutOrder = i
	b:SetAttribute("SlotEquipo", slot)
	b.InputBegan:Connect(function(input: InputObject)
		empezarArrastre("Equipo", slot, input)
	end)
	b.MouseEnter:Connect(function()
		mostrarDetalle(itemEquipado(slot))
	end)
	b.SelectionGained:Connect(function()
		mostrarDetalle(itemEquipado(slot))
	end)
	b.Activated:Connect(function(input: InputObject?)
		if os.clock() < ignorarActivadoHasta then
			return
		end
		local item = itemEquipado(slot)
		mostrarDetalle(item)
		if item then
			abrirMenu(posicionMenu(b, input), {
				{
					Texto = "Desequipar",
					Fn = function()
						desequipar(slot)
					end,
				},
			}, b)
		end
	end)
	botonesEquipo[slot] = b
end

------------------------------------------------------------------------
-- Redibujado
------------------------------------------------------------------------

local function textoProfesionesActual(): string
	local profesiones = EstadoCliente.Get("Profesiones")
	local lineas = { "Profesiones:" }
	for _, id in { "Mineria", "Herboristeria", "Herreria", "Alquimia", "Sastreria" } do
		local p = if typeof(profesiones) == "table" then profesiones[id] else nil
		local nivel = if typeof(p) == "table" then p.Nivel else 1
		table.insert(lineas, `{ProfesionesConfig.Profesiones[id].Nombre}: nivel {nivel}`)
	end
	return table.concat(lineas, "\n")
end

local function redibujar()
	local inv = inventario()
	if not inv then
		return
	end
	local ocupadas = 0
	for i = 1, inv.MaxSlots do
		local clave = tostring(i)
		local item = inv.Slots[clave]
		if item then
			ocupadas += 1
		end
		estiloRanura(botonRanura(clave, i), item, "")
	end
	for clave, boton in botonesRanura do
		local n = tonumber(clave)
		boton.Visible = n ~= nil and n <= inv.MaxSlots
	end
	for slot, boton in botonesEquipo do
		estiloRanura(boton, itemEquipado(slot), NOMBRES_SLOT[slot])
	end
	pie.Text = `Oro: {EstadoCliente.Get("Oro") or 0}   ·   {ocupadas}/{inv.MaxSlots} ranuras`
	textoProfesiones.Text = textoProfesionesActual()
	local s = seleccion
	if s then
		mostrarDetalle(if s.Tipo == "Ranura" then itemEnRanura(s.Clave) else itemEquipado(s.Clave))
	end
end

EstadoCliente.Cambio:Connect(function(campo: string)
	if campo == "*" or campo == "Inventario" or campo == "Equipamiento" or campo == "Oro" or campo == "Profesiones" then
		redibujar()
	end
end)
redibujar()

------------------------------------------------------------------------
-- Abrir / cerrar
------------------------------------------------------------------------

local alternar: () -> ()

-- Con gamepad, B cierra la mochila mientras está abierta.
local function cerrarConB(_, estado: Enum.UserInputState): Enum.ContextActionResult
	if estado == Enum.UserInputState.Begin and ventana.Visible then
		if menu.Visible then
			menu.Visible = false -- primero cierra el menú contextual
			if origenMenu and origenMenu:IsDescendantOf(gui) then
				GuiService.SelectedObject = origenMenu
			end
		else
			alternar()
		end
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

alternar = function()
	ventana.Visible = not ventana.Visible
	menu.Visible = false
	modoMover = nil
	if ventana.Visible then
		redibujar()
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = botonesRanura["1"]
			ContextActionService:BindActionAtPriority(
				"CerrarMochila",
				cerrarConB,
				false,
				Enum.ContextActionPriority.High.Value,
				Enum.KeyCode.ButtonB
			)
		end
	else
		ContextActionService:UnbindAction("CerrarMochila")
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
	end
end

-- Si la ventana se cierra por otro camino (botón X), se limpia el estado.
ventana:GetPropertyChangedSignal("Visible"):Connect(function()
	if not ventana.Visible then
		menu.Visible = false
		modoMover = nil
		ContextActionService:UnbindAction("CerrarMochila")
	end
end)

atajo.Activated:Connect(alternar)
-- I en teclado; cruceta abajo en gamepad (ButtonSelect lo usa Roblox para el
-- modo de selección de interfaz). Si la mochila está abierta y hay un botón
-- seleccionado, la cruceta se deja pasar para navegar.
ContextActionService:BindAction(
	"MochilaRaidBlox",
	function(_, estado: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if input.KeyCode == Enum.KeyCode.DPadDown then
			local seleccionado = GuiService.SelectedObject
			if seleccionado ~= nil then
				return Enum.ContextActionResult.Pass
			end
		end
		if estado == Enum.UserInputState.Begin then
			alternar()
		end
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.KeyCode.I,
	Enum.KeyCode.DPadDown
)
