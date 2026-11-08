--!strict
-- ItemCatalog: definición de cada ítem del juego. El servidor siempre busca
-- precios, stacks y slots acá; nunca confía en lo que mande el cliente.
-- Este catálogo es mínimo: se amplía en la Fase 3 (rarezas) y Fase 4 (crafteo).

local Types = require(script.Parent.Parent.Shared.Types)

export type TipoItem = "Material" | "Consumible" | "Equipo" | "Cosmetico"

export type DefinicionItem = {
	Nombre: string,
	Tipo: TipoItem,
	Apilable: boolean,
	MaxStack: number?, -- solo apilables; por defecto GameConfig.Inventario.MaxStackPorDefecto
	SlotEquipo: Types.SlotEquipo?, -- solo equipos
	PrecioVenta: number, -- oro que paga un NPC
	Atributos: { Fuerza: number?, Agilidad: number?, Inteligencia: number? }?,
	SoloRaidBlox: boolean?, -- ítems Únicos: solo caen de jefes RaidBlox
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
	},
	EspadaHierro = {
		Nombre = "Espada de Hierro",
		Tipo = "Equipo",
		Apilable = false,
		SlotEquipo = "ArmaPrincipal",
		PrecioVenta = 25,
		Atributos = { Fuerza = 4 },
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
