--!strict
-- MascotasConfig: mascotas coleccionistas (Fase 6.3).
--
-- Una mascota equipada flota al lado del jugador y le junta sola el botín que
-- cae a menos de RadioRecogida studs (la bolsa sigue siendo personal: solo
-- junta la del dueño). Son puramente de comodidad: no pelean ni dan stats.
-- Se ganan en el pase de batalla; se pueden sumar más acá y darlas con
-- { Tipo = "Mascota", Id = "<Clave>" }.

export type Mascota = {
	Nombre: string,
	Descripcion: string,
	Color: Color3,
	Material: Enum.Material,
	Tam: number,
	Efecto: ("Fuego" | "Chispas")?,
	Luz: Color3?,
	-- Mascotas del Vendedor de Mascotas (NPC-032): se compran con oro. Las que
	-- no tienen precio se consiguen en el pase de batalla.
	Precio: number?,
}

return {
	RadioRecogida = 25,
	IntervaloRecogida = 1, -- segundos entre barridas
	Desplazamiento = Vector3.new(2.5, 2.2, 1.5), -- dónde flota respecto del jugador

	Mascotas = {
		Lumi = {
			Nombre = "Lumi",
			Descripcion = "Un espíritu de luz que ilumina el camino.",
			Color = Color3.fromRGB(150, 220, 255),
			Material = Enum.Material.Neon,
			Tam = 0.9,
			Efecto = "Chispas",
			Luz = Color3.fromRGB(150, 220, 255),
		},
		Brasa = {
			Nombre = "Brasa",
			Descripcion = "Una chispa de fuego juguetona.",
			Color = Color3.fromRGB(255, 120, 40),
			Material = Enum.Material.Neon,
			Tam = 1,
			Efecto = "Fuego",
			Luz = Color3.fromRGB(255, 140, 60),
		},
		Hojita = {
			Nombre = "Hojita",
			Descripcion = "Un brote travieso que sigue a los herboristas.",
			Color = Color3.fromRGB(120, 200, 110),
			Material = Enum.Material.Grass,
			Tam = 0.9,
			Precio = 2500,
		},
		Piedrin = {
			Nombre = "Piedrín",
			Descripcion = "Un pedacito de montaña con ganas de pasear.",
			Color = Color3.fromRGB(140, 140, 150),
			Material = Enum.Material.Slate,
			Tam = 1.1,
			Precio = 4000,
		},
		Lucero = {
			Nombre = "Lucero",
			Descripcion = "Una estrella caída que todavía brilla.",
			Color = Color3.fromRGB(255, 240, 180),
			Material = Enum.Material.Neon,
			Tam = 0.8,
			Efecto = "Chispas",
			Luz = Color3.fromRGB(255, 240, 180),
			Precio = 9000,
		},
	} :: { [string]: Mascota },
}
