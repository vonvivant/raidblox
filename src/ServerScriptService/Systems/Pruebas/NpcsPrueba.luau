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
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local DataManager = require(script.Parent.Parent.DataManager)
local ConfigServidor = require(script.Parent.Parent.ConfigServidor)
local NpcFactory = require(script.Parent.Parent.NpcFactory)

local ORO_POR_CLIC = 10_000
local PRECIO_MATERIAL = 1
local DISTANCIA_MAXIMA = 14
local POS_BANQUERO = Vector3.new(68, 0, -52)
local POS_MERCADER = Vector3.new(78, 0, -52)

local NpcsPrueba = {}

local mercader: BasePart? = nil
local ultimoClic: { [Player]: number } = {}
local iniciado = false

-- En un servidor publicado, solo el creador y los probadores anotados en
-- ConfigServidor (lista que los clientes no ven). En Studio, todos.
local function permitido(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(ConfigServidor.Probadores, player.UserId) ~= nil
end

NpcsPrueba.Permitido = permitido

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function cerca(player: Player, parte: BasePart): boolean
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return raiz ~= nil and raiz:IsA("BasePart") and (raiz.Position - parte.Position).Magnitude <= DISTANCIA_MAXIMA
end

local function darOro(player: Player, banquero: BasePart)
	local ahora = os.clock()
	if ahora - (ultimoClic[player] or 0) < 0.5 or not cerca(player, banquero) then
		return
	end
	ultimoClic[player] = ahora
	if not permitido(player) then
		avisar(player, "Este NPC es solo para los probadores del juego.", "Error")
		return
	end
	if DataManager.AddGold(player, ORO_POR_CLIC) then
		avisar(player, `+{ORO_POR_CLIC} de oro (pruebas)`, "Oro")
	else
		avisar(player, "No se pudo dar el oro (¿llegaste al tope?).", "Error")
	end
end

local function comprar(player: Player, itemId: unknown, cantidad: unknown): Types.Respuesta
	local m = mercader
	if not Pruebas.Activas() or not m or not permitido(player) then
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

	local banquero, promptOro = NpcFactory.Crear(
		"BanqueroPruebas",
		"Banquero de pruebas",
		POS_BANQUERO,
		Color3.fromRGB(230, 180, 40),
		"+10.000 de oro"
	)
	promptOro.Triggered:Connect(function(player: Player)
		darOro(player, banquero)
	end)

	local raizMercader, promptTienda = NpcFactory.Crear(
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
