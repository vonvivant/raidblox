--!strict
-- ItemRarityConfig: jerarquía de rarezas (Común -> Único).
--
-- Cada rareza multiplica los atributos base del ítem y suma efectos:
--   Común   gris     x1.0
--   Raro    azul     x1.3  1 efecto secundario
--   Épico   morado   x1.6  2 efectos secundarios + partículas
--   Místico cian     x2.0  2 efectos secundarios + pasiva única
--   Único   dorado   x2.5  2 efectos + pasiva + aura; solo cae de RaidBlox y se anuncia a todo el servidor
--
-- Épico, Místico y Único proyectan un haz de luz vertical del color de su rareza
-- cuando caen al suelo.

local Types = require(script.Parent.Parent.Shared.Types)

export type Rareza = Types.Rareza

export type DefinicionRareza = {
	Nombre: string,
	Color: Color3,
	Multiplicador: number,
	EfectosSecundarios: number,
	TienePasiva: boolean,
	Particulas: boolean,
	Haz: boolean, -- Beam vertical al caer al suelo
	Aura: boolean,
	AnuncioGlobal: boolean,
	Orden: number,
}

-- Efecto secundario: rango de valor que se sortea al generar el ítem.
export type DefinicionEfecto = {
	Nombre: string,
	Min: number,
	Max: number,
	Formato: string, -- para mostrar: string.format(Formato, valor)
}

export type DefinicionPasiva = {
	Nombre: string,
	Descripcion: string,
}

local ItemRarityConfig = {
	Rarezas = {
		Comun = {
			Nombre = "Común",
			Color = Color3.fromHex("#808080"),
			Multiplicador = 1.0,
			EfectosSecundarios = 0,
			TienePasiva = false,
			Particulas = false,
			Haz = false,
			Aura = false,
			AnuncioGlobal = false,
			Orden = 1,
		},
		Raro = {
			Nombre = "Raro",
			Color = Color3.fromHex("#0070DD"),
			Multiplicador = 1.3,
			EfectosSecundarios = 1,
			TienePasiva = false,
			Particulas = false,
			Haz = false,
			Aura = false,
			AnuncioGlobal = false,
			Orden = 2,
		},
		Epico = {
			Nombre = "Épico",
			Color = Color3.fromHex("#A335EE"),
			Multiplicador = 1.6,
			EfectosSecundarios = 2,
			TienePasiva = false,
			Particulas = true,
			Haz = true,
			Aura = false,
			AnuncioGlobal = false,
			Orden = 3,
		},
		Mistico = {
			Nombre = "Místico",
			Color = Color3.fromHex("#00F0FF"),
			Multiplicador = 2.0,
			EfectosSecundarios = 2,
			TienePasiva = true,
			Particulas = true,
			Haz = true,
			Aura = false,
			AnuncioGlobal = false,
			Orden = 4,
		},
		Unico = {
			Nombre = "Único",
			Color = Color3.fromHex("#FFD700"),
			Multiplicador = 2.5,
			EfectosSecundarios = 2,
			TienePasiva = true,
			Particulas = true,
			Haz = true,
			Aura = true,
			AnuncioGlobal = true,
			Orden = 5,
		},
	} :: { [string]: DefinicionRareza },

	-- Efectos secundarios posibles (se sortean sin repetir).
	Efectos = {
		Critico = { Nombre = "Crítico", Min = 2, Max = 6, Formato = "+%d%% probabilidad de crítico" },
		RoboVida = { Nombre = "Robo de vida", Min = 2, Max = 5, Formato = "%d%% del daño cura" },
		RegenMana = { Nombre = "Regeneración de maná", Min = 1, Max = 3, Formato = "+%d maná por segundo" },
		Defensa = { Nombre = "Defensa", Min = 4, Max = 12, Formato = "+%d defensa" },
		Ataque = { Nombre = "Ataque", Min = 3, Max = 9, Formato = "+%d ataque" },
		Poder = { Nombre = "Poder", Min = 3, Max = 9, Formato = "+%d poder" },
	} :: { [string]: DefinicionEfecto },

	-- Pasivas únicas de Místicos y Únicos.
	Pasivas = {
		Ejecutor = { Nombre = "Ejecutor", Descripcion = "+25% de daño a objetivos con menos de 30% de vida." },
		Vampirismo = { Nombre = "Vampirismo", Descripcion = "8% del daño que hacés te cura." },
		Furia = { Nombre = "Furia", Descripcion = "+15% de daño mientras tenés menos de 50% de vida." },
	} :: { [string]: DefinicionPasiva },

	-- Probabilidades por defecto cuando una tabla de botín no fija la rareza.
	-- Único nunca sale de acá: solo de entradas de RaidBlox que lo fijan.
	PesosPorDefecto = { Comun = 60, Raro = 27, Epico = 10, Mistico = 3 } :: { [string]: number },
}

return ItemRarityConfig
