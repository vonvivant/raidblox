--!strict
-- VozManager: chat de voz con canales (API de audio de Roblox).
--
-- Requiere VoiceChatService.EnableDefaultVoice = false y UseAudioApi =
-- Enabled (lo pone default.project.json). El servidor arma, por jugador:
--
--   AudioDeviceInput (micrófono) ──Wire──> AudioEmitter en el personaje   (Proximidad)
--                                └─Wire──> AudioFader global ─> AudioDeviceOutput (Grupo, Hermandad, Zona)
--
-- Cada jugador habla por UN canal a la vez:
--   Proximidad  3D, se apaga a los 80 studs; lo oye cualquiera cerca.
--   Grupo       sin distancia; solo los de su grupo.
--   Hermandad   sin distancia; solo los de su hermandad EN ESTE SERVIDOR.
--   Zona        sin distancia; todos los jugadores de este servidor (zona).
--
-- Quién lo oye lo decide el servidor con la lista de acceso del micrófono
-- (AccessType + SetUserIdAccessList): el sonido solo le llega a esos usuarios.
-- La escucha (AudioListener) y silenciar a otros los arma cada cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.DataManager)
local GrupoManager = require(script.Parent.GrupoManager)
local HermandadManager = require(script.Parent.HermandadManager)

type Respuesta = Types.Respuesta
type CanalVoz = string -- Types.CanalVoz, validado contra GameConfig.Voz.Canales

type Voz = {
	Microfono: AudioDeviceInput,
	AEmisor: Wire,
	AGlobal: Wire,
	Emisor: AudioEmitter?,
	Firma: string, -- última lista aplicada (para no repetir)
}

local CFG = GameConfig.Voz
local CANALES: { [string]: true } = {}
for _, c in CFG.Canales do
	CANALES[c] = true
end

local VozManager = {}

local voces: { [Player]: Voz } = {}
local canalDe: { [Player]: CanalVoz } = {}
local fader: AudioFader? = nil
local pendiente = false
local iniciado = false

-- Wire.TargetInstance acepta nil (cable cortado) aunque el tipo diga Instance.
local function conectar(w: Wire, destino: Instance?)
	(w :: any).TargetInstance = destino
end

local function cablear(origen: Instance, destino: Instance?, nombre: string): Wire
	local w = Instance.new("Wire")
	w.Name = nombre
	w.SourceInstance = origen
	conectar(w, destino)
	w.Parent = origen
	return w
end

local function disponible(player: Player, canal: CanalVoz): boolean
	if canal == "Grupo" then
		return GrupoManager.GrupoDe(player) ~= nil
	elseif canal == "Hermandad" then
		return HermandadManager.HermandadDe(player) ~= nil
	end
	return true
end

-- Quién oye a `player` en su canal (sin él mismo). nil = cualquiera (proximidad).
local function oyentes(player: Player, canal: CanalVoz): { number }?
	if canal == "Proximidad" then
		return nil
	end
	local lista: { number } = {}
	if canal == "Grupo" then
		for _, m in GrupoManager.MiembrosDe(player) do
			if m ~= player then
				table.insert(lista, m.UserId)
			end
		end
	else
		for _, otro in Players:GetPlayers() do
			if otro ~= player and (canal == "Zona" or HermandadManager.MismaHermandad(player, otro)) then
				table.insert(lista, otro.UserId)
			end
		end
	end
	table.sort(lista)
	return lista
end

local function enviarEstado(player: Player)
	local canal = canalDe[player] or "Proximidad"
	local lista = oyentes(player, canal)
	NetworkBridge.Server.FireClient("VozEstado", player, {
		Canal = canal,
		Grupo = disponible(player, "Grupo"),
		Hermandad = disponible(player, "Hermandad"),
		Oyentes = if lista then #lista else -1,
	})
end

local function aplicar(player: Player)
	local voz = voces[player]
	if not voz then
		return
	end
	local canal = canalDe[player] or "Proximidad"
	if not disponible(player, canal) then
		-- Se quedó sin grupo o sin hermandad: vuelve a proximidad.
		canal = "Proximidad"
		canalDe[player] = canal
		NetworkBridge.Server.FireClient("Notificacion", player, "Tu canal de voz volvió a Proximidad.", "Info")
	end
	local lista = oyentes(player, canal)
	local firma = canal .. ":" .. (if lista then table.concat(lista, ",") else "*")
	if firma == voz.Firma then
		enviarEstado(player) -- puede haber cambiado qué canales tiene disponibles
		return
	end
	voz.Firma = firma
	if lista then
		conectar(voz.AEmisor, nil)
		conectar(voz.AGlobal, fader)
		voz.Microfono.AccessType = Enum.AccessModifierType.Allow
		voz.Microfono:SetUserIdAccessList(lista)
	else
		conectar(voz.AEmisor, voz.Emisor)
		conectar(voz.AGlobal, nil)
		voz.Microfono.AccessType = Enum.AccessModifierType.Deny
		voz.Microfono:SetUserIdAccessList({})
	end
	enviarEstado(player)
end

-- Varios cambios seguidos (alguien entra a un grupo, sale del servidor...) se
-- juntan en un solo recálculo para todos.
local function recalcular()
	if pendiente then
		return
	end
	pendiente = true
	task.defer(function()
		pendiente = false
		for player in voces do
			aplicar(player)
		end
	end)
end

local function alPersonaje(player: Player, personaje: Model)
	local voz = voces[player]
	local raiz = personaje:WaitForChild("HumanoidRootPart", 10)
	if not voz or not raiz or voces[player] ~= voz then
		return
	end
	local emisor = Instance.new("AudioEmitter")
	emisor.Name = "VozEmisor"
	pcall(function()
		emisor:SetDistanceAttenuation({ [0] = 1, [CFG.DistanciaMaxima * 0.25] = 0.8, [CFG.DistanciaMaxima] = 0 })
	end)
	emisor.Parent = raiz
	voz.Emisor = emisor
	voz.Firma = "" -- fuerza a reconectar el cable al emisor nuevo
	aplicar(player)
end

local function alEntrar(player: Player)
	local f = fader
	if not f then
		return
	end
	local microfono = Instance.new("AudioDeviceInput")
	microfono.Name = "AudioDeviceInput"
	microfono.Player = player
	pcall(function()
		(microfono :: any).Active = true
	end)
	microfono.Parent = player
	voces[player] = {
		Microfono = microfono,
		AEmisor = cablear(microfono, nil, "VozAEmisor"),
		AGlobal = cablear(microfono, nil, "VozAGlobal"),
		Emisor = nil,
		Firma = "",
	}
	player.CharacterAdded:Connect(function(personaje: Model)
		alPersonaje(player, personaje)
	end)
	if player.Character then
		task.spawn(alPersonaje, player, player.Character)
	end
	recalcular()
end

local function alCargar(player: Player, datos: Types.DatosJugador)
	local guardado = datos.Ajustes.CanalVoz
	if guardado and CANALES[guardado] then
		canalDe[player] = guardado
	end
	recalcular()
end

function VozManager.Init()
	assert(not iniciado, "VozManager.Init() se llamó dos veces")
	iniciado = true

	local carpeta = Instance.new("Folder")
	carpeta.Name = "Voz"
	carpeta.Parent = Workspace
	local f = Instance.new("AudioFader")
	f.Name = "VozCanales"
	f.Parent = carpeta
	local salida = Instance.new("AudioDeviceOutput")
	salida.Name = "VozSalida"
	salida.Parent = carpeta
	cablear(f, salida, "VozASalida")
	fader = f

	for _, player in Players:GetPlayers() do
		task.spawn(alEntrar, player)
	end
	Players.PlayerAdded:Connect(alEntrar)
	Players.PlayerRemoving:Connect(function(player: Player)
		voces[player] = nil
		canalDe[player] = nil
		recalcular()
	end)
	DataManager.PerfilCargado:Connect(alCargar)
	GrupoManager.Cambio:Connect(recalcular)
	HermandadManager.Cambio:Connect(recalcular)

	NetworkBridge.Server.OnInvoke("VozCanal", function(player: Player, canal: unknown): Respuesta
		local c = NetworkBridge.Guard.OneOf(canal, CANALES)
		if not c then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		local elegido = c :: CanalVoz
		if not disponible(player, elegido) then
			NetworkBridge.Server.FireClient(
				"Notificacion",
				player,
				if elegido == "Grupo" then "No estás en un grupo." else "No estás en una hermandad.",
				"Error"
			)
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		canalDe[player] = elegido
		DataManager.SetAjuste(player, "CanalVoz", elegido)
		local voz = voces[player]
		if voz then
			voz.Firma = ""
		end
		aplicar(player)
		return NetworkBridge.Ok(nil)
	end)
end

return VozManager
