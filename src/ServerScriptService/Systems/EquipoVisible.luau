--!strict
-- EquipoVisible: dibuja en el personaje el equipo puesto (Fase 6.3).
--
-- * Arma principal en la mano derecha, secundaria en la izquierda, casco en la
--   cabeza y pechera en el torso, con los modelos de AparienciaEquipoConfig.
-- * Si el ítem tiene un modelo en ReplicatedStorage.CustomizableItems, se
--   dibuja ese modelo con la personalización guardada en el ítem (`Meta.Pers`),
--   igual que en el probador del NPC personalizador.
-- * Transmog: si el jugador eligió una apariencia para un slot y tiene un
--   ítem puesto ahí, se dibuja la apariencia en vez del ítem. Las stats son
--   siempre las del ítem.
-- * Las piezas son del servidor (todos las ven), sin colisión ni masa, y se
--   rehacen al cambiar el equipo, la apariencia o al reaparecer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local CFG = require(ReplicatedStorage.Configs.AparienciaEquipoConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Personalizador = require(ReplicatedStorage.Modules.Personalizador)
local PersonalizadorConfig = require(ReplicatedStorage.Configs.PersonalizadorConfig)
local DataManager = require(script.Parent.DataManager)

type Respuesta = Types.Respuesta
type Modelo = typeof(CFG.Modelos.Espada)

local EquipoVisible = {}

local iniciado = false
local ultimoPedido: { [Player]: number } = {}
-- Firma de lo que está dibujado: si no cambió, no se rehace (Cosmeticos
-- cambia seguido, por ejemplo con cada XP del pase de batalla).
local firmas: { [Player]: string } = {}

local NOMBRES_ANCLAJE: { [string]: { string } } = {
	ManoDerecha = { "RightHand", "Right Arm" },
	ManoIzquierda = { "LeftHand", "Left Arm" },
	Cabeza = { "Head" },
	Torso = { "UpperTorso", "Torso" },
}

local function anclaje(personaje: Model, nombre: string): (BasePart?, CFrame)
	for _, n in NOMBRES_ANCLAJE[nombre] do
		local p = personaje:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			local base = CFrame.identity
			if nombre == "ManoDerecha" or nombre == "ManoIzquierda" then
				-- La mano de R15 es corta; el brazo de R6 llega más abajo.
				base = CFrame.new(0, if n == "RightHand" or n == "LeftHand" then -0.15 else -1, 0)
			elseif nombre == "Torso" and n == "UpperTorso" then
				base = CFrame.new(0, -0.1, 0)
			end
			return p, base
		end
	end
	return nil, CFrame.identity
end

local function agregarEfecto(parte: BasePart, efecto: string?, color: Color3?)
	if efecto == "Fuego" then
		local f = Instance.new("Fire")
		f.Size = 2
		f.Heat = 4
		f.Color = color or Color3.fromRGB(255, 140, 40)
		f.SecondaryColor = Color3.fromRGB(255, 220, 120)
		f.Parent = parte
	elseif efecto == "Chispas" then
		local s = Instance.new("Sparkles")
		s.SparkleColor = color or Color3.new(1, 1, 1)
		s.Parent = parte
	elseif efecto == "Humo" then
		local h = Instance.new("Smoke")
		h.Size = 0.6
		h.Opacity = 0.15
		h.RiseVelocity = 1.5
		h.Color = color or Color3.fromRGB(90, 90, 90)
		h.Parent = parte
	end
end

local function construir(
	carpeta: Model,
	personaje: Model,
	modelo: Modelo,
	anclajeNombre: string,
	color: Color3,
	material: Enum.Material,
	efecto: string?,
	colorEfecto: Color3?,
	slot: string
)
	local base, desplazamiento = anclaje(personaje, anclajeNombre)
	if not base then
		return
	end
	local origen = base.CFrame * desplazamiento
	if modelo.Empunadura then
		origen *= CFrame.Angles(math.rad(-90), 0, 0)
	end
	for _, p in modelo.Piezas do
		local parte = Instance.new("Part")
		parte.Name = "Pieza"
		parte:SetAttribute("Slot", slot) -- el probador oculta lo que hay en el slot que se prueba
		parte.Size = p.Tam
		parte.Shape = p.Forma or Enum.PartType.Block
		parte.Material = if p.Tinte then material else (p.Material or Enum.Material.SmoothPlastic)
		parte.Color = if p.Tinte then color else (p.Color or color)
		parte.CanCollide = false
		parte.CanQuery = false
		parte.CanTouch = false
		parte.Massless = true
		parte.CastShadow = false
		local rot = p.Rot or Vector3.zero
		parte.CFrame = origen * CFrame.new(p.Pos) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		local w = Instance.new("WeldConstraint")
		w.Part0 = base
		w.Part1 = parte
		w.Parent = parte
		if p.Efecto then
			agregarEfecto(parte, efecto, colorEfecto)
		end
		parte.Parent = carpeta
	end
end

-- Dibuja el ítem con su modelo de CustomizableItems y su personalización.
-- Devuelve false si el ítem no tiene modelo (o no se pudo montar): en ese caso
-- se dibuja con las piezas simples de siempre.
local function dibujarModelo(carpeta: Model, personaje: Model, slot: string, item: Types.ItemInstancia): boolean
	local entrada = Personalizador.Catalogo()[item.ItemId]
	if not entrada then
		return false
	end
	local clon = entrada.Modelo:Clone()
	clon.Name = slot
	clon:SetAttribute("Slot", slot)
	local mapa = Personalizador.Mapa(clon) -- antes de montar
	local pers = PersonalizadorConfig.Decodificar(if item.Meta then item.Meta.Pers else nil)
	-- Aplicar ignora piezas, materiales o colores que ya no existan en el modelo.
	Personalizador.Aplicar(entrada, mapa, pers or {})
	if not Personalizador.Montar(clon, personaje, slot) then
		clon:Destroy()
		return false
	end
	for _, d in clon:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	clon.Parent = carpeta
	return true
end

-- (Un personaje nuevo no tiene la carpeta "EquipoVisible", así que se rehace igual.)
local function firmaDe(datos: Types.DatosJugador): string
	local partes: { string } = {}
	local equipamiento = datos.Equipamiento :: { [string]: Types.ItemInstancia? }
	local transmog = datos.Transmog or {}
	for _, slot in CFG.SlotsVisibles do
		local item = equipamiento[slot]
		local pers = if item and item.Meta then item.Meta.Pers else nil
		table.insert(
			partes,
			`{slot}={if item then item.ItemId else ""}/{transmog[slot] or ""}/{if typeof(pers) == "string"
				then pers
				else ""}`
		)
	end
	return table.concat(partes, ";")
end

-- `forzar`: rehacer aunque nada haya cambiado (el cuerpo cambió de tamaño).
function EquipoVisible.Actualizar(player: Player, forzar: boolean?)
	local personaje = player.Character
	local datos = DataManager.GetData(player)
	if not personaje or not datos then
		return
	end
	local firma = firmaDe(datos)
	if not forzar and firmas[player] == firma and personaje:FindFirstChild("EquipoVisible") then
		return
	end
	firmas[player] = firma
	local vieja = personaje:FindFirstChild("EquipoVisible")
	if vieja then
		vieja:Destroy()
	end
	local carpeta = Instance.new("Model")
	carpeta.Name = "EquipoVisible"
	local equipamiento = datos.Equipamiento :: { [string]: Types.ItemInstancia? }
	local transmog = datos.Transmog or {}
	for _, slot in CFG.SlotsVisibles do
		local item = equipamiento[slot]
		if not item then
			continue
		end
		local idApariencia = transmog[slot]
		local apariencia = if idApariencia then CFG.Apariencias[idApariencia] else nil
		local nombreModelo: string, color: Color3, material: Enum.Material
		local efecto: string?, colorEfecto: Color3? = nil, nil
		if apariencia and apariencia.Slot == slot then
			nombreModelo, color, material = apariencia.Modelo, apariencia.Color, apariencia.Material
			efecto, colorEfecto = apariencia.Efecto, apariencia.ColorEfecto
		else
			if dibujarModelo(carpeta, personaje, slot, item) then
				continue
			end
			local visual = CFG.Items[item.ItemId]
			if not visual then
				continue
			end
			nombreModelo, color, material = visual.Modelo, visual.Color, visual.Material
		end
		local modelo = CFG.Modelos[nombreModelo]
		if not modelo then
			continue
		end
		local anclajeSlot: string = if slot == "ArmaSecundaria" then "ManoIzquierda" else modelo.Anclaje
		construir(carpeta, personaje, modelo, anclajeSlot, color, material, efecto, colorEfecto, slot)
	end
	carpeta.Parent = personaje
end

-- Elige (o quita, con "") la apariencia de un slot.
local function elegir(player: Player, slot: string, id: string): Respuesta
	local datos = DataManager.GetData(player)
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	if not table.find(CFG.SlotsVisibles, slot :: any) then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if id ~= "" then
		local apariencia = CFG.Apariencias[id]
		if not apariencia or apariencia.Slot ~= slot then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not datos.Apariencias or not table.find(datos.Apariencias, id) then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
	end
	DataManager.Mutar(player, "Cosmeticos", function(d)
		local t: { [string]: string } = table.clone(d.Transmog or {})
		if id == "" then
			t[slot] = nil
		else
			t[slot] = id
		end
		d.Transmog = t
	end)
	return NetworkBridge.Ok(nil)
end

function EquipoVisible.Init()
	assert(not iniciado, "EquipoVisible.Init() se llamó dos veces")
	iniciado = true

	NetworkBridge.Server.OnInvoke("EquiparTransmog", function(player: Player, slot: unknown, id: unknown): Respuesta
		local s = NetworkBridge.Guard.String(slot, 20)
		local i = if id == "" then "" else NetworkBridge.Guard.String(id, 40)
		if not s or not i then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		local t = os.clock()
		if t - (ultimoPedido[player] or 0) < 0.4 then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		ultimoPedido[player] = t
		return elegir(player, s, i)
	end)

	DataManager.DatosCambiados:Connect(function(player: Player, seccion: string)
		if seccion == "Equipamiento" or seccion == "Cosmeticos" then
			EquipoVisible.Actualizar(player)
		end
	end)

	local function alPersonaje(player: Player, personaje: Model)
		-- Espera a que estén las partes del cuerpo (y a que se aplique el avatar).
		personaje:WaitForChild("Head", 10)
		task.wait(1)
		if player.Character == personaje then
			EquipoVisible.Actualizar(player)
		end
	end
	local function alEntrar(player: Player)
		player.CharacterAdded:Connect(function(personaje: Model)
			alPersonaje(player, personaje)
		end)
		if player.Character then
			task.spawn(alPersonaje, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(alEntrar)
	for _, p in Players:GetPlayers() do
		alEntrar(p)
	end
	DataManager.PerfilCargado:Connect(function(player: Player)
		EquipoVisible.Actualizar(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		ultimoPedido[player] = nil
		firmas[player] = nil
	end)
end

return EquipoVisible
