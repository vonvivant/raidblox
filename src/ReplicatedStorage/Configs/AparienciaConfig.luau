--!strict
-- AparienciaConfig: cómo se ve cada opción de género.
--
-- "Escalas" son propiedades de HumanoidDescription (proporciones del cuerpo).
-- "Partes" son ids de partes del cuerpo del Catálogo de Roblox (0 = no cambiar):
-- si querés un cuerpo o cabeza específicos para cada género, poné acá el id del
-- ítem del Catálogo (Torso, LeftArm, RightArm, LeftLeg, RightLeg, Head).

export type DefGenero = {
	Nombre: string,
	Escalas: { [string]: number },
	Partes: { [string]: number },
}

-- Opciones del Barbero (NPC-029). `AssetId = 0` significa "falta subir el
-- modelo": esa opción no se muestra hasta que tenga un id del Catálogo.
export type Estilo = { Nombre: string, AssetId: number }
export type Piel = { Nombre: string, Color: Color3 }

local AparienciaConfig = {
	Generos = {
		Masculino = {
			Nombre = "Masculino",
			Escalas = { BodyTypeScale = 0.3, ProportionScale = 0, WidthScale = 1, HeightScale = 1 },
			Partes = { Torso = 0, LeftArm = 0, RightArm = 0, LeftLeg = 0, RightLeg = 0, Head = 0 },
		},
		Femenino = {
			Nombre = "Femenino",
			Escalas = { BodyTypeScale = 0.3, ProportionScale = 1, WidthScale = 0.85, HeightScale = 0.97 },
			Partes = { Torso = 0, LeftArm = 0, RightArm = 0, LeftLeg = 0, RightLeg = 0, Head = 0 },
		},
	} :: { [string]: DefGenero },

	-- Barbero: cambiar de estilo cuesta `Costo` de oro (cada cambio).
	Barbero = {
		Costo = 100,
		-- Colores de piel. Funcionan hoy: se aplican al cuerpo del personaje.
		Pieles = {
			Avatar = { Nombre = "El de mi avatar", Color = Color3.fromRGB(234, 184, 146) },
			Clara = { Nombre = "Clara", Color = Color3.fromRGB(245, 215, 185) },
			Dorada = { Nombre = "Dorada", Color = Color3.fromRGB(226, 185, 130) },
			Oliva = { Nombre = "Oliva", Color = Color3.fromRGB(198, 155, 109) },
			Canela = { Nombre = "Canela", Color = Color3.fromRGB(165, 115, 75) },
			Oscura = { Nombre = "Oscura", Color = Color3.fromRGB(110, 72, 48) },
			Ebano = { Nombre = "Ébano", Color = Color3.fromRGB(74, 48, 33) },
			Ceniza = { Nombre = "Ceniza (élfica)", Color = Color3.fromRGB(190, 190, 205) },
			Verdosa = { Nombre = "Verdosa (orca)", Color = Color3.fromRGB(130, 165, 115) },
		} :: { [string]: Piel },
		-- Peinados y marcas faciales: accesorios del Catálogo de Roblox. Hay que
		-- subirlos y poner su id acá (mientras sean 0, no aparecen en la lista).
		Peinados = {
			Corto = { Nombre = "Corto", AssetId = 0 },
			Largo = { Nombre = "Largo", AssetId = 0 },
			Trenza = { Nombre = "Trenza", AssetId = 0 },
			Rapado = { Nombre = "Rapado", AssetId = 0 },
		} :: { [string]: Estilo },
		Marcas = {
			CicatrizOjo = { Nombre = "Cicatriz en el ojo", AssetId = 0 },
			PinturaGuerra = { Nombre = "Pintura de guerra", AssetId = 0 },
			TatuajeRunico = { Nombre = "Tatuaje rúnico", AssetId = 0 },
		} :: { [string]: Estilo },
	},
}

return AparienciaConfig
