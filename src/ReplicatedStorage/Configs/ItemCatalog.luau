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
	-- Consumibles con efecto propio (ver ConsumiblesConfig)
	PocionRegeneracion = {
		Nombre = "Poción de Regeneración",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 8,
		Descripcion = "Cura 4% de la vida cada 2 s durante 20 s.",
	},
	PocionVitalidad = {
		Nombre = "Poción de Vitalidad",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 10,
		Descripcion = "Escudo que absorbe daño por 20% de tu vida máxima durante 60 s.",
	},
	Antidoto = {
		Nombre = "Antídoto",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 8,
		Descripcion = "Quita debilitamientos, sangrados y quemaduras.",
	},
	TonicoEnergia = {
		Nombre = "Tónico de Energía",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 9,
		Descripcion = "Tónico: recupera 3% del maná o stamina cada 5 s durante 5 min.",
	},
	TonicoEnfoque = {
		Nombre = "Tónico de Enfoque",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 12,
		Descripcion = "Tónico: -10% a las recargas de habilidades durante 2 min.",
	},
	ElixirFuerza = {
		Nombre = "Elixir de Fuerza",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 18,
		Descripcion = "Elixir: +15% de ataque durante 10 min.",
	},
	ElixirAgilidad = {
		Nombre = "Elixir de Agilidad",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 18,
		Descripcion = "Elixir: -10% a las recargas de habilidades durante 10 min.",
	},
	ElixirResistencia = {
		Nombre = "Elixir de Resistencia",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 18,
		Descripcion = "Elixir: +15% de defensa durante 10 min.",
	},
	MezclaInestable = {
		Nombre = "Mezcla Inestable",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 22,
		Descripcion = "Elixir: +30% de ataque y -20% de defensa durante 5 min.",
	},
	PocionExperimental = {
		Nombre = "Poción Experimental",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 15,
		Descripcion = "Elixir de 5 min. 65%: +25% de ataque y poder. 35%: -15% de defensa.",
	},
	TeManantial = {
		Nombre = "Té de Manantial",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 7,
		Descripcion = "Infusión: recupera 2% del maná o stamina cada 5 s durante 15 min.",
	},
	TeRaices = {
		Nombre = "Té de Raíces",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 7,
		Descripcion = "Infusión: +10% de defensa durante 15 min.",
	},
	TeJazminLunar = {
		Nombre = "Té de Jazmín Lunar",
		Tipo = "Consumible",
		Apilable = true,
		MaxStack = 20,
		PrecioVenta = 9,
		Descripcion = "Infusión: -6% a las recargas de habilidades durante 15 min.",
	},
	AguaManantial = { Nombre = "Agua de Manantial", Tipo = "Material", Apilable = true, PrecioVenta = 1 },
	-- Esencias (Desencantador): se usan para reforjar y engarzar
	PolvoEncantamiento = { Nombre = "Polvo de Encantamiento", Tipo = "Material", Apilable = true, PrecioVenta = 8 },
	EsenciaMagica = { Nombre = "Esencia Mágica", Tipo = "Material", Apilable = true, PrecioVenta = 25 },
	EsenciaMayor = { Nombre = "Esencia Mayor", Tipo = "Material", Apilable = true, PrecioVenta = 80 },
	FragmentoReliquia = { Nombre = "Fragmento de Reliquia", Tipo = "Material", Apilable = true, PrecioVenta = 250 },
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
	-- Materiales del Spoil del Chatarrero
	Chatarra = {
		Nombre = "Chatarra",
		Tipo = "Material",
		Apilable = true,
		PrecioVenta = 2,
		Descripcion = "Restos de metal. Sale del Spoil y de desmantelar equipo.",
	},
	Engranaje = {
		Nombre = "Engranaje",
		Tipo = "Material",
		Apilable = true,
		PrecioVenta = 15,
		Descripcion = "Pieza mecánica rara que el Chatarrero saca de los restos.",
	},
	NucleoTitan = {
		Nombre = "Núcleo de Titán",
		Tipo = "Material",
		Apilable = true,
		PrecioVenta = 400,
		Descripcion = "Componente legendario. Solo sale con Extracción Quirúrgica de un jefe.",
	},
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
