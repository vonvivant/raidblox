--!strict
-- ItemCatalog: definición de cada ítem del juego. El servidor siempre busca
-- precios, stacks y slots acá; nunca confía en lo que mande el cliente.
-- Este catálogo es mínimo: se amplía en la Fase 3 (rarezas) y Fase 4 (crafteo).

local Types = require(script.Parent.Parent.Shared.Types)

export type TipoItem = "Material" | "Consumible" | "Equipo" | "Herramienta" | "Cosmetico"

export type TipoHerramienta = "Pico" | "Hoz"

export type DefinicionItem = {
	Nombre: string,
	Tipo: TipoItem,
	Apilable: boolean,
	MaxStack: number?, -- solo apilables; por defecto GameConfig.Inventario.MaxStackPorDefecto
	SlotEquipo: Types.SlotEquipo?, -- solo equipos
	PrecioVenta: number, -- oro que paga un NPC
	Atributos: { Fuerza: number?, Agilidad: number?, Inteligencia: number? }?,
	SoloRaidBlox: boolean?, -- ítems Únicos: solo caen de jefes RaidBlox
	Herramienta: TipoHerramienta?, -- solo Tipo "Herramienta" (se equipa en el slot Herramienta)
	Consumo: { Recurso: "Vida" | "Mana", Porcentaje: number }?, -- solo consumibles
	Descripcion: string?,
}

local ItemCatalog: { [string]: DefinicionItem } = {
	Madera = { Nombre = "Madera", Tipo = "Material", Apilable = true, PrecioVenta = 1 },
	Piedra = { Nombre = "Piedra", Tipo = "Material", Apilable = true, PrecioVenta = 1 },
	Hierro = { Nombre = "Lingote de Hierro", Tipo = "Material", Apilable = true, PrecioVenta = 4 },
	PocionVida = {
		Nombre = "Poción de Vida",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 5,
		Consumo = { Recurso = "Vida", Porcentaje = 35 },
		Descripcion = "Recupera 35% de la vida.",
	},
	PocionMana = {
		Nombre = "Poción de Maná",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 5,
		Consumo = { Recurso = "Mana", Porcentaje = 35 },
		Descripcion = "Recupera 35% del maná.",
	},
	-- Recolección
	MineralHierro = { Nombre = "Mineral de Hierro", Tipo = "Material", Apilable = true, PrecioVenta = 2 },
	MineralPlata = { Nombre = "Mineral de Plata", Tipo = "Material", Apilable = true, PrecioVenta = 6 },
	HierbaSanadora = { Nombre = "Hierba Sanadora", Tipo = "Material", Apilable = true, PrecioVenta = 2 },
	FlorLunar = { Nombre = "Flor Lunar", Tipo = "Material", Apilable = true, PrecioVenta = 3 },
	Lino = { Nombre = "Lino", Tipo = "Material", Apilable = true, PrecioVenta = 1 },
	-- Producción
	LingotePlata = { Nombre = "Lingote de Plata", Tipo = "Material", Apilable = true, PrecioVenta = 15 },
	TelaLino = { Nombre = "Tela de Lino", Tipo = "Material", Apilable = true, PrecioVenta = 4 },
	-- Herramientas
	PicoHierro = {
		Nombre = "Pico de Hierro",
		Tipo = "Herramienta",
		Apilable = false,
		SlotEquipo = "Herramienta",
		Herramienta = "Pico",
		PrecioVenta = 8,
		Descripcion = "Equipalo para minar vetas.",
	},
	HozHierro = {
		Nombre = "Hoz de Hierro",
		Tipo = "Herramienta",
		Apilable = false,
		SlotEquipo = "Herramienta",
		Herramienta = "Hoz",
		PrecioVenta = 8,
		Descripcion = "Equipala para recolectar hierbas y lino.",
	},
	-- Equipos fabricables
	CascoHierro = {
		Nombre = "Casco de Hierro",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "Casco",
		PrecioVenta = 20,
		Atributos = { Fuerza = 3, Agilidad = 1 },
	},
	TunicaLino = {
		Nombre = "Túnica de Lino",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "Pechera",
		PrecioVenta = 18,
		Atributos = { Inteligencia = 4 },
	},
	CapaSeda = {
		Nombre = "Capa de Seda",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "Accesorio1",
		PrecioVenta = 60,
		Atributos = { Agilidad = 3, Inteligencia = 3 },
	},
	AnilloPlata = {
		Nombre = "Anillo de Plata",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "Accesorio1",
		PrecioVenta = 45,
		Atributos = { Fuerza = 2, Inteligencia = 3 },
	},
	EspadaHierro = {
		Nombre = "Espada de Hierro",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "ArmaPrincipal",
		PrecioVenta = 25,
		Atributos = { Fuerza = 4 },
	},
	-- Gemas (por ahora salen de cajas; más adelante se engarzan en el equipo)
	Amatista = { Nombre = "Amatista", Tipo = "Material", Apilable = true, PrecioVenta = 20 },
	Esmeralda = { Nombre = "Esmeralda", Tipo = "Material", Apilable = true, PrecioVenta = 30 },
	Zafiro = { Nombre = "Zafiro", Tipo = "Material", Apilable = true, PrecioVenta = 35 },
	Rubi = { Nombre = "Rubí", Tipo = "Material", Apilable = true, PrecioVenta = 40 },
	Diamante = { Nombre = "Diamante", Tipo = "Material", Apilable = true, PrecioVenta = 100 },
	NucleoObsidiana = { Nombre = "Núcleo de Obsidiana", Tipo = "Material", Apilable = true, PrecioVenta = 30 },
	SedaArana = { Nombre = "Seda de Araña", Tipo = "Material", Apilable = true, PrecioVenta = 20 },
	PecheraCuero = {
		Nombre = "Pechera de Cuero",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "Pechera",
		PrecioVenta = 15,
		Atributos = { Fuerza = 2, Agilidad = 2 },
	},
	BaculoRoble = {
		Nombre = "Báculo de Roble",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "ArmaPrincipal",
		PrecioVenta = 25,
		Atributos = { Inteligencia = 5 },
	},
	AnilloCobre = {
		Nombre = "Anillo de Cobre",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "Accesorio1",
		PrecioVenta = 20,
		Atributos = { Agilidad = 2, Inteligencia = 2 },
	},
	CoronaObsidiana = {
		Nombre = "Corona de Obsidiana",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "Casco",
		PrecioVenta = 500,
		Atributos = { Fuerza = 6, Agilidad = 3, Inteligencia = 6 },
		SoloRaidBlox = true,
	},
	ColmilloReina = {
		Nombre = "Colmillo de la Reina",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "ArmaPrincipal",
		PrecioVenta = 600,
		Atributos = { Fuerza = 8, Agilidad = 6 },
		SoloRaidBlox = true,
	},
	CascoCuero = {
		Nombre = "Casco de Cuero",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "Casco",
		PrecioVenta = 10,
		Atributos = { Agilidad = 1 },
	},
}

return ItemCatalog
