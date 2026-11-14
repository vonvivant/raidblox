--!strict
-- VaultManager: bóveda global del jugador (banco personal).
--
-- * Hasta 8 pestañas de 30 ranuras, guardadas en el perfil (`Vault`).
-- * Se opera solo cerca de un punto de bóveda: un Banquero, un banco de ciudad
--   (tag "BancoVault") o el cofre de bóveda de una parcela (tag "CofreVault").
-- * Todas las operaciones son del servidor y de "todo o nada": primero se
--   verifica que la operación entera se pueda hacer y recién después se mueven
--   los ítems, sin ceder el hilo en el medio (no hay forma de duplicar).
-- * Las pestañas se compran con oro (precio creciente); el pase VIP suma una.
--
-- Los ítems conservan su Uid, rareza y metadatos al entrar y salir.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local VaultConfig = require(ReplicatedStorage.Configs.VaultConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local NpcManager = require(script.Parent.Parent.NpcManager)
local PasesManager = require(script.Parent.Parent.Monetizacion.PasesManager)

type ItemInstancia = Types.ItemInstancia
type Vault = Types.Vault
type PestanaVault = Types.PestanaVault

local RANURAS = VaultConfig.RanurasPorPestana

local VaultManager = {}

local iniciado = false
local iconosValidos: { [string]: boolean } = {}
for _, icono in VaultConfig.Iconos do
	iconosValidos[icono] = true
end

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
end

------------------------------------------------------------------------
-- Acceso a los datos
------------------------------------------------------------------------

-- Bóveda del perfil (la crea la primera vez).
local function vaultDe(datos: Types.DatosJugador): Vault
	local vault = datos.Vault
	if not vault then
		local nueva: Vault = { Compradas = VaultConfig.PestanasIniciales, Pestanas = {} }
		datos.Vault = nueva
		return nueva
	end
	return vault
end

local function pestanaDe(vault: Vault, numero: number): PestanaVault
	local clave = tostring(numero)
	local pestana = vault.Pestanas[clave]
	if not pestana then
		local nueva: PestanaVault = { Nombre = `Pestaña {numero}`, Icono = VaultConfig.Iconos[1], Slots = {} }
		vault.Pestanas[clave] = nueva
		return nueva
	end
	return pestana
end

-- Pestañas que puede usar: las compradas más las del pase.
function VaultManager.Disponibles(player: Player): number
	local datos = DataManager.GetData(player)
	local compradas = if datos and datos.Vault then datos.Vault.Compradas else VaultConfig.PestanasIniciales
	local extra = if PasesManager.Tiene(player, VaultConfig.Pase) then VaultConfig.PestanasConPase else 0
	return math.min(VaultConfig.MaxPestanas, compradas + extra)
end

local function maxStackDe(itemId: string): number
	local def = ItemCatalog[itemId]
	if not def or not def.Apilable then
		return 1
	end
	return def.MaxStack or GameConfig.Inventario.MaxStackPorDefecto
end

-- ¿`item` se puede sumar a la pila `otro`?
local function apilables(item: ItemInstancia, otro: ItemInstancia): boolean
	return item.ItemId == otro.ItemId and item.Rareza == otro.Rareza and item.Meta == nil and otro.Meta == nil
end

local function primeraLibre(pestana: PestanaVault): string?
	for i = 1, RANURAS do
		local clave = tostring(i)
		if pestana.Slots[clave] == nil then
			return clave
		end
	end
	return nil
end

-- Cuánto de `item` entra en la pestaña (sumando a pilas iguales y ranuras libres).
local function capacidad(pestana: PestanaVault, item: ItemInstancia): number
	local maxStack = maxStackDe(item.ItemId)
	local apila = maxStack > 1 and item.Meta == nil
	local total = 0
	for i = 1, RANURAS do
		local otro = pestana.Slots[tostring(i)]
		if otro == nil then
			total += maxStack
		elseif apila and apilables(item, otro) then
			total += math.max(0, maxStack - otro.Cantidad)
		end
	end
	return total
end

-- Guarda `item` entero en la pestaña. Llamar solo si capacidad() alcanzó.
local function guardar(pestana: PestanaVault, item: ItemInstancia)
	local maxStack = maxStackDe(item.ItemId)
	if maxStack > 1 and item.Meta == nil then
		for i = 1, RANURAS do
			local otro = pestana.Slots[tostring(i)]
			if otro and apilables(item, otro) and otro.Cantidad < maxStack then
				local pasa = math.min(item.Cantidad, maxStack - otro.Cantidad)
				otro.Cantidad += pasa
				item.Cantidad -= pasa
				if item.Cantidad == 0 then
					return
				end
			end
		end
	end
	-- Lo que queda va a ranuras libres (la primera conserva la instancia original).
	local primera = true
	while item.Cantidad > 0 do
		local clave = primeraLibre(pestana)
		assert(clave, "guardar() sin lugar: faltó verificar capacidad()")
		local pasa = math.min(item.Cantidad, maxStack)
		if primera and pasa == item.Cantidad then
			pestana.Slots[clave] = item
			return
		end
		pestana.Slots[clave] = {
			Uid = if primera then item.Uid else HttpService:GenerateGUID(false),
			ItemId = item.ItemId,
			Cantidad = pasa,
			Rareza = item.Rareza,
			Meta = nil, -- solo se parte en varias pilas lo que no tiene metadatos
		}
		item.Cantidad -= pasa
		primera = false
	end
end

------------------------------------------------------------------------
-- Cercanía
------------------------------------------------------------------------

local function raizDe(player: Player): BasePart?
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

-- ¿Está junto a un punto de bóveda?
function VaultManager.Cerca(player: Player): boolean
	local raiz = raizDe(player)
	if not raiz then
		return false
	end
	for _, tag in VaultConfig.Tags do
		for _, punto in CollectionService:GetTagged(tag) do
			if punto:IsA("BasePart") and (punto.Position - raiz.Position).Magnitude <= VaultConfig.Distancia then
				return true
			end
		end
	end
	return false
end

function VaultManager.Abrir(player: Player): boolean
	if not VaultManager.Cerca(player) or not DataManager.GetData(player) then
		return false
	end
	NetworkBridge.Server.FireClient("VaultAbrir", player, VaultManager.Disponibles(player))
	return true
end

-- Validación común: datos cargados, cerca de un punto de bóveda y pestaña
-- desbloqueada. Devuelve los datos del jugador o el código de error.
local function validar(player: Player, ...: number): (Types.DatosJugador?, string?)
	local datos = DataManager.GetData(player)
	if not datos then
		return nil, "DATA_NOT_LOADED"
	end
	if not VaultManager.Cerca(player) then
		avisar(player, "Tenés que estar junto a un banco o un cofre de bóveda.")
		return nil, "NOT_ALLOWED"
	end
	local disponibles = VaultManager.Disponibles(player)
	for _, numero in { ... } do
		if numero > disponibles then
			return nil, "NOT_ALLOWED"
		end
	end
	return datos, nil
end

local function fallo(codigo: string?): Types.Respuesta
	return NetworkBridge.Fail((codigo or "INTERNAL_ERROR") :: any)
end

local function sincronizar(player: Player)
	DataManager.Mutar(player, "Vault", function() end)
end

------------------------------------------------------------------------
-- Operaciones
------------------------------------------------------------------------

local function depositar(player: Player, ranuraMochila: string, numero: number, cantidad: number): Types.Respuesta
	local datos, codigo = validar(player, numero)
	if not datos then
		return fallo(codigo)
	end
	local item = DataManager.ItemEnRanura(player, ranuraMochila)
	if not item or item.Cantidad < cantidad then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local pestana = pestanaDe(vaultDe(datos), numero)
	local muestra: ItemInstancia =
		{ Uid = item.Uid, ItemId = item.ItemId, Cantidad = cantidad, Rareza = item.Rareza, Meta = item.Meta }
	if capacidad(pestana, muestra) < cantidad then
		avisar(player, "Esa pestaña está llena.")
		return NetworkBridge.Fail("INVENTORY_FULL")
	end
	local quitado = DataManager.QuitarDeRanura(player, ranuraMochila, cantidad)
	if not quitado then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	guardar(pestana, quitado)
	sincronizar(player)
	return NetworkBridge.Ok(nil)
end

local function retirar(player: Player, numero: number, ranura: string, cantidad: number): Types.Respuesta
	local datos, codigo = validar(player, numero)
	if not datos then
		return fallo(codigo)
	end
	local pestana = pestanaDe(vaultDe(datos), numero)
	local item = pestana.Slots[ranura]
	if not item or item.Cantidad < cantidad then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local sale: ItemInstancia = if cantidad == item.Cantidad
		then item
		else {
			Uid = HttpService:GenerateGUID(false),
			ItemId = item.ItemId,
			Cantidad = cantidad,
			Rareza = item.Rareza,
			Meta = if item.Meta then table.clone(item.Meta) else nil,
		}
	-- AgregarInstancia es todo o nada: si no entra, la bóveda queda igual.
	if not DataManager.AgregarInstancia(player, sale) then
		avisar(player, "No tenés lugar en la mochila.")
		return NetworkBridge.Fail("INVENTORY_FULL")
	end
	if sale == item then
		pestana.Slots[ranura] = nil
	else
		item.Cantidad -= cantidad
	end
	sincronizar(player)
	return NetworkBridge.Ok(nil)
end

-- Mueve dentro de la bóveda. `ranuraB` nil = primera ranura libre de la pestaña B
-- (o pilas iguales). Si el destino está ocupado: suma a la pila si es el mismo
-- ítem; si no, intercambia.
local function mover(
	player: Player,
	numeroA: number,
	ranuraA: string,
	numeroB: number,
	ranuraB: string?
): Types.Respuesta
	local datos, codigo = validar(player, numeroA, numeroB)
	if not datos then
		return fallo(codigo)
	end
	local vault = vaultDe(datos)
	local pestanaA = pestanaDe(vault, numeroA)
	local pestanaB = pestanaDe(vault, numeroB)
	local item = pestanaA.Slots[ranuraA]
	if not item then
		return NetworkBridge.Fail("NOT_FOUND")
	end

	if ranuraB == nil then
		if pestanaA == pestanaB then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if capacidad(pestanaB, item) < item.Cantidad then
			avisar(player, "Esa pestaña está llena.")
			return NetworkBridge.Fail("INVENTORY_FULL")
		end
		pestanaA.Slots[ranuraA] = nil
		guardar(pestanaB, item)
	else
		if pestanaA == pestanaB and ranuraA == ranuraB then
			return NetworkBridge.Ok(nil)
		end
		local otro = pestanaB.Slots[ranuraB]
		local maxStack = maxStackDe(item.ItemId)
		if otro and maxStack > 1 and apilables(item, otro) and otro.Cantidad < maxStack then
			local pasa = math.min(item.Cantidad, maxStack - otro.Cantidad)
			otro.Cantidad += pasa
			item.Cantidad -= pasa
			if item.Cantidad == 0 then
				pestanaA.Slots[ranuraA] = nil
			end
		else
			pestanaA.Slots[ranuraA] = otro :: any -- nil si el destino estaba vacío
			pestanaB.Slots[ranuraB] = item
		end
	end
	sincronizar(player)
	return NetworkBridge.Ok(nil)
end

local function expandir(player: Player): Types.Respuesta
	local datos, codigo = validar(player)
	if not datos then
		return fallo(codigo)
	end
	local vault = vaultDe(datos)
	if VaultManager.Disponibles(player) >= VaultConfig.MaxPestanas then
		avisar(player, "Ya tenés todas las pestañas.", "Info")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local costo = VaultConfig.CostoPestana[vault.Compradas]
	if not costo then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not DataManager.SpendGold(player, costo) then
		avisar(player, `La próxima pestaña cuesta {costo} de oro.`)
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	vault.Compradas += 1
	sincronizar(player)
	local disponibles = VaultManager.Disponibles(player)
	avisar(player, `Pestaña {disponibles} desbloqueada.`, "Oro")
	return NetworkBridge.Ok({ Disponibles = disponibles })
end

local function personalizar(player: Player, numero: number, nombre: string, icono: string): Types.Respuesta
	local datos, codigo = validar(player, numero)
	if not datos then
		return fallo(codigo)
	end
	local limpio = string.gsub(nombre, "^%s+", "")
	limpio = string.gsub(limpio, "%s+$", "")
	local largo = utf8.len(limpio)
	if not largo or largo < 1 or largo > VaultConfig.LargoNombre then
		avisar(player, `El nombre puede tener hasta {VaultConfig.LargoNombre} letras.`)
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	-- El filtro de texto cede el hilo: los datos se vuelven a leer después.
	local ok, filtrado = pcall(function(): string
		local r = TextService:FilterStringAsync(limpio, player.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if filtrado ~= limpio then
		avisar(player, "Ese nombre no está permitido.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local actuales = DataManager.GetData(player)
	if not actuales then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	local pestana = pestanaDe(vaultDe(actuales), numero)
	pestana.Nombre = limpio
	pestana.Icono = icono
	sincronizar(player)
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- Puntos de bóveda del mapa
------------------------------------------------------------------------

local function prepararPunto(objeto: Instance)
	-- Los NPC (Banquero) abren la bóveda desde su propia ventana.
	if not objeto:IsA("BasePart") or objeto:GetAttribute("SinPrompt") == true then
		return
	end
	local prompt = objeto:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir"
	prompt.ObjectText = "Bóveda"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = VaultConfig.Distancia - 4
	prompt.RequiresLineOfSight = false
	prompt.Parent = objeto
	prompt.Triggered:Connect(function(player: Player)
		VaultManager.Abrir(player)
	end)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function VaultManager.Init()
	assert(not iniciado, "VaultManager.Init() se llamó dos veces")
	iniciado = true

	for _, tag in VaultConfig.Tags do
		for _, punto in CollectionService:GetTagged(tag) do
			prepararPunto(punto)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(prepararPunto)
	end

	NpcManager.RegistrarAccion("Vault", function(player: Player): boolean
		return VaultManager.Abrir(player)
	end)

	local Guard = NetworkBridge.Guard
	local MAX = VaultConfig.MaxPestanas

	local function ranura(valor: unknown): string?
		local n = Guard.Integer(valor, 1, RANURAS)
		return if n then tostring(n) else nil
	end

	NetworkBridge.Server.OnInvoke(
		"VaultDepositar",
		function(player: Player, ranuraMochila: unknown, pestana: unknown, cantidad: unknown): Types.Respuesta
			local clave = Guard.String(ranuraMochila, 4)
			local numero = Guard.Integer(pestana, 1, MAX)
			local n = Guard.Integer(cantidad, 1, 9999)
			if not clave or not numero or not n then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			return depositar(player, clave, numero, n)
		end
	)

	NetworkBridge.Server.OnInvoke(
		"VaultRetirar",
		function(player: Player, pestana: unknown, ranuraVault: unknown, cantidad: unknown): Types.Respuesta
			local numero = Guard.Integer(pestana, 1, MAX)
			local clave = ranura(ranuraVault)
			local n = Guard.Integer(cantidad, 1, 9999)
			if not numero or not clave or not n then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			return retirar(player, numero, clave, n)
		end
	)

	NetworkBridge.Server.OnInvoke(
		"VaultMover",
		function(
			player: Player,
			pestanaA: unknown,
			ranuraA: unknown,
			pestanaB: unknown,
			ranuraB: unknown
		): Types.Respuesta
			local numeroA = Guard.Integer(pestanaA, 1, MAX)
			local numeroB = Guard.Integer(pestanaB, 1, MAX)
			local claveA = ranura(ranuraA)
			local destino = Guard.Integer(ranuraB, 0, RANURAS) -- 0 = primera libre
			if not numeroA or not numeroB or not claveA or not destino then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			return mover(player, numeroA, claveA, numeroB, if destino == 0 then nil else tostring(destino))
		end
	)

	NetworkBridge.Server.OnInvoke("VaultExpandir", function(player: Player): Types.Respuesta
		return expandir(player)
	end)

	NetworkBridge.Server.OnInvoke(
		"VaultPersonalizar",
		function(player: Player, pestana: unknown, nombre: unknown, icono: unknown): Types.Respuesta
			local numero = Guard.Integer(pestana, 1, MAX)
			local texto = Guard.String(nombre, 64)
			local elegido = Guard.OneOf(icono, iconosValidos)
			if not numero or not texto or not elegido then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			return personalizar(player, numero, texto, elegido)
		end
	)
end

return VaultManager
