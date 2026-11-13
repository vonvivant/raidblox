--!strict
-- MonetizacionConfig: pases (Game Passes) y monturas.
--
-- Id = 0: el pase todavía no está creado en el Creator Hub. No se puede
-- comprar, pero en modo pruebas el creador y los probadores lo pueden
-- "simular" desde la tienda para probarlo. Al crear el pase (Creator Hub >
-- tu experiencia > Monetización > Pases), pegá su Id acá.

export type Pase = { Id: number, Nombre: string, Descripcion: string, Orden: number }
export type Producto = {
	Id: number, -- Developer Product (0 = todavía no creado)
	Nombre: string,
	Descripcion: string,
	Orden: number,
	Tipo: "Booster" | "Pack" | "Ficha" | "Caja",
	Ficha: string?, -- Tipo "Ficha": "Reroll" o "Bando"
	Caja: string?, -- Tipo "Caja": clave en Cajas
	UnaVez: boolean?,
}
export type EntradaCaja = { ItemId: string, Peso: number, Min: number, Max: number }
export type Caja = {
	Nombre: string,
	Tiradas: number, -- cuántos ítems salen por caja
	Contenido: { EntradaCaja },
	Rarezas: { [string]: number }?, -- solo equipo: pesos de rareza de esta caja
}
export type Montura = {
	Nombre: string,
	Velocidad: number, -- WalkSpeed montado (a pie es 16)
	Pase: string?, -- pase necesario (nil = gratis)
	NivelMinimo: number,
	Color: Color3,
	Fuego: boolean?,
}

local MonetizacionConfig = {
	Pases = {
		VIP = {
			Id = 0,
			Nombre = "VIP",
			Descripcion = "+15% de experiencia y de oro, y etiqueta [VIP] dorada en el chat y sobre tu cabeza.",
			Orden = 1,
		},
		MochilaExtra = {
			Id = 0,
			Nombre = "Mochila Extra",
			Descripcion = "Tu mochila pasa de 30 a 50 lugares, para siempre.",
			Orden = 2,
		},
		SubastaExtra = {
			Id = 0,
			Nombre = "Puesto en la Subasta",
			Descripcion = "Hasta 15 publicaciones a la vez en la Casa de Subastas (en vez de 5).",
			Orden = 3,
		},
		MonturaDragon = {
			Id = 0,
			Nombre = "Dragón de Fuego",
			Descripcion = "Montura exclusiva envuelta en llamas, 15% más rápida que el caballo.",
			Orden = 4,
		},
		TituloPersonal = {
			Id = 0,
			Nombre = "Título Personalizado",
			Descripcion = "Escribí tu propio título y mostralo sobre tu cabeza.",
			Orden = 5,
		},
	} :: { [string]: Pase },

	Vip = { MultXp = 1.15, MultOro = 1.15, Color = Color3.fromRGB(255, 213, 74) },
	PublicacionesConPase = 15,
	LargoTitulo = 24,

	Monturas = {
		Caballo = {
			Nombre = "Caballo",
			Velocidad = 24,
			NivelMinimo = 1,
			Color = Color3.fromRGB(120, 80, 45),
		},
		Dragon = {
			Nombre = "Dragón de Fuego",
			Velocidad = 27.6, -- +15% sobre el caballo
			Pase = "MonturaDragon",
			NivelMinimo = 1,
			Color = Color3.fromRGB(140, 30, 25),
			Fuego = true,
		},
	} :: { [string]: Montura },
	SegundosSinCombateParaMontar = 5,

	-- Fase 6.2: Developer Products (compras repetibles). Id = 0: igual que los
	-- pases, no se venden todavía pero se pueden simular en modo pruebas.
	Productos = {
		BoosterXp = {
			Id = 0,
			Nombre = "Booster de Experiencia",
			Descripcion = "2× experiencia durante 1 hora. Si ya tenés uno, se suma otra hora.",
			Orden = 1,
			Tipo = "Booster",
		},
		PackInicio = {
			Id = 0,
			Nombre = "Pack de Inicio",
			Descripcion = "1.000 de oro, una Espada de Hierro Rara y 3 pociones de vida y de maná. Una sola vez por cuenta.",
			Orden = 2,
			Tipo = "Pack",
			UnaVez = true,
		},
		FichaReroll = {
			Id = 0,
			Nombre = "Ficha de Re-roll",
			Descripcion = "Vuelve a tirar la calidad y los efectos de un equipo de tu mochila (dentro del rango de su rareza).",
			Orden = 3,
			Tipo = "Ficha",
			Ficha = "Reroll",
		},
		FichaBando = {
			Id = 0,
			Nombre = "Ficha de Cambio de Bando",
			Descripcion = "Cambiá a Rojo, Azul o Violeta cuando quieras, sin pagar oro.",
			Orden = 4,
			Tipo = "Ficha",
			Ficha = "Bando",
		},
		CajaMateriales = {
			Id = 0,
			Nombre = "Caja de Materiales",
			Descripcion = "5 materiales al azar.",
			Orden = 10,
			Tipo = "Caja",
			Caja = "Materiales",
		},
		CajaArmadura = {
			Id = 0,
			Nombre = "Caja de Armadura",
			Descripcion = "1 pieza de armadura de rareza al azar.",
			Orden = 11,
			Tipo = "Caja",
			Caja = "Armadura",
		},
		CajaConsumibles = {
			Id = 0,
			Nombre = "Caja de Consumibles",
			Descripcion = "3 pociones al azar.",
			Orden = 12,
			Tipo = "Caja",
			Caja = "Consumibles",
		},
		CajaMagica = {
			Id = 0,
			Nombre = "Caja Mágica",
			Descripcion = "1 objeto mágico, mínimo Raro.",
			Orden = 13,
			Tipo = "Caja",
			Caja = "Magica",
		},
		CajaGemas = {
			Id = 0,
			Nombre = "Caja de Gemas",
			Descripcion = "2 gemas al azar.",
			Orden = 14,
			Tipo = "Caja",
			Caja = "Gemas",
		},
	} :: { [string]: Producto },

	-- Contenido de las cajas. Las probabilidades se calculan de los pesos y se
	-- MUESTRAN en la tienda antes de comprar (regla de Roblox para ítems
	-- aleatorios pagos). En países donde están restringidas, no se venden.
	Cajas = {
		Materiales = {
			Nombre = "Caja de Materiales",
			Tiradas = 5,
			Contenido = {
				{ ItemId = "Madera", Peso = 25, Min = 3, Max = 6 },
				{ ItemId = "Piedra", Peso = 25, Min = 3, Max = 6 },
				{ ItemId = "MineralHierro", Peso = 18, Min = 2, Max = 4 },
				{ ItemId = "Hierro", Peso = 12, Min = 1, Max = 3 },
				{ ItemId = "MineralPlata", Peso = 10, Min = 1, Max = 3 },
				{ ItemId = "LingotePlata", Peso = 6, Min = 1, Max = 2 },
				{ ItemId = "SedaArana", Peso = 3, Min = 1, Max = 1 },
				{ ItemId = "NucleoObsidiana", Peso = 1, Min = 1, Max = 1 },
			},
		},
		Armadura = {
			Nombre = "Caja de Armadura",
			Tiradas = 1,
			Contenido = {
				{ ItemId = "CascoCuero", Peso = 30, Min = 1, Max = 1 },
				{ ItemId = "PecheraCuero", Peso = 30, Min = 1, Max = 1 },
				{ ItemId = "CascoHierro", Peso = 20, Min = 1, Max = 1 },
				{ ItemId = "TunicaLino", Peso = 20, Min = 1, Max = 1 },
			},
			Rarezas = { Comun = 50, Raro = 33, Epico = 13, Mistico = 4 },
		},
		Consumibles = {
			Nombre = "Caja de Consumibles",
			Tiradas = 3,
			Contenido = {
				{ ItemId = "PocionVida", Peso = 55, Min = 1, Max = 3 },
				{ ItemId = "PocionMana", Peso = 45, Min = 1, Max = 3 },
			},
		},
		Magica = {
			Nombre = "Caja Mágica",
			Tiradas = 1,
			Contenido = {
				{ ItemId = "AnilloCobre", Peso = 35, Min = 1, Max = 1 },
				{ ItemId = "AnilloPlata", Peso = 25, Min = 1, Max = 1 },
				{ ItemId = "BaculoRoble", Peso = 25, Min = 1, Max = 1 },
				{ ItemId = "CapaSeda", Peso = 15, Min = 1, Max = 1 },
			},
			Rarezas = { Raro = 60, Epico = 30, Mistico = 10 },
		},
		Gemas = {
			Nombre = "Caja de Gemas",
			Tiradas = 2,
			Contenido = {
				{ ItemId = "Amatista", Peso = 35, Min = 1, Max = 2 },
				{ ItemId = "Esmeralda", Peso = 25, Min = 1, Max = 2 },
				{ ItemId = "Zafiro", Peso = 20, Min = 1, Max = 1 },
				{ ItemId = "Rubi", Peso = 15, Min = 1, Max = 1 },
				{ ItemId = "Diamante", Peso = 5, Min = 1, Max = 1 },
			},
		},
	} :: { [string]: Caja },

	Booster = { Multiplicador = 2, Segundos = 3600 },
	PackInicio = {
		Oro = 1000,
		Items = {
			{ ItemId = "EspadaHierro", Cantidad = 1, Rareza = "Raro" },
			{ ItemId = "PocionVida", Cantidad = 3 },
			{ ItemId = "PocionMana", Cantidad = 3 },
		} :: { { ItemId: string, Cantidad: number, Rareza: string? } },
	},
	-- Re-roll: la calidad (Meta.Mult) cae entre estos factores del multiplicador
	-- de su rareza, y cada efecto secundario vuelve a tirarse en su rango.
	Reroll = { MinFactor = 0.9, MaxFactor = 1.1 },
}

return MonetizacionConfig
