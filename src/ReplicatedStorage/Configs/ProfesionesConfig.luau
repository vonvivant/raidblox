--!strict
-- ProfesionesConfig: profesiones de producción (Herrería, Alquimia, Sastrería) y
-- de recolección (Minería, Herboristería), recetas, estaciones y nodos.
--
-- Estaciones: Parts con tag "EstacionCrafteo" y atributo Estacion = "Yunque" |
-- "MesaAlquimia" | "Telar". Hay que estar a 12 studs o menos para fabricar.
-- Nodos de recolección: Parts con tag "NodoRecoleccion" y atributo Nodo = id de
-- la tabla Nodos (ej. "VetaHierro"). Requieren la herramienta equipada.
-- En Studio, si no hay estaciones ni nodos, se crea un área de prueba.

local Types = require(script.Parent.Parent.Shared.Types)

type Profesion = Types.Profesion

export type Estacion = "Yunque" | "MesaAlquimia" | "Telar"

export type DefinicionProfesion = {
	Nombre: string,
	Tipo: "Produccion" | "Recoleccion",
	Descripcion: string,
}

export type Receta = {
	Nombre: string,
	Profesion: Profesion,
	NivelRequerido: number,
	Estacion: Estacion,
	Materiales: { [string]: number },
	Resultado: { ItemId: string, Cantidad: number },
	Tiempo: number, -- segundos
	Xp: number, -- XP de profesión al terminar
}

export type DefinicionNodo = {
	Nombre: string,
	Profesion: Profesion,
	Herramienta: "Pico" | "Hoz",
	NivelRequerido: number,
	ItemId: string,
	CantidadMin: number,
	CantidadMax: number,
	Respawn: number, -- segundos
	Xp: number,
	Color: Color3,
}

local ProfesionesConfig = {
	Profesiones = {
		Herreria = {
			Nombre = "Herrería",
			Tipo = "Produccion",
			Descripcion = "Armas, armaduras, lingotes y herramientas.",
		},
		Alquimia = { Nombre = "Alquimia", Tipo = "Produccion", Descripcion = "Pociones de vida y maná." },
		Sastreria = { Nombre = "Sastrería", Tipo = "Produccion", Descripcion = "Telas, túnicas y capas." },
		Mineria = { Nombre = "Minería", Tipo = "Recoleccion", Descripcion = "Minerales de las vetas (requiere pico)." },
		Herboristeria = {
			Nombre = "Herboristería",
			Tipo = "Recoleccion",
			Descripcion = "Hierbas, flores y lino (requiere hoz).",
		},
	} :: { [string]: DefinicionProfesion },

	NivelMaximo = 50,
	-- XP para pasar del nivel n al n+1: XpBase * n ^ Exponente
	XpBase = 50,
	XpExponente = 1.4,

	DistanciaEstacion = 12, -- studs
	DistanciaNodo = 12,

	-- Calidad Masterpiece: probabilidad base + extra por cada nivel sobre el requerido.
	MasterpieceBase = 0.05,
	MasterpiecePorNivel = 0.01,
	MasterpieceMaximo = 0.25,
	MasterpieceBonus = 1.10, -- +10% de atributos en equipos (en el resto: +1 unidad)

	-- Minijuego de recolección: una barra se llena y hay que acertar la zona verde.
	Minijuego = {
		DuracionBarra = 2.2, -- segundos que tarda en llenarse
		InicioZonaMin = 0.8, -- segundos desde el inicio
		InicioZonaMax = 1.6,
		AnchoZona = 0.35,
		ToleranciaLatencia = 0.15, -- si el cliente no manda su hora
		LatenciaMaxima = 0.6, -- la hora que manda el cliente no puede ser más vieja que esto
	},

	Recetas = {
		FundirPlata = {
			Nombre = "Lingote de Plata",
			Profesion = "Herreria",
			NivelRequerido = 1,
			Estacion = "Yunque",
			Materiales = { MineralPlata = 3 },
			Resultado = { ItemId = "LingotePlata", Cantidad = 1 },
			Tiempo = 3,
			Xp = 15,
		},
		FundirHierro = {
			Nombre = "Lingote de Hierro",
			Profesion = "Herreria",
			NivelRequerido = 1,
			Estacion = "Yunque",
			Materiales = { MineralHierro = 2 },
			Resultado = { ItemId = "Hierro", Cantidad = 1 },
			Tiempo = 2,
			Xp = 10,
		},
		PicoHierro = {
			Nombre = "Pico de Hierro",
			Profesion = "Herreria",
			NivelRequerido = 1,
			Estacion = "Yunque",
			Materiales = { Hierro = 3, Madera = 1 },
			Resultado = { ItemId = "PicoHierro", Cantidad = 1 },
			Tiempo = 4,
			Xp = 20,
		},
		HozHierro = {
			Nombre = "Hoz de Hierro",
			Profesion = "Herreria",
			NivelRequerido = 1,
			Estacion = "Yunque",
			Materiales = { Hierro = 2, Madera = 1 },
			Resultado = { ItemId = "HozHierro", Cantidad = 1 },
			Tiempo = 4,
			Xp = 20,
		},
		EspadaHierro = {
			Nombre = "Espada de Hierro",
			Profesion = "Herreria",
			NivelRequerido = 3,
			Estacion = "Yunque",
			Materiales = { Hierro = 4, Madera = 2 },
			Resultado = { ItemId = "EspadaHierro", Cantidad = 1 },
			Tiempo = 6,
			Xp = 40,
		},
		CascoHierro = {
			Nombre = "Casco de Hierro",
			Profesion = "Herreria",
			NivelRequerido = 4,
			Estacion = "Yunque",
			Materiales = { Hierro = 5 },
			Resultado = { ItemId = "CascoHierro", Cantidad = 1 },
			Tiempo = 6,
			Xp = 45,
		},
		AnilloPlata = {
			Nombre = "Anillo de Plata",
			Profesion = "Herreria",
			NivelRequerido = 6,
			Estacion = "Yunque",
			Materiales = { LingotePlata = 3 },
			Resultado = { ItemId = "AnilloPlata", Cantidad = 1 },
			Tiempo = 8,
			Xp = 70,
		},
		TransmutarPlata = {
			Nombre = "Transmutar hierro en plata",
			Profesion = "Herreria",
			NivelRequerido = 8,
			Estacion = "Yunque",
			Materiales = { Hierro = 5 },
			Resultado = { ItemId = "LingotePlata", Cantidad = 1 },
			Tiempo = 10,
			Xp = 60,
		},
		PocionVida = {
			Nombre = "Poción de Vida",
			Profesion = "Alquimia",
			NivelRequerido = 1,
			Estacion = "MesaAlquimia",
			Materiales = { HierbaSanadora = 2 },
			Resultado = { ItemId = "PocionVida", Cantidad = 2 },
			Tiempo = 3,
			Xp = 12,
		},
		PocionMana = {
			Nombre = "Poción de Maná",
			Profesion = "Alquimia",
			NivelRequerido = 2,
			Estacion = "MesaAlquimia",
			Materiales = { FlorLunar = 2 },
			Resultado = { ItemId = "PocionMana", Cantidad = 2 },
			Tiempo = 3,
			Xp = 15,
		},
		PocionRegeneracion = {
			Nombre = "Poción de Regeneración",
			Profesion = "Alquimia",
			NivelRequerido = 2,
			Estacion = "MesaAlquimia",
			Materiales = { HierbaSanadora = 3 },
			Resultado = { ItemId = "PocionRegeneracion", Cantidad = 2 },
			Tiempo = 4,
			Xp = 16,
		},
		Antidoto = {
			Nombre = "Antídoto",
			Profesion = "Alquimia",
			NivelRequerido = 3,
			Estacion = "MesaAlquimia",
			Materiales = { HierbaSanadora = 2, FlorLunar = 1 },
			Resultado = { ItemId = "Antidoto", Cantidad = 2 },
			Tiempo = 4,
			Xp = 20,
		},
		PocionVitalidad = {
			Nombre = "Poción de Vitalidad",
			Profesion = "Alquimia",
			NivelRequerido = 4,
			Estacion = "MesaAlquimia",
			Materiales = { HierbaSanadora = 4, FlorLunar = 1 },
			Resultado = { ItemId = "PocionVitalidad", Cantidad = 1 },
			Tiempo = 4,
			Xp = 26,
		},
		TonicoEnergia = {
			Nombre = "Tónico de Energía",
			Profesion = "Alquimia",
			NivelRequerido = 3,
			Estacion = "MesaAlquimia",
			Materiales = { FlorLunar = 2, AguaManantial = 1 },
			Resultado = { ItemId = "TonicoEnergia", Cantidad = 2 },
			Tiempo = 4,
			Xp = 20,
		},
		TonicoEnfoque = {
			Nombre = "Tónico de Enfoque",
			Profesion = "Alquimia",
			NivelRequerido = 5,
			Estacion = "MesaAlquimia",
			Materiales = { FlorLunar = 4, AguaManantial = 1 },
			Resultado = { ItemId = "TonicoEnfoque", Cantidad = 1 },
			Tiempo = 4,
			Xp = 32,
		},
		TeManantial = {
			Nombre = "Té de Manantial",
			Profesion = "Alquimia",
			NivelRequerido = 1,
			Estacion = "MesaAlquimia",
			Materiales = { AguaManantial = 2, HierbaSanadora = 1 },
			Resultado = { ItemId = "TeManantial", Cantidad = 2 },
			Tiempo = 4,
			Xp = 10,
		},
		TeRaices = {
			Nombre = "Té de Raíces",
			Profesion = "Alquimia",
			NivelRequerido = 2,
			Estacion = "MesaAlquimia",
			Materiales = { AguaManantial = 2, HierbaSanadora = 3 },
			Resultado = { ItemId = "TeRaices", Cantidad = 2 },
			Tiempo = 4,
			Xp = 16,
		},
		TeJazminLunar = {
			Nombre = "Té de Jazmín Lunar",
			Profesion = "Alquimia",
			NivelRequerido = 4,
			Estacion = "MesaAlquimia",
			Materiales = { AguaManantial = 2, FlorLunar = 3 },
			Resultado = { ItemId = "TeJazminLunar", Cantidad = 2 },
			Tiempo = 4,
			Xp = 26,
		},
		ElixirFuerza = {
			Nombre = "Elixir de Fuerza",
			Profesion = "Alquimia",
			NivelRequerido = 5,
			Estacion = "MesaAlquimia",
			Materiales = { HierbaSanadora = 4, FlorLunar = 2 },
			Resultado = { ItemId = "ElixirFuerza", Cantidad = 1 },
			Tiempo = 6,
			Xp = 36,
		},
		ElixirResistencia = {
			Nombre = "Elixir de Resistencia",
			Profesion = "Alquimia",
			NivelRequerido = 5,
			Estacion = "MesaAlquimia",
			Materiales = { HierbaSanadora = 5, MineralHierro = 2 },
			Resultado = { ItemId = "ElixirResistencia", Cantidad = 1 },
			Tiempo = 6,
			Xp = 36,
		},
		ElixirAgilidad = {
			Nombre = "Elixir de Agilidad",
			Profesion = "Alquimia",
			NivelRequerido = 6,
			Estacion = "MesaAlquimia",
			Materiales = { FlorLunar = 5, Lino = 2 },
			Resultado = { ItemId = "ElixirAgilidad", Cantidad = 1 },
			Tiempo = 6,
			Xp = 40,
		},
		PocionExperimental = {
			Nombre = "Poción Experimental",
			Profesion = "Alquimia",
			NivelRequerido = 6,
			Estacion = "MesaAlquimia",
			Materiales = { HierbaSanadora = 2, FlorLunar = 2, MineralPlata = 1 },
			Resultado = { ItemId = "PocionExperimental", Cantidad = 1 },
			Tiempo = 6,
			Xp = 40,
		},
		MezclaInestable = {
			Nombre = "Mezcla Inestable",
			Profesion = "Alquimia",
			NivelRequerido = 8,
			Estacion = "MesaAlquimia",
			Materiales = { FlorLunar = 4, MineralPlata = 2 },
			Resultado = { ItemId = "MezclaInestable", Cantidad = 1 },
			Tiempo = 6,
			Xp = 52,
		},
		TelaLino = {
			Nombre = "Tela de Lino",
			Profesion = "Sastreria",
			NivelRequerido = 1,
			Estacion = "Telar",
			Materiales = { Lino = 3 },
			Resultado = { ItemId = "TelaLino", Cantidad = 1 },
			Tiempo = 2,
			Xp = 10,
		},
		TunicaLino = {
			Nombre = "Túnica de Lino",
			Profesion = "Sastreria",
			NivelRequerido = 3,
			Estacion = "Telar",
			Materiales = { TelaLino = 4 },
			Resultado = { ItemId = "TunicaLino", Cantidad = 1 },
			Tiempo = 6,
			Xp = 40,
		},
		CapaSeda = {
			Nombre = "Capa de Seda",
			Profesion = "Sastreria",
			NivelRequerido = 5,
			Estacion = "Telar",
			Materiales = { SedaArana = 3, TelaLino = 2 },
			Resultado = { ItemId = "CapaSeda", Cantidad = 1 },
			Tiempo = 8,
			Xp = 70,
		},
	} :: { [string]: Receta },

	Nodos = {
		VetaHierro = {
			Nombre = "Veta de Hierro",
			Profesion = "Mineria",
			Herramienta = "Pico",
			NivelRequerido = 1,
			ItemId = "MineralHierro",
			CantidadMin = 1,
			CantidadMax = 3,
			Respawn = 20,
			Xp = 8,
			Color = Color3.fromRGB(140, 110, 95),
		},
		VetaPlata = {
			Nombre = "Veta de Plata",
			Profesion = "Mineria",
			Herramienta = "Pico",
			NivelRequerido = 3,
			ItemId = "MineralPlata",
			CantidadMin = 1,
			CantidadMax = 2,
			Respawn = 40,
			Xp = 15,
			Color = Color3.fromRGB(200, 205, 215),
		},
		HierbaSanadora = {
			Nombre = "Hierba Sanadora",
			Profesion = "Herboristeria",
			Herramienta = "Hoz",
			NivelRequerido = 1,
			ItemId = "HierbaSanadora",
			CantidadMin = 1,
			CantidadMax = 3,
			Respawn = 20,
			Xp = 8,
			Color = Color3.fromRGB(90, 200, 90),
		},
		FlorLunar = {
			Nombre = "Flor Lunar",
			Profesion = "Herboristeria",
			Herramienta = "Hoz",
			NivelRequerido = 2,
			ItemId = "FlorLunar",
			CantidadMin = 1,
			CantidadMax = 2,
			Respawn = 30,
			Xp = 12,
			Color = Color3.fromRGB(150, 160, 255),
		},
		Lino = {
			Nombre = "Planta de Lino",
			Profesion = "Herboristeria",
			Herramienta = "Hoz",
			NivelRequerido = 1,
			ItemId = "Lino",
			CantidadMin = 2,
			CantidadMax = 4,
			Respawn = 15,
			Xp = 6,
			Color = Color3.fromRGB(220, 210, 150),
		},
	} :: { [string]: DefinicionNodo },

	-- Herramientas que recibe cada jugador nuevo (una sola vez).
	KitInicial = { "PicoHierro", "HozHierro" },
}

return ProfesionesConfig
