--!strict
-- RazaManager: la raza del jugador (Humano por defecto, Artesano).
--
-- La raza no toca el combate. Lo que hace es engancharse en cuatro lugares
-- que ya existían, en vez de duplicar nada:
--
--   * NpcManager: cuánto paga un NPC por lo que le vendés (Humano).
--   * CraftingManager: probabilidad de obra maestra y **firma de autoría**
--     (Artesano). La firma es `Meta.Autor`, que la bóveda ya busca.
--   * ForjaManager: el costo de reparar (Artesano).
--
-- Cada sistema expone un `Registrar...` y pregunta; así ninguno depende de
-- este módulo y se puede sacar la raza sin romper nada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage.Configs.RazasConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local CombatManager = require(script.Parent.Combate.CombatManager)
local CraftingManager = require(script.Parent.Economia.CraftingManager)
local DataManager = require(script.Parent.DataManager)
local ForjaManager = require(script.Parent.Economia.ForjaManager)
local NpcManager = require(script.Parent.NpcManager)

local RazaManager = {}

local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
	end
end

-- La raza guardada, o la de por defecto si todavía no eligió.
function RazaManager.De(player: Player): string
	local datos = DataManager.GetData(player)
	if not datos then
		return CFG.PorDefecto
	end
	local raza = (datos :: any).Raza
	return if CFG.Valida(raza) then raza else CFG.PorDefecto
end

-- ¿Ya eligió alguna vez? (para saber si el cambio es gratis)
local function yaEligio(player: Player): boolean
	local datos = DataManager.GetData(player)
	return datos ~= nil and CFG.Valida((datos :: any).Raza)
end

local function elegir(player: Player, razaId: string): Types.Respuesta
	if not CFG.Valida(razaId) then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local datos = DataManager.GetData(player)
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	if RazaManager.De(player) == razaId and yaEligio(player) then
		return NetworkBridge.Ok({ Raza = razaId })
	end
	if CombatManager.EnCombate(player) then
		avisar(player, "No se cambia de raza en combate.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end

	local libre: { [string]: any } = datos :: any
	local ultimo: number? = if typeof(libre.RazaCambio) == "number" then libre.RazaCambio else nil
	local ahora = os.time()
	if yaEligio(player) and not CFG.PuedeCambiar(ultimo, ahora) then
		local faltan = math.ceil(CFG.FaltaParaCambiar(ultimo, ahora) / 60)
		avisar(player, `Podés volver a cambiar de raza en {faltan} min.`, "Aviso")
		return NetworkBridge.Fail("RATE_LIMITED")
	end

	local costo = CFG.Costo(yaEligio(player))
	if costo > 0 and not DataManager.SpendGold(player, costo) then
		avisar(player, `Cambiar de raza cuesta {costo} de oro.`, "Error")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	DataManager.Mutar(player, "Raza", function(d)
		local campos: { [string]: any } = d :: any
		campos.Raza = razaId
		campos.RazaCambio = ahora
	end)
	local def = CFG.Raza(razaId)
	avisar(player, `Ahora sos {def.Nombre}.{if costo > 0 then ` Costó {costo} de oro.` else ""}`, "Exito")
	return NetworkBridge.Ok({ Raza = razaId, Costo = costo })
end

function RazaManager.Init()
	if iniciado then
		return
	end
	iniciado = true

	-- Humano: los NPC pagan mejor lo que les vendés.
	NpcManager.RegistrarBonusVenta(function(player: Player, pago: number): number
		return CFG.PagoConBono(pago, RazaManager.De(player))
	end)

	-- Artesano: más obras maestras y firma en lo que fabrica.
	CraftingManager.RegistrarBonusMasterpiece(function(player: Player, probabilidad: number, tope: number): number
		return CFG.MasterpieceConBono(probabilidad, RazaManager.De(player), tope)
	end)
	CraftingManager.RegistrarFirma(function(player: Player): string?
		if not CFG.Raza(RazaManager.De(player)).Firma then
			return nil
		end
		return string.sub(player.DisplayName, 1, CFG.LargoAutorMaximo)
	end)

	-- Artesano: reparar le sale más barato.
	ForjaManager.RegistrarDescuentoReparacion(function(player: Player, costo: number): number
		return CFG.CostoConDescuento(costo, RazaManager.De(player))
	end)

	NetworkBridge.Server.OnInvoke("RazaElegir", function(player: Player, razaId: unknown): Types.Respuesta
		local id = NetworkBridge.Guard.String(razaId, 24)
		if not id then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return elegir(player, id)
	end)
end

return RazaManager
