--!strict
-- MascotaManager: mascotas coleccionistas (Fase 6.3).
--
-- * La mascota equipada flota junto al jugador (la ven todos) y cada segundo
--   le junta el botín personal que esté a menos de MascotasConfig.RadioRecogida
--   studs (LootManager.RecogerCerca). La distancia se mide desde el jugador en
--   el servidor: el cliente no decide nada.
-- * La física de la mascota la simula el cliente del dueño (es solo visual),
--   con AlignPosition / AlignOrientation hacia un punto al lado del jugador.
-- * Se equipa desde la tienda (pestaña Colección) con EquiparMascota.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local CFG = require(ReplicatedStorage.Configs.MascotasConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local LootManager = require(script.Parent.Parent.Combate.LootManager)

type Respuesta = Types.Respuesta

local MascotaManager = {}

local iniciado = false
local ultimoPedido: { [Player]: number } = {}

local function quitar(personaje: Model)
	local vieja = personaje:FindFirstChild("Mascota")
	if vieja then
		vieja:Destroy()
	end
end

function MascotaManager.Actualizar(player: Player)
	local personaje = player.Character
	local datos = DataManager.GetData(player)
	if not personaje or not datos then
		return
	end
	local raiz = personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return
	end
	local id = datos.MascotaEquipada
	local def = if id then CFG.Mascotas[id] else nil
	local actual = personaje:FindFirstChild("Mascota")
	if actual and def and actual:GetAttribute("Id") == id then
		return -- ya está la correcta
	end
	quitar(personaje)
	if not def or not id then
		return
	end

	local cuerpo = Instance.new("Part")
	cuerpo.Name = "Mascota"
	cuerpo.Shape = Enum.PartType.Ball
	cuerpo.Size = Vector3.one * def.Tam
	cuerpo.Color = def.Color
	cuerpo.Material = def.Material
	cuerpo.CanCollide = false
	cuerpo.CanQuery = false
	cuerpo.CanTouch = false
	cuerpo.Massless = true
	cuerpo.CastShadow = false
	cuerpo.CFrame = raiz.CFrame * CFrame.new(CFG.Desplazamiento)
	cuerpo:SetAttribute("Id", id)

	-- Ojitos, para que se note hacia dónde mira.
	for _, x in { -0.2, 0.2 } do
		local ojo = Instance.new("Part")
		ojo.Shape = Enum.PartType.Ball
		ojo.Size = Vector3.one * def.Tam * 0.2
		ojo.Color = Color3.fromRGB(25, 25, 35)
		ojo.Material = Enum.Material.SmoothPlastic
		ojo.CanCollide = false
		ojo.CanQuery = false
		ojo.CanTouch = false
		ojo.Massless = true
		ojo.CFrame = cuerpo.CFrame * CFrame.new(x * def.Tam, 0.1 * def.Tam, -0.42 * def.Tam)
		local w = Instance.new("WeldConstraint")
		w.Part0 = cuerpo
		w.Part1 = ojo
		w.Parent = ojo
		ojo.Parent = cuerpo
	end

	if def.Efecto == "Fuego" then
		local f = Instance.new("Fire")
		f.Size = def.Tam * 2
		f.Heat = 3
		f.Color = def.Color
		f.Parent = cuerpo
	elseif def.Efecto == "Chispas" then
		local s = Instance.new("Sparkles")
		s.SparkleColor = def.Color
		s.Parent = cuerpo
	end
	if def.Luz then
		local l = Instance.new("PointLight")
		l.Color = def.Luz
		l.Range = 10
		l.Brightness = 1.2
		l.Parent = cuerpo
	end

	local a0 = Instance.new("Attachment")
	a0.Parent = cuerpo
	local a1 = Instance.new("Attachment")
	a1.Name = "PuntoMascota"
	a1.Position = CFG.Desplazamiento
	a1.Parent = raiz
	cuerpo.Destroying:Connect(function()
		a1:Destroy()
	end)

	local alinear = Instance.new("AlignPosition")
	alinear.Attachment0 = a0
	alinear.Attachment1 = a1
	alinear.Responsiveness = 18
	alinear.MaxForce = 1e5
	alinear.Parent = cuerpo
	local girar = Instance.new("AlignOrientation")
	girar.Attachment0 = a0
	girar.Attachment1 = a1
	girar.Responsiveness = 12
	girar.MaxTorque = 1e5
	girar.Parent = cuerpo

	cuerpo.Parent = personaje
	pcall(function()
		cuerpo:SetNetworkOwner(player)
	end)
end

local function elegir(player: Player, id: string): Respuesta
	local datos = DataManager.GetData(player)
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	if id ~= "" and (not CFG.Mascotas[id] or not datos.Mascotas or not table.find(datos.Mascotas, id)) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	DataManager.Mutar(player, "Cosmeticos", function(d)
		d.MascotaEquipada = if id == "" then nil else id
	end)
	MascotaManager.Actualizar(player)
	return NetworkBridge.Ok(nil)
end

function MascotaManager.Init()
	assert(not iniciado, "MascotaManager.Init() se llamó dos veces")
	iniciado = true

	NetworkBridge.Server.OnInvoke("EquiparMascota", function(player: Player, id: unknown): Respuesta
		local i = if id == "" then "" else NetworkBridge.Guard.String(id, 40)
		if not i then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		local t = os.clock()
		if t - (ultimoPedido[player] or 0) < 0.5 then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		ultimoPedido[player] = t
		return elegir(player, i)
	end)

	local function alEntrar(player: Player)
		player.CharacterAdded:Connect(function(personaje: Model)
			personaje:WaitForChild("HumanoidRootPart", 10)
			if player.Character == personaje then
				MascotaManager.Actualizar(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(alEntrar)
	for _, p in Players:GetPlayers() do
		alEntrar(p)
	end
	DataManager.PerfilCargado:Connect(function(player: Player)
		MascotaManager.Actualizar(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		ultimoPedido[player] = nil
	end)

	-- Recolección automática.
	task.spawn(function()
		while true do
			task.wait(CFG.IntervaloRecogida)
			for _, player in Players:GetPlayers() do
				local datos = DataManager.GetData(player)
				if datos and datos.MascotaEquipada and CFG.Mascotas[datos.MascotaEquipada] then
					LootManager.RecogerCerca(player, CFG.RadioRecogida)
				end
			end
		end
	end)
end

return MascotaManager
