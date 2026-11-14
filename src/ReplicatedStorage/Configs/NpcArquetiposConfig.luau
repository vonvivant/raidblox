--!strict
-- NpcArquetiposConfig: base de datos de los 38 arquetipos de NPC, en 8
-- categorías. La usa NpcManager (servidor) para decidir qué ofrece cada NPC y
-- NpcUI (cliente) para mostrarlo.
--
-- Facciones: "Rojo", "Azul" y "Neutral". Un jugador Violeta cuenta como Neutral.
--   * Jugador Rojo:    habla con NPCs Rojos y Neutrales.
--   * Jugador Azul:    habla con NPCs Azules y Neutrales.
--   * Jugador Neutral: habla con todos.
-- `Facciones` dice en qué versiones existe el arquetipo:
--   { "Rojo", "Azul", "Neutral" }  versión Roja y Azul en las capitales y Neutral en zonas libres
--   { "Rojo", "Azul" }             exclusivo de bando (economías separadas)
--   { "Neutral" }                  solo en zonas libres, atiende a cualquiera
--
-- Interfaces (servicios acoplables):
--   IVendor           compra/venta: `Vende` (por oro u honor) y `Compra`
--   ICrafter          fabricación: `Estacion` abre las recetas de esa estación
--   IServiceProvider  acciones al instante: `Servicios` (y `Viajes` del Guardián)
--   IQuestGiver       misiones y contratos
--
-- `Estado`:
--   "Listo"      funciona hoy hablando con el NPC.
--   "Parcial"    el sistema existe en el juego pero se usa desde otro lado
--                (`Sistema` dice cuál); el NPC lo explica.
--   "Pendiente"  falta el sistema; `Parametros` deja definido cómo va a ser.
-- En `Vende` solo hay ítems que existen en ItemCatalog; lo que falta crear
-- está descripto en `Parametros`.

export type Faccion = "Rojo" | "Azul" | "Neutral"
export type Interfaz = "IVendor" | "ICrafter" | "IServiceProvider" | "IQuestGiver"
export type Categoria = "Alquimia" | "Herreria" | "Economia" | "Viajes" | "Misiones" | "Cosmeticos" | "Social" | "PvP"

export type Oferta = {
	ItemId: string,
	Precio: number,
	Moneda: ("Oro" | "Honor")?, -- por defecto Oro
	Solo: Faccion?, -- solo lo vende la versión de ese bando
}

export type Servicio = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	Costo: number, -- oro
	Accion: string?, -- acción registrada en NpcManager; sin acción = todavía no disponible
}

export type Arquetipo = {
	Numero: number,
	Nombre: string,
	Categoria: Categoria,
	Descripcion: string,
	Interfaces: { Interfaz },
	Facciones: { Faccion },
	Estado: "Listo" | "Parcial" | "Pendiente",
	Sistema: string?, -- módulo o lugar del juego donde ya existe (Parcial)
	Color: Color3,
	Vende: { Oferta }?,
	Compra: { Factor: number, Tipos: { string } }?, -- paga PrecioVenta × Factor por esos tipos de ítem
	Estacion: ("Yunque" | "MesaAlquimia" | "Telar")?,
	Servicios: { Servicio }?,
	Viajes: boolean?, -- Guardián de Portales
	Tags: { string }?, -- tags de CollectionService que recibe la raíz del NPC
	Parametros: { [string]: any },
}

local TODAS: { Faccion } = { "Rojo", "Azul", "Neutral" }
local BANDOS: { Faccion } = { "Rojo", "Azul" }
local NEUTRAL: { Faccion } = { "Neutral" }

local VERDE = Color3.fromRGB(70, 140, 80)
local GRIS = Color3.fromRGB(110, 110, 120)
local ORO = Color3.fromRGB(190, 150, 50)
local CELESTE = Color3.fromRGB(70, 130, 180)
local MARRON = Color3.fromRGB(130, 90, 60)
local ROSA = Color3.fromRGB(190, 100, 150)
local NARANJA = Color3.fromRGB(200, 120, 50)
local BORDO = Color3.fromRGB(140, 50, 60)

local Arquetipos: { [string]: Arquetipo } = {
	--------------------------------------------------------------------
	-- 1. Alquimia, magia y consumibles
	--------------------------------------------------------------------
	Boticario = {
		Numero = 1,
		Nombre = "Boticario",
		Categoria = "Alquimia",
		Descripcion = "Herborista dedicado: pociones de salud y antídotos.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = VERDE,
		Vende = { { ItemId = "PocionVida", Precio = 15 }, { ItemId = "HierbaSanadora", Precio = 6 } },
		Estacion = "MesaAlquimia",
		Parametros = {
			Recurso = "Vida",
			Futuro = { "Poción de vitalidad", "Regeneración lenta", "Curación instantánea", "Antídoto" },
			RecetasAltas = "Exigen plantas y flores silvestres (Herboristería)",
		},
	},
	BoticarioEspiritual = {
		Numero = 2,
		Nombre = "Boticario Espiritual",
		Categoria = "Alquimia",
		Descripcion = "Místico: maná, stamina, enfoque y reducción de recargas.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = CELESTE,
		Vende = { { ItemId = "PocionMana", Precio = 15 }, { ItemId = "FlorLunar", Precio = 9 } },
		Estacion = "MesaAlquimia",
		Parametros = {
			Recursos = { "Mana", "Stamina", "Energia", "Conciencia", "Concentracion", "Enfoque" },
			Futuro = { "Poción de stamina", "Poción de reducción de recarga (-10% por 60 s)" },
		},
	},
	AlquimistaExperimental = {
		Numero = 3,
		Nombre = "Alquimista Experimental",
		Categoria = "Alquimia",
		Descripcion = "Elixires temporales de atributos y de riesgo/recompensa.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = Color3.fromRGB(120, 60, 150),
		Estacion = "MesaAlquimia",
		Parametros = {
			Elixires = {
				{ Nombre = "Elixir de Fuerza", Efecto = "+15% Ataque", Duracion = 600 },
				{ Nombre = "Elixir de Agilidad", Efecto = "+5% Crítico y Esquiva", Duracion = 600 },
				{ Nombre = "Elixir de Resistencia Elemental", Efecto = "-15% daño mágico", Duracion = 600 },
			},
			Riesgo = {
				{ Nombre = "Mezcla Inestable", Efecto = "+30% Ataque", Secundario = "-20% Defensa", Duracion = 300 },
				{
					Nombre = "Suero de Berserker",
					Efecto = "+20% velocidad de ataque",
					Secundario = "pierde 1% de vida por segundo",
					Duracion = 120,
				},
			},
			Requiere = "Efecto de buff por consumible (hoy los consumibles solo recuperan vida o maná)",
		},
	},
	BorradorRecuerdos = {
		Numero = 4,
		Nombre = "Borrador de Recuerdos",
		Categoria = "Alquimia",
		Descripcion = "Chamán de restablecimiento: reinicia talentos, habilidades o atributos.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = Color3.fromRGB(90, 90, 150),
		Servicios = {
			{
				Id = "Respec",
				Nombre = "Reiniciar talentos",
				Descripcion = "Devuelve todos los puntos gastados.",
				Costo = 2000,
			},
		},
		Parametros = {
			CostoAlternativo = { ItemId = "FlorLunar", Cantidad = 20 },
			CostoCreciente = "+50% por cada uso en la misma semana",
			Requiere = "Sistema de talentos (hoy la clase define todas las habilidades)",
		},
	},
	Inscriptor = {
		Numero = 5,
		Nombre = "Inscriptor",
		Categoria = "Alquimia",
		Descripcion = "Sastre de pergaminos: teletransporte, buffs de grupo y mapas.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = Color3.fromRGB(170, 150, 110),
		Estacion = "Telar",
		Parametros = {
			Pergaminos = {
				{ Nombre = "Pergamino de Teletransporte", Efecto = "Vuelve a la última ciudad", Precio = 120 },
				{ Nombre = "Pergamino de Fortaleza", Efecto = "+10% Defensa al grupo por 10 min", Precio = 200 },
				{
					Nombre = "Mapa de Identificación",
					Efecto = "Revela los efectos de un ítem sin identificar",
					Precio = 80,
				},
			},
			Materiales = { "TelaLino", "FlorLunar" },
			Requiere = "Consumibles con efecto propio",
		},
	},

	--------------------------------------------------------------------
	-- 2. Herrería, equipo y forja
	--------------------------------------------------------------------
	HerreroGeneral = {
		Numero = 6,
		Nombre = "Herrero General",
		Categoria = "Herreria",
		Descripcion = "Equipo básico de hierro y piezas iniciales con lingotes.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = GRIS,
		Vende = {
			{ ItemId = "EspadaHierro", Precio = 75 },
			{ ItemId = "CascoHierro", Precio = 60 },
			{ ItemId = "Hierro", Precio = 12 },
		},
		Estacion = "Yunque",
		Parametros = { NivelMaximoEquipo = 10, Futuro = { "Línea de acero" } },
	},
	AfiladorArmas = {
		Numero = 7,
		Nombre = "Afilador de Armas",
		Categoria = "Herreria",
		Descripcion = "Maestro de filo: mejora temporal del arma.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = GRIS,
		Servicios = {
			{
				Id = "Afilar",
				Nombre = "Afilar el arma",
				Descripcion = "+10% de ataque por 10 minutos.",
				Costo = 60,
				Accion = "Afilar",
			},
		},
		Parametros = {
			Buff = { Stat = "Ataque", Porcentaje = 10, Duracion = 600 },
			Futuro = { "Precisión", "Penetración de armadura", "Pago con piedras de afilar" },
		},
	},
	ReparadorArmaduras = {
		Numero = 8,
		Nombre = "Reparador de Armaduras",
		Categoria = "Herreria",
		Descripcion = "Remendador: restaura la durabilidad del equipo.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = MARRON,
		Servicios = {
			{ Id = "Reparar", Nombre = "Reparar todo", Descripcion = "Durabilidad al máximo.", Costo = 100 },
		},
		Parametros = {
			TarifaCiudad = 1,
			TarifaMazmorra = 3, -- de emergencia, dentro de mazmorras
			CostoPorPunto = 0.5,
			Requiere = "Durabilidad del equipo",
		},
	},
	MaestroEncantador = {
		Numero = 9,
		Nombre = "Maestro Encantador",
		Categoria = "Herreria",
		Descripcion = "Aumentos, gemas, encantamientos y runas con brillo.",
		Interfaces = { "IServiceProvider", "ICrafter" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = Color3.fromRGB(150, 80, 200),
		Servicios = {
			{
				Id = "Engarzar",
				Nombre = "Engarzar gema",
				Descripcion = "Agrega la estadística de la gema al ítem.",
				Costo = 300,
			},
		},
		Parametros = {
			Gemas = {
				Amatista = "Poder",
				Esmeralda = "RegenMana",
				Zafiro = "Defensa",
				Rubi = "Ataque",
				Diamante = "Critico",
			},
			RanurasPorRareza = { Comun = 0, Raro = 1, Epico = 2, Mistico = 2, Unico = 3 },
			Brillo = true,
			Requiere = "Gemas engarzables (las gemas ya existen como material)",
		},
	},
	Desencantador = {
		Numero = 10,
		Nombre = "Desencantador",
		Categoria = "Herreria",
		Descripcion = "Desmantelador: destruye ítems mágicos para sacar esencias.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Yunque Portátil del Chatarrero (desmantela equipo Común o Raro)",
		Color = Color3.fromRGB(100, 70, 130),
		Servicios = {
			{
				Id = "Desencantar",
				Nombre = "Desencantar ítem",
				Descripcion = "Devuelve esencias según la rareza.",
				Costo = 25,
			},
		},
		Parametros = {
			Resultado = {
				Raro = "Polvo de encantamiento",
				Epico = "Esencia mágica",
				Mistico = "Esencia mayor",
				Unico = "Fragmento de reliquia",
			},
			Requiere = "Ítems de esencia",
		},
	},
	ReforjadorAtributos = {
		Numero = 11,
		Nombre = "Reforjador de Atributos",
		Categoria = "Herreria",
		Descripcion = "Cambia las estadísticas secundarias de un arma o armadura.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Ficha de Re-roll (Tienda → Colección)",
		Color = NARANJA,
		Servicios = {
			{ Id = "Reforjar", Nombre = "Reforjar", Descripcion = "Tira de nuevo los efectos del ítem.", Costo = 500 },
		},
		Parametros = { CostoPorRareza = { Raro = 500, Epico = 1500, Mistico = 4000, Unico = 10000 } },
	},
	Fundidor = {
		Numero = 12,
		Nombre = "Fundidor",
		Categoria = "Herreria",
		Descripcion = "Metalúrgico: minerales en lingotes y transmutación.",
		Interfaces = { "ICrafter", "IVendor" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = NARANJA,
		Vende = { { ItemId = "MineralHierro", Precio = 6 }, { ItemId = "MineralPlata", Precio = 18 } },
		Estacion = "Yunque",
		Parametros = {
			Transmutacion = { De = "Hierro", A = "LingotePlata", Proporcion = 5 },
			Requiere = "Receta de transmutación",
		},
	},

	--------------------------------------------------------------------
	-- 3. Economía, comercio y almacenamiento
	--------------------------------------------------------------------
	Banquero = {
		Numero = 13,
		Nombre = "Banquero",
		Categoria = "Economia",
		Descripcion = "Guardián de la bóveda: almacén personal y compartido de la cuenta.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = ORO,
		Servicios = {
			{
				Id = "Vault",
				Nombre = "Abrir la bóveda",
				Descripcion = "Tu almacén global: lo que guardes está en todos los bancos.",
				Costo = 0,
				Accion = "Vault",
			},
		},
		Tags = { "BancoVault" },
		Parametros = { Pestanas = 8, RanurasPorPestana = 30, Config = "VaultConfig" },
	},
	BanqueroClan = {
		Numero = 14,
		Nombre = "Banquero de Clan",
		Categoria = "Economia",
		Descripcion = "Tesorero: inventario y fondos de la hermandad.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Banco de hermandad (botón Hermandad del menú)",
		Color = ORO,
		Servicios = {
			{
				Id = "BancoClan",
				Nombre = "Banco de la hermandad",
				Descripcion = "4 pestañas de 28 lugares.",
				Costo = 0,
			},
		},
		Parametros = { Pestanas = 4, RanurasPorPestana = 28 },
	},
	Subastador = {
		Numero = 15,
		Nombre = "Subastador",
		Categoria = "Economia",
		Descripcion = "Corredor de bolsa: Casa de Subastas.",
		Interfaces = { "IServiceProvider" },
		Facciones = BANDOS, -- economías separadas: no hay subastador neutral
		Estado = "Listo",
		Color = ORO,
		Servicios = {
			{
				Id = "Subasta",
				Nombre = "Casa de Subastas",
				Descripcion = "Comprar y publicar.",
				Costo = 0,
				Accion = "Subasta",
			},
		},
		Parametros = {
			MercadoPorBando = true,
			-- Hoy la Casa de Subastas es una sola para todos. Separarla por bando
			-- cambia la economía actual: queda apagado hasta decidirlo.
			SeparacionActiva = false,
		},
	},
	ComercianteExcedentes = {
		Numero = 16,
		Nombre = "Comerciante de Excedentes",
		Categoria = "Economia",
		Descripcion = "Chatarreo: compra lo que te sobra y vende herramientas básicas.",
		Interfaces = { "IVendor" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = MARRON,
		Vende = { { ItemId = "PicoHierro", Precio = 30 }, { ItemId = "HozHierro", Precio = 30 } },
		Compra = { Factor = 1, Tipos = { "Material", "Consumible", "Equipo", "Herramienta" } },
		Parametros = { Futuro = { "Hacha", "Caña de pescar" } },
	},
	Prestamista = {
		Numero = 17,
		Nombre = "Prestamista",
		Categoria = "Economia",
		Descripcion = "Cambista: convierte monedas y divisas de eventos.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = ORO,
		Servicios = {
			{ Id = "Cambiar", Nombre = "Cambiar divisas", Descripcion = "Divisas de evento por oro.", Costo = 0 },
		},
		Parametros = {
			Monedas = { Bronce = 1, Plata = 100, Oro = 10000 }, -- el juego usa una sola moneda (oro); esto es solo de presentación
			Comision = 0.05,
			Requiere = "Divisas de evento",
		},
	},
	MercadoNegro = {
		Numero = 18,
		Nombre = "Vendedor del Mercado Negro",
		Categoria = "Economia",
		Descripcion = "Rarezas, recetas especiales y contenedores por oro, para cualquiera.",
		Interfaces = { "IVendor" },
		Facciones = NEUTRAL,
		Estado = "Listo",
		Color = Color3.fromRGB(60, 50, 70),
		Vende = {
			{ ItemId = "Amatista", Precio = 90 },
			{ ItemId = "Esmeralda", Precio = 130 },
			{ ItemId = "Zafiro", Precio = 150 },
			{ ItemId = "Rubi", Precio = 170 },
			{ ItemId = "SedaArana", Precio = 80 },
		},
		Parametros = {
			Ubicacion = "Zonas neutrales o tabernas libres",
			Futuro = {
				"Cosméticos raros",
				"Recetas especiales",
				"Contenedores aleatorios por oro (con probabilidades a la vista)",
			},
		},
	},

	--------------------------------------------------------------------
	-- 4. Viajes, cartografía y logística
	--------------------------------------------------------------------
	GuardianPortales = {
		Numero = 19,
		Nombre = "Guardián de Portales",
		Categoria = "Viajes",
		Descripcion = "Teletransporta entre mapas respetando los territorios.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = Color3.fromRGB(120, 80, 190),
		Viajes = true,
		Parametros = {
			Regla = "Rojo: zonas Rojas y Neutrales. Azul: zonas Azules y Neutrales. Neutral: cualquiera, más caro.",
		},
	},
	MaestroEstablo = {
		Numero = 20,
		Nombre = "Maestro de Establo",
		Categoria = "Viajes",
		Descripcion = "Criador: monturas básicas, alquiler y entrenamiento.",
		Interfaces = { "IVendor", "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Monturas (tecla G): caballo gratis y Dragón de Fuego con pase",
		Color = MARRON,
		Servicios = {
			{ Id = "Alquilar", Nombre = "Alquilar montura", Descripcion = "Montura rápida por 1 hora.", Costo = 150 },
			{
				Id = "Entrenar",
				Nombre = "Entrenar velocidad",
				Descripcion = "+2% de velocidad de montura (hasta +10%).",
				Costo = 1000,
			},
		},
		Parametros = { Requiere = "Monturas compradas con oro y entrenamiento" },
	},
	Navegante = {
		Numero = 21,
		Nombre = "Navegante",
		Categoria = "Viajes",
		Descripcion = "Transportista: barcos, dirigibles o carros entre puertos.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = CELESTE,
		Parametros = {
			Rutas = { { De = "CiudadPrincipal", A = "ReinoFuego", Costo = 80, Cada = 300 } },
			Requiere = "Rutas con vehículo (hoy se puede usar el Guardián de Portales)",
		},
	},
	Cartografo = {
		Numero = 22,
		Nombre = "Cartógrafo",
		Categoria = "Viajes",
		Descripcion = "Explorador: mapas de zonas ocultas y puntos de interés.",
		Interfaces = { "IVendor", "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = VERDE,
		Servicios = {
			{
				Id = "RevelarPOI",
				Nombre = "Revelar puntos de interés",
				Descripcion = "Los marca en tu minimapa.",
				Costo = 200,
			},
		},
		Parametros = {
			Coleccionables = "Intercambia coleccionables de exploración",
			Requiere = "Puntos de interés por zona",
		},
	},
	GuardianPiedraTeleport = {
		Numero = 23,
		Nombre = "Guardián de Piedra Teleport",
		Categoria = "Viajes",
		Descripcion = "Portalero: activa puntos de viaje rápido.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = Color3.fromRGB(90, 160, 200),
		Servicios = {
			{
				Id = "ActivarWaypoint",
				Nombre = "Activar piedra",
				Descripcion = "Guarda este punto para volver.",
				Costo = 0,
			},
		},
		Parametros = { CostoViaje = { Mana = 50, Cristales = 1 }, Requiere = "Waypoints guardados en el perfil" },
	},

	--------------------------------------------------------------------
	-- 5. Misiones, facciones y progresión
	--------------------------------------------------------------------
	Tabernero = {
		Numero = 24,
		Nombre = "Tabernero",
		Categoria = "Misiones",
		Descripcion = "Informante: misiones secundarias, rumores y descanso.",
		Interfaces = { "IQuestGiver", "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Misiones (NPCs con ! del mapa)",
		Color = MARRON,
		Servicios = {
			{ Id = "Rumores", Nombre = "Rumores", Descripcion = "Dónde está el próximo jefe de mundo.", Costo = 10 },
		},
		Parametros = { RestedXP = { Bonus = 1.5, MaximoHoras = 8 }, Requiere = "Experiencia de descanso" },
	},
	TablonAnuncios = {
		Numero = 25,
		Nombre = "Tablón de Anuncios",
		Categoria = "Misiones",
		Descripcion = "Cazador de recompensas: misiones diarias y contratos de caza.",
		Interfaces = { "IQuestGiver" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = MARRON,
		Parametros = {
			Diarias = 3,
			Contratos = { "Matar N monstruos de un tipo", "Derrotar jugadores del bando enemigo en zona PvP" },
			Requiere = "Misiones diarias con reinicio",
		},
	},
	EmisarioFaccion = {
		Numero = 26,
		Nombre = "Emisario de Facción",
		Categoria = "Misiones",
		Descripcion = "Intendente: recompensas exclusivas por reputación.",
		Interfaces = { "IVendor" },
		Facciones = BANDOS,
		Estado = "Pendiente",
		Color = BORDO,
		Parametros = {
			Niveles = { "Neutral", "Amistoso", "Honorable", "Reverenciado", "Exaltado" },
			Recompensas = { "Títulos", "Skins", "Monturas", "Equipo" },
			Requiere = "Reputación por bando",
		},
	},
	EntrenadorClase = {
		Numero = 27,
		Nombre = "Entrenador de Clase",
		Categoria = "Misiones",
		Descripcion = "Maestro de habilidades: enseña técnicas y vende libros.",
		Interfaces = { "IServiceProvider", "IVendor" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Las habilidades vienen con la clase (panel Personaje; el Chatarrero elige con K)",
		Color = CELESTE,
		Parametros = { LibrosDeTecnica = "Desbloquean habilidades extra", Requiere = "Habilidades que se aprenden" },
	},

	--------------------------------------------------------------------
	-- 6. Cosméticos, personalización y estilo
	--------------------------------------------------------------------
	Barbero = {
		Numero = 28,
		Nombre = "Barbero",
		Categoria = "Cosmeticos",
		Descripcion = "Estilista: peinado, marcas, color de piel y tatuajes.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Género del personaje (panel Personaje)",
		Color = ROSA,
		Servicios = { { Id = "Estilo", Nombre = "Cambiar de estilo", Descripcion = "Peinado y marcas.", Costo = 100 } },
		Parametros = { Requiere = "Catálogo de peinados y tatuajes (Stencils)" },
	},
	Transfigurador = {
		Numero = 29,
		Nombre = "Transfigurador",
		Categoria = "Cosmeticos",
		Descripcion = "Maestro del disfraz: cambia el aspecto del equipo sin tocar sus stats.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Apariencias (Tienda → Colección)",
		Color = ROSA,
		Servicios = {
			{ Id = "Transmog", Nombre = "Transfigurar", Descripcion = "Elegí cómo se ve cada pieza.", Costo = 0 },
		},
		Parametros = {},
	},
	Tintorero = {
		Numero = 30,
		Nombre = "Tintorero",
		Categoria = "Cosmeticos",
		Descripcion = "Maestro de colores: tintes para armaduras y telas.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = ROSA,
		Estacion = "Telar",
		Parametros = {
			Tintes = { "Negro", "Blanco", "Verde", "Dorado" },
			Exclusivos = { Rojo = "Carmesí del Reino", Azul = "Azul Real" },
			Requiere = "Personalización de color por partes",
		},
	},
	VendedorMascotas = {
		Numero = 31,
		Nombre = "Vendedor de Mascotas",
		Categoria = "Cosmeticos",
		Descripcion = "Mascotas que acompañan y juntan botín.",
		Interfaces = { "IVendor" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "Mascotas (se ganan en el Pase de batalla; Tienda → Colección)",
		Color = ROSA,
		Parametros = { Requiere = "Mascotas compradas con oro" },
	},

	--------------------------------------------------------------------
	-- 7. Vida social, casas y minijuegos
	--------------------------------------------------------------------
	Arquitecto = {
		Numero = 32,
		Nombre = "Arquitecto",
		Categoria = "Social",
		Descripcion = "Planos de casas, terrenos y decoración.",
		Interfaces = { "IVendor" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = GRIS,
		Parametros = { Vende = { "Planos", "Muebles", "Trofeos de jefes" }, Requiere = "Parcelas" },
	},
	Chef = {
		Numero = 33,
		Nombre = "Chef",
		Categoria = "Social",
		Descripcion = "Maestro culinario: ingredientes, recetas y comida con buffs largos.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = NARANJA,
		Parametros = {
			Platos = { { Nombre = "Guiso del Viajero", Efecto = "+5% vida máxima", Duracion = 1800 } },
			Requiere = "Profesión de cocina y buffs por consumible",
		},
	},
	MaestroPesca = {
		Numero = 34,
		Nombre = "Maestro de Pesca",
		Categoria = "Social",
		Descripcion = "Biólogo marino: cañas, cebos por bioma y peces raros.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = CELESTE,
		Parametros = { Cebos = { "Río", "Lago", "Mar" }, CompraPecesRaros = true, Requiere = "Pesca" },
	},
	Crupier = {
		Numero = 35,
		Nombre = "Crupier",
		Categoria = "Social",
		Descripcion = "Maestro de juegos: dados, cartas y carreras en tabernas.",
		Interfaces = { "IServiceProvider" },
		Facciones = NEUTRAL,
		Estado = "Pendiente",
		Color = Color3.fromRGB(60, 110, 70),
		Parametros = {
			Juegos = { "Dados", "Cartas", "Carreras" },
			-- Roblox no permite apuestas con nada que se compre con Robux: las
			-- recompensas tienen que ser informales (títulos, emotes), sin oro.
			Recompensas = "Solo cosméticos informales; sin apostar oro",
			Requiere = "Minijuegos",
		},
	},

	--------------------------------------------------------------------
	-- 8. PvP y guerra
	--------------------------------------------------------------------
	IntendenteGuerra = {
		Numero = 36,
		Nombre = "Intendente de Guerra",
		Categoria = "PvP",
		Descripcion = "Equipo y consumibles PvP por puntos de honor.",
		Interfaces = { "IVendor" },
		Facciones = BANDOS,
		Estado = "Listo",
		Color = BORDO,
		Vende = {
			{ ItemId = "PocionVida", Precio = 5, Moneda = "Honor" },
			{ ItemId = "PocionMana", Precio = 5, Moneda = "Honor" },
			{ ItemId = "Diamante", Precio = 150, Moneda = "Honor" },
		} :: { Oferta },
		Parametros = {
			Moneda = "PuntosHonor (se ganan en la Guerra de Arquitectos)",
			Futuro = { "Set de armadura PvP por bando" },
		},
	},
	ReclutadorArenas = {
		Numero = 37,
		Nombre = "Reclutador de Arenas",
		Categoria = "PvP",
		Descripcion = "Inscribe jugadores o grupos en partidas clasificatorias.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Pendiente",
		Color = BORDO,
		Servicios = { { Id = "Inscribir", Nombre = "Inscribirse", Descripcion = "Arena 1v1, 2v2 o 3v3.", Costo = 0 } },
		Parametros = { Modos = { "1v1", "2v2", "3v3" }, Requiere = "Arenas con emparejamiento" },
	},
	EstrategaAsedio = {
		Numero = 38,
		Nombre = "Estratega de Asedio",
		Categoria = "PvP",
		Descripcion = "Maquinaria pesada para guerras de clanes y castillos.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = BANDOS,
		Estado = "Pendiente",
		Color = BORDO,
		Estacion = "Yunque",
		Parametros = {
			Maquinas = {
				{ Nombre = "Catapulta", Materiales = { Madera = 200, Hierro = 50 } },
				{ Nombre = "Ariete", Materiales = { Madera = 150, Hierro = 30 } },
				{ Nombre = "Barril de pólvora", Materiales = { Madera = 20, NucleoObsidiana = 2 } },
			} :: { any },
			Requiere = "Asedios de castillos entre hermandades",
		},
	},
}

return {
	Arquetipos = Arquetipos,

	NombresCategoria = {
		Alquimia = "Alquimia, magia y consumibles",
		Herreria = "Herrería, equipo y forja",
		Economia = "Economía, comercio y almacenamiento",
		Viajes = "Viajes, cartografía y logística",
		Misiones = "Misiones, facciones y progresión",
		Cosmeticos = "Cosméticos, personalización y estilo",
		Social = "Vida social, casas y minijuegos",
		PvP = "PvP y guerra",
	} :: { [string]: string },

	ColoresFaccion = {
		Rojo = Color3.fromRGB(220, 60, 60),
		Azul = Color3.fromRGB(70, 120, 235),
		Neutral = Color3.fromRGB(200, 200, 210),
	} :: { [string]: Color3 },

	DistanciaInteraccion = 14, -- studs: más lejos, el servidor rechaza

	-- Guardián de Portales: costo = Base + PorNivel × nivel mínimo de la zona.
	-- El Guardián Neutral lleva a cualquier destino, pero cobra más.
	Viajes = { CostoBase = 25, CostoPorNivel = 5, FactorNeutral = 2 },

	-- Frases cuando un jugador le habla a un NPC del bando contrario.
	Rechazos = {
		"No hablo con los tuyos. Fuera de acá.",
		"¿Un enemigo en mi puesto? Andate antes de que llame a la guardia.",
		"Tu oro no sirve en este reino.",
	},

	-- NPCs que aparecen en la zona de pruebas (Studio o ModoPruebas). En los
	-- mapas reales: un Model con el tag "NpcArquetipo" y los atributos
	-- `Arquetipo` (clave de esta tabla) y `Faccion` ("Rojo" | "Azul" | "Neutral").
	DePrueba = {
		{ Arquetipo = "GuardianPortales", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 12) },
		{ Arquetipo = "GuardianPortales", Faccion = "Rojo", Posicion = Vector3.new(-25, 0, 12) },
		{ Arquetipo = "GuardianPortales", Faccion = "Azul", Posicion = Vector3.new(-35, 0, 12) },
		{ Arquetipo = "HerreroGeneral", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 12) },
		{ Arquetipo = "Boticario", Faccion = "Rojo", Posicion = Vector3.new(-15, 0, 22) },
		{ Arquetipo = "BoticarioEspiritual", Faccion = "Azul", Posicion = Vector3.new(-25, 0, 22) },
		{ Arquetipo = "ComercianteExcedentes", Faccion = "Neutral", Posicion = Vector3.new(-35, 0, 22) },
		{ Arquetipo = "AfiladorArmas", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 22) },
		{ Arquetipo = "MercadoNegro", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 32) },
		{ Arquetipo = "Subastador", Faccion = "Rojo", Posicion = Vector3.new(-25, 0, 32) },
		{ Arquetipo = "IntendenteGuerra", Faccion = "Azul", Posicion = Vector3.new(-35, 0, 32) },
		{ Arquetipo = "Banquero", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 32) },
	} :: { { Arquetipo: string, Faccion: Faccion, Posicion: Vector3 } },
}
