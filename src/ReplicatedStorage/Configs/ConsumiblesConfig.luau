--!strict
-- ConsumiblesConfig: qué hace cada consumible con efecto propio (elixires,
-- tónicos, infusiones, antídotos) y cada mejora temporal que da un NPC.
-- Las pociones simples de vida y maná siguen en ItemCatalog (campo `Consumo`).
--
-- Dos clases:
--   * Instantáneos (`Instantaneo = true`): hacen su efecto en el momento y
--     comparten la recarga de las pociones (GameConfig.Consumibles).
--   * Temporales (`Categoria` + `Duracion`): quedan activos. Reglas de acumulación:
--       - Uno solo activo por categoría: tomar otro de la misma lo reemplaza.
--       - Categorías distintas se suman (un elixir + una infusión + un tónico).
--       - La reducción de recargas total nunca pasa de `PrisaMaxima`.
--     Siguen corriendo aunque el jugador muera, cambie de zona o se desconecte
--     (se guardan en el perfil con su hora de vencimiento).
--
-- El resultado de los consumibles con riesgo se sortea en el servidor al
-- tomarlos; las probabilidades están en `Descripcion`, a la vista del jugador.

-- Efectos temporales (`Tipo`):
--   "Aura"       +/- `Porcentaje` % a `Stat` ("Ataque" | "Poder" | "Defensa")
--   "Prisa"      reduce las recargas de habilidades en `Porcentaje` %
--   "RegenMana"  recupera `Porcentaje` % del maná o stamina cada `IntervaloRegen` s
--   "RegenVida"  ídem con la vida
export type EfectoTemporal = { Tipo: string, Porcentaje: number, Stat: string? }

-- Efectos instantáneos (`Tipo`):
--   "Purificar"   quita debilitamientos, sangrados y quemaduras
--   "Escudo"      absorbe daño por `Porcentaje` % de la vida máxima durante `Duracion` s
--   "CuraTiempo"  cura `Porcentaje` % de la vida máxima cada `Intervalo` s durante `Duracion` s
export type EfectoInstantaneo = {
	Tipo: string,
	Porcentaje: number?,
	Duracion: number?,
	Intervalo: number?,
}

-- Categorías: "Elixir" | "Tonico" | "Infusion" | "Filo" (NombresCategoria).

export type Definicion = {
	Nombre: string,
	Instantaneo: boolean?,
	EfectosInstantaneos: { EfectoInstantaneo }?,
	Categoria: string?,
	Duracion: number?, -- segundos
	Efectos: { EfectoTemporal }?,
	-- Consumibles con riesgo: con `Probabilidad` salen los efectos `Malos` en
	-- lugar de los normales.
	Riesgo: { Probabilidad: number, Malos: { EfectoTemporal }, Texto: string }?,
}

local Definiciones: { [string]: Definicion } = {
	-- Boticario -------------------------------------------------------
	PocionRegeneracion = {
		Nombre = "Poción de Regeneración",
		Instantaneo = true,
		EfectosInstantaneos = { { Tipo = "CuraTiempo", Porcentaje = 4, Intervalo = 2, Duracion = 20 } },
	},
	PocionVitalidad = {
		Nombre = "Poción de Vitalidad",
		Instantaneo = true,
		EfectosInstantaneos = { { Tipo = "Escudo", Porcentaje = 20, Duracion = 60 } },
	},
	Antidoto = {
		Nombre = "Antídoto",
		Instantaneo = true,
		EfectosInstantaneos = { { Tipo = "Purificar" } },
	},

	-- Boticario Espiritual ---------------------------------------------
	TonicoEnergia = {
		Nombre = "Tónico de Energía",
		Categoria = "Tonico",
		Duracion = 300,
		Efectos = { { Tipo = "RegenMana", Porcentaje = 3 } },
	},
	TonicoEnfoque = {
		Nombre = "Tónico de Enfoque",
		Categoria = "Tonico",
		Duracion = 120,
		Efectos = { { Tipo = "Prisa", Porcentaje = 10 } },
	},

	-- Alquimista Experimental --------------------------------------------
	ElixirFuerza = {
		Nombre = "Elixir de Fuerza",
		Categoria = "Elixir",
		Duracion = 600,
		Efectos = { { Tipo = "Aura", Stat = "Ataque", Porcentaje = 15 } },
	},
	ElixirAgilidad = {
		Nombre = "Elixir de Agilidad",
		Categoria = "Elixir",
		Duracion = 600,
		Efectos = { { Tipo = "Prisa", Porcentaje = 10 } },
	},
	ElixirResistencia = {
		Nombre = "Elixir de Resistencia",
		Categoria = "Elixir",
		Duracion = 600,
		Efectos = { { Tipo = "Aura", Stat = "Defensa", Porcentaje = 15 } },
	},
	MezclaInestable = {
		Nombre = "Mezcla Inestable",
		Categoria = "Elixir",
		Duracion = 300,
		Efectos = {
			{ Tipo = "Aura", Stat = "Ataque", Porcentaje = 30 },
			{ Tipo = "Aura", Stat = "Defensa", Porcentaje = -20 },
		},
	},
	PocionExperimental = {
		Nombre = "Poción Experimental",
		Categoria = "Elixir",
		Duracion = 300,
		Efectos = {
			{ Tipo = "Aura", Stat = "Ataque", Porcentaje = 25 },
			{ Tipo = "Aura", Stat = "Poder", Porcentaje = 25 },
		},
		Riesgo = {
			Probabilidad = 0.35,
			Malos = { { Tipo = "Aura", Stat = "Defensa", Porcentaje = -15 } },
			Texto = "La poción salió mal: -15% de defensa.",
		},
	},

	-- Barista de Tés -----------------------------------------------------
	TeManantial = {
		Nombre = "Té de Manantial",
		Categoria = "Infusion",
		Duracion = 900,
		Efectos = { { Tipo = "RegenMana", Porcentaje = 2 } },
	},
	TeRaices = {
		Nombre = "Té de Raíces",
		Categoria = "Infusion",
		Duracion = 900,
		Efectos = { { Tipo = "Aura", Stat = "Defensa", Porcentaje = 10 } },
	},
	TeJazminLunar = {
		Nombre = "Té de Jazmín Lunar",
		Categoria = "Infusion",
		Duracion = 900,
		Efectos = { { Tipo = "Prisa", Porcentaje = 6 } },
	},

	-- Servicios de NPC (no son ítems) -------------------------------------
	ServicioAfilar = {
		Nombre = "Arma afilada",
		Categoria = "Filo",
		Duracion = 600,
		Efectos = { { Tipo = "Aura", Stat = "Ataque", Porcentaje = 10 } },
	},
}

return {
	Definiciones = Definiciones,
	NombresCategoria = { Elixir = "Elixir", Tonico = "Tónico", Infusion = "Infusión", Filo = "Filo" } :: { [string]: string },
	PrisaMaxima = 30, -- % de reducción de recargas sumando todo
	IntervaloRegen = 5, -- segundos entre pulsos de RegenMana / RegenVida
}
