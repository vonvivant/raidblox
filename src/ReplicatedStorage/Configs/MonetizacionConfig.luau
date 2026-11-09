--!strict
-- MonetizacionConfig: pases (Game Passes) y monturas.
--
-- Id = 0: el pase todavía no está creado en el Creator Hub. No se puede
-- comprar, pero en modo pruebas el creador y los probadores lo pueden
-- "simular" desde la tienda para probarlo. Al crear el pase (Creator Hub >
-- tu experiencia > Monetización > Pases), pegá su Id acá.

export type Pase = { Id: number, Nombre: string, Descripcion: string, Orden: number }
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
}

return MonetizacionConfig
