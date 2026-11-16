--!strict
-- AparienciaManager: ajustes del jugador (género y chat) y su aplicación.
--
-- Género:
--   * "Avatar": el avatar de Roblox del jugador, sin cambios.
-- También aplica el estilo del Barbero (NPC-029): color de piel y, cuando haya
-- assets cargados, peinado y marca facial.
--
--   * "Masculino" / "Femenino": ajusta proporciones con HumanoidDescription y,
--     si se configuran, aplica las partes del cuerpo de AparienciaConfig (ids
--     de partes del Catálogo de Roblox que elijas vos).
-- El chat (posición, tamaño, visible) lo aplica el cliente; acá solo se guarda.
-- El color del nombre según el bando también se aplica acá.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local AparienciaConfig = require(ReplicatedStorage.Configs.AparienciaConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.DataManager)
local EquipoVisible = require(script.Parent.EquipoVisible)
local NpcManager = require(script.Parent.NpcManager)

local AparienciaManager = {}

local descripcionOriginal: { [Player]: HumanoidDescription } = {}
local modificado: { [Player]: boolean } = {} -- si alguna vez se le cambió el cuerpo
local aplicando: { [Player]: boolean } = {}
local pendienteAplicar: { [Player]: boolean } = {}
local ultimoGenero: { [Player]: number } = {}
local iniciado = false

local aplicarGenero: (Player) -> ()

-- Un solo ApplyDescriptionAsync por jugador a la vez; si llega otro pedido
-- mientras tanto, se aplica una vez más al terminar (con el último ajuste).
local function aplicarGeneroSeguro(player: Player)
	if aplicando[player] then
		pendienteAplicar[player] = true
		return
	end
	aplicando[player] = true
	repeat
		pendienteAplicar[player] = nil
		aplicarGenero(player)
	until not pendienteAplicar[player] or player.Parent ~= Players
	aplicando[player] = nil
end

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local CFG_BARBERO = AparienciaConfig.Barbero
local PARTES_PIEL = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }

-- ¿El jugador tiene algún cambio del Barbero puesto?
local function estilizado(datos: Types.DatosJugador): boolean
	local estilo = datos.Apariencia
	if not estilo then
		return false
	end
	local piel = if estilo.Piel then CFG_BARBERO.Pieles[estilo.Piel] else nil
	local peinado = if estilo.Peinado then CFG_BARBERO.Peinados[estilo.Peinado] else nil
	local marca = if estilo.Marca then CFG_BARBERO.Marcas[estilo.Marca] else nil
	return (piel ~= nil and estilo.Piel ~= "Avatar")
		or (peinado ~= nil and peinado.AssetId ~= 0)
		or (marca ~= nil and marca.AssetId ~= 0)
end

-- Escribe el estilo del Barbero en una HumanoidDescription.
local function aplicarEstilo(base: HumanoidDescription, datos: Types.DatosJugador)
	local estilo = datos.Apariencia
	if not estilo then
		return
	end
	local piel = if estilo.Piel and estilo.Piel ~= "Avatar" then CFG_BARBERO.Pieles[estilo.Piel] else nil
	if piel then
		for _, propiedad in PARTES_PIEL do
			(base :: any)[propiedad] = piel.Color
		end
	end
	local peinado = if estilo.Peinado then CFG_BARBERO.Peinados[estilo.Peinado] else nil
	if peinado and peinado.AssetId ~= 0 then
		base.HairAccessory = tostring(peinado.AssetId)
	end
	local marca = if estilo.Marca then CFG_BARBERO.Marcas[estilo.Marca] else nil
	if marca and marca.AssetId ~= 0 then
		base.FaceAccessory = tostring(marca.AssetId)
	end
end

aplicarGenero = function(player: Player)
	local personaje = player.Character
	local humanoid = personaje and personaje:FindFirstChildOfClass("Humanoid")
	local datos = DataManager.GetData(player)
	if not humanoid or not datos then
		return
	end
	if datos.Ajustes.Genero == "Avatar" and not estilizado(datos) and not modificado[player] then
		return -- su avatar tal cual: no hace falta tocar nada
	end
	-- Se guarda la descripción del avatar real una vez, para poder volver a él.
	local original = descripcionOriginal[player]
	if not original then
		local ok, desc = pcall(function()
			return humanoid:GetAppliedDescription()
		end)
		if not ok or not desc then
			return
		end
		original = desc
		descripcionOriginal[player] = desc
	end
	local base = (original :: HumanoidDescription):Clone()
	aplicarEstilo(base, datos)
	local def = AparienciaConfig.Generos[datos.Ajustes.Genero]
	if def then
		for propiedad, valor in def.Escalas do
			(base :: any)[propiedad] = valor
		end
		for propiedad, assetId in def.Partes do
			if assetId ~= 0 then
				(base :: any)[propiedad] = assetId
			end
		end
	end
	modificado[player] = datos.Ajustes.Genero ~= "Avatar" or estilizado(datos)
	local ok, err = pcall(function()
		humanoid:ApplyDescriptionAsync(base)
	end)
	if not ok then
		warn(`[Apariencia] No se pudo aplicar el género a {player.Name}: {err}`)
	end
	-- El cuerpo pudo cambiar de tamaño: se vuelve a ubicar el equipo visible.
	EquipoVisible.Actualizar(player, true)
end

local function colorearNombre(player: Player)
	local personaje = player.Character
	local humanoid = personaje and personaje:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local bando = player:GetAttribute("Bando")
	local etiqueta = if bando == "Rojo" then "🔴" elseif bando == "Azul" then "🔵" else "🟣"
	humanoid.DisplayName = `{etiqueta} {player.DisplayName}`
end

local function alAparecer(player: Player)
	task.defer(function()
		colorearNombre(player)
		aplicarGeneroSeguro(player)
		colorearNombre(player)
	end)
end

-- Barbero: cambia el estilo del jugador si las opciones existen y le alcanza
-- el oro. Devuelve false (ya avisó) si algo no cierra.
local function barbero(player: Player, piel: string?, peinado: string?, marca: string?): boolean
	local datos = DataManager.GetData(player)
	if not datos then
		return false
	end
	if piel and not CFG_BARBERO.Pieles[piel] then
		return false
	end
	local defPeinado = if peinado then CFG_BARBERO.Peinados[peinado] else nil
	local defMarca = if marca then CFG_BARBERO.Marcas[marca] else nil
	-- Un peinado o una marca sin asset cargado todavía no se puede usar.
	if
		(peinado and (not defPeinado or defPeinado.AssetId == 0)) or (marca and (not defMarca or defMarca.AssetId == 0))
	then
		avisar(player, "Ese estilo todavía no está disponible.", "Error")
		return false
	end
	local actual: { Piel: string?, Peinado: string?, Marca: string? } = datos.Apariencia or {}
	local nuevo = {
		Piel = piel or actual.Piel,
		Peinado = peinado or actual.Peinado,
		Marca = marca or actual.Marca,
	}
	if nuevo.Piel == actual.Piel and nuevo.Peinado == actual.Peinado and nuevo.Marca == actual.Marca then
		avisar(player, "Ya tenés ese estilo.", "Info")
		return false
	end
	if not DataManager.SpendGold(player, CFG_BARBERO.Costo) then
		avisar(player, `Cambiar de estilo cuesta {CFG_BARBERO.Costo} de oro.`, "Error")
		return false
	end
	DataManager.Mutar(player, "Cosmeticos", function(d)
		d.Apariencia = nuevo
	end)
	task.spawn(aplicarGeneroSeguro, player)
	avisar(player, "Estilo nuevo listo.", "Oro")
	return true
end

function AparienciaManager.Init()
	assert(not iniciado, "AparienciaManager.Init() se llamó dos veces")
	iniciado = true

	-- Barbero (NPC-029): el servicio solo abre la ventana; cobra al confirmar.
	NpcManager.RegistrarAccion("Barbero", function(player: Player): boolean
		NetworkBridge.Server.FireClient("NpcVentana", player, "Barbero")
		return true
	end)

	NetworkBridge.Server.OnInvoke(
		"BarberoAplicar",
		function(player: Player, npcId: unknown, piel: unknown, peinado: unknown, marca: unknown): Types.Respuesta
			local p = if piel == nil then nil else NetworkBridge.Guard.OneOf(piel, CFG_BARBERO.Pieles)
			local pe = if peinado == nil then nil else NetworkBridge.Guard.OneOf(peinado, CFG_BARBERO.Peinados)
			local m = if marca == nil then nil else NetworkBridge.Guard.OneOf(marca, CFG_BARBERO.Marcas)
			if (piel ~= nil and not p) or (peinado ~= nil and not pe) or (marca ~= nil and not m) then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if not NpcManager.Cerca(player, npcId, "Barbero") then
				return NetworkBridge.Fail("NOT_ALLOWED")
			end
			-- Cambiar el cuerpo es caro: una vez cada 3 s, igual que el género.
			local ahora = os.clock()
			if ahora - (ultimoGenero[player] or -math.huge) < 3 then
				return NetworkBridge.Fail("RATE_LIMITED")
			end
			ultimoGenero[player] = ahora
			return if barbero(player, p, pe, m) then NetworkBridge.Ok(nil) else NetworkBridge.Fail("NOT_ALLOWED")
		end
	)

	NetworkBridge.Server.OnInvoke(
		"GuardarAjuste",
		function(player: Player, clave: unknown, valor: unknown): Types.Respuesta
			local c = NetworkBridge.Guard.String(clave, 20)
			if not c or (typeof(valor) ~= "string" and typeof(valor) ~= "boolean" and typeof(valor) ~= "number") then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if c == "Genero" then
				-- Cambiar el cuerpo es caro para el servidor: una vez cada 3 s.
				local ahora = os.clock()
				if ahora - (ultimoGenero[player] or -math.huge) < 3 then
					return NetworkBridge.Fail("RATE_LIMITED")
				end
				ultimoGenero[player] = ahora
			end
			if not DataManager.SetAjuste(player, c, valor) then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if c == "Genero" then
				task.spawn(aplicarGeneroSeguro, player)
			end
			return NetworkBridge.Ok(nil)
		end
	)

	local function alEntrar(player: Player)
		player.CharacterAdded:Connect(function()
			alAparecer(player)
		end)
		player:GetAttributeChangedSignal("Bando"):Connect(function()
			colorearNombre(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		alEntrar(player)
	end
	Players.PlayerAdded:Connect(alEntrar)
	DataManager.PerfilCargado:Connect(function(player: Player)
		alAparecer(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		descripcionOriginal[player] = nil
		modificado[player] = nil
		aplicando[player] = nil
		pendienteAplicar[player] = nil
		ultimoGenero[player] = nil
	end)
end

return AparienciaManager
