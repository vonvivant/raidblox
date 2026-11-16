--!strict
-- Arenas clasificatorias (NPC-038, Reclutador de Arenas).
--
-- Acá viven solo las reglas puras: modos, emparejamiento, rating y premios.
-- Las usa ArenaManager en el servidor y ArenaUI en el cliente, y las pruebas
-- de tests/run.py las verifican sin necesidad de Studio.

export type Modo = {
	Id: string,
	Nombre: string,
	PorEquipo: number, -- jugadores de cada lado
	Descripcion: string,
}

export type Rango = { Desde: number, Nombre: string }

local Config = {}

-- Modos disponibles. El orden es el que ve el jugador en el NPC.
Config.Modos = {
	{ Id = "1v1", Nombre = "Duelo 1v1", PorEquipo = 1, Descripcion = "Uno contra uno, sin ayuda." },
	{ Id = "2v2", Nombre = "Dupla 2v2", PorEquipo = 2, Descripcion = "De a dos. Podés anotarte con tu grupo." },
	{ Id = "3v3", Nombre = "Escuadra 3v3", PorEquipo = 3, Descripcion = "De a tres. Podés anotarte con tu grupo." },
} :: { Modo }

-- Partida: se gana ganando 2 de 3 rondas.
Config.RondasParaGanar = 2
Config.RondasMaximas = 3
Config.Preparacion = 6 -- segundos quietos antes de que arranque la ronda
Config.DuracionRonda = 100 -- si nadie cae, se resuelve por vida restante
Config.EntreRondas = 6
Config.Celebracion = 8 -- cuánto se queda el equipo en el arena al terminar
Config.PartidasSimultaneas = 6

-- Rating (Elo). Arranca en 1000 y no baja de 0.
Config.RatingInicial = 1000
Config.K = 24
Config.RatingMinimo = 0

Config.Rangos = {
	{ Desde = 0, Nombre = "Sin rango" },
	{ Desde = 900, Nombre = "Bronce" },
	{ Desde = 1150, Nombre = "Plata" },
	{ Desde = 1400, Nombre = "Oro" },
	{ Desde = 1650, Nombre = "Platino" },
	{ Desde = 1900, Nombre = "Diamante" },
	{ Desde = 2200, Nombre = "Leyenda" },
} :: { Rango }

-- Emparejamiento: la ventana de rating se abre con la espera, así nadie queda
-- colgado en la cola de un servidor vacío.
Config.VentanaInicial = 150
Config.VentanaPorPaso = 50
Config.SegundosPorPaso = 10
Config.VentanaMaxima = 1200
Config.TickEmparejar = 2

-- Premios en honor y tope diario (el rating no tiene tope).
Config.HonorVictoria = 30
Config.HonorDerrota = 10
Config.HonorPorRacha = 5 -- extra por victoria seguida, hasta RachaMaxima
Config.RachaMaxima = 5
Config.TopeHonorDiario = 300
Config.HoraReinicio = 19 -- UTC, igual que las misiones diarias

-- Mapa generado: una plataforma por partida, lejos de la ciudad.
Config.Mapa = {
	Origen = Vector3.new(-1800, 120, 1500),
	Separacion = 260,
	Tamano = Vector3.new(120, 1, 120),
	AlturaMuro = 20,
	Spawn = 44, -- distancia del centro a cada lado
	SeparacionCompanero = 7,
}

Config.CooldownInscripcion = 8 -- segundos entre intentos de anotarse
Config.DistanciaNpc = 14

-- ¿Qué modo es? (nil si el id no existe)
function Config.Modo(id: string): Modo?
	for _, modo in Config.Modos do
		if modo.Id == id then
			return modo
		end
	end
	return nil
end

function Config.RangoDe(rating: number): string
	local nombre = Config.Rangos[1].Nombre
	for _, rango in Config.Rangos do
		if rating >= rango.Desde then
			nombre = rango.Nombre
		end
	end
	return nombre
end

-- Cuánto rating puede separar a dos jugadores que esperaron estos segundos.
function Config.Ventana(segundosEsperando: number): number
	local pasos = math.floor(math.max(0, segundosEsperando) / Config.SegundosPorPaso)
	return math.min(Config.VentanaMaxima, Config.VentanaInicial + pasos * Config.VentanaPorPaso)
end

-- ¿Se pueden cruzar? Vale la ventana del que esperó más.
function Config.Compatibles(ratingA: number, ratingB: number, esperaA: number, esperaB: number): boolean
	local ventana = math.max(Config.Ventana(esperaA), Config.Ventana(esperaB))
	return math.abs(ratingA - ratingB) <= ventana
end

-- Elo clásico. Devuelve cuánto se mueve el rating propio (ya redondeado).
function Config.Delta(propio: number, rival: number, gano: boolean): number
	local esperado = 1 / (1 + 10 ^ ((rival - propio) / 400))
	local real = if gano then 1 else 0
	local delta = Config.K * (real - esperado)
	-- Nunca cero: ganar siempre suma algo y perder siempre resta algo.
	if delta > 0 then
		return math.max(1, math.floor(delta + 0.5))
	end
	return math.min(-1, -math.floor(-delta + 0.5))
end

function Config.AplicarDelta(rating: number, delta: number): number
	return math.max(Config.RatingMinimo, rating + delta)
end

function Config.Promedio(ratings: { number }): number
	if #ratings == 0 then
		return Config.RatingInicial
	end
	local suma = 0
	for _, r in ratings do
		suma += r
	end
	return suma / #ratings
end

-- Honor de una partida, respetando el tope del día.
-- Devuelve cuánto se paga y cuánto queda anotado como ganado hoy.
function Config.Honor(gano: boolean, racha: number, ganadoHoy: number): (number, number)
	local bruto = if gano then Config.HonorVictoria else Config.HonorDerrota
	if gano then
		bruto += Config.HonorPorRacha * math.clamp(math.floor(racha), 0, Config.RachaMaxima)
	end
	local libre = math.max(0, Config.TopeHonorDiario - math.max(0, ganadoHoy))
	local pago = math.min(bruto, libre)
	return pago, math.max(0, ganadoHoy) + pago
end

-- Día del tope diario (mismo corte que las diarias del Tablón).
function Config.DiaDe(ahora: number): number
	return math.floor((ahora - Config.HoraReinicio * 3600) / 86400)
end

return Config
