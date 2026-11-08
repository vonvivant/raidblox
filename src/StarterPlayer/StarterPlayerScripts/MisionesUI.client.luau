--!strict
-- MisionesUI: diálogo con los NPCs, seguimiento de misiones y marcadores.
--
-- Marcadores sobre cada NPC (solo los ve este jugador):
--   "!" amarillo   hay una misión disponible
--   "?" gris       tenés una misión de este NPC en curso
--   "?" amarillo   tenés una misión lista para entregarle
-- El seguimiento (derecha) muestra las misiones activas y su progreso. Todo
-- lo decide el servidor: acá solo se muestra y se piden acciones.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MisionesConfig = require(ReplicatedStorage.Configs.MisionesConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)

type Mision = MisionesConfig.Mision

local AMARILLO = Color3.fromRGB(255, 215, 60)
local GRIS = Color3.fromRGB(170, 170, 170)

local gui = UIKit.Gui("MisionesUI", 63)
local ventana, contenido = UIKit.Ventana(gui, "Misiones", UDim2.fromScale(0.46, 0.62))
local lista = UIKit.Lista(contenido, UDim2.fromScale(1, 1))

local npcAbierto: string? = nil

------------------------------------------------------------------------
-- Estado del jugador (espejo local)
------------------------------------------------------------------------

local function activas(): { [string]: any }
	local a = EstadoCliente.Get("MisionesActivas")
	return if typeof(a) == "table" then a else {}
end

local function completadas(): { [string]: any }
	local c = EstadoCliente.Get("MisionesCompletadas")
	return if typeof(c) == "table" then c else {}
end

local function contarItem(itemId: string): number
	local inv = EstadoCliente.Get("Inventario")
	if typeof(inv) ~= "table" or typeof(inv.Slots) ~= "table" then
		return 0
	end
	local total = 0
	for _, item in inv.Slots do
		if typeof(item) == "table" and item.ItemId == itemId then
			total += item.Cantidad
		end
	end
	return total
end

local function progresoObjetivo(progreso: any, obj: MisionesConfig.Objetivo): number
	if obj.Tipo == "Recolectar" then
		return math.min(contarItem(obj.Objetivo), obj.Cantidad)
	end
	local objetivos = if typeof(progreso) == "table" then progreso.Objetivos else nil
	local v = if typeof(objetivos) == "table" then objetivos[obj.Id] else nil
	return math.min(if typeof(v) == "number" then v else 0, obj.Cantidad)
end

local function lista_para_entregar(id: string, mision: Mision): boolean
	local progreso = activas()[id]
	if not progreso then
		return false
	end
	for _, obj in mision.Objetivos do
		if progresoObjetivo(progreso, obj) < obj.Cantidad then
			return false
		end
	end
	return true
end

local function disponible(id: string, mision: Mision): boolean
	if activas()[id] then
		return false
	end
	if completadas()[id] and not mision.Repetible then
		return false
	end
	local nivel = EstadoCliente.Get("Nivel")
	if typeof(nivel) == "number" and nivel < mision.NivelRequerido then
		return false
	end
	return mision.Previa == nil or completadas()[mision.Previa] ~= nil
end

------------------------------------------------------------------------
-- Diálogo
------------------------------------------------------------------------

local function textoObjetivos(id: string, mision: Mision): string
	local progreso = activas()[id]
	local partes: { string } = {}
	for _, obj in mision.Objetivos do
		local v = if progreso then progresoObjetivo(progreso, obj) else 0
		table.insert(partes, `{obj.Texto}: {v}/{obj.Cantidad}`)
	end
	return table.concat(partes, " · ")
end

local function textoRecompensa(mision: Mision): string
	local r = mision.Recompensas
	local texto = `{r.Xp} XP · {r.Oro} de oro`
	if r.Items and #r.Items > 0 then
		texto ..= " · +objetos"
	end
	return texto
end

local function fila(orden: number, titulo: string, detalle: string, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 86)
	f.BackgroundColor3 = UIKit.Colores.Fondo
	f.LayoutOrder = orden
	UIKit.Esquinas(f, 6)
	local t = UIKit.Texto(f, titulo, UDim2.new(0.66, 0, 0, 24), UDim2.fromOffset(8, 4))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color
	local d = UIKit.Texto(f, detalle, UDim2.new(0.66, 0, 0, 52), UDim2.fromOffset(8, 30))
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.TextYAlignment = Enum.TextYAlignment.Top
	d.TextWrapped = true
	d.TextScaled = false
	d.TextSize = 14
	d.Font = Enum.Font.Gotham
	d.TextColor3 = UIKit.Colores.TextoSuave
	f.Parent = lista
	return f
end

local function redibujar()
	local npcId = npcAbierto
	if not npcId then
		return
	end
	UIKit.Limpiar(lista)
	local npc = MisionesConfig.Npcs[npcId]
	local orden = 0
	-- Orden estable por nombre.
	local ids: { string } = {}
	for id in MisionesConfig.Misiones do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return MisionesConfig.Misiones[a].Nombre < MisionesConfig.Misiones[b].Nombre
	end)
	for _, id in ids do
		local mision = MisionesConfig.Misiones[id]
		local entrega = mision.NpcEntrega or mision.Npc
		local activa = activas()[id] ~= nil
		local boton: string? = nil
		local accion: string? = nil
		local color = UIKit.Colores.Texto
		if activa and entrega == npcId and lista_para_entregar(id, mision) then
			boton, accion, color = "Entregar", "MisionEntregar", AMARILLO
		elseif activa and (mision.Npc == npcId or entrega == npcId) then
			boton, accion, color = "Abandonar", "MisionAbandonar", GRIS
		elseif mision.Npc == npcId and disponible(id, mision) then
			boton, accion, color = "Aceptar", "MisionAceptar", AMARILLO
		end
		if not boton or not accion then
			continue
		end
		orden += 1
		local detalle = if activa
			then textoObjetivos(id, mision)
			else `{mision.Descripcion}\nRecompensa: {textoRecompensa(mision)}`
		local f = fila(orden, mision.Nombre, detalle, color)
		local b = UIKit.Boton(
			f,
			boton,
			UDim2.new(0.3, 0, 0, 40),
			UDim2.new(0.68, 0, 0.5, -20),
			if boton == "Abandonar" then UIKit.Colores.BotonPeligro else UIKit.Colores.BotonPrimario
		)
		local nombreAccion: string = accion
		b.Activated:Connect(function()
			NetworkBridge.Client.Invoke(nombreAccion, id)
		end)
	end
	if orden == 0 then
		local f = fila(1, if npc then npc.Nombre else "NPC", "No tengo nada para vos por ahora.", UIKit.Colores.Texto)
		f.Size = UDim2.new(1, 0, 0, 60)
	end
end

NetworkBridge.Client.OnEvent("MisionDialogo", function(npcId: any)
	if typeof(npcId) ~= "string" or not MisionesConfig.Npcs[npcId] then
		return
	end
	npcAbierto = npcId
	local npc = MisionesConfig.Npcs[npcId]
	local titulo = ventana:FindFirstChildOfClass("TextLabel")
	if titulo then
		titulo.Text = `{npc.Nombre} — {npc.Titulo}`
	end
	redibujar()
	ventana.Visible = true
	UIKit.EnfocarPrimero(ventana)
end)

ventana:GetPropertyChangedSignal("Visible"):Connect(function()
	if not ventana.Visible then
		npcAbierto = nil
	end
end)

------------------------------------------------------------------------
-- Seguimiento (derecha)
------------------------------------------------------------------------

local seguimiento = Instance.new("Frame")
seguimiento.Name = "Seguimiento"
seguimiento.AnchorPoint = Vector2.new(1, 0)
seguimiento.Position = UDim2.fromScale(0.99, 0.3)
seguimiento.Size = UDim2.fromScale(0.2, 0.3)
seguimiento.BackgroundTransparency = 1
seguimiento.Parent = gui
local layoutSeg = Instance.new("UIListLayout")
layoutSeg.Padding = UDim.new(0, 4)
layoutSeg.HorizontalAlignment = Enum.HorizontalAlignment.Right
layoutSeg.Parent = seguimiento

local function etiquetaSeg(texto: string, color: Color3, grande: boolean, orden: number)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 0, if grande then 20 else 16)
	t.BackgroundTransparency = 1
	t.Font = if grande then Enum.Font.GothamBold else Enum.Font.Gotham
	t.TextSize = if grande then 16 else 14
	t.TextXAlignment = Enum.TextXAlignment.Right
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.4
	t.Text = texto
	t.LayoutOrder = orden
	t.Parent = seguimiento
end

local function redibujarSeguimiento()
	UIKit.Limpiar(seguimiento)
	local orden = 0
	local mostradas = 0
	for id, progreso in activas() do
		local mision = MisionesConfig.Misiones[id]
		if not mision or mostradas >= 5 then
			continue
		end
		mostradas += 1
		local lista_ = lista_para_entregar(id, mision)
		orden += 1
		etiquetaSeg(
			if lista_ then `✔ {mision.Nombre}` else mision.Nombre,
			if lista_ then AMARILLO else Color3.new(1, 1, 1),
			true,
			orden
		)
		for _, obj in mision.Objetivos do
			orden += 1
			local v = progresoObjetivo(progreso, obj)
			etiquetaSeg(
				`{obj.Texto}: {v}/{obj.Cantidad}`,
				if v >= obj.Cantidad then Color3.fromRGB(130, 230, 130) else UIKit.Colores.TextoSuave,
				false,
				orden
			)
		end
	end
end

------------------------------------------------------------------------
-- Marcadores sobre los NPCs
------------------------------------------------------------------------

local marcadores: { [Model]: TextLabel } = {}

local function estadoNpc(npcId: string): (string?, Color3?)
	local hayEnCurso = false
	for id, mision in MisionesConfig.Misiones do
		local entrega = mision.NpcEntrega or mision.Npc
		if activas()[id] then
			if entrega == npcId and lista_para_entregar(id, mision) then
				return "?", AMARILLO
			end
			if mision.Npc == npcId or entrega == npcId then
				hayEnCurso = true
			end
		end
	end
	for id, mision in MisionesConfig.Misiones do
		if mision.Npc == npcId and disponible(id, mision) then
			return "!", AMARILLO
		end
	end
	if hayEnCurso then
		return "?", GRIS
	end
	return nil, nil
end

local function actualizarMarcador(modelo: Model)
	local etiqueta = marcadores[modelo]
	local npcId = modelo:GetAttribute("NpcId")
	if not etiqueta or typeof(npcId) ~= "string" then
		return
	end
	local signo, color = estadoNpc(npcId)
	etiqueta.Visible = signo ~= nil
	etiqueta.Text = signo or ""
	if color then
		etiqueta.TextColor3 = color
	end
end

local function agregarMarcador(objeto: Instance)
	if not objeto:IsA("Model") then
		return
	end
	local modelo: Model = objeto
	local cabeza = modelo:FindFirstChild("Head") or modelo.PrimaryPart
	if not cabeza or not cabeza:IsA("BasePart") then
		return
	end
	local cartel = Instance.new("BillboardGui")
	cartel.Size = UDim2.fromOffset(60, 60)
	cartel.StudsOffset = Vector3.new(0, 3.2, 0)
	cartel.AlwaysOnTop = true
	cartel.MaxDistance = 120
	cartel.Adornee = cabeza
	local etiqueta = Instance.new("TextLabel")
	etiqueta.Size = UDim2.fromScale(1, 1)
	etiqueta.BackgroundTransparency = 1
	etiqueta.Font = Enum.Font.GothamBlack
	etiqueta.TextScaled = true
	etiqueta.TextStrokeTransparency = 0
	etiqueta.Parent = cartel
	cartel.Parent = gui
	marcadores[modelo] = etiqueta
	modelo.Destroying:Connect(function()
		marcadores[modelo] = nil
		cartel:Destroy()
	end)
	actualizarMarcador(modelo)
end

for _, modelo in CollectionService:GetTagged("NpcMision") do
	agregarMarcador(modelo)
end
CollectionService:GetInstanceAddedSignal("NpcMision"):Connect(agregarMarcador)

------------------------------------------------------------------------
-- Refresco
------------------------------------------------------------------------

local function refrescar()
	for modelo in marcadores do
		actualizarMarcador(modelo)
	end
	redibujarSeguimiento()
	if ventana.Visible then
		redibujar()
	end
end

EstadoCliente.Cambio:Connect(function(campo: string)
	if campo == "Misiones" or campo == "Nivel" or campo == "Inventario" or campo == "*" then
		refrescar()
	end
end)
refrescar()
