--!strict
-- AparienciaManager: ajustes del jugador (género y chat) y su aplicación.
--
-- Género:
--   * "Avatar": el avatar de Roblox del jugador, sin cambios.
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

aplicarGenero = function(player: Player)
	local personaje = player.Character
	local humanoid = personaje and personaje:FindFirstChildOfClass("Humanoid")
	local datos = DataManager.GetData(player)
	if not humanoid or not datos then
		return
	end
	if datos.Ajustes.Genero == "Avatar" and not modificado[player] then
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
	modificado[player] = datos.Ajustes.Genero ~= "Avatar"
	local ok, err = pcall(function()
		humanoid:ApplyDescriptionAsync(base)
	end)
	if not ok then
		warn(`[Apariencia] No se pudo aplicar el género a {player.Name}: {err}`)
	end
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

function AparienciaManager.Init()
	assert(not iniciado, "AparienciaManager.Init() se llamó dos veces")
	iniciado = true

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
