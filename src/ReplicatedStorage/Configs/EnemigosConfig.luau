--!strict
-- EnemigosConfig: enemigos comunes, dónde aparecen y qué sueltan.
--
-- Zona: id de ZoneConfig donde aparece el spawn. "Pruebas" solo se usa en Studio
-- (área de práctica cerca del origen, hacia -Z).

export type EntradaBotin = {
	ItemId: string,
	Probabilidad: number, -- 0..1
	Min: number,
	Max: number,
	Rareza: string?, -- fija; nil = se sortea con ItemRarityConfig.PesosPorDefecto (solo equipos)
}

export type DefinicionEnemigo = {
	Nombre: string,
	Nivel: number,
	Vida: number,
	Danio: number,
	Defensa: number,
	RangoAtaque: number,
	CadenciaAtaque: number, -- segundos entre ataques
	Velocidad: number,
	RadioAgro: number, -- distancia a la que detecta jugadores
	RadioCorrea: number, -- si se aleja más que esto de su spawn, vuelve y se cura
	Escala: number,
	Color: Color3,
	Pasivo: boolean?, -- muñeco de práctica: no ataca ni se mueve
	Xp: number,
	Oro: number,
	Botin: { EntradaBotin },
}

export type Spawn = {
	Enemigo: string,
	Zona: string,
	Posicion: Vector3,
	Cantidad: number,
	Dispersion: number, -- radio alrededor de Posicion
	Reaparicion: number, -- segundos
}

local EnemigosConfig = {
	Enemigos = {
		Muneco = {
			Nombre = "Muñeco de Práctica",
			Nivel = 1,
			Vida = 2000,
			Danio = 0,
			Defensa = 0,
			RangoAtaque = 0,
			CadenciaAtaque = 999,
			Velocidad = 0,
			RadioAgro = 0,
			RadioCorrea = 999,
			Escala = 1.2,
			Color = Color3.fromRGB(190, 160, 110),
			Pasivo = true,
			Xp = 0,
			Oro = 0,
			Botin = {},
		},
		Lobo = {
			Nombre = "Lobo Gris",
			Nivel = 2,
			Vida = 120,
			Danio = 8,
			Defensa = 4,
			RangoAtaque = 6,
			CadenciaAtaque = 2,
			Velocidad = 14,
			RadioAgro = 30,
			RadioCorrea = 70,
			Escala = 1,
			Color = Color3.fromRGB(120, 120, 125),
			Xp = 40,
			Oro = 6,
			Botin = {
				{ ItemId = "Madera", Probabilidad = 0.5, Min = 1, Max = 3 },
				{ ItemId = "PocionVida", Probabilidad = 0.25, Min = 1, Max = 1 },
				{ ItemId = "CascoCuero", Probabilidad = 0.08, Min = 1, Max = 1 },
				{ ItemId = "EspadaHierro", Probabilidad = 0.05, Min = 1, Max = 1 },
			},
		},
		Bandido = {
			Nombre = "Bandido",
			Nivel = 4,
			Vida = 220,
			Danio = 14,
			Defensa = 8,
			RangoAtaque = 7,
			CadenciaAtaque = 2.2,
			Velocidad = 15,
			RadioAgro = 35,
			RadioCorrea = 80,
			Escala = 1,
			Color = Color3.fromRGB(150, 70, 60),
			Xp = 90,
			Oro = 15,
			Botin = {
				{ ItemId = "Hierro", Probabilidad = 0.5, Min = 1, Max = 2 },
				{ ItemId = "PocionVida", Probabilidad = 0.3, Min = 1, Max = 2 },
				{ ItemId = "PecheraCuero", Probabilidad = 0.08, Min = 1, Max = 1 },
				{ ItemId = "BaculoRoble", Probabilidad = 0.06, Min = 1, Max = 1 },
				{ ItemId = "AnilloCobre", Probabilidad = 0.05, Min = 1, Max = 1 },
			},
		},
	} :: { [string]: DefinicionEnemigo },

	Spawns = {
		{
			Enemigo = "Muneco",
			Zona = "Pruebas",
			Posicion = Vector3.new(-20, 0, -110),
			Cantidad = 2,
			Dispersion = 8,
			Reaparicion = 5,
		},
		{
			Enemigo = "Lobo",
			Zona = "Pruebas",
			Posicion = Vector3.new(30, 0, -130),
			Cantidad = 3,
			Dispersion = 12,
			Reaparicion = 15,
		},
		{
			Enemigo = "Bandido",
			Zona = "Pruebas",
			Posicion = Vector3.new(-40, 0, -150),
			Cantidad = 2,
			Dispersion = 10,
			Reaparicion = 25,
		},
		{
			Enemigo = "Lobo",
			Zona = "Bosque",
			Posicion = Vector3.new(0, 0, 60),
			Cantidad = 6,
			Dispersion = 30,
			Reaparicion = 20,
		},
		{
			Enemigo = "Bandido",
			Zona = "Bosque",
			Posicion = Vector3.new(80, 0, 120),
			Cantidad = 4,
			Dispersion = 20,
			Reaparicion = 30,
		},
	} :: { Spawn },

	-- Amenaza: cuánto vale cada punto de curación (repartido entre los enemigos que
	-- ya están peleando con el curado).
	AmenazaPorCura = 0.5,
	TickIA = 0.25, -- segundos entre decisiones de la IA
	AvisoAtaque = 0.45, -- segundos entre el aviso "¡!" y el golpe (ventana para hacer parry)
}

return EnemigosConfig
