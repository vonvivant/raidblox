--!strict
-- NpcsPrueba: dos NPCs para probar la economía sin farmear.
--
--   * Banquero de pruebas: da 10.000 de oro por clic.
--   * Mercader de materiales: vende cualquier material a 1 de oro la unidad.
--
-- Solo existen con Pruebas.Activas() (Studio o GameConfig.ModoPruebas). Todo lo
-- valida el servidor: modo de pruebas, distancia al NPC, que el ítem sea un
-- material del catálogo y la cantidad. OJO: el oro y los materiales se guardan
-- en el perfil real (Studio y el juego publicado comparten el guardado).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local DataManager = require(script.Parent.Parent.DataManager)

local ORO_POR_CLIC = 10_000
local PRECIO_MATERIAL = 1
local DISTANCIA_MAXIMA = 14
local POS_BANQUERO = Vector3.new(68, 0, -52)
local POS_MERCADER = Vector3.new(78, 0, -52)

local NpcsPrueba = {}

local mercader: BasePart? = nil
local ultimoClic: { [Player]: number } = {}
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function cerca(player: Player, parte: BasePart): boolean
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return raiz ~= nil and raiz:IsA("BasePart") and (raiz.Position - parte.Position).Magnitude <= DISTANCIA_MAXIMA
end

-- Crea un NPC quieto con cartel y ProximityPrompt. Devuelve su raíz.
local function crearNpc(
	nombre: string,
	titulo: string,
	posicion: Vector3,
	color: Color3,
	accion: string
): (BasePart, ProximityPrompt)
	local modelo: Model
	local ok, resultado = pcall(function()
		local descripcion = Instance.new("HumanoidDescription")
		descripcion.HeadColor = Color3.fromRGB(234, 184, 146)
		descripcion.TorsoColor = color
		descripcion.LeftArmColor = color
		descripcion.RightArmColor = color
		descripcion.LeftLegColor = Color3.fromRGB(40, 40, 50)
		descripcion.RightLegColor = Color3.fromRGB(40, 40, 50)
		return Players:CreateHumanoidModelFromDescription(descripcion, Enum.HumanoidRigType.R15)
	end)
	if ok and typeof(resultado) == "Instance" and resultado:IsA("Model") then
		modelo = resultado
	else
		modelo = Instance.new("Model")
		local cuerpo = Instance.new("Part")
		cuerpo.Name = "HumanoidRootPart"
		cuerpo.Size = Vector3.new(2, 5, 1)
		cuerpo.Color = color
		cuerpo.Parent = modelo
		modelo.PrimaryPart = cuerpo
	end
	modelo.Name = nombre
	local raiz = modelo:FindFirstChild("HumanoidRootPart") :: BasePart
	for _, d in modelo:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = titulo
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.NameDisplayDistance = 60
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	-- Mirando hacia el spawn.
	local alto = if humanoid then humanoid.HipHeight + raiz.Size.Y / 2 else 2.5
	local pos = posicion + Vector3.new(0, alto, 0)
	modelo:PivotTo(CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = accion
	prompt.ObjectText = titulo
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = raiz
	modelo.Parent = Workspace
	return raiz, prompt
end

local function darOro(player: Player, banquero: BasePart)
	local ahora = os.clock()
	if ahora - (ultimoClic[player] or 0) < 0.5 or not cerca(player, banquero) then
		return
	end
	ultimoClic[player] = ahora
	if DataManager.AddGold(player, ORO_POR_CLIC) then
		avisar(player, `+{ORO_POR_CLIC} de oro (pruebas)`, "Oro")
	else
		avisar(player, "No se pudo dar el oro (¿llegaste al tope?).", "Error")
	end
end

local function comprar(player: Player, itemId: unknown, cantidad: unknown): Types.Respuesta
	local m = mercader
	if not Pruebas.Activas() or not m then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local id = NetworkBridge.Guard.OneOf(itemId, ItemCatalog)
	local n = NetworkBridge.Guard.Integer(cantidad, 1, 99)
	if not id or not n then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local def = ItemCatalog[id]
	if not def or def.Tipo ~= "Material" then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not cerca(player, m) then
		avisar(player, "Acercate al mercader.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local costo = n * PRECIO_MATERIAL
	if not DataManager.SpendGold(player, costo) then
		avisar(player, "No tenés oro suficiente. Pedile al banquero.", "Error")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	local ok = DataManager.AddItem(player, id, n)
	if not ok then
		DataManager.AddGold(player, costo) -- todo o nada
		avisar(player, "No tenés lugar en la mochila.", "Error")
		return NetworkBridge.Fail("INVENTORY_FULL")
	end
	avisar(player, `Compraste {n} × {def.Nombre} por {costo} de oro.`, "Oro")
	return NetworkBridge.Ok(nil)
end

function NpcsPrueba.Init()
	assert(not iniciado, "NpcsPrueba.Init() se llamó dos veces")
	iniciado = true
	if not Pruebas.Activas() then
		return
	end

	local banquero, promptOro =
		crearNpc("BanqueroPruebas", "Banquero de pruebas", POS_BANQUERO, Color3.fromRGB(230, 180, 40), "+10.000 de oro")
	promptOro.Triggered:Connect(function(player: Player)
		darOro(player, banquero)
	end)

	local raizMercader, promptTienda = crearNpc(
		"MercaderPruebas",
		"Mercader de materiales",
		POS_MERCADER,
		Color3.fromRGB(70, 140, 90),
		"Comprar materiales"
	)
	mercader = raizMercader
	promptTienda.Triggered:Connect(function(player: Player)
		if cerca(player, raizMercader) then
			NetworkBridge.Server.FireClient("TiendaPruebaAbrir", player)
		end
	end)

	NetworkBridge.Server.OnInvoke("TiendaPruebaComprar", comprar)
	Players.PlayerRemoving:Connect(function(player: Player)
		ultimoClic[player] = nil
	end)
end

return NpcsPrueba
