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
local ArenaManager = require(Systems.Guerra.ArenaManager)
local JuegosManager = require(Systems.JuegosManager)
local ParcelaManager = require(Systems.Economia.ParcelaManager)
local ConstruccionManager = require(Systems.Economia.ConstruccionManager)
local PergaminoManager = require(Systems.Economia.PergaminoManager)
local RazaManager = require(Systems.RazaManager)
local StencilManager = require(Systems.Economia.StencilManager)
local CosmeticosManager = require(Systems.Economia.CosmeticosManager)
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
local MazmorraManager = require(Systems.MazmorraManager)
local PasesManager = require(Systems.Monetizacion.PasesManager)
local MonturaManager = require(Systems.Monetizacion.MonturaManager)
local ProductosManager = require(Systems.Monetizacion.ProductosManager)
local PaseBatallaManager = require(Systems.Monetizacion.PaseBatallaManager)
local MascotaManager = require(Systems.Monetizacion.MascotaManager)
local EquipoVisible = require(Systems.EquipoVisible)
local AdminManager = require(Systems.AdminManager)
local ChatarreroManager = require(Systems.Combate.ChatarreroManager)
local BuffManager = require(Systems.Combate.BuffManager)
local ExploracionManager = require(Systems.ExploracionManager)
local ProgresionSocialManager = require(Systems.ProgresionSocialManager)
local NpcManager = require(Systems.NpcManager)
local VaultManager = require(Systems.Economia.VaultManager)
local ForjaManager = require(Systems.Economia.ForjaManager)
local PersonalizadorManager = require(Systems.Economia.PersonalizadorManager)
local DebugStudio = require(Systems.DebugStudio)
local NpcsPrueba = require(Systems.Pruebas.NpcsPrueba)
local EditorPiedra = require(Systems.Pruebas.EditorPiedra)

------------------------------------------------------------------------
-- Arranque protegido
------------------------------------------------------------------------
-- Antes, un error en cualquier Init cortaba el arranque y todos los sistemas
-- que venían después no se inicializaban nunca, sin dejar rastro claro: el
-- síntoma era "tal cosa dejó de funcionar" y nada en el log. Ahora cada
-- sistema arranca aislado: si uno falla, se anota, se avisa fuerte y los demás
-- siguen. Al final se imprime el resumen, que es lo primero que hay que mirar
-- en la consola del servidor (F9 → Server) cuando algo no responde.

local fallados: { string } = {}

local function arrancar(nombre: string, iniciar: () -> ())
	-- `:: any` porque los Init no devuelven nada y el checker no deja leer el
	-- segundo valor de pcall si la función no declara retorno.
	local ok, err = pcall(iniciar :: any)
	if not ok then
		table.insert(fallados, nombre)
		warn(`[RaidBlox] ✗ {nombre}.Init() falló: {err}`)
	end
end

-- 1. Red primero: los demás sistemas registran sus remotes sobre ella.
arrancar("NetworkBridge", NetworkBridge.Server.Init)

-- 2. Datos de jugadores.
DataManager.Init()

-- 3. Seguridad de movimiento.
AntiCheat.Init()

-- 4. Mundo: portales y teletransporte.
ZoneManager.Init()

-- 5. Bandos (PvP) y apariencia; después el combate: motor, botín, enemigos y
-- jefes de la zona de este place.
BandoManager.Init(ZoneManager.ZonaActual())
arrancar("AparienciaManager", AparienciaManager.Init)
arrancar("CombatManager", CombatManager.Init)
arrancar("LootManager", LootManager.Init)
local zona = ZoneManager.ZonaActual()
-- El minimapa del cliente muestra el nombre de la zona.
game:GetService("Workspace"):SetAttribute("Zona", zona or "Desconocida")
arrancar("EnemyManager", function()
	EnemyManager.Init(zona)
end)
RaidBloxManager.Init(zona)

-- 6. Economía: inventario, profesiones, subastas y comercio.
arrancar("InventarioManager", InventarioManager.Init)
arrancar("CraftingManager", CraftingManager.Init)
arrancar("RecoleccionManager", RecoleccionManager.Init)
arrancar("AuctionManager", AuctionManager.Init)
TradeManager.Init()

-- 6b. Fase 5: grupos y misiones.
arrancar("GrupoManager", GrupoManager.Init)
arrancar("HermandadManager", HermandadManager.Init)
arrancar("VozManager", VozManager.Init)
arrancar("MazmorraManager", function()
	MazmorraManager.Init(zona)
end)
arrancar("PasesManager", PasesManager.Init)
arrancar("MonturaManager", MonturaManager.Init)
arrancar("ProductosManager", ProductosManager.Init)
arrancar("PaseBatallaManager", PaseBatallaManager.Init)
arrancar("MascotaManager", MascotaManager.Init)
-- Antes de EquipoVisible: crea los modelos que este dibuja.
arrancar("PersonalizadorManager", PersonalizadorManager.Init)
arrancar("EquipoVisible", EquipoVisible.Init)
arrancar("AdminManager", AdminManager.Init)
arrancar("ChatarreroManager", ChatarreroManager.Init)
arrancar("BuffManager", BuffManager.Init)
arrancar("NpcManager", NpcManager.Init)
arrancar("ExploracionManager", function()
	ExploracionManager.Init(zona)
end)
arrancar("ProgresionSocialManager", ProgresionSocialManager.Init)
arrancar("ArenaManager", ArenaManager.Init)
arrancar("JuegosManager", JuegosManager.Init)
arrancar("ParcelaManager", ParcelaManager.Init)
arrancar("ConstruccionManager", ConstruccionManager.Init)
arrancar("PergaminoManager", PergaminoManager.Init)
arrancar("RazaManager", RazaManager.Init)
arrancar("StencilManager", StencilManager.Init)
arrancar("CosmeticosManager", CosmeticosManager.Init)
arrancar("VaultManager", VaultManager.Init)
arrancar("ForjaManager", ForjaManager.Init)
MisionManager.Init()

-- 7. Modos de juego según el place.
if ArchitectWarManager.DebeActivarse() then
	arrancar("ArchitectWarManager", ArchitectWarManager.Init)
end

-- 8. Herramientas de prueba: comandos (solo Studio) y NPCs de oro y materiales.
arrancar("DebugStudio", DebugStudio.Init)
arrancar("NpcsPrueba", NpcsPrueba.Init)
arrancar("EditorPiedra", EditorPiedra.Init)

------------------------------------------------------------------------
-- Resumen de arranque
------------------------------------------------------------------------
-- Diagnóstico corto para la consola del servidor: con esto se ve de una
-- pasada si el contenido de prueba se creó, cuántos nodos y estaciones hay y
-- qué sistema se cayó, sin tener que reproducir el problema.
local CollectionService = game:GetService("CollectionService")
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)

local function cuantos(tag: string): number
	return #CollectionService:GetTagged(tag)
end

print(`[RaidBlox] Servidor iniciado (zona: {zona or "sin configurar"})`)
print(
	`[RaidBlox] Modo pruebas: {Pruebas.Activas()}`
		.. ` · nodos: {cuantos("NodoRecoleccion")}`
		.. ` · estaciones: {cuantos("EstacionCrafteo")}`
		.. ` · NPC: {cuantos("NpcArquetipo")}`
		.. ` · piedras: {cuantos("PiedraTeleport")}`
		.. ` · bóvedas: {cuantos("BancoVault") + cuantos("CofreVault")}`
)
if #fallados > 0 then
	warn(`[RaidBlox] ✗ {#fallados} sistema(s) NO arrancaron: {table.concat(fallados, ", ")}`)
	warn("[RaidBlox] Lo que dependa de ellos no va a funcionar. El error de cada uno está más arriba.")
else
	print("[RaidBlox] Todos los sistemas arrancaron sin errores.")
end
