--!strict
-- MisionesConfig: NPCs que dan misiones y las misiones. Lo leen el servidor
-- (reglas) y el cliente (diálogos, marcadores y seguimiento).
--
-- Objetivos:
--   Matar      Objetivo = id del enemigo (EnemigosConfig.Enemigos o RaidBloxConfig.Jefes).
--              Cuenta para todos los que participaron en la pelea.
--   Recolectar Objetivo = id del ítem. Se cuenta lo que tenés en la mochila y
--              se entrega (se quita) al completar la misión.
--   Hablar     Objetivo = id del NPC. Se cumple al hablarle.

export type TipoObjetivo = "Matar" | "Recolectar" | "Hablar"
export type Objetivo = { Id: string, Tipo: TipoObjetivo, Objetivo: string, Cantidad: number, Texto: string }
export type RecompensaItem = { ItemId: string, Cantidad: number, Rareza: string? }
export type Mision = {
	Nombre: string,
	Descripcion: string,
	NivelRequerido: number,
	Npc: string, -- quien la da
	NpcEntrega: string?, -- quien la recibe (por defecto, el mismo)
	Previa: string?, -- misión que hay que haber completado antes
	Repetible: boolean?,
	Objetivos: { Objetivo },
	Recompensas: { Xp: number, Oro: number, Items: { RecompensaItem }? },
}
export type Npc = { Nombre: string, Titulo: string, Color: Color3, Posicion: Vector3 }

local MisionesConfig = {
	MaxActivas = 10,
	DistanciaNpc = 14,

	-- NPCs de la zona de pruebas (en los mapas reales, una parte con la
	-- etiqueta "NpcMision" y el atributo NpcId en el modelo).
	Npcs = {
		Capitan = {
			Nombre = "Capitán Aldric",
			Titulo = "Guardia del reino",
			Color = Color3.fromRGB(70, 90, 160),
			Posicion = Vector3.new(-12, 0, -22),
		},
		Herrero = {
			Nombre = "Brom",
			Titulo = "Herrero",
			Color = Color3.fromRGB(120, 70, 40),
			Posicion = Vector3.new(64, 0, -32),
		},
		Herbolaria = {
			Nombre = "Mira",
			Titulo = "Herbolaria",
			Color = Color3.fromRGB(70, 140, 70),
			Posicion = Vector3.new(92, 0, -50),
		},
	} :: { [string]: Npc },

	Misiones = {
		Bienvenida = {
			Nombre = "Bienvenida al reino",
			Descripcion = "El capitán quiere que conozcas a Brom, el herrero, junto a las estaciones de crafteo.",
			NivelRequerido = 1,
			Npc = "Capitan",
			NpcEntrega = "Herrero",
			Objetivos = { { Id = "h", Tipo = "Hablar", Objetivo = "Herrero", Cantidad = 1, Texto = "Hablá con Brom" } },
			Recompensas = { Xp = 50, Oro = 20 },
		},
		PracticaCombate = {
			Nombre = "Práctica de combate",
			Descripcion = "Afiná tus golpes con los muñecos de práctica.",
			NivelRequerido = 1,
			Npc = "Capitan",
			Repetible = true,
			Objetivos = { { Id = "m", Tipo = "Matar", Objetivo = "Muneco", Cantidad = 5, Texto = "Derrotá muñecos" } },
			Recompensas = { Xp = 40, Oro = 10 },
		},
		LobosAlAcecho = {
			Nombre = "Lobos al acecho",
			Descripcion = "Los lobos grises atacan a los viajeros. Reducí la manada.",
			NivelRequerido = 1,
			Npc = "Capitan",
			Previa = "Bienvenida",
			Objetivos = { { Id = "m", Tipo = "Matar", Objetivo = "Lobo", Cantidad = 3, Texto = "Lobos grises" } },
			Recompensas = { Xp = 150, Oro = 40, Items = { { ItemId = "PocionVida", Cantidad = 2 } } },
		},
		BandidosDelCamino = {
			Nombre = "Bandidos del camino",
			Descripcion = "Un grupo de bandidos asalta el camino del reino.",
			NivelRequerido = 3,
			Npc = "Capitan",
			Previa = "LobosAlAcecho",
			Objetivos = { { Id = "m", Tipo = "Matar", Objetivo = "Bandido", Cantidad = 2, Texto = "Bandidos" } },
			Recompensas = { Xp = 300, Oro = 80, Items = { { ItemId = "AnilloCobre", Cantidad = 1, Rareza = "Raro" } } },
		},
		HierbasCurativas = {
			Nombre = "Hierbas curativas",
			Descripcion = "Mira necesita hierbas sanadoras para sus pociones.",
			NivelRequerido = 1,
			Npc = "Herbolaria",
			Objetivos = {
				{ Id = "r", Tipo = "Recolectar", Objetivo = "HierbaSanadora", Cantidad = 5, Texto = "Hierba Sanadora" },
			},
			Recompensas = { Xp = 120, Oro = 30, Items = { { ItemId = "PocionVida", Cantidad = 3 } } },
		},
		MineralParaLaForja = {
			Nombre = "Mineral para la forja",
			Descripcion = "Brom se quedó sin mineral de hierro.",
			NivelRequerido = 1,
			Npc = "Herrero",
			Objetivos = {
				{
					Id = "r",
					Tipo = "Recolectar",
					Objetivo = "MineralHierro",
					Cantidad = 6,
					Texto = "Mineral de Hierro",
				},
			},
			Recompensas = { Xp = 150, Oro = 50, Items = { { ItemId = "Hierro", Cantidad = 2 } } },
		},
		ElGolem = {
			Nombre = "El Gólem de Obsidiana",
			Descripcion = "Un gólem antiguo despertó al sur. Reuní un grupo y derrotalo.",
			NivelRequerido = 5,
			Npc = "Capitan",
			Previa = "BandidosDelCamino",
			Objetivos = {
				{ Id = "m", Tipo = "Matar", Objetivo = "GolemObsidiana", Cantidad = 1, Texto = "Gólem de Obsidiana" },
			},
			Recompensas = { Xp = 1500, Oro = 500 },
		},
	} :: { [string]: Mision },
}

return MisionesConfig
