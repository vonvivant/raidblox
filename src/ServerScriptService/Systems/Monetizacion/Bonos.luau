--!strict
-- Bonos: multiplicadores de experiencia y oro por jugador (VIP, boosters).
-- Módulo hoja (no requiere a nadie): lo escriben los sistemas de
-- monetización y lo leen los que dan recompensas (enemigos, misiones,
-- mazmorras). Solo se aplica a recompensas de juego, nunca a oro que viene de
-- otro jugador (comercio, subastas, buzón).

local Bonos = {}

type Estado = { Vip: number, BoosterXpHasta: number, MultBoosterXp: number }
local estados: { [Player]: Estado } = {}

local function de(player: Player): Estado
	local e = estados[player]
	if not e then
		e = { Vip = 1, BoosterXpHasta = 0, MultBoosterXp = 1 }
		estados[player] = e
	end
	return e
end

function Bonos.SetVip(player: Player, multiplicador: number?)
	de(player).Vip = multiplicador or 1
end

-- Booster de experiencia hasta `hasta` (os.time()).
function Bonos.SetBoosterXp(player: Player, hasta: number, multiplicador: number)
	local e = de(player)
	e.BoosterXpHasta = hasta
	e.MultBoosterXp = multiplicador
end

function Bonos.Xp(player: Player, base: number): number
	local e = estados[player]
	if not e or base <= 0 then
		return base
	end
	local mult = e.Vip * (if os.time() < e.BoosterXpHasta then e.MultBoosterXp else 1)
	return math.floor(base * mult + 0.5)
end

function Bonos.Oro(player: Player, base: number): number
	local e = estados[player]
	if not e or base <= 0 then
		return base
	end
	return math.floor(base * e.Vip + 0.5)
end

function Bonos.Limpiar(player: Player)
	estados[player] = nil
end

return Bonos
