--!strict
-- MazmorrasConfig: mazmorras para grupos (hasta 5).
--
-- PlaceId = 0: todavía no hay un place propio, la instancia se arma en un área
-- aparte de este mismo servidor (modo local, sirve para probar). Con un
-- PlaceId real, el líder abre un servidor reservado y van todos juntos.
--
-- Cada mazmorra: salas con enemigos (EnemigosConfig) y un jefe con mecánicas.
-- Se gana matando al jefe. Se pierde si el grupo muere entero más veces que
-- los intentos, o si se acaba el tiempo.

local EnemigosConfig = require(script.Parent.EnemigosConfig)

export type Grupo = { Enemigo: string, Cantidad: number }
export type Sala = { Nombre: string, Enemigos: { Grupo } }
export type Mecanica = {
	Tipo: "Pisoton" | "Lluvia" | "Invocar",
	Nombre: string,
	Radio: number?, -- Pisoton (alrededor del jefe) y Lluvia (sobre un jugador)
	Aviso: number?, -- segundos de zona roja antes del golpe
	Multiplicador: number?, -- sobre el daño del jefe
	Cada: number?, -- segundos entre usos
	Enemigo: string?, -- Invocar
	Cantidad: number?,
	AlPorcentaje: { number }?, -- Invocar: fracciones de vida (0.66 = al 66%)
}
export type Jefe = {
	Nombre: string,
	Nivel: number,
	Vida: number, -- con 1 jugador; se multiplica por (0.7 + 0.3 × jugadores)
	Danio: number,
	Defensa: number,
	RangoAtaque: number,
	CadenciaAtaque: number,
	Velocidad: number,
	Escala: number,
	Color: Color3,
	Mecanicas: { Mecanica },
	Xp: number,
	Oro: number,
	Botin: { EnemigosConfig.EntradaBotin },
}
export type Mazmorra = {
	Nombre: string,
	PlaceId: number,
	NivelMinimo: number, -- en modo pruebas no se exige
	TiempoLimite: number, -- segundos
	Intentos: number, -- veces que el grupo puede morir entero
	Salas: { Sala },
	Jefe: Jefe,
	Recompensa: { Oro: number, Xp: number }, -- a cada uno al ganar
}

local MazmorrasConfig = {
	-- Portal de entrada en la zona de pruebas.
	PosicionPortal = Vector3.new(20, 0, -62),
	DistanciaGrupo = 60, -- todos los del grupo tienen que estar cerca del portal
	-- Modo local: las instancias se arman lejos, en el aire, separadas entre sí.
	OrigenLocal = Vector3.new(1500, 60, 1500),
	SeparacionLocal = 500,
	SegundosParaSalirTrasGanar = 45,
	SegundosParaSalirTrasPerder = 6,
	NombreMemoria = "MazmorrasReservadas", -- MemoryStore: qué grupo va a cada servidor reservado

	Mazmorras = {
		CriptaDelGuardian = {
			Nombre = "Cripta del Guardián",
			PlaceId = 0,
			NivelMinimo = 3,
			TiempoLimite = 20 * 60,
			Intentos = 3,
			Salas = {
				{ Nombre = "Antesala", Enemigos = { { Enemigo = "Lobo", Cantidad = 3 } } },
				{
					Nombre = "Galería de los Saqueadores",
					Enemigos = { { Enemigo = "Bandido", Cantidad = 3 }, { Enemigo = "Lobo", Cantidad = 2 } },
				},
			},
			Jefe = {
				Nombre = "Guardián de la Cripta",
				Nivel = 8,
				Vida = 2600,
				Danio = 22,
				Defensa = 25,
				RangoAtaque = 10,
				CadenciaAtaque = 2.4,
				Velocidad = 11,
				Escala = 2.6,
				Color = Color3.fromRGB(70, 95, 85),
				Mecanicas = {
					{
						Tipo = "Pisoton",
						Nombre = "Golpe Sísmico",
						Radio = 14,
						Aviso = 1.8,
						Multiplicador = 1.8,
						Cada = 11,
					},
					{ Tipo = "Lluvia", Nombre = "Derrumbe", Radio = 8, Aviso = 1.6, Multiplicador = 1.4, Cada = 8 },
					{
						Tipo = "Invocar",
						Nombre = "Llamado de la Manada",
						Enemigo = "Lobo",
						Cantidad = 2,
						AlPorcentaje = { 0.66, 0.33 },
					},
				},
				Xp = 600,
				Oro = 150,
				Botin = {
					{ ItemId = "Hierro", Probabilidad = 0.9, Min = 2, Max = 5 },
					{ ItemId = "PocionVida", Probabilidad = 0.6, Min = 1, Max = 3 },
					{ ItemId = "EspadaHierro", Probabilidad = 0.2, Min = 1, Max = 1 },
					{ ItemId = "BaculoRoble", Probabilidad = 0.2, Min = 1, Max = 1 },
					{ ItemId = "AnilloCobre", Probabilidad = 0.15, Min = 1, Max = 1 },
				},
			},
			Recompensa = { Oro = 100, Xp = 300 },
		},
	} :: { [string]: Mazmorra },
}

return MazmorrasConfig
