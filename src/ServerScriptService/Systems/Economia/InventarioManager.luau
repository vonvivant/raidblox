--!strict
-- InventarioManager: acciones del jugador sobre su inventario.
--
-- * MoverItem(desde, hacia): mover, combinar pilas o intercambiar (drag & drop).
-- * DividirPila(desde, cantidad): separar una pila en una ranura libre.
-- * UsarItem(ranura): consumibles (pociones con cooldown compartido).
-- * DestruirItem(ranura): borrar un ítem (el cliente pide confirmación antes).
-- * Equipar/desequipar ya están en CombatManager (afectan las estadísticas).
-- * Kit inicial: herramientas de recolección para cada jugador nuevo.
--
-- Todo lo valida y lo ejecuta DataManager de forma síncrona: no hay estados a medias.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ProfesionesConfig = require(ReplicatedStorage.Configs.ProfesionesConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local CombatManager = require(script.Parent.Parent.Combate.CombatManager)
local BuffManager = require(script.Parent.Parent.Combate.BuffManager)

local InventarioManager = {}

local MAX_RANURA = 500 -- techo de validación; la cantidad real la limita MaxSlots
local proximaPocion: { [Player]: number } = {}
local iniciado = false

local function ranura(valor: unknown): string?
	local n = NetworkBridge.Guard.Integer(valor, 1, MAX_RANURA)
	return if n then tostring(n) else nil
end

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
end

local function usar(player: Player, clave: string)
	local item = DataManager.ItemEnRanura(player, clave)
	local def = item and ItemCatalog[item.ItemId]
	if not item or not def then
		return
	end
	local consumo = def.Consumo
	local conEfecto, instantaneo = BuffManager.Maneja(item.ItemId)
	if def.Tipo ~= "Consumible" or (not consumo and not conEfecto) then
		avisar(player, "Ese objeto no se puede usar.")
		return
	end
	local t = Workspace:GetServerTimeNow()
	-- Pociones y consumibles instantáneos comparten recarga; los temporales
	-- (elixires, tónicos, infusiones) no la usan.
	if (consumo or instantaneo) and t < (proximaPocion[player] or 0) then
		avisar(player, `Esperá {math.ceil((proximaPocion[player] or 0) - t)} s para otra poción.`)
		return
	end
	if conEfecto then
		local ok, motivo = BuffManager.Usar(player, item.ItemId)
		if not ok then
			avisar(player, motivo or "No podés usarlo ahora.")
			return
		end
		-- Se consume recién cuando el efecto se aplicó.
		DataManager.QuitarDeRanura(player, clave, 1)
		if instantaneo then
			proximaPocion[player] = t + GameConfig.Consumibles.CooldownPociones
		end
		return
	end
	if not consumo then
		return
	end
	if not CombatManager.RecuperarJugador(player, consumo.Recurso, consumo.Porcentaje) then
		avisar(player, if consumo.Recurso == "Vida" then "Tu vida ya está llena." else "Tu maná ya está lleno.")
		return
	end
	-- Se consume recién cuando el efecto se aplicó.
	DataManager.QuitarDeRanura(player, clave, 1)
	proximaPocion[player] = t + GameConfig.Consumibles.CooldownPociones
end

local function entregarKit(player: Player)
	if not DataManager.MarcarKitInicial(player) then
		return
	end
	for _, itemId in ProfesionesConfig.KitInicial do
		if not DataManager.AddItem(player, itemId, 1, "Comun", nil) then
			warn(`[Inventario] No entró el kit inicial ({itemId}) para {player.UserId}`)
		end
	end
	avisar(player, "Recibiste un pico y una hoz: equipalos para recolectar.", "Oro")
end

function InventarioManager.Init()
	assert(not iniciado, "InventarioManager.Init() se llamó dos veces")
	iniciado = true

	NetworkBridge.Server.OnEvent("MoverItem", function(player: Player, desde: unknown, hacia: unknown)
		local a, b = ranura(desde), ranura(hacia)
		if a and b then
			DataManager.MoverRanura(player, a, b)
		end
	end)

	NetworkBridge.Server.OnEvent("DividirPila", function(player: Player, desde: unknown, cantidad: unknown)
		local a = ranura(desde)
		local n = NetworkBridge.Guard.Integer(cantidad, 1, 999)
		if a and n then
			local ok, codigo = DataManager.DividirPila(player, a, n)
			if not ok and codigo == "INVENTORY_FULL" then
				avisar(player, "No hay ranuras libres para dividir la pila.")
			end
		end
	end)

	NetworkBridge.Server.OnEvent("UsarItem", function(player: Player, valor: unknown)
		local clave = ranura(valor)
		if clave then
			usar(player, clave)
		end
	end)

	NetworkBridge.Server.OnInvoke("DestruirItem", function(player: Player, valor: unknown): Types.Respuesta
		local clave = ranura(valor)
		local item = clave and DataManager.ItemEnRanura(player, clave)
		if not clave or not item then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		DataManager.QuitarDeRanura(player, clave, item.Cantidad)
		return NetworkBridge.Ok(nil)
	end)

	DataManager.PerfilCargado:Connect(entregarKit)
	for _, player in game:GetService("Players"):GetPlayers() do
		if DataManager.IsLoaded(player) then
			task.spawn(entregarKit, player)
		end
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		proximaPocion[player] = nil
	end)
end

return InventarioManager
