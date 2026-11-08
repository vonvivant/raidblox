--!strict
-- Main: arranque del servidor. Único Script del servidor; todos los sistemas
-- son ModuleScripts que se inicializan acá en orden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Systems = ServerScriptService.Systems
local DataManager = require(Systems.DataManager)
local AntiCheat = require(Systems.AntiCheat)
local ZoneManager = require(Systems.ZoneManager)
local ArchitectWarManager = require(Systems.Guerra.ArchitectWarManager)

-- 1. Red primero: los demás sistemas registran sus remotes sobre ella.
NetworkBridge.Server.Init()

-- 2. Datos de jugadores.
DataManager.Init()

-- 3. Seguridad de movimiento.
AntiCheat.Init()

-- 4. Mundo: portales y teletransporte.
ZoneManager.Init()

-- 5. Modos de juego según el place.
if ArchitectWarManager.DebeActivarse() then
	ArchitectWarManager.Init()
end

print("[RaidBlox] Servidor iniciado - Fase 2")
