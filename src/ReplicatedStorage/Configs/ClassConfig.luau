--!strict
-- ClassConfig: las 8 clases jugables, sus estadísticas por nivel y sus 4 habilidades.
-- El servidor calcula todo a partir de esta tabla; el cliente la lee solo para
-- mostrar nombres, costos y tiempos de recarga.
--
-- Fórmulas (ver Estadisticas y CombatManager):
--   stat(nivel)     = Base + PorNivel * (nivel - 1)
--   daño            = (Base + Escala * Factor) * multiplicadores
--   mitigación      = Defensa / (Defensa + 100)
--   crítico         = x1.5 (el Asesino por la espalda: crítico seguro x2.25)

export type Stat = "Ataque" | "Poder" | "Defensa"

export type Efecto =
	{ Tipo: "Danio", Escuela: "Fisico" | "Magico", Base: number, Escala: Stat, Factor: number }
	| { Tipo: "Cura", Base: number, Factor: number }
	| { Tipo: "CuraTiempo", Base: number, Factor: number, Duracion: number, Intervalo: number }
	| {
		Tipo: "DanioTiempo",
		Escuela: "Fisico" | "Magico",
		Base: number,
		Escala: Stat,
		Factor: number,
		Duracion: number,
		Intervalo: number,
	}
	| { Tipo: "Aturdir", Duracion: number }
	| { Tipo: "Provocar", Duracion: number }
	| { Tipo: "Aura", Stat: Stat, Porcentaje: number, Duracion: number }
	| { Tipo: "Invisible", Duracion: number }

-- A quién afecta la habilidad:
--   Enemigo / Aliado: un objetivo seleccionado (Aliado acepta al propio jugador).
--   Propio: solo quien la lanza.
--   AreaEnemigos / AreaAliados: todos en `Radio` alrededor de `Centro`.
export type TipoObjetivo = "Enemigo" | "Aliado" | "Propio" | "AreaEnemigos" | "AreaAliados"

export type Habilidad = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	CostoMana: number,
	Cooldown: number, -- segundos
	Rango: number, -- studs hasta el objetivo (o hasta el centro del área)
	TiempoCasteo: number, -- 0 = instantánea
	Objetivo: TipoObjetivo,
	Centro: ("Objetivo" | "Propio")?, -- solo áreas
	Radio: number?, -- solo áreas y auras
	Efectos: { Efecto },
}

export type EstadisticasBase = {
	Vida: number,
	Mana: number,
	RegenMana: number, -- por segundo
	Ataque: number,
	Poder: number,
	Defensa: number,
	Critico: number, -- probabilidad 0..1
}

export type DefinicionClase = {
	Nombre: string,
	Rol: string,
	Descripcion: string,
	Base: EstadisticasBase,
	PorNivel: EstadisticasBase,
	MultiplicadorAmenaza: number, -- el Tanque genera 3x
	MultiplicadorEspalda: number?, -- el Asesino: crítico seguro y extra por la espalda
	Habilidades: { Habilidad },
}

local function stats(
	vida: number,
	mana: number,
	regen: number,
	ataque: number,
	poder: number,
	defensa: number,
	critico: number
): EstadisticasBase
	return {
		Vida = vida,
		Mana = mana,
		RegenMana = regen,
		Ataque = ataque,
		Poder = poder,
		Defensa = defensa,
		Critico = critico,
	}
end

local Clases: { [string]: DefinicionClase } = {
	Tanque = {
		Nombre = "Tanque",
		Rol = "Defensor",
		Descripcion = "Aguanta golpes y obliga a los enemigos a atacarlo.",
		Base = stats(160, 60, 2, 10, 4, 20, 0.05),
		PorNivel = stats(18, 4, 0.1, 1.5, 0.5, 2.5, 0),
		MultiplicadorAmenaza = 3,
		Habilidades = {
			{
				Id = "GolpeDefensivo",
				Nombre = "Golpe Defensivo",
				Descripcion = "Golpe básico con el escudo.",
				CostoMana = 0,
				Cooldown = 1.5,
				Rango = 8,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 8, Escala = "Ataque", Factor = 0.8 } },
			},
			{
				Id = "Provocacion",
				Nombre = "Provocación",
				Descripcion = "Obliga al enemigo a atacarte durante 4 s.",
				CostoMana = 10,
				Cooldown = 10,
				Rango = 25,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = {
					{ Tipo = "Provocar", Duracion = 4 },
					{ Tipo = "Danio", Escuela = "Fisico", Base = 4, Escala = "Ataque", Factor = 0.3 },
				},
			},
			{
				Id = "Terremoto",
				Nombre = "Terremoto",
				Descripcion = "Golpea el suelo: daña y aturde a los enemigos cercanos.",
				CostoMana = 20,
				Cooldown = 12,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "AreaEnemigos",
				Centro = "Propio",
				Radio = 12,
				Efectos = {
					{ Tipo = "Danio", Escuela = "Fisico", Base = 10, Escala = "Ataque", Factor = 0.6 },
					{ Tipo = "Aturdir", Duracion = 1.5 },
				},
			},
			{
				Id = "Muralla",
				Nombre = "Muralla",
				Descripcion = "+40% de defensa durante 6 s.",
				CostoMana = 15,
				Cooldown = 20,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "Propio",
				Efectos = { { Tipo = "Aura", Stat = "Defensa", Porcentaje = 40, Duracion = 6 } },
			},
		},
	},

	Guerrero = {
		Nombre = "Guerrero",
		Rol = "Daño cuerpo a cuerpo",
		Descripcion = "Golpes poderosos de cerca y gritos que animan al grupo.",
		Base = stats(130, 50, 2, 16, 3, 12, 0.1),
		PorNivel = stats(14, 3, 0.1, 2.5, 0.3, 1.5, 0),
		MultiplicadorAmenaza = 1,
		Habilidades = {
			{
				Id = "Tajo",
				Nombre = "Tajo",
				Descripcion = "Ataque básico con el arma.",
				CostoMana = 0,
				Cooldown = 1.5,
				Rango = 8,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 12, Escala = "Ataque", Factor = 1.0 } },
			},
			{
				Id = "GolpeBrutal",
				Nombre = "Golpe Brutal",
				Descripcion = "Un golpe que hace mucho daño.",
				CostoMana = 15,
				Cooldown = 6,
				Rango = 8,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 25, Escala = "Ataque", Factor = 1.6 } },
			},
			{
				Id = "Torbellino",
				Nombre = "Torbellino",
				Descripcion = "Gira y golpea a todos los enemigos cercanos.",
				CostoMana = 20,
				Cooldown = 10,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "AreaEnemigos",
				Centro = "Propio",
				Radio = 10,
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 15, Escala = "Ataque", Factor = 0.9 } },
			},
			{
				Id = "GritoGuerra",
				Nombre = "Grito de Guerra",
				Descripcion = "+25% de ataque para vos y tus aliados cercanos durante 8 s.",
				CostoMana = 20,
				Cooldown = 25,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "AreaAliados",
				Centro = "Propio",
				Radio = 20,
				Efectos = { { Tipo = "Aura", Stat = "Ataque", Porcentaje = 25, Duracion = 8 } },
			},
		},
	},

	Mago = {
		Nombre = "Mago",
		Rol = "Daño mágico a distancia",
		Descripcion = "Hechizos devastadores desde lejos, pero frágil.",
		Base = stats(80, 150, 5, 4, 18, 4, 0.08),
		PorNivel = stats(8, 12, 0.3, 0.3, 3, 0.6, 0),
		MultiplicadorAmenaza = 1,
		Habilidades = {
			{
				Id = "ProyectilArcano",
				Nombre = "Proyectil Arcano",
				Descripcion = "Hechizo básico rápido.",
				CostoMana = 3,
				Cooldown = 1.5,
				Rango = 40,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Magico", Base = 10, Escala = "Poder", Factor = 0.9 } },
			},
			{
				Id = "BolaFuego",
				Nombre = "Bola de Fuego",
				Descripcion = "Gran daño mágico. Se cancela si te movés al lanzarla.",
				CostoMana = 20,
				Cooldown = 5,
				Rango = 40,
				TiempoCasteo = 1.5,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Magico", Base = 30, Escala = "Poder", Factor = 1.8 } },
			},
			{
				Id = "NovaEscarcha",
				Nombre = "Nova de Escarcha",
				Descripcion = "Congela a los enemigos cercanos.",
				CostoMana = 25,
				Cooldown = 14,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "AreaEnemigos",
				Centro = "Propio",
				Radio = 12,
				Efectos = {
					{ Tipo = "Danio", Escuela = "Magico", Base = 12, Escala = "Poder", Factor = 0.8 },
					{ Tipo = "Aturdir", Duracion = 1 },
				},
			},
			{
				Id = "Meteoro",
				Nombre = "Meteoro",
				Descripcion = "Un meteoro cae sobre el objetivo y los que lo rodean.",
				CostoMana = 45,
				Cooldown = 20,
				Rango = 45,
				TiempoCasteo = 2,
				Objetivo = "AreaEnemigos",
				Centro = "Objetivo",
				Radio = 10,
				Efectos = { { Tipo = "Danio", Escuela = "Magico", Base = 40, Escala = "Poder", Factor = 2.2 } },
			},
		},
	},

	Arquero = {
		Nombre = "Arquero",
		Rol = "Daño físico a distancia",
		Descripcion = "Precisión desde lejos y venenos que desgastan.",
		Base = stats(95, 80, 3, 15, 4, 6, 0.15),
		PorNivel = stats(10, 6, 0.2, 2.3, 0.4, 0.9, 0),
		MultiplicadorAmenaza = 1,
		Habilidades = {
			{
				Id = "Disparo",
				Nombre = "Disparo",
				Descripcion = "Flecha básica.",
				CostoMana = 0,
				Cooldown = 1.5,
				Rango = 45,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 11, Escala = "Ataque", Factor = 0.9 } },
			},
			{
				Id = "DisparoCertero",
				Nombre = "Disparo Certero",
				Descripcion = "Apuntás un segundo y hacés mucho daño.",
				CostoMana = 15,
				Cooldown = 6,
				Rango = 50,
				TiempoCasteo = 1,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 28, Escala = "Ataque", Factor = 1.5 } },
			},
			{
				Id = "FlechaVenenosa",
				Nombre = "Flecha Venenosa",
				Descripcion = "Daño inicial y veneno durante 6 s.",
				CostoMana = 15,
				Cooldown = 10,
				Rango = 45,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = {
					{ Tipo = "Danio", Escuela = "Fisico", Base = 6, Escala = "Ataque", Factor = 0.4 },
					{
						Tipo = "DanioTiempo",
						Escuela = "Fisico",
						Base = 5,
						Escala = "Ataque",
						Factor = 0.3,
						Duracion = 6,
						Intervalo = 1,
					},
				},
			},
			{
				Id = "LluviaFlechas",
				Nombre = "Lluvia de Flechas",
				Descripcion = "Llueven flechas sobre el objetivo y los que lo rodean.",
				CostoMana = 30,
				Cooldown = 15,
				Rango = 45,
				TiempoCasteo = 0,
				Objetivo = "AreaEnemigos",
				Centro = "Objetivo",
				Radio = 12,
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 18, Escala = "Ataque", Factor = 1.0 } },
			},
		},
	},

	Asesino = {
		Nombre = "Asesino",
		Rol = "Daño cuerpo a cuerpo (sigilo)",
		Descripcion = "Se vuelve invisible y hace críticos devastadores por la espalda.",
		Base = stats(90, 70, 3, 17, 3, 6, 0.2),
		PorNivel = stats(9, 5, 0.2, 2.6, 0.3, 0.8, 0),
		MultiplicadorAmenaza = 1,
		MultiplicadorEspalda = 1.5,
		Habilidades = {
			{
				Id = "Punalada",
				Nombre = "Puñalada",
				Descripcion = "Ataque básico rápido.",
				CostoMana = 0,
				Cooldown = 1.2,
				Rango = 6,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 12, Escala = "Ataque", Factor = 1.0 } },
			},
			{
				Id = "Veneno",
				Nombre = "Hoja Envenenada",
				Descripcion = "Envenena al objetivo durante 6 s.",
				CostoMana = 12,
				Cooldown = 8,
				Rango = 6,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = {
					{
						Tipo = "DanioTiempo",
						Escuela = "Fisico",
						Base = 6,
						Escala = "Ataque",
						Factor = 0.35,
						Duracion = 6,
						Intervalo = 1,
					},
				},
			},
			{
				Id = "Sombras",
				Nombre = "Sombras",
				Descripcion = "Invisible durante 6 s: los enemigos te pierden. Atacar te revela.",
				CostoMana = 20,
				Cooldown = 20,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "Propio",
				Efectos = { { Tipo = "Invisible", Duracion = 6 } },
			},
			{
				Id = "Ejecucion",
				Nombre = "Ejecución",
				Descripcion = "Golpe letal. Por la espalda es un crítico seguro.",
				CostoMana = 25,
				Cooldown = 12,
				Rango = 6,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 35, Escala = "Ataque", Factor = 2.0 } },
			},
		},
	},

	Healer = {
		Nombre = "Healer",
		Rol = "Sanador",
		Descripcion = "Cura heridas al instante y mantiene vivo al grupo.",
		Base = stats(85, 160, 6, 4, 16, 6, 0.05),
		PorNivel = stats(9, 12, 0.35, 0.3, 2.8, 0.8, 0),
		MultiplicadorAmenaza = 1,
		Habilidades = {
			{
				Id = "Castigo",
				Nombre = "Castigo",
				Descripcion = "Rayo de luz que daña al enemigo.",
				CostoMana = 3,
				Cooldown = 1.5,
				Rango = 35,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Magico", Base = 8, Escala = "Poder", Factor = 0.6 } },
			},
			{
				Id = "Sanar",
				Nombre = "Sanar",
				Descripcion = "Cura directa a un aliado (o a vos sin objetivo).",
				CostoMana = 15,
				Cooldown = 2,
				Rango = 40,
				TiempoCasteo = 1.2,
				Objetivo = "Aliado",
				Efectos = { { Tipo = "Cura", Base = 25, Factor = 1.4 } },
			},
			{
				Id = "Renovar",
				Nombre = "Renovar",
				Descripcion = "Curación cada 2 s durante 10 s.",
				CostoMana = 15,
				Cooldown = 6,
				Rango = 40,
				TiempoCasteo = 0,
				Objetivo = "Aliado",
				Efectos = { { Tipo = "CuraTiempo", Base = 6, Factor = 0.4, Duracion = 10, Intervalo = 2 } },
			},
			{
				Id = "Plegaria",
				Nombre = "Plegaria",
				Descripcion = "Cura a todos los aliados cercanos.",
				CostoMana = 40,
				Cooldown = 18,
				Rango = 0,
				TiempoCasteo = 1.5,
				Objetivo = "AreaAliados",
				Centro = "Propio",
				Radio = 25,
				Efectos = { { Tipo = "Cura", Base = 20, Factor = 1.0 } },
			},
		},
	},

	Druida = {
		Nombre = "Druida",
		Rol = "Sanador de la naturaleza",
		Descripcion = "Curaciones sostenidas y raíces que inmovilizan.",
		Base = stats(100, 130, 5, 8, 14, 8, 0.07),
		PorNivel = stats(11, 10, 0.3, 1, 2.4, 1, 0),
		MultiplicadorAmenaza = 1,
		Habilidades = {
			{
				Id = "Espinas",
				Nombre = "Espinas",
				Descripcion = "Lanza espinas al enemigo.",
				CostoMana = 3,
				Cooldown = 1.5,
				Rango = 35,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Magico", Base = 9, Escala = "Poder", Factor = 0.7 } },
			},
			{
				Id = "Rejuvenecer",
				Nombre = "Rejuvenecer",
				Descripcion = "Curación cada 2 s durante 12 s.",
				CostoMana = 15,
				Cooldown = 5,
				Rango = 40,
				TiempoCasteo = 0,
				Objetivo = "Aliado",
				Efectos = { { Tipo = "CuraTiempo", Base = 7, Factor = 0.45, Duracion = 12, Intervalo = 2 } },
			},
			{
				Id = "Raices",
				Nombre = "Raíces",
				Descripcion = "Atrapa al enemigo 2.5 s.",
				CostoMana = 20,
				Cooldown = 12,
				Rango = 35,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = {
					{ Tipo = "Aturdir", Duracion = 2.5 },
					{ Tipo = "Danio", Escuela = "Magico", Base = 6, Escala = "Poder", Factor = 0.4 },
				},
			},
			{
				Id = "Florecer",
				Nombre = "Florecer",
				Descripcion = "Cura directa más curación sostenida.",
				CostoMana = 30,
				Cooldown = 10,
				Rango = 40,
				TiempoCasteo = 0,
				Objetivo = "Aliado",
				Efectos = {
					{ Tipo = "Cura", Base = 30, Factor = 1.5 },
					{ Tipo = "CuraTiempo", Base = 4, Factor = 0.2, Duracion = 8, Intervalo = 2 },
				},
			},
		},
	},

	Buffer = {
		Nombre = "Buffer",
		Rol = "Apoyo",
		Descripcion = "Auras que potencian a todo el grupo.",
		Base = stats(105, 120, 5, 8, 12, 9, 0.06),
		PorNivel = stats(11, 9, 0.3, 1, 2, 1.1, 0),
		MultiplicadorAmenaza = 1,
		Habilidades = {
			{
				Id = "GolpeRunico",
				Nombre = "Golpe Rúnico",
				Descripcion = "Ataque mágico básico.",
				CostoMana = 3,
				Cooldown = 1.5,
				Rango = 30,
				TiempoCasteo = 0,
				Objetivo = "Enemigo",
				Efectos = { { Tipo = "Danio", Escuela = "Magico", Base = 9, Escala = "Poder", Factor = 0.7 } },
			},
			{
				Id = "AuraFuerza",
				Nombre = "Aura de Fuerza",
				Descripcion = "+20% de ataque al grupo cercano durante 12 s.",
				CostoMana = 25,
				Cooldown = 20,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "AreaAliados",
				Centro = "Propio",
				Radio = 25,
				Efectos = { { Tipo = "Aura", Stat = "Ataque", Porcentaje = 20, Duracion = 12 } },
			},
			{
				Id = "AuraProteccion",
				Nombre = "Aura de Protección",
				Descripcion = "+25% de defensa al grupo cercano durante 12 s.",
				CostoMana = 25,
				Cooldown = 20,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "AreaAliados",
				Centro = "Propio",
				Radio = 25,
				Efectos = { { Tipo = "Aura", Stat = "Defensa", Porcentaje = 25, Duracion = 12 } },
			},
			{
				Id = "Inspiracion",
				Nombre = "Inspiración",
				Descripcion = "+30% de poder y una pequeña cura al grupo cercano.",
				CostoMana = 40,
				Cooldown = 30,
				Rango = 0,
				TiempoCasteo = 0,
				Objetivo = "AreaAliados",
				Centro = "Propio",
				Radio = 25,
				Efectos = {
					{ Tipo = "Aura", Stat = "Poder", Porcentaje = 30, Duracion = 10 },
					{ Tipo = "Cura", Base = 10, Factor = 0.5 },
				},
			},
		},
	},
}

local ClassConfig = {
	Clases = Clases,
	-- Orden de presentación en el selector.
	Orden = { "Tanque", "Guerrero", "Mago", "Arquero", "Asesino", "Healer", "Druida", "Buffer" },
	-- Stats de quien todavía no eligió clase.
	SinClase = {
		Base = stats(100, 50, 2, 8, 6, 6, 0.05),
		PorNivel = stats(10, 5, 0.1, 1, 1, 1, 0),
	},
	GCD = 0.8, -- bloqueo global tras cada habilidad (estado Attacking)
	ToleranciaRango = 4, -- studs extra por latencia
	MovimientoMaxCasteo = 2.5, -- studs: moverse más cancela el casteo
	VentanaParry = 0.5,
	CooldownParry = 3,
	AturdimientoParry = 1.5,
	InmunidadAturdir = 3, -- segundos de inmunidad tras terminar un aturdimiento
	MultiplicadorCritico = 1.5,
	RegenVidaFueraCombate = 0.02, -- fracción de vida máxima por segundo
	SegundosParaFueraDeCombate = 6,
}

return ClassConfig
