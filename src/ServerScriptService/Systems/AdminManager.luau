--!strict
-- AdminManager: panel de administración y moderación (Fase 7.4).
--
-- * Quién es admin lo decide SOLO el servidor: el creador del juego (o el
--   dueño del grupo, si el juego es de un grupo), los UserIds de
--   ConfigServidor.Admins y, en Studio, quien prueba. El atributo "Admin" del
--   jugador solo sirve para mostrar el botón; cada acción se vuelve a validar.
-- * Moderación: ir hacia un jugador, traerlo, expulsar, banear para siempre
--   (Players:BanAsync de Roblox + registro en el DataStore "Baneos") y
--   desbanear. El baneo también se revisa al entrar.
-- * Diseño de juego: dar ítem por id (con rareza), dar oro, ver el inventario
--   de un jugador, revivir e invocar un RaidBlox de prueba junto al admin.
-- * Registro: cada acción va a la consola y, si hay ConfigServidor.WebhookAdmin,
--   a un webhook privado de Discord (con cola y de a una cada 2 s).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local RaidBloxConfig = require(ReplicatedStorage.Configs.RaidBloxConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local ConfigServidor = require(script.Parent.ConfigServidor)
local DataManager = require(script.Parent.DataManager)
local AntiCheat = require(script.Parent.AntiCheat)
local LootManager = require(script.Parent.Combate.LootManager)
local RaidBloxManager = require(script.Parent.Combate.RaidBloxManager)

type Respuesta = Types.Respuesta

local AdminManager = {}

local NOMBRE_STORE = if RunService:IsStudio() then "Baneos_Studio" else "Baneos"
local RAREZAS: { [string]: Types.Rareza } = {
	Comun = "Comun",
	Raro = "Raro",
	Epico = "Epico",
	Mistico = "Mistico",
	Unico = "Unico",
}

local iniciado = false
local esAdminCache: { [Player]: boolean } = {}
local ultimos: { [Player]: { number } } = {}
local colaWebhook: { string } = {}
local storeBaneos: DataStore? = nil

local function store(): DataStore
	local s = storeBaneos
	if not s then
		s = DataStoreService:GetDataStore(NOMBRE_STORE)
		storeBaneos = s
	end
	return s :: DataStore
end

------------------------------------------------------------------------
-- Permisos
------------------------------------------------------------------------

local function calcularAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(ConfigServidor.Admins, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	-- Juego de un grupo: el dueño del grupo.
	local ok, info = pcall(function()
		return game:GetService("GroupService"):GetGroupInfoAsync(game.CreatorId)
	end)
	return ok and typeof(info) == "table" and typeof(info.Owner) == "table" and info.Owner.Id == player.UserId
end

function AdminManager.EsAdmin(player: Player): boolean
	local v = esAdminCache[player]
	if v == nil then
		v = calcularAdmin(player)
		esAdminCache[player] = v
	end
	return v
end

-- 5 acciones por cada 2 segundos.
local function permitirRitmo(player: Player): boolean
	local lista = ultimos[player] or {}
	ultimos[player] = lista
	local t = os.clock()
	while lista[1] and t - lista[1] > 2 do
		table.remove(lista, 1)
	end
	if #lista >= 5 then
		return false
	end
	table.insert(lista, t)
	return true
end

------------------------------------------------------------------------
-- Registro (consola + Discord)
------------------------------------------------------------------------

local function registrar(admin: Player, accion: string, detalle: string)
	local linea = `[Admin] {admin.Name} ({admin.UserId}) · {accion} · {detalle}`
	print(linea)
	if ConfigServidor.WebhookAdmin ~= "" and #colaWebhook < 50 then
		table.insert(colaWebhook, linea)
	end
end

local function enviarWebhook(linea: string)
	local cuerpo = HttpService:JSONEncode({
		username = "RaidBlox Admin",
		content = string.sub(linea, 1, 1900),
		allowed_mentions = { parse = {} }, -- nunca menciona a nadie
	})
	local ok, err = pcall(function()
		HttpService:PostAsync(ConfigServidor.WebhookAdmin, cuerpo, Enum.HttpContentType.ApplicationJson)
	end)
	if not ok then
		warn(`[Admin] No se pudo enviar al webhook: {err}`)
	end
end

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function raiz(player: Player): BasePart?
	local personaje = player.Character
	local r = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function jugadorPorId(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

------------------------------------------------------------------------
-- Baneos
------------------------------------------------------------------------

type RegistroBaneo = { Motivo: string, Por: number, Fecha: number }

local function leerBaneo(userId: number): (boolean, RegistroBaneo?)
	local ok, valor = pcall(function()
		return store():GetAsync(`U_{userId}`)
	end)
	if not ok then
		return false, nil
	end
	return true, if typeof(valor) == "table" then valor :: RegistroBaneo else nil
end

local function banear(admin: Player, userId: number, motivo: string): Respuesta
	if userId == admin.UserId then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local objetivo = jugadorPorId(userId)
	if objetivo and AdminManager.EsAdmin(objetivo) then
		avisar(admin, "No se puede banear a otro admin.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local registro: RegistroBaneo = { Motivo = motivo, Por = admin.UserId, Fecha = os.time() }
	local ok, err = pcall(function()
		store():SetAsync(`U_{userId}`, registro)
	end)
	if not ok then
		warn(`[Admin] No se pudo guardar el baneo: {err}`)
		avisar(admin, "No se pudo guardar el baneo. Probá de nuevo.", "Error")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	-- Baneo oficial de Roblox (todos los servidores y lugares del juego).
	-- En Studio no funciona: queda solo el del DataStore.
	if not RunService:IsStudio() then
		local okBan, errBan = pcall(function()
			Players:BanAsync({
				UserIds = { userId },
				ApplyToUniverse = true,
				Duration = -1,
				DisplayReason = string.sub(motivo, 1, 400),
				PrivateReason = `Baneado por {admin.Name} ({admin.UserId})`,
				ExcludeAltAccounts = false,
			})
		end)
		if not okBan then
			warn(`[Admin] BanAsync falló (queda el del DataStore): {errBan}`)
		end
	end
	if objetivo then
		objetivo:Kick(`Fuiste baneado de RaidBlox. Motivo: {motivo}`)
	end
	registrar(admin, "Ban", `{userId} · {motivo}`)
	return NetworkBridge.Ok(nil)
end

local function desbanear(admin: Player, userId: number): Respuesta
	local ok, err = pcall(function()
		store():RemoveAsync(`U_{userId}`)
	end)
	if not ok then
		warn(`[Admin] No se pudo quitar el baneo: {err}`)
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if not RunService:IsStudio() then
		pcall(function()
			Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
		end)
	end
	registrar(admin, "Desban", tostring(userId))
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- Acciones
------------------------------------------------------------------------

local function objetivoOnline(admin: Player, valor: unknown): Player?
	local id = NetworkBridge.Guard.Integer(valor, 1, 2 ^ 53)
	local p = id and jugadorPorId(id)
	if not p then
		avisar(admin, "Ese jugador no está en este servidor.", "Error")
	end
	return p
end

local function inventarioDe(p: Player): any
	local d = DataManager.GetData(p)
	if not d then
		return nil
	end
	local lineas = {}
	for clave, item in d.Inventario.Slots do
		local def = ItemCatalog[item.ItemId]
		table.insert(lineas, {
			Ranura = tonumber(clave) or 0,
			Nombre = if def then def.Nombre else item.ItemId,
			ItemId = item.ItemId,
			Cantidad = item.Cantidad,
			Rareza = item.Rareza,
		})
	end
	table.sort(lineas, function(a, b)
		return a.Ranura < b.Ranura
	end)
	local equipo = {}
	for slot, item in d.Equipamiento :: { [string]: Types.ItemInstancia? } do
		if item then
			local def = ItemCatalog[item.ItemId]
			table.insert(equipo, `{slot}: {if def then def.Nombre else item.ItemId} ({item.Rareza})`)
		end
	end
	return {
		Nombre = p.Name,
		Nivel = d.Nivel,
		Oro = d.Oro,
		Clase = d.Clase,
		Items = lineas,
		Equipo = equipo,
	}
end

local function accion(admin: Player, nombre: string, a: unknown, b: unknown, c: unknown): Respuesta
	if nombre == "Ir" or nombre == "Traer" then
		local p = objetivoOnline(admin, a)
		local ra, rp = raiz(admin), p and raiz(p)
		if not p or not ra or not rp then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		if nombre == "Ir" then
			AntiCheat.Gracia(admin, 3)
			ra.CFrame = rp.CFrame * CFrame.new(0, 0, 4)
		else
			AntiCheat.Gracia(p, 3)
			rp.CFrame = ra.CFrame * CFrame.new(0, 0, -4)
		end
		registrar(admin, nombre, p.Name)
		return NetworkBridge.Ok(nil)
	elseif nombre == "Kick" then
		local p = objetivoOnline(admin, a)
		local motivo = NetworkBridge.Guard.String(b, 200) or "Expulsado por un administrador."
		if not p then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		if AdminManager.EsAdmin(p) and p ~= admin then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		registrar(admin, "Kick", `{p.Name} · {motivo}`)
		p:Kick(motivo)
		return NetworkBridge.Ok(nil)
	elseif nombre == "Ban" then
		local id = NetworkBridge.Guard.Integer(a, 1, 2 ^ 53)
		local motivo = NetworkBridge.Guard.String(b, 300)
		if not id or not motivo or motivo == "" then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return banear(admin, id, motivo)
	elseif nombre == "Desban" then
		local id = NetworkBridge.Guard.Integer(a, 1, 2 ^ 53)
		return if id then desbanear(admin, id) else NetworkBridge.Fail("INVALID_ARGS")
	elseif nombre == "DarItem" then
		local p = objetivoOnline(admin, a)
		local itemId = NetworkBridge.Guard.String(b, 40)
		local cantidad = NetworkBridge.Guard.Integer(c, 1, 999) or 1
		if not p or not itemId or not ItemCatalog[itemId] then
			avisar(admin, "Ítem inexistente.", "Error")
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		local def = ItemCatalog[itemId]
		local veces = if def.Apilable then 1 else math.min(cantidad, 10)
		local porVez = if def.Apilable then cantidad else 1
		local dados = 0
		for _ = 1, veces do
			local item = LootManager.GenerarItem(itemId, porVez, nil)
			if not item or not DataManager.AddItem(p, item.ItemId, item.Cantidad, item.Rareza, item.Meta) then
				break
			end
			dados += item.Cantidad
		end
		registrar(admin, "DarItem", `{p.Name} · {itemId} x{dados}`)
		avisar(admin, `Entregado: {def.Nombre} x{dados}` .. (if dados < cantidad then " (mochila llena)" else ""))
		return NetworkBridge.Ok(dados)
	elseif nombre == "DarItemRareza" then
		local p = objetivoOnline(admin, a)
		local itemId = NetworkBridge.Guard.String(b, 40)
		local rareza = NetworkBridge.Guard.OneOf(c, RAREZAS)
		if not p or not itemId or not ItemCatalog[itemId] or not rareza then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		local item = LootManager.GenerarItem(itemId, 1, rareza)
		if not item or not DataManager.AddItem(p, item.ItemId, item.Cantidad, item.Rareza, item.Meta) then
			avisar(admin, "No entró en la mochila.", "Error")
			return NetworkBridge.Fail("INVENTORY_FULL")
		end
		registrar(admin, "DarItem", `{p.Name} · {itemId} ({rareza})`)
		return NetworkBridge.Ok(1)
	elseif nombre == "DarOro" then
		local p = objetivoOnline(admin, a)
		local cantidad = NetworkBridge.Guard.Integer(b, 1, 1000000)
		if not p or not cantidad then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not DataManager.AddGold(p, cantidad) then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		registrar(admin, "DarOro", `{p.Name} · {cantidad}`)
		return NetworkBridge.Ok(nil)
	elseif nombre == "Inventario" then
		local p = objetivoOnline(admin, a)
		local info = p and inventarioDe(p)
		if not p or not info then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		registrar(admin, "VerInventario", p.Name)
		return NetworkBridge.Ok(info)
	elseif nombre == "Revivir" then
		local p = objetivoOnline(admin, a)
		if not p then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			h.Health = h.MaxHealth
		else
			task.spawn(function()
				pcall(function()
					p:LoadCharacterAsync()
				end)
			end)
		end
		registrar(admin, "Revivir", p.Name)
		return NetworkBridge.Ok(nil)
	elseif nombre == "InvocarJefe" then
		local id = NetworkBridge.Guard.String(a, 40)
		local r = raiz(admin)
		if not id or not r then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		local pos = (r.CFrame * CFrame.new(0, 0, -30)).Position
		local ok, motivo = RaidBloxManager.Invocar(id, Vector3.new(pos.X, r.Position.Y - 2.5, pos.Z))
		if not ok then
			avisar(admin, motivo or "No se pudo invocar.", "Error")
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		registrar(admin, "InvocarJefe", id)
		return NetworkBridge.Ok(nil)
	end
	return NetworkBridge.Fail("INVALID_ARGS")
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function AdminManager.Init()
	assert(not iniciado, "AdminManager.Init() se llamó dos veces")
	iniciado = true

	NetworkBridge.Server.OnInvoke(
		"AdminAccion",
		function(player: Player, nombre: unknown, a: unknown, b: unknown, c: unknown): Respuesta
			if not AdminManager.EsAdmin(player) then
				warn(`[Admin] {player.Name} ({player.UserId}) intentó usar el panel sin permiso.`)
				return NetworkBridge.Fail("NOT_ALLOWED")
			end
			local n = NetworkBridge.Guard.String(nombre, 20)
			if not n then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if not permitirRitmo(player) then
				return NetworkBridge.Fail("RATE_LIMITED")
			end
			return accion(player, n, a, b, c)
		end
	)
	NetworkBridge.Server.OnInvoke("AdminInfo", function(player: Player): Respuesta
		if not AdminManager.EsAdmin(player) then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		local jefes = {}
		for id, def in RaidBloxConfig.Jefes do
			table.insert(jefes, { Id = id, Nombre = def.Nombre })
		end
		return NetworkBridge.Ok({ Jefes = jefes, Webhook = ConfigServidor.WebhookAdmin ~= "" })
	end)

	local function alEntrar(player: Player)
		task.spawn(function()
			local ok, registro = leerBaneo(player.UserId)
			if ok and registro then
				player:Kick(`Estás baneado de RaidBlox. Motivo: {registro.Motivo}`)
				return
			end
			if AdminManager.EsAdmin(player) then
				player:SetAttribute("Admin", true)
			end
		end)
	end
	Players.PlayerAdded:Connect(alEntrar)
	for _, p in Players:GetPlayers() do
		alEntrar(p)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		esAdminCache[player] = nil
		ultimos[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(2)
			local linea = table.remove(colaWebhook, 1)
			if linea then
				enviarWebhook(linea)
			end
		end
	end)
end

return AdminManager
