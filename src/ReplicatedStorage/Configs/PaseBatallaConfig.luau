--!strict
-- PaseBatallaConfig: pase de batalla (Fase 6.3) y códigos de creador.
--
-- 50 niveles por temporada. Cada nivel tiene una recompensa en la vía Gratis y
-- otra en la Premium (pase "PaseBatalla" de MonetizacionConfig). La XP del pase
-- se gana jugando (no se compra). Al cambiar `Temporada`, el progreso de todos
-- vuelve a cero (lo ya reclamado se queda).

export type Recompensa = {
	Tipo: "Oro" | "Item" | "Titulo" | "Skin" | "Ficha" | "Booster" | "Mascota" | "Apariencia",
	Cantidad: number?,
	ItemId: string?,
	Rareza: string?,
	Titulo: string?,
	Skin: string?,
	Ficha: string?,
	Id: string?, -- Mascota / Apariencia
	Texto: string, -- para mostrar
}

local function oro(n: number): Recompensa
	return { Tipo = "Oro", Cantidad = n, Texto = `{n} de oro` }
end
local function item(id: string, nombre: string, cantidad: number, rareza: string?): Recompensa
	return {
		Tipo = "Item",
		ItemId = id,
		Cantidad = cantidad,
		Rareza = rareza,
		Texto = `{nombre}{if cantidad > 1 then ` x{cantidad}` else ""}{if rareza then ` ({rareza})` else ""}`,
	}
end

-- Recompensas especiales por nivel (el resto se completa con oro y pociones).
local GRATIS: { [number]: Recompensa } = {
	[5] = item("PocionVida", "Poción de Vida", 5),
	[10] = { Tipo = "Ficha", Ficha = "Reroll", Cantidad = 1, Texto = "Ficha de Re-roll" },
	[15] = item("Amatista", "Amatista", 2),
	[20] = item("CascoHierro", "Casco de Hierro", 1, "Raro"),
	[25] = { Tipo = "Titulo", Titulo = "Aventurero del Despertar", Texto = "Título: Aventurero del Despertar" },
	[30] = { Tipo = "Booster", Cantidad = 1800, Texto = "Booster 2× XP (30 min)" },
	[35] = item("Zafiro", "Zafiro", 1),
	[40] = item("AnilloPlata", "Anillo de Plata", 1, "Epico"),
	[45] = { Tipo = "Ficha", Ficha = "Reroll", Cantidad = 2, Texto = "2 Fichas de Re-roll" },
	[50] = { Tipo = "Titulo", Titulo = "Veterano de la T1", Texto = "Título: Veterano de la T1" },
}
local PREMIUM: { [number]: Recompensa } = {
	[1] = { Tipo = "Mascota", Id = "Lumi", Texto = "Mascota: Lumi (juntabotín)" },
	[5] = { Tipo = "Booster", Cantidad = 3600, Texto = "Booster 2× XP (1 h)" },
	[10] = { Tipo = "Skin", Skin = "Gotica", Texto = "Skin del castillo: Gótica" },
	[15] = { Tipo = "Apariencia", Id = "EspadaLlameante", Texto = "Apariencia: Espada Llameante" },
	[20] = { Tipo = "Skin", Skin = "Hielo", Texto = "Skin del castillo: Hielo" },
	[25] = { Tipo = "Mascota", Id = "Brasa", Texto = "Mascota: Brasa (juntabotín)" },
	[30] = { Tipo = "Skin", Skin = "Jade", Texto = "Skin del castillo: Jade" },
	[35] = { Tipo = "Apariencia", Id = "BaculoArcano", Texto = "Apariencia: Báculo Arcano" },
	[40] = item("CapaSeda", "Capa de Seda", 1, "Mistico"),
	[45] = { Tipo = "Apariencia", Id = "CascoDragon", Texto = "Apariencia: Casco de Dragón" },
	[50] = { Tipo = "Titulo", Titulo = "Leyenda del Despertar", Texto = "Título: Leyenda del Despertar" },
}

local Niveles: { { Gratis: Recompensa, Premium: Recompensa } } = {}
for n = 1, 50 do
	Niveles[n] = {
		Gratis = GRATIS[n] or (if n % 2 == 0 then oro(50 + n * 5) else item("PocionMana", "Poción de Maná", 2)),
		Premium = PREMIUM[n] or oro(120 + n * 10),
	}
end

local PaseBatallaConfig = {
	Temporada = "T1",
	Nombre = "Temporada 1: El Despertar",
	XpPorNivel = 1000,
	PasePremium = "PaseBatalla", -- clave en MonetizacionConfig.Pases
	Xp = { Enemigo = 15, Jefe = 150, Mision = 250, Mazmorra = 600 },
	Niveles = Niveles,

	-- Códigos de creador / promocionales. En mayúsculas, sin espacios.
	-- Cada uno se canjea una vez por cuenta y se cuenta cuántas veces se usó.
	Codigos = {
		RAIDBLOX = {
			Creador = "Equipo RaidBlox",
			Activo = true,
			Recompensas = { oro(500), item("PocionVida", "Poción de Vida", 3) },
		},
		BIENVENIDA = {
			Creador = "Equipo RaidBlox",
			Activo = true,
			Recompensas = { { Tipo = "Booster", Cantidad = 1800, Texto = "Booster 2× XP (30 min)" } :: Recompensa },
		},
	} :: { [string]: { Creador: string, Activo: boolean, Recompensas: { Recompensa } } },
}

return PaseBatallaConfig
