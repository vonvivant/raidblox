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
}

return AparienciaConfig
