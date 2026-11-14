--!strict
-- LootManager: generación de ítems con rareza y botín personal (instanciado).
--
-- * Cada jugador recibe su propio botín: nadie puede robar el de otro.
-- * El botín aparece como una bolsa que solo ve su dueño (la dibuja su cliente),
--   con un haz de luz vertical si es Épico, Místico o Único.
-- * Para recogerlo, el cliente pide RecogerBotin(id); el servidor valida que la
--   bolsa sea suya, que exista y que esté cerca.
-- * Si no lo recoge en 2 minutos o se desconecta, se le entrega igual (al
--   inventario o, si está lleno, al buzón). El botín nunca se pierde.
-- * Un Único se anuncia a todo el servidor.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ItemRarityConfig = require(ReplicatedStorage.Configs.ItemRarityConfig)
local EnemigosConfig = require(ReplicatedStorage.Configs.EnemigosConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local Buzon = require(script.Parent.Parent.Buzon)

type Rareza = Types.Rareza
type ItemMeta = Types.ItemMeta

export type ItemGenerado = {
	ItemId: string,
	Cantidad: number,
	Rareza: Rareza,
	Meta: ItemMeta?,
}

type Pendiente = {
	Item: ItemGenerado,
	Posicion: Vector3,
	Expira: number,
	Origen: string,
}

local LootManager = {}

local DISTANCIA_RECOGIDA = 14
local DURACION_BOLSA = 120
local azar = Random.new()
local pendientes: { [Player]: { [string]: Pendiente } } = {}
local iniciado = false

local RAREZAS: { [string]: Rareza } = {
	Comun = "Comun",
	Raro = "Raro",
	Epico = "Epico",
	Mistico = "Mistico",
	Unico = "Unico",
}

------------------------------------------------------------------------
-- Generación
------------------------------------------------------------------------

local function sortearRareza(): Rareza
	local total = 0
	for _, peso in ItemRarityConfig.PesosPorDefecto do
		total += peso
	end
	local tirada = azar:NextNumber() * total
	for nombre, peso in ItemRarityConfig.PesosPorDefecto do
		tirada -= peso
		if tirada <= 0 then
			return RAREZAS[nombre] or "Comun"
		end
	end
	return "Comun"
end

-- Crea los metadatos de un equipo según su rareza: multiplicador, efectos
-- secundarios (sin repetir) y pasiva.
local function generarMeta(rareza: Rareza): ItemMeta?
	local def = ItemRarityConfig.Rarezas[rareza]
	if not def or rareza == "Comun" then
		return nil
	end
	local meta: ItemMeta = { Mult = def.Multiplicador }

	local efectos: { string } = {}
	for clave in ItemRarityConfig.Efectos do
		table.insert(efectos, clave)
	end
	table.sort(efectos) -- orden estable antes de mezclar
	for i = #efectos, 2, -1 do
		local j = azar:NextInteger(1, i)
		efectos[i], efectos[j] = efectos[j], efectos[i]
	end
	for i = 1, math.min(def.EfectosSecundarios, #efectos) do
		local efecto = ItemRarityConfig.Efectos[efectos[i]]
		meta["Efecto_" .. efectos[i]] = azar:NextInteger(efecto.Min, efecto.Max)
	end

	if def.TienePasiva then
		local pasivas: { string } = {}
		for clave in ItemRarityConfig.Pasivas do
			table.insert(pasivas, clave)
		end
		table.sort(pasivas)
		meta.Pasiva = pasivas[azar:NextInteger(1, #pasivas)]
	end
	if def.Aura then
		meta.Aura = true
	end
	return meta
end

-- Genera un ítem: los equipos sortean rareza (o usan la fija); el resto es Común.
function LootManager.GenerarItem(itemId: string, cantidad: number, rarezaFija: string?): ItemGenerado?
	local def = ItemCatalog[itemId]
	if not def then
		warn(`[Botin] Ítem desconocido en tabla de botín: {itemId}`)
		return nil
	end
	if def.Tipo ~= "Equipo" then
		return { ItemId = itemId, Cantidad = cantidad, Rareza = "Comun", Meta = nil }
	end
	local rareza: Rareza = if rarezaFija and RAREZAS[rarezaFija] then RAREZAS[rarezaFija] else sortearRareza()
	-- Los Únicos solo existen si vienen fijados por un RaidBlox.
	if rareza == "Unico" and not def.SoloRaidBlox then
		rareza = "Mistico"
	end
	return { ItemId = itemId, Cantidad = 1, Rareza = rareza, Meta = generarMeta(rareza) }
end

-- Tira una tabla de botín y devuelve lo que salió.
function LootManager.TirarTabla(tabla: { EnemigosConfig.EntradaBotin }): { ItemGenerado }
	local resultado: { ItemGenerado } = {}
	for _, entrada in tabla do
		if azar:NextNumber() <= entrada.Probabilidad then
			local cantidad = azar:NextInteger(entrada.Min, math.max(entrada.Min, entrada.Max))
			local item = LootManager.GenerarItem(entrada.ItemId, cantidad, entrada.Rareza)
			if item then
				table.insert(resultado, item)
			end
		end
	end
	return resultado
end

------------------------------------------------------------------------
-- Entrega
------------------------------------------------------------------------

local function nombreItem(item: ItemGenerado): string
	local def = ItemCatalog[item.ItemId]
	return if def then def.Nombre else item.ItemId
end

-- Envía un ítem al buzón (reintentos, id fijo y espera al cierre: módulo Buzon).
local function enviarAlBuzon(userId: number, item: ItemGenerado, origen: string)
	Buzon.EnviarItem(userId, item, origen)
end

-- Entrega sin bolsa: inventario o, si está lleno, buzón.
local function entregarDirecto(player: Player, item: ItemGenerado, origen: string)
	local ok = DataManager.AddItem(player, item.ItemId, item.Cantidad, item.Rareza, item.Meta)
	if not ok then
		enviarAlBuzon(player.UserId, item, origen)
	end
end

local function retirar(player: Player, id: string)
	local delJugador = pendientes[player]
	if delJugador then
		delJugador[id] = nil
	end
	NetworkBridge.Server.FireClient("BotinRetirado", player, id)
end

-- Suelta botín personal cerca de `posicion` para un jugador.
function LootManager.Soltar(player: Player, posicion: Vector3, items: { ItemGenerado }, origen: string)
	if player.Parent ~= Players then
		return
	end
	local delJugador = pendientes[player]
	if not delJugador then
		delJugador = {}
		pendientes[player] = delJugador
	end
	local t = os.clock()
	for i, item in items do
		local id = HttpService:GenerateGUID(false)
		-- Las bolsas se reparten en círculo para que no se superpongan.
		local angulo = (i / math.max(1, #items)) * math.pi * 2
		local pos = posicion + Vector3.new(math.cos(angulo) * 3, 0, math.sin(angulo) * 3)
		delJugador[id] = { Item = item, Posicion = pos, Expira = t + DURACION_BOLSA, Origen = origen }

		local rareza = ItemRarityConfig.Rarezas[item.Rareza]
		NetworkBridge.Server.FireClient("BotinSoltado", player, id, pos, {
			Nombre = nombreItem(item),
			Cantidad = item.Cantidad,
			Rareza = item.Rareza,
			NombreRareza = rareza.Nombre,
			Color = rareza.Color,
			Haz = rareza.Haz,
			Particulas = rareza.Particulas,
		})

		if rareza.AnuncioGlobal then
			NetworkBridge.Server.FireAll(
				"AnuncioGlobal",
				`¡{player.DisplayName} obtuvo {nombreItem(item)} ({rareza.Nombre}) de {origen}!`,
				rareza.Color
			)
		end
	end
end

local function recoger(player: Player, id: string)
	local delJugador = pendientes[player]
	local pendiente = delJugador and delJugador[id]
	if not pendiente then
		return -- no existe o no es suyo
	end
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return
	end
	if (raiz.Position - pendiente.Posicion).Magnitude > DISTANCIA_RECOGIDA then
		return
	end
	local item = pendiente.Item
	local ok = DataManager.AddItem(player, item.ItemId, item.Cantidad, item.Rareza, item.Meta)
	if not ok then
		NetworkBridge.Server.FireClient("Notificacion", player, "Inventario lleno.", "Error")
		return
	end
	retirar(player, id)
	NetworkBridge.Server.FireClient(
		"Notificacion",
		player,
		`+{nombreItem(item)} x{item.Cantidad}`,
		if item.Rareza == "Comun" then "Info" else "Oro"
	)
end

-- Mascotas coleccionistas: junta todo el botín del jugador a menos de `radio`
-- studs. Devuelve cuántas bolsas juntó. Si el inventario se llena, para (las
-- bolsas siguen ahí y al vencer van al buzón).
function LootManager.RecogerCerca(player: Player, radio: number): number
	local delJugador = pendientes[player]
	if not delJugador or next(delJugador) == nil then
		return 0
	end
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return 0
	end
	local juntadas = 0
	for id, p in table.clone(delJugador) do
		if (raiz.Position - p.Posicion).Magnitude <= radio then
			local item = p.Item
			if not DataManager.AddItem(player, item.ItemId, item.Cantidad, item.Rareza, item.Meta) then
				break
			end
			retirar(player, id)
			juntadas += 1
			NetworkBridge.Server.FireClient(
				"Notificacion",
				player,
				`🐾 +{nombreItem(item)} x{item.Cantidad}`,
				if item.Rareza == "Comun" then "Info" else "Oro"
			)
		end
	end
	return juntadas
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function LootManager.Init()
	assert(not iniciado, "LootManager.Init() se llamó dos veces")
	iniciado = true

	NetworkBridge.Server.OnEvent("RecogerBotin", function(player: Player, id: unknown)
		local s = NetworkBridge.Guard.String(id, 64)
		if s then
			recoger(player, s)
		end
	end)

	-- Al salir, todo lo pendiente va al buzón.
	Players.PlayerRemoving:Connect(function(player: Player)
		local delJugador = pendientes[player]
		pendientes[player] = nil
		if not delJugador then
			return
		end
		for _, p in delJugador do
			enviarAlBuzon(player.UserId, p.Item, p.Origen)
		end
	end)

	-- Bolsas vencidas: se entregan solas.
	task.spawn(function()
		while true do
			task.wait(5)
			local t = os.clock()
			for player, delJugador in pendientes do
				for id, p in table.clone(delJugador) do
					if p.Expira <= t then
						retirar(player, id)
						entregarDirecto(player, p.Item, p.Origen)
					end
				end
			end
		end
	end)
end

return LootManager
