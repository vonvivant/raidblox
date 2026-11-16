--!strict
-- Juegos del Crupier (NPC-036): minijuegos de habilidad, sin apuestas.
--
-- Decisión que ya estaba anotada en el arquetipo: Roblox no permite apostar
-- con nada que se compre con Robux, así que acá **no se apuesta ni se paga
-- oro**. Jugar es gratis y lo único que se gana son títulos y el récord
-- personal. Si alguien hace trampa, se hace trampa a sí mismo.
--
-- Dos juegos:
--   * Runas:  el servidor arma una secuencia, el jugador la repite. Cada
--             ronda suma una runa. Clásico "Simón dice".
--   * Pares:  tablero de 16 cartas, 8 pares. El servidor guarda el tablero
--             oculto y solo revela lo que el jugador toca. Gana el que lo
--             limpia con pocos intentos.

export type Premio = { Marca: number, Titulo: string, Texto: string }

export type Juego = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	-- "Mas" = mejor cuanto más alto (rondas); "Menos" = mejor cuanto más bajo (intentos).
	Mejor: "Mas" | "Menos",
	Unidad: string,
	Premios: { Premio },
}

local Config = {}

Config.Cooldown = 15 -- segundos entre partidas
Config.DistanciaNpc = 14

-- Runas ---------------------------------------------------------------
Config.Runas = {
	Colores = 4,
	RondaMaxima = 20,
	-- Tiempo para tocar cada runa de la respuesta.
	TiempoPorPaso = 3.5,
	-- Lo que tarda el cliente en mostrar la secuencia (el servidor espera eso
	-- antes de empezar a contar).
	MostrarPorRuna = 0.75,
	MargenMostrar = 1.5,
}

-- Pares ---------------------------------------------------------------
Config.Pares = {
	Pares = 8, -- 16 cartas
	Simbolos = 8,
	IntentosMaximos = 16, -- un intento = dar vuelta dos cartas
	Duracion = 150, -- segundos para todo el tablero
}

Config.Juegos = {
	{
		Id = "Runas",
		Nombre = "Memoria de Runas",
		Descripcion = "Repetí la secuencia. Cada ronda agrega una runa más.",
		Mejor = "Mas",
		Unidad = "rondas",
		Premios = {
			{ Marca = 5, Titulo = "Aprendiz de Runas", Texto = "5 rondas seguidas" },
			{ Marca = 9, Titulo = "Memoria de Acero", Texto = "9 rondas seguidas" },
			{ Marca = 14, Titulo = "Oráculo de la Taberna", Texto = "14 rondas seguidas" },
		},
	},
	{
		Id = "Pares",
		Nombre = "Encontrá los Pares",
		Descripcion = "16 cartas, 8 pares. Limpiá el tablero con los menos intentos posibles.",
		Mejor = "Menos",
		Unidad = "intentos",
		Premios = {
			{ Marca = 14, Titulo = "Ojo Rápido", Texto = "el tablero en 14 intentos o menos" },
			{ Marca = 11, Titulo = "Buena Mano", Texto = "el tablero en 11 intentos o menos" },
			{ Marca = 9, Titulo = "Mente de Crupier", Texto = "el tablero en 9 intentos o menos" },
		},
	},
} :: { Juego }

function Config.Juego(id: string): Juego?
	for _, juego in Config.Juegos do
		if juego.Id == id then
			return juego
		end
	end
	return nil
end

function Config.Cartas(): number
	return Config.Pares.Pares * 2
end

-- ¿El resultado alcanza la marca del premio?
function Config.Alcanza(juego: Juego, resultado: number, marca: number): boolean
	if juego.Mejor == "Mas" then
		return resultado >= marca
	end
	return resultado > 0 and resultado <= marca
end

-- ¿El nuevo resultado es mejor que el récord guardado? (0 = sin récord)
function Config.EsMejor(juego: Juego, resultado: number, record: number): boolean
	if resultado <= 0 then
		return false
	end
	if record <= 0 then
		return true
	end
	if juego.Mejor == "Mas" then
		return resultado > record
	end
	return resultado < record
end

-- Títulos que corresponden a un resultado (los que ya tenga se ignoran al darlos).
function Config.PremiosDe(juego: Juego, resultado: number): { Premio }
	local ganados: { Premio } = {}
	for _, premio in juego.Premios do
		if Config.Alcanza(juego, resultado, premio.Marca) then
			table.insert(ganados, premio)
		end
	end
	return ganados
end

-- Cuánto tiempo tiene el jugador para responder una secuencia de `largo` runas.
function Config.TiempoRespuesta(largo: number): number
	return math.max(1, largo) * Config.Runas.TiempoPorPaso
end

-- Cuánto tarda el cliente en mostrar esa secuencia antes de que el jugador pueda responder.
function Config.TiempoMostrar(largo: number): number
	return math.max(1, largo) * Config.Runas.MostrarPorRuna + Config.Runas.MargenMostrar
end

-- Colores de las runas (los usan el servidor para validar y el cliente para dibujar).
Config.ColoresRuna = {
	Color3.fromRGB(230, 80, 80),
	Color3.fromRGB(80, 170, 240),
	Color3.fromRGB(240, 200, 80),
	Color3.fromRGB(110, 210, 120),
	Color3.fromRGB(190, 120, 240),
	Color3.fromRGB(240, 150, 70),
}

-- Símbolos de las cartas, en texto (así no hacen falta imágenes).
Config.SimbolosCarta = { "☀", "☾", "★", "⚒", "♆", "✦", "☘", "⚑" }

return Config
