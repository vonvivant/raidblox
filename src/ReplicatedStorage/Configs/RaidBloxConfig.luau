--!strict
-- RaidBloxConfig: jefes de raid de mundo (RaidBlox) por mapa.
--
-- * Vida máxima = SaludBase * (1 + jugadoresEnCombate * 0.2), recalculada en vivo.
-- * Al 20% de vida entra en Furia: +30% de daño y ataques de área más seguidos.
-- * Sus ataques de área se anuncian con zonas rojas en el suelo antes de golpear.
-- * El botín es personal: cada participante con al menos 1% del aporte total
--   tira su propia tabla. Los Únicos solo caen de acá.

local EnemigosConfig = require(script.Parent.EnemigosConfig)

export type AtaqueArea = {
	Nombre: string,
	Tipo: "AlrededorDelJefe" | "SobreJugador",
	Radio: number,
	Aviso: number, -- segundos de zona roja antes del golpe
	DanioMultiplicador: number, -- sobre el daño base del jefe
	Cada: number, -- segundos entre usos
}

export type DefinicionRaidBlox = {
	Nombre: string,
	Zona: string,
	Posicion: Vector3,
	Nivel: number,
	SaludBase: number,
	DanioBase: number,
	Defensa: number,
	RangoAtaque: number,
	CadenciaAtaque: number,
	Velocidad: number,
	Escala: number,
	Color: Color3,
	Reaparicion: number, -- segundos tras morir
	ReaparicionEnStudio: number,
	Ataques: { AtaqueArea },
	Xp: number,
	Oro: number,
	Botin: { EnemigosConfig.EntradaBotin },
}

local RaidBloxConfig = {
	FactorPorJugador = 0.2,
	UmbralFuria = 0.2, -- fracción de vida
	MultiplicadorFuria = 1.3,
	AceleracionFuria = 0.6, -- en Furia los ataques de área se usan cada (Cada * 0.6) s
	AvisoFuria = 0.75, -- y avisan un 25% menos
	RadioCombate = 100, -- jugadores a esta distancia cuentan para el escalado y la barra
	RadioHUD = 250, -- la barra gigante se muestra hasta esta distancia
	AporteMinimo = 0.01, -- 1% del aporte total para recibir botín

	Jefes = {
		GolemObsidiana = {
			Nombre = "Gólem de Obsidiana",
			Zona = "Pruebas",
			Posicion = Vector3.new(60, 0, -200),
			Nivel = 10,
			SaludBase = 4000,
			DanioBase = 25,
			Defensa = 30,
			RangoAtaque = 12,
			CadenciaAtaque = 2.5,
			Velocidad = 10,
			Escala = 3,
			Color = Color3.fromRGB(45, 35, 55),
			Reaparicion = 900,
			ReaparicionEnStudio = 45,
			Ataques = {
				{
					Nombre = "Pisotón",
					Tipo = "AlrededorDelJefe",
					Radio = 16,
					Aviso = 1.8,
					DanioMultiplicador = 2,
					Cada = 12,
				},
				{
					Nombre = "Lluvia de Rocas",
					Tipo = "SobreJugador",
					Radio = 9,
					Aviso = 1.5,
					DanioMultiplicador = 1.6,
					Cada = 8,
				},
			},
			Xp = 1500,
			Oro = 400,
			Botin = {
				{ ItemId = "NucleoObsidiana", Probabilidad = 1, Min = 1, Max = 3 },
				{ ItemId = "EspadaHierro", Probabilidad = 0.6, Min = 1, Max = 1, Rareza = "Epico" },
				{ ItemId = "BaculoRoble", Probabilidad = 0.4, Min = 1, Max = 1, Rareza = "Mistico" },
				{ ItemId = "CoronaObsidiana", Probabilidad = 0.08, Min = 1, Max = 1, Rareza = "Unico" },
			},
		},
		ReinaArana = {
			Nombre = "Reina Araña del Bosque",
			Zona = "Bosque",
			Posicion = Vector3.new(-150, 0, 200),
			Nivel = 12,
			SaludBase = 6000,
			DanioBase = 30,
			Defensa = 25,
			RangoAtaque = 10,
			CadenciaAtaque = 2,
			Velocidad = 14,
			Escala = 2.5,
			Color = Color3.fromRGB(60, 90, 50),
			Reaparicion = 1200,
			ReaparicionEnStudio = 45,
			Ataques = {
				{
					Nombre = "Nido de Veneno",
					Tipo = "SobreJugador",
					Radio = 10,
					Aviso = 1.5,
					DanioMultiplicador = 1.5,
					Cada = 7,
				},
			},
			Xp = 2000,
			Oro = 500,
			Botin = {
				{ ItemId = "SedaArana", Probabilidad = 1, Min = 2, Max = 4 },
				{ ItemId = "AnilloCobre", Probabilidad = 0.5, Min = 1, Max = 1, Rareza = "Epico" },
				{ ItemId = "ColmilloReina", Probabilidad = 0.06, Min = 1, Max = 1, Rareza = "Unico" },
			},
		},
	} :: { [string]: DefinicionRaidBlox },
}

return RaidBloxConfig
