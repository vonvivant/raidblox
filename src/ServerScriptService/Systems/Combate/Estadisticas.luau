--!strict
-- Estadisticas: calcula las estadísticas de combate de jugadores y enemigos.
--
-- Jugador = clase (base + por nivel) + equipamiento.
-- Cada ítem equipado aporta sus Atributos multiplicados por su rareza:
--   Fuerza -> +1 Ataque, Inteligencia -> +1 Poder, Agilidad -> +0.5% crítico
-- y además sus efectos secundarios (Meta.Efecto_*) y su pasiva (Meta.Pasiva).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ClassConfig = require(ReplicatedStorage.Configs.ClassConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ItemRarityConfig = require(ReplicatedStorage.Configs.ItemRarityConfig)

export type Stats = {
	VidaMax: number,
	ManaMax: number,
	RegenMana: number,
	Ataque: number,
	Poder: number,
	Defensa: number,
	Critico: number, -- 0..1
	RoboVida: number, -- 0..1
	Pasivas: { [string]: boolean },
	MultiplicadorAmenaza: number,
	MultiplicadorEspalda: number?,
	Esquiva: number, -- 0..ClassConfig.EsquivaMaxima, solo contra golpes físicos directos
}

local Estadisticas = {}

local function porNivel(base: number, incremento: number, nivel: number): number
	return base + incremento * (nivel - 1)
end

-- Suma lo que aporta un ítem equipado.
local function aplicarItem(stats: Stats, item: Types.ItemInstancia)
	local def = ItemCatalog[item.ItemId]
	if not def then
		return
	end
	local rareza = ItemRarityConfig.Rarezas[item.Rareza]
	local meta = item.Meta
	-- El multiplicador se guarda en el ítem al generarlo; si no está, se usa el de la rareza.
	local mult = if meta and typeof(meta.Mult) == "number"
		then meta.Mult :: number
		else (if rareza then rareza.Multiplicador else 1)

	local atributos = def.Atributos
	if atributos then
		stats.Ataque += (atributos.Fuerza or 0) * mult
		stats.Poder += (atributos.Inteligencia or 0) * mult
		stats.Critico += (atributos.Agilidad or 0) * mult * 0.005
		stats.Esquiva += (atributos.Agilidad or 0) * mult * ClassConfig.EsquivaPorAgilidad
	end

	if meta then
		for clave, valor in meta do
			if typeof(valor) ~= "number" or string.sub(clave, 1, 7) ~= "Efecto_" then
				continue
			end
			local efecto = string.sub(clave, 8)
			local v = valor :: number
			if efecto == "Critico" then
				stats.Critico += v / 100
			elseif efecto == "RoboVida" then
				stats.RoboVida += v / 100
			elseif efecto == "RegenMana" then
				stats.RegenMana += v
			elseif efecto == "Defensa" then
				stats.Defensa += v
			elseif efecto == "Ataque" then
				stats.Ataque += v
			elseif efecto == "Poder" then
				stats.Poder += v
			end
		end
		local pasiva = meta.Pasiva
		if typeof(pasiva) == "string" and ItemRarityConfig.Pasivas[pasiva] then
			stats.Pasivas[pasiva] = true
		end
	end
end

function Estadisticas.DeJugador(datos: Types.DatosJugador): Stats
	local def = ClassConfig.Clases[datos.Clase]
	local base = if def then def.Base else ClassConfig.SinClase.Base
	local inc = if def then def.PorNivel else ClassConfig.SinClase.PorNivel
	local nivel = datos.Nivel

	local stats: Stats = {
		VidaMax = porNivel(base.Vida, inc.Vida, nivel),
		ManaMax = porNivel(base.Mana, inc.Mana, nivel),
		RegenMana = porNivel(base.RegenMana, inc.RegenMana, nivel),
		Ataque = porNivel(base.Ataque, inc.Ataque, nivel),
		Poder = porNivel(base.Poder, inc.Poder, nivel),
		Defensa = porNivel(base.Defensa, inc.Defensa, nivel),
		Critico = base.Critico,
		RoboVida = 0,
		Pasivas = {},
		MultiplicadorAmenaza = if def then def.MultiplicadorAmenaza else 1,
		MultiplicadorEspalda = if def then def.MultiplicadorEspalda else nil,
		Esquiva = ClassConfig.EsquivaPorClase[datos.Clase] or ClassConfig.EsquivaBase,
	}

	for _, item in datos.Equipamiento :: { [string]: Types.ItemInstancia } do
		aplicarItem(stats, item)
	end
	if stats.Pasivas.Vampirismo then
		stats.RoboVida += 0.08
	end

	stats.VidaMax = math.floor(stats.VidaMax)
	stats.ManaMax = math.floor(stats.ManaMax)
	stats.Critico = math.clamp(stats.Critico, 0, 0.75)
	stats.RoboVida = math.clamp(stats.RoboVida, 0, 0.5)
	stats.Esquiva = math.clamp(stats.Esquiva, 0, ClassConfig.EsquivaMaxima)
	return stats
end

function Estadisticas.DeEnemigo(vida: number, danio: number, defensa: number): Stats
	return {
		VidaMax = vida,
		ManaMax = 0,
		RegenMana = 0,
		Ataque = danio,
		Poder = danio,
		Defensa = defensa,
		Critico = 0.05,
		RoboVida = 0,
		Pasivas = {},
		MultiplicadorAmenaza = 1,
		MultiplicadorEspalda = nil,
		Esquiva = ClassConfig.EsquivaEnemigos,
	}
end

return Estadisticas
