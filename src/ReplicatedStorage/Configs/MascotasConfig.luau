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
	} :: { [string]: Mascota },
}
