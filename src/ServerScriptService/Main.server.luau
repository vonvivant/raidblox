--!strict
-- Main: arranque del servidor. Único Script del servidor; todos los sistemas
-- son ModuleScripts que se inicializan acá en orden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Systems = ServerScriptService.Systems
local DataManager = require(Systems.DataManager)
local BandoManager = require(Systems.BandoManager)
local AparienciaManager = require(Systems.AparienciaManager)
local AntiCheat = require(Systems.AntiCheat)
local ZoneManager = require(Systems.ZoneManager)
local ArchitectWarManager = require(Systems.Guerra.ArchitectWarManager)
local CombatManager = require(Systems.Combate.CombatManager)
local LootManager = require(Systems.Combate.LootManager)
local EnemyManager = require(Systems.Combate.EnemyManager)
local RaidBloxManager = require(Systems.Combate.RaidBloxManager)
local InventarioManager = require(Systems.Economia.InventarioManager)
local CraftingManager = require(Systems.Economia.CraftingManager)
local RecoleccionManager = require(Systems.Economia.RecoleccionManager)
local AuctionManager = require(Systems.Economia.AuctionManager)
local TradeManager = require(Systems.Economia.TradeManager)
local MisionManager = require(Systems.MisionManager)
local GrupoManager = require(Systems.GrupoManager)
local HermandadManager = require(Systems.HermandadManager)
local VozManager = require(Systems.VozManager)
local DebugStudio = require(Systems.DebugStudio)
local NpcsPrueba = require(Systems.Pruebas.NpcsPrueba)

-- 1. Red primero: los demás sistemas registran sus remotes sobre ella.
NetworkBridge.Server.Init()

-- 2. Datos de jugadores.
DataManager.Init()

-- 3. Seguridad de movimiento.
AntiCheat.Init()

-- 4. Mundo: portales y teletransporte.
ZoneManager.Init()

-- 5. Bandos (PvP) y apariencia; después el combate: motor, botín, enemigos y
-- jefes de la zona de este place.
BandoManager.Init(ZoneManager.ZonaActual())
AparienciaManager.Init()
CombatManager.Init()
LootManager.Init()
local zona = ZoneManager.ZonaActual()
EnemyManager.Init(zona)
RaidBloxManager.Init(zona)

-- 6. Economía: inventario, profesiones, subastas y comercio.
InventarioManager.Init()
CraftingManager.Init()
RecoleccionManager.Init()
AuctionManager.Init()
TradeManager.Init()

-- 6b. Fase 5: grupos y misiones.
GrupoManager.Init()
HermandadManager.Init()
VozManager.Init()
MisionManager.Init()

-- 7. Modos de juego según el place.
if ArchitectWarManager.DebeActivarse() then
	ArchitectWarManager.Init()
end

-- 8. Herramientas de prueba: comandos (solo Studio) y NPCs de oro y materiales.
DebugStudio.Init()
NpcsPrueba.Init()

print(`[RaidBlox] Servidor iniciado - Fase 5 (zona: {zona or "sin configurar"})`)
