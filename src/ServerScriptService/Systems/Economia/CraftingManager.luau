--!strict
-- CraftingManager: profesiones de producción (Herrería, Alquimia, Sastrería).
--
-- Flujo:
--   1. El jugador activa una estación (Yunque, Mesa de Alquimia, Telar) y se le
--      abre la lista de recetas de esa estación.
--   2. CraftearIniciar(recetaId): el servidor valida la receta, el nivel de
--      profesión, que esté a 12 studs o menos de una estación del tipo correcto
--      y que tenga TODOS los materiales.
--   3. Descuenta todos los materiales en una sola operación síncrona (todo o nada)
--      y recién ahí arranca el contador.
--   4. Al terminar: si se alejó, se cancela y se devuelven los materiales; si no,
--      entrega el resultado. Probabilidad de calidad Masterpiece: +10% de
--      atributos en equipos (o +1 unidad en el resto) y efecto visual.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pruebas = require(game:GetService("ReplicatedStorage").Modules.Pruebas)
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ProfesionesConfig = require(ReplicatedStorage.Configs.ProfesionesConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local Buzon = require(script.Parent.Parent.Buzon)

type Receta = ProfesionesConfig.Receta

local CraftingManager = {}

local TAG_ESTACION = "EstacionCrafteo"
local AREA_PRUEBA = Vector3.new(70, 0, -40)

type Trabajo = { RecetaId: string, Receta: Receta, Estacion: BasePart, Fin: number }
local trabajos: { [Player]: Trabajo } = {}
local duplicador: ((Player) -> boolean)? = nil

-- Otro sistema decide si lo que fabrica un jugador sale duplicado.
function CraftingManager.SetDuplicador(fn: (Player) -> boolean)
	duplicador = fn
end
local iniciado = false

local NOMBRES_ESTACION: { [string]: string } = {
	Yunque = "Yunque",
	MesaAlquimia = "Mesa de Alquimia",
	Telar = "Telar",
}

function CraftingManager.XpPorNivel(nivel: number): number
	return math.floor(ProfesionesConfig.XpBase * nivel ^ ProfesionesConfig.XpExponente)
end

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
end

local function raizDe(player: Player): BasePart?
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

-- Estación más cercana del tipo pedido dentro de la distancia permitida.
local function estacionCercana(player: Player, tipo: string, margen: number): BasePart?
	local raiz = raizDe(player)
	if not raiz then
		return nil
	end
	local mejor: BasePart? = nil
	local mejorDistancia = ProfesionesConfig.DistanciaEstacion + margen
	for _, objeto in CollectionService:GetTagged(TAG_ESTACION) do
		if objeto:IsA("BasePart") and objeto:GetAttribute("Estacion") == tipo then
			local d = (objeto.Position - raiz.Position).Magnitude
			if d <= mejorDistancia then
				mejor, mejorDistancia = objeto, d
			end
		end
	end
	return mejor
end

-- Entrega un ítem al inventario o, si no entra, al buzón.
local function entregar(player: Player, itemId: string, cantidad: number, meta: Types.ItemMeta?, motivo: string)
	if player.Parent == Players and DataManager.AddItem(player, itemId, cantidad, "Comun", meta) then
		return
	end
	Buzon.EnviarItem(player.UserId, { ItemId = itemId, Cantidad = cantidad, Rareza = "Comun", Meta = meta }, motivo)
	if player.Parent == Players then
		avisar(player, "Inventario lleno: el objeto fue a tu buzón.", "Info")
	end
end

local function devolverMateriales(player: Player, receta: Receta)
	for itemId, cantidad in receta.Materiales do
		entregar(player, itemId, cantidad, nil, "Crafteo cancelado")
	end
end

local function efectoMasterpiece(estacion: BasePart)
	local emisor = Instance.new("ParticleEmitter")
	emisor.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 255, 255))
	emisor.LightEmission = 1
	emisor.Lifetime = NumberRange.new(0.8, 1.5)
	emisor.Speed = NumberRange.new(8, 16)
	emisor.SpreadAngle = Vector2.new(180, 180)
	emisor.Size = NumberSequence.new(0.6, 0)
	emisor.Rate = 0
	emisor.Parent = estacion
	emisor:Emit(60)
	task.delay(2, function()
		emisor:Destroy()
	end)
end

local function completar(player: Player, trabajo: Trabajo)
	if trabajos[player] ~= trabajo then
		return
	end
	trabajos[player] = nil
	local receta = trabajo.Receta

	-- Si se fue del juego, el resultado va al buzón; si se alejó, se cancela.
	if player.Parent == Players then
		local cerca = estacionCercana(player, receta.Estacion, 4)
		if not cerca then
			devolverMateriales(player, receta)
			avisar(player, "Te alejaste de la estación: se canceló y recuperaste los materiales.")
			NetworkBridge.Server.FireClient("CrafteoEstado", player, { Cancelado = true })
			return
		end
	end

	local nivel = DataManager.NivelProfesion(player, receta.Profesion)
	local probabilidad = math.min(
		ProfesionesConfig.MasterpieceMaximo,
		ProfesionesConfig.MasterpieceBase
			+ math.max(0, nivel - receta.NivelRequerido) * ProfesionesConfig.MasterpiecePorNivel
	)
	local masterpiece = math.random() < probabilidad

	local resultado = receta.Resultado
	local def = ItemCatalog[resultado.ItemId]
	local cantidad = resultado.Cantidad
	local meta: Types.ItemMeta? = nil
	if masterpiece then
		if def and def.Tipo == "Equipo" then
			local m: Types.ItemMeta = {}
			m.Mult = ProfesionesConfig.MasterpieceBonus
			m.Masterpiece = true
			meta = m
		else
			cantidad += 1
		end
	end
	-- Sobreaceleración del Chatarrero (u otro bono): duplica lo fabricado.
	if duplicador and player.Parent == Players and duplicador(player) then
		if meta then
			entregar(player, resultado.ItemId, cantidad, table.clone(meta), `Crafteo: {receta.Nombre}`)
		else
			cantidad *= 2
		end
		avisar(player, "¡Producción duplicada!", "Oro")
	end
	entregar(player, resultado.ItemId, cantidad, meta, `Crafteo: {receta.Nombre}`)

	if player.Parent ~= Players then
		return
	end
	local niveles = DataManager.AddXpProfesion(
		player,
		receta.Profesion,
		receta.Xp,
		ProfesionesConfig.NivelMaximo,
		CraftingManager.XpPorNivel
	)
	local nombreProfesion = ProfesionesConfig.Profesiones[receta.Profesion].Nombre
	if masterpiece then
		efectoMasterpiece(trabajo.Estacion)
		avisar(player, `¡Masterpiece! {receta.Nombre} de calidad excepcional.`, "Oro")
	else
		avisar(player, `Fabricaste: {receta.Nombre} x{cantidad}`, "Info")
	end
	if niveles > 0 then
		avisar(
			player,
			`¡{nombreProfesion} subió al nivel {DataManager.NivelProfesion(player, receta.Profesion)}!`,
			"Oro"
		)
	end
	NetworkBridge.Server.FireClient("CrafteoEstado", player, { Terminado = true, Masterpiece = masterpiece })
end

local function iniciar(player: Player, recetaId: string): Types.Respuesta
	local receta = ProfesionesConfig.Recetas[recetaId]
	if not receta then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if trabajos[player] then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local estacion = estacionCercana(player, receta.Estacion, 0)
	if not estacion then
		avisar(player, `Necesitás estar junto a un {NOMBRES_ESTACION[receta.Estacion]}.`)
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if DataManager.NivelProfesion(player, receta.Profesion) < receta.NivelRequerido then
		avisar(
			player,
			`Necesitás nivel {receta.NivelRequerido} de {ProfesionesConfig.Profesiones[receta.Profesion].Nombre}.`
		)
		return NetworkBridge.Fail("NOT_ALLOWED")
	end

	-- Transacción atómica: primero se verifica TODO, después se descuenta TODO.
	for itemId, cantidad in receta.Materiales do
		if not DataManager.HasItem(player, itemId, cantidad) then
			avisar(player, "Te faltan materiales.")
			return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
		end
	end
	for itemId, cantidad in receta.Materiales do
		local ok = DataManager.RemoveItem(player, itemId, cantidad)
		assert(ok, "RemoveItem falló tras verificar materiales") -- síncrono: no puede pasar
	end

	local fin = Workspace:GetServerTimeNow() + receta.Tiempo
	local trabajo: Trabajo = { RecetaId = recetaId, Receta = receta, Estacion = estacion, Fin = fin }
	trabajos[player] = trabajo
	task.delay(receta.Tiempo, completar, player, trabajo)
	return NetworkBridge.Ok({ RecetaId = recetaId, Nombre = receta.Nombre, Fin = fin })
end

------------------------------------------------------------------------
-- Estaciones
------------------------------------------------------------------------

local function prepararEstacion(objeto: Instance)
	if not objeto:IsA("BasePart") then
		return
	end
	local tipo = objeto:GetAttribute("Estacion")
	if typeof(tipo) ~= "string" or not NOMBRES_ESTACION[tipo] then
		warn(`[Crafteo] Estación {objeto:GetFullName()} sin atributo Estacion válido`)
		return
	end
	local estacion = objeto
	local prompt = estacion:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Fabricar"
	prompt.ObjectText = NOMBRES_ESTACION[tipo]
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ProfesionesConfig.DistanciaEstacion
	prompt.RequiresLineOfSight = false
	prompt.Parent = estacion
	prompt.Triggered:Connect(function(player: Player)
		local raiz = raizDe(player)
		if raiz and (raiz.Position - estacion.Position).Magnitude <= ProfesionesConfig.DistanciaEstacion + 4 then
			NetworkBridge.Server.FireClient("CrafteoAbrir", player, tipo)
		end
	end)
end

local function crearEstacionPrueba(tipo: string, offset: Vector3, color: Color3, material: Enum.Material)
	local parte = Instance.new("Part")
	parte.Name = tipo
	parte.Anchored = true
	parte.Size = Vector3.new(5, 3.5, 3)
	parte.Color = color
	parte.Material = material
	parte.Position = AREA_PRUEBA + offset + Vector3.new(0, 1.75, 0)
	parte:SetAttribute("Estacion", tipo)
	local cartel = Instance.new("BillboardGui")
	cartel.Size = UDim2.fromScale(8, 1.5)
	cartel.StudsOffset = Vector3.new(0, 3.5, 0)
	cartel.MaxDistance = 80
	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.TextColor3 = Color3.new(1, 1, 1)
	texto.TextStrokeTransparency = 0.3
	texto.Text = NOMBRES_ESTACION[tipo]
	texto.Parent = cartel
	cartel.Parent = parte
	parte.Parent = Workspace
	CollectionService:AddTag(parte, TAG_ESTACION)
end

function CraftingManager.Init()
	assert(not iniciado, "CraftingManager.Init() se llamó dos veces")
	iniciado = true

	if Pruebas.Activas() and #CollectionService:GetTagged(TAG_ESTACION) == 0 then
		crearEstacionPrueba("Yunque", Vector3.new(0, 0, 0), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
		crearEstacionPrueba("MesaAlquimia", Vector3.new(10, 0, 0), Color3.fromRGB(110, 60, 140), Enum.Material.Wood)
		crearEstacionPrueba("Telar", Vector3.new(20, 0, 0), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
	end
	for _, estacion in CollectionService:GetTagged(TAG_ESTACION) do
		prepararEstacion(estacion)
	end
	CollectionService:GetInstanceAddedSignal(TAG_ESTACION):Connect(prepararEstacion)

	NetworkBridge.Server.OnInvoke("CraftearIniciar", function(player: Player, recetaId: unknown): Types.Respuesta
		local id = NetworkBridge.Guard.OneOf(recetaId, ProfesionesConfig.Recetas)
		if not id then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return iniciar(player, id)
	end)

	-- Si el servidor se apaga con trabajos en curso, los materiales vuelven por
	-- el buzón (el trabajo se descarta, así no se entrega además el resultado).
	game:BindToClose(function()
		-- Primero directo al inventario (entra en el último guardado del perfil);
		-- si no se puede, por el buzón con id fijo, esperando a que termine.
		local enviando = 0
		for player, trabajo in table.clone(trabajos) do
			trabajos[player] = nil
			for itemId, cantidad in trabajo.Receta.Materiales do
				if not DataManager.AddItem(player, itemId, cantidad) then
					enviando += 1
					task.spawn(function()
						Buzon.EnviarItemAsync(
							player.UserId,
							{ ItemId = itemId, Cantidad = cantidad, Rareza = "Comun" },
							"Crafteo interrumpido",
							`crafteo:{player.UserId}:{math.floor(trabajo.Fin * 1000)}:{itemId}`
						)
						enviando -= 1
					end)
				end
			end
		end
		local limite = os.clock() + 25
		while enviando > 0 and os.clock() < limite do
			task.wait(0.1)
		end
	end)
end

return CraftingManager
