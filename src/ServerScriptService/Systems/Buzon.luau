--!strict
-- Buzon: envíos durables al buzón de un jugador (ProfileStore MessageAsync),
-- compartidos por botín, crafteo, comercio y subastas.
--
-- * Reintenta con espera creciente.
-- * Usa SIEMPRE el mismo Id de mensaje en todos los reintentos: si un intento
--   se escribió pero devolvió error, el reintento no genera un duplicado
--   (DataManager descarta Ids ya procesados).
-- * El cierre del servidor espera (hasta 25 s) a que terminen los envíos en curso.

local HttpService = game:GetService("HttpService")

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local DataManager = require(script.Parent.DataManager)

local Buzon = {}

-- Lo mínimo para enviar un ítem (ItemInstancia también sirve).
export type ItemEnvio = {
	ItemId: string,
	Cantidad: number,
	Rareza: Types.Rareza,
	Meta: Types.ItemMeta?,
}

local REINTENTOS = 5
local enCurso = 0
local cierreRegistrado = false

local function registrarCierre()
	if cierreRegistrado then
		return
	end
	cierreRegistrado = true
	game:BindToClose(function()
		local limite = os.clock() + 25
		while enCurso > 0 and os.clock() < limite do
			task.wait(0.2)
		end
	end)
end

local function conReintentos(fn: () -> boolean): boolean
	registrarCierre()
	enCurso += 1
	local espera = 1
	local ok = false
	for intento = 1, REINTENTOS do
		local llamada, resultado = pcall(fn)
		if llamada and resultado then
			ok = true
			break
		end
		if intento < REINTENTOS then
			task.wait(espera)
			espera *= 2
		end
	end
	enCurso -= 1
	return ok
end

-- Se registra al cargar el módulo: un BindToClose conectado durante el cierre
-- podría no ejecutarse.
registrarCierre()

function Buzon.NuevoId(): string
	return HttpService:GenerateGUID(false)
end

-- Envía un ítem y espera el resultado (bloquea). Devuelve true si quedó escrito.
function Buzon.EnviarItemAsync(userId: number, item: ItemEnvio, motivo: string, id: string): boolean
	local ok = conReintentos(function()
		return DataManager.EnviarItemOffline(userId, item.ItemId, item.Cantidad, item.Rareza, item.Meta, motivo, id)
	end)
	if not ok then
		warn(`[Buzon] No se pudo enviar {item.ItemId} x{item.Cantidad} a {userId} ({motivo}, id {id})`)
	end
	return ok
end

-- Envía oro y espera el resultado (bloquea).
function Buzon.EnviarOroAsync(userId: number, cantidad: number, motivo: string, id: string): boolean
	if cantidad <= 0 then
		return true
	end
	local ok = conReintentos(function()
		return DataManager.EnviarOroOffline(userId, cantidad, motivo, id)
	end)
	if not ok then
		warn(`[Buzon] No se pudo enviar {cantidad} de oro a {userId} ({motivo}, id {id})`)
	end
	return ok
end

-- Versiones en segundo plano (no bloquean a quien llama).
function Buzon.EnviarItem(userId: number, item: ItemEnvio, motivo: string, id: string?)
	local fijo = id or Buzon.NuevoId()
	task.spawn(Buzon.EnviarItemAsync, userId, item, motivo, fijo)
end

function Buzon.EnviarOro(userId: number, cantidad: number, motivo: string, id: string?)
	local fijo = id or Buzon.NuevoId()
	task.spawn(Buzon.EnviarOroAsync, userId, cantidad, motivo, fijo)
end

-- Da oro al jugador si está conectado; si no se puede (se fue, tope), al buzón.
function Buzon.DarOro(player: Player, cantidad: number, motivo: string)
	if cantidad <= 0 then
		return
	end
	if not DataManager.AddGold(player, cantidad) then
		Buzon.EnviarOro(player.UserId, cantidad, motivo)
	end
end

-- Da un ítem al jugador si entra; si no, al buzón.
function Buzon.DarItem(player: Player, item: Types.ItemInstancia, motivo: string)
	if not DataManager.AgregarInstancia(player, item) then
		Buzon.EnviarItem(player.UserId, item, motivo)
	end
end

return Buzon
