--!strict
-- NpcArquetiposConfig: base de datos de los 39 arquetipos de NPC, en 8
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
	-- Oferta rotativa: solo está a la venta en algunos ciclos (ver `Rotacion`
	-- del arquetipo) y cada jugador puede comprar hasta `Limite` por ciclo.
	Rotativa: boolean?,
	Limite: number?,
}

export type Servicio = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	Costo: number, -- oro
	Accion: string?, -- acción registrada en NpcManager; sin acción = todavía no disponible
	-- El costo depende del jugador (por ejemplo, reparar): lo calcula y lo cobra
	-- la propia acción, y el servidor lo informa al abrir la ventana.
	Cotiza: boolean?,
	Etiqueta: string?, -- texto del botón cuando el costo no es oro (por ejemplo, honor)
	Lote: number?, -- cantidad que mueve el servicio (Cambista)
}

-- Operación sobre un ítem de la mochila (desencantar, reforjar, engarzar).
-- `Id` es la operación de ForjaConfig y la acción registrada en NpcManager.
export type OperacionItem = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	Confirmar: boolean?, -- pide un segundo clic (operaciones que no se deshacen)
	EligeGema: boolean?, -- después de elegir el ítem hay que elegir una gema
	EligeGemaPuesta: boolean?, -- después de elegir el ítem hay que elegir cuál de sus gemas
}

export type Arquetipo = {
	Numero: number,
	Nombre: string,
	Categoria: Categoria,
	Descripcion: string,
	Interfaces: { Interfaz },
	Facciones: { Faccion },
	Estado: "Listo" | "Parcial" | "Pendiente",
	Sistema: string?,
	-- Arquetipo que absorbió a este: su oficio se atiende allá y este no
	-- aparece en el mundo. Sirve para que la matriz no mienta.
	Absorbido: string?, -- módulo o lugar del juego donde ya existe (Parcial)
	Color: Color3,
	Vende: { Oferta }?,
	Compra: { Factor: number, Tipos: { string } }?, -- paga PrecioVenta × Factor por esos tipos de ítem
	Estacion: ("Yunque" | "MesaAlquimia" | "Telar" | "Fogon")?,
	Servicios: { Servicio }?,
	Viajes: boolean?, -- Guardián de Portales
	SobreItem: { OperacionItem }?,
	-- Stock rotativo: cada `Cada` segundos cambian las `Cantidad` ofertas rotativas a la venta.
	Rotacion: { Cada: number, Cantidad: number }?,
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
		Descripcion = "Herborista dedicado: pociones de salud, regeneración, vitalidad y antídotos.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = VERDE,
		Vende = {
			{ ItemId = "PocionVida", Precio = 15 },
			{ ItemId = "PocionRegeneracion", Precio = 26 },
			{ ItemId = "Antidoto", Precio = 26 },
			{ ItemId = "PocionVitalidad", Precio = 34 },
			{ ItemId = "HierbaSanadora", Precio = 6 },
		},
		Estacion = "MesaAlquimia",
		Parametros = {
			Recurso = "Vida",
			Recetas = "Alquimia, niveles 1 a 4 (ProfesionesConfig)",
			Efectos = "ConsumiblesConfig: instantáneos, comparten la recarga de las pociones",
		},
	},
	BoticarioEspiritual = {
		Numero = 2,
		Nombre = "Boticario Espiritual",
		Categoria = "Alquimia",
		Descripcion = "Místico: maná, energía, enfoque y reducción de recargas.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = CELESTE,
		Vende = {
			{ ItemId = "PocionMana", Precio = 15 },
			{ ItemId = "TonicoEnergia", Precio = 30 },
			{ ItemId = "TonicoEnfoque", Precio = 40 },
			{ ItemId = "FlorLunar", Precio = 9 },
		},
		Estacion = "MesaAlquimia",
		Parametros = {
			Recursos = "Maná o Stamina, según la clase",
			Acumulacion = "Un tónico activo a la vez; se suma a elixires e infusiones",
		},
	},
	AlquimistaExperimental = {
		Numero = 3,
		Nombre = "Alquimista Experimental",
		Categoria = "Alquimia",
		Descripcion = "Elixires temporales de atributos y pociones de riesgo y recompensa.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = Color3.fromRGB(120, 60, 150),
		Vende = {
			{ ItemId = "ElixirFuerza", Precio = 60 },
			{ ItemId = "ElixirAgilidad", Precio = 60 },
			{ ItemId = "ElixirResistencia", Precio = 60 },
			{ ItemId = "PocionExperimental", Precio = 50 },
			{ ItemId = "MezclaInestable", Precio = 75 },
		},
		Estacion = "MesaAlquimia",
		Parametros = {
			Acumulacion = "Un elixir activo a la vez; tomar otro lo reemplaza",
			Riesgo = "Poción Experimental: 65% bueno, 35% malo (se sortea en el servidor; figura en el ítem)",
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
		Estado = "Listo",
		Color = Color3.fromRGB(170, 150, 110),
		Estacion = "Telar",
		Vende = {
			{ ItemId = "PergaminoRegreso", Precio = 120 },
			{ ItemId = "PergaminoReunion", Precio = 160 },
			{ ItemId = "PergaminoFortaleza", Precio = 220 },
			{ ItemId = "LibroRunas", Precio = 1500 },
			{ ItemId = "LibroHeraldica", Precio = 1500 },
			{ ItemId = "LibroBestias", Precio = 1500 },
		} :: { Oferta },
		Servicios = {} :: { Servicio },
		Parametros = {
			Pergaminos = { "Regreso a tu capital", "Fortaleza al grupo (10 min)", "Reunión con tu líder" },
			Libros = "Los tres libros de stencils del personalizador",
			Graba = "Las calcomanías se aplican en el NPC Cosméticos (#30); acá se compran los libros",
			Donde = "Se usan desde la mochila; no andan en combate, Guerra, arena ni mazmorra",
			Fabricar = "También se hacen en el Telar con tela de lino y flor lunar",
			Futuro = { "Ítems sin identificar y el mapa que los revela" },
		},
	},
	BaristaTes = {
		Numero = 6,
		Nombre = "Barista de Tés",
		Categoria = "Alquimia",
		Descripcion = "Maestro infusor: tés de larga duración para maná, defensa y recargas.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = Color3.fromRGB(150, 110, 70),
		Vende = {
			{ ItemId = "TeManantial", Precio = 22 },
			{ ItemId = "TeRaices", Precio = 22 },
			{ ItemId = "TeJazminLunar", Precio = 30 },
			{ ItemId = "AguaManantial", Precio = 4 },
		},
		Estacion = "MesaAlquimia",
		Parametros = {
			Acumulacion = "Una infusión activa a la vez; dura 15 minutos y se suma a elixires y tónicos",
			Futuro = { "Recetas raras por bioma", "Resistencia a estados negativos (hoy: +defensa)" },
		},
	},

	--------------------------------------------------------------------
	-- 2. Herrería, equipo y forja
	--------------------------------------------------------------------
	HerreroGeneral = {
		Numero = 7,
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
		Numero = 8,
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
			Buff = "ConsumiblesConfig.Definiciones.ServicioAfilar (categoría Filo)",
			Futuro = { "Precisión", "Penetración de armadura", "Pago con piedras de afilar" },
		},
	},
	ReparadorArmaduras = {
		Numero = 9,
		Nombre = "Reparador de Armaduras",
		Categoria = "Herreria",
		Descripcion = "Remendador: restaura la durabilidad del equipo.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = MARRON,
		Servicios = {
			{
				Id = "RepararEquipado",
				Nombre = "Reparar lo equipado",
				Descripcion = "Deja enteras las piezas que llevás puestas.",
				Costo = 0,
				Accion = "RepararEquipado",
				Cotiza = true,
			},
			{
				Id = "RepararTodo",
				Nombre = "Reparar todo",
				Descripcion = "Lo equipado y lo que tenés en la mochila.",
				Costo = 0,
				Accion = "RepararTodo",
				Cotiza = true,
			},
		},
		Parametros = {
			Reglas = "ForjaConfig.Durabilidad: costo por punto según la rareza; no se repara en combate",
			Futuro = { "Tarifa de emergencia dentro de mazmorras (x3)" },
		},
	},
	MaestroEncantador = {
		Numero = 10,
		Nombre = "Maestro Encantador",
		Categoria = "Herreria",
		Descripcion = "Engarza gemas en el equipo, y las saca si te arrepentís (cobrando bien).",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = Color3.fromRGB(150, 80, 200),
		SobreItem = {
			{
				Id = "Engarzar",
				Nombre = "Engarzar gema",
				Descripcion = "300 de oro, 1 Esencia Mágica y la gema.",
				EligeGema = true,
			},
			{
				Id = "Extraer",
				Nombre = "Sacar gema",
				Descripcion = "Devuelve la gema entera a la mochila. Cuesta más que ponerla: 400 a 3.500 de oro según la rareza, más 1 Polvo de Encantamiento.",
				EligeGemaPuesta = true,
				Confirmar = true,
			},
		} :: { OperacionItem },
		Parametros = {
			Reglas = "ForjaConfig.Engarzar: ranuras por rareza (Raro 1, Épico 2, Místico 2, Único 3). ForjaConfig.Extraer: sacar cuesta más que engarzar",
			Futuro = { "Runas con brillo" },
		},
	},
	Desencantador = {
		Numero = 11,
		Nombre = "Desencantador",
		Categoria = "Herreria",
		Descripcion = "Desmantelador: destruye equipo mágico para sacar esencias.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = Color3.fromRGB(100, 70, 130),
		SobreItem = {
			{
				Id = "Desencantar",
				Nombre = "Desencantar",
				Descripcion = "25 de oro. Destruye el equipo (Raro o mejor) y devuelve esencias según su rareza. No se deshace.",
				Confirmar = true,
			},
		},
		Parametros = {
			Reglas = "ForjaConfig.Desencantar.Resultado; solo ítems de la mochila (lo equipado no se toca)",
			Nota = "El equipo Común lo desmantela el Chatarrero en su Yunque Portátil",
		},
	},
	ReforjadorAtributos = {
		Numero = 12,
		Nombre = "Reforjador de Atributos",
		Categoria = "Herreria",
		Descripcion = "Cambia los efectos secundarios de un equipo. Conserva su calidad, pasiva y gemas.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = NARANJA,
		SobreItem = {
			{
				Id = "Reforjar",
				Nombre = "Reforjar",
				Descripcion = "Oro según la rareza (sube 25% con cada reforja) y 2 Polvo de Encantamiento. Salen efectos distintos.",
				Confirmar = true,
			},
		},
		Parametros = {
			Reglas = "ForjaConfig.Reforjar: 500 / 1.500 / 4.000 / 10.000 de oro",
			Futuro = { "Elegir qué efecto reemplazar", "Vista previa antes de confirmar" },
			Relacionado = "La Ficha de Re-roll de la tienda vuelve a tirar los valores; esto cambia cuáles son",
		},
	},
	Fundidor = {
		Numero = 13,
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
			Transmutacion = { De = "Hierro", A = "LingotePlata", Proporcion = 5, Receta = "TransmutarPlata" },
		},
	},

	--------------------------------------------------------------------
	-- 3. Economía, comercio y almacenamiento
	--------------------------------------------------------------------
	Banquero = {
		Numero = 14,
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
		Numero = 15,
		Nombre = "Banquero de Clan",
		Categoria = "Economia",
		Descripcion = "Tesorero: inventario y fondos de la hermandad.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = ORO,
		Servicios = {
			{
				Id = "BancoClan",
				Nombre = "Banco de la hermandad",
				Descripcion = "Oro y 4 pestañas de ítems, con permisos por rango y registro de movimientos.",
				Costo = 0,
				Accion = "BancoClan",
			},
		},
		Parametros = {
			Pestanas = 4,
			RanurasPorPestana = 28,
			Sistema = "HermandadManager (permisos por rango, registro y candado entre servidores)",
			Futuro = { "Límite diario de retiro por rango", "Exigir estar junto al NPC para operar" },
		},
	},
	Subastador = {
		Numero = 16,
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
			Futuro = { "Pujas con reserva de fondos y devolución al superado", "Filtro por nivel" },
		},
	},
	ComercianteExcedentes = {
		Numero = 17,
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
		Numero = 18,
		Nombre = "Cambista",
		Categoria = "Economia",
		Descripcion = "Cambia puntos de honor por oro. No hace préstamos.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = ORO,
		Servicios = {
			{
				Id = "Cambiar10",
				Nombre = "Cambiar 10 de honor",
				Descripcion = "Recibís 5 de oro.",
				Costo = 0,
				Accion = "CambiarHonor",
				Cotiza = true,
				Etiqueta = "10 honor",
				Lote = 10,
			},
			{
				Id = "Cambiar100",
				Nombre = "Cambiar 100 de honor",
				Descripcion = "Recibís 50 de oro.",
				Costo = 0,
				Accion = "CambiarHonor",
				Cotiza = true,
				Etiqueta = "100 honor",
				Lote = 100,
			},
			{
				Id = "Cambiar1000",
				Nombre = "Cambiar 1.000 de honor",
				Descripcion = "Recibís 500 de oro.",
				Costo = 0,
				Accion = "CambiarHonor",
				Cotiza = true,
				Etiqueta = "1.000 honor",
				Lote = 1000,
			},
		},
		Parametros = {
			Tasa = "NpcArquetiposConfig.Cambio.OroPorHonor",
			-- El juego usa una sola moneda (oro): Bronce / Plata / Oro sería solo
			-- una forma de mostrarla.
			Futuro = { "Divisas de evento", "Mostrar el oro como Bronce / Plata / Oro" },
		},
	},
	MercadoNegro = {
		Numero = 19,
		Nombre = "Vendedor del Mercado Negro",
		Categoria = "Economia",
		Descripcion = "Rarezas con stock limitado que cambia cada 6 horas, para cualquiera.",
		Interfaces = { "IVendor" },
		Facciones = NEUTRAL,
		Estado = "Listo",
		Color = Color3.fromRGB(60, 50, 70),
		Vende = {
			{ ItemId = "SedaArana", Precio = 80 },
			{ ItemId = "Amatista", Precio = 90, Rotativa = true, Limite = 3 },
			{ ItemId = "Esmeralda", Precio = 130, Rotativa = true, Limite = 3 },
			{ ItemId = "Zafiro", Precio = 150, Rotativa = true, Limite = 3 },
			{ ItemId = "Rubi", Precio = 170, Rotativa = true, Limite = 3 },
			{ ItemId = "Diamante", Precio = 420, Rotativa = true, Limite = 1 },
			{ ItemId = "PolvoEncantamiento", Precio = 45, Rotativa = true, Limite = 6 },
			{ ItemId = "EsenciaMagica", Precio = 140, Rotativa = true, Limite = 2 },
			{ ItemId = "NucleoObsidiana", Precio = 160, Rotativa = true, Limite = 2 },
		},
		Rotacion = { Cada = 21600, Cantidad = 3 },
		Parametros = {
			Ubicacion = "Zonas neutrales o tabernas libres",
			Stock = "Límite por jugador y por ciclo (no un stock compartido entre servidores)",
			Futuro = { "Requisito de reputación", "Recetas exclusivas", "Cosméticos raros" },
		},
	},

	--------------------------------------------------------------------
	-- 4. Viajes, cartografía y logística
	--------------------------------------------------------------------
	GuardianPortales = {
		Numero = 20,
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
		Numero = 21,
		Nombre = "Maestro de Establo",
		Categoria = "Viajes",
		Descripcion = "Criador: vende monturas, las alquila por hora y las entrena.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = MARRON,
		Servicios = {
			{
				Id = "ComprarCorcel",
				Nombre = "Comprar el Corcel de Guerra",
				Descripcion = "Más rápido que el caballo. Tuyo para siempre. Nivel 5.",
				Costo = 1500,
				Accion = "ComprarMonturaCorcel",
			},
			{
				Id = "ComprarLobo",
				Nombre = "Comprar el Lobo de las Nieves",
				Descripcion = "La montura más rápida que se compra con oro. Nivel 12.",
				Costo = 6000,
				Accion = "ComprarMonturaLobo",
			},
			{
				Id = "Alquilar",
				Nombre = "Alquilar un corcel por una hora",
				Descripcion = "Para salir ya, sin comprarlo.",
				Costo = 150,
				Accion = "AlquilarMontura",
			},
			{
				Id = "Entrenar",
				Nombre = "Entrenar velocidad",
				Descripcion = "+2% a todas tus monturas, hasta +10%. Cada sesión sale más cara.",
				Costo = 0,
				Accion = "EntrenarMontura",
				Cotiza = true,
			},
		},
		Parametros = {
			Monturas = "MonetizacionConfig.Monturas con Precio; alquiler y entrenamiento en MonetizacionConfig.Establo",
			Futuro = { "Alimentar monturas", "Restricciones de montura por zona" },
		},
	},
	Navegante = {
		Numero = 22,
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
		Numero = 23,
		Nombre = "Cartógrafo",
		Categoria = "Viajes",
		Descripcion = "Explorador: marca en tu mapa los puntos de interés de la zona.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = VERDE,
		Servicios = {
			{
				Id = "RevelarPOI",
				Nombre = "Comprar el mapa de la zona",
				Descripcion = "Marca en tu mapa del mundo todo lo que haya para ver por acá.",
				Costo = 0,
				Accion = "RevelarPOI",
				Cotiza = true,
			},
		},
		Parametros = {
			Puntos = "ExploracionConfig.Interes (también se descubren caminando cerca)",
			Futuro = { "Mapas de otras zonas", "Coleccionables de exploración" },
		},
	},
	GuardianPiedraTeleport = {
		Numero = 24,
		Nombre = "Guardián de Piedra Teleport",
		Categoria = "Viajes",
		Descripcion = "Portalero: te explica las piedras de viaje rápido y activa la de acá.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = Color3.fromRGB(90, 160, 200),
		Servicios = {
			{
				Id = "ActivarPiedra",
				Nombre = "Activar la piedra cercana",
				Descripcion = "Las piedras activadas quedan para siempre; viajar entre ellas cuesta oro.",
				Costo = 0,
				Accion = "ActivarPiedra",
			},
		},
		Parametros = {
			Piedras = "ExploracionConfig.Piedras (se activan tocándolas; el NPC activa la más cercana)",
			Futuro = { "Costo en cristales en lugar de oro" },
		},
	},

	--------------------------------------------------------------------
	-- 5. Misiones, facciones y progresión
	--------------------------------------------------------------------
	Tabernero = {
		Numero = 25,
		Nombre = "Tabernero",
		Categoria = "Misiones",
		Descripcion = "Informante: alquila habitación para descansar y cuenta rumores.",
		Interfaces = { "IServiceProvider", "IQuestGiver" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = MARRON,
		Servicios = {
			{
				Id = "Descansar",
				Nombre = "Alquilar una habitación",
				Descripcion = "Tu próxima experiencia rinde un 50% más, hasta agotar el descanso.",
				Costo = 50,
				Accion = "Descansar",
			},
			{
				Id = "Rumores",
				Nombre = "Preguntar por rumores",
				Descripcion = "Si hay un jefe de mundo suelto, te dice dónde.",
				Costo = 10,
				Accion = "Rumores",
			},
		},
		Parametros = {
			Descanso = "ProgresionSocialConfig.Descanso: 2.000 de saldo por habitación, tope 12.000",
			Misiones = "Las misiones secundarias las dan los NPC de misiones (MisionManager)",
		},
	},
	TablonAnuncios = {
		Numero = 26,
		Nombre = "Tablón de Anuncios",
		Categoria = "Misiones",
		Descripcion = "Cazador de recompensas: contratos diarios.",
		Interfaces = { "IQuestGiver" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "El Tablón de Anuncios de las misiones (3 contratos diarios; hablale a él, no a este NPC)",
		Color = MARRON,
		Parametros = {
			Diarias = "5 contratos, hasta 3 por día, reinicio a las 19:00 UTC (16:00 en Argentina)",
			Recompensa = "El doble que una misión normal del mismo tamaño",
			Futuro = { "Contratos de PvP", "Contratos semanales" },
		},
	},
	EmisarioFaccion = {
		Numero = 27,
		Nombre = "Emisario de Facción",
		Categoria = "Misiones",
		Descripcion = "Intendente: títulos y materiales por reputación con tu bando.",
		Interfaces = { "IVendor" },
		Facciones = BANDOS,
		Estado = "Listo",
		Color = BORDO,
		Servicios = {
			{
				Id = "Emisario",
				Nombre = "Ver recompensas de facción",
				Descripcion = "Se pagan con puntos de honor y piden reputación.",
				Costo = 0,
				Accion = "Emisario",
			},
		},
		Parametros = {
			Niveles = "Neutral, Amistoso, Honorable, Reverenciado, Exaltado (ProgresionSocialConfig)",
			Reputacion = "Se gana en la Guerra de Arquitectos y derrotando rivales (tope diario 1.500)",
			Futuro = { "Monturas y equipo exclusivo por reputación" },
		},
	},
	EntrenadorClase = {
		Numero = 28,
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
		Numero = 29,
		Nombre = "Barbero",
		Categoria = "Cosmeticos",
		Descripcion = "Estilista: color de piel, peinado y marcas faciales.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = ROSA,
		Servicios = {
			{
				Id = "Barbero",
				Nombre = "Cambiar de estilo",
				Descripcion = "100 de oro por cambio. Vista previa antes de confirmar.",
				Costo = 0,
				Accion = "Barbero",
			},
		},
		Parametros = {
			Pieles = "9 colores de piel (funcionan hoy)",
			Pendiente = "Peinados y marcas: hay que subir los accesorios al Catálogo y poner su id en AparienciaConfig.Barbero",
		},
	},
	Transfigurador = {
		Numero = 30,
		Nombre = "Cosméticos",
		Categoria = "Cosmeticos",
		Descripcion = "Todo el aspecto de lo que tenés puesto: visual, colores, decals y marcas.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Sistema = "CosmeticosManager (absorbió al Tintorero #31 y el grabado del Inscriptor #5)",
		Color = ROSA,
		Servicios = {
			{
				Id = "Cosmeticos",
				Nombre = "Cambiar el aspecto de mi equipo",
				Descripcion = "Visual, colores, decals y marcas, con vista previa de tu personaje.",
				Costo = 0,
				Accion = "Cosmeticos",
			},
			{
				Id = "Coleccion",
				Nombre = "Ver mi colección",
				Descripcion = "Apariencias, mascotas y títulos que tenés desbloqueados.",
				Costo = 0,
				Accion = "Coleccion",
			},
		} :: { Servicio },
		Parametros = {
			Pestanas = { "Visual", "Colores", "Decals", "Marcas" },
			Cobro = "Aplicar es gratis; deshacer sube en potencias de dos (CosmeticosConfig)",
			Alcance = "Los ítems equipados en los slots visibles",
		},
	},
	Tintorero = {
		Numero = 31,
		Nombre = "Tintorero",
		Categoria = "Cosmeticos",
		Descripcion = "Maestro de colores. Su oficio ahora lo atiende el NPC Cosméticos (#30).",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = ROSA,
		-- Absorbido por el NPC Cosméticos (#30): su oficio vive ahí, en la
		-- pestaña de colores, junto con el resto de la estética.
		Absorbido = "Transfigurador",
		Servicios = {} :: { Servicio },
		Parametros = {
			Como = "Abre el probador en modo retoque: solo colores, se paga por pieza que cambia",
			Precio = "PersonalizadorConfig.CostoRetoque por pieza que cambia",
			Nota = "Para cambiar materiales, el Maestro Personalizador",
		},
	},
	VendedorMascotas = {
		Numero = 32,
		Nombre = "Vendedor de Mascotas",
		Categoria = "Cosmeticos",
		Descripcion = "Mascotas que te acompañan y juntan el botín.",
		Interfaces = { "IVendor" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = ROSA,
		Servicios = {
			{
				Id = "Hojita",
				Nombre = "Comprar a Hojita",
				Descripcion = "Un brote travieso. Junta el botín como todas las mascotas.",
				Costo = 2500,
				Accion = "ComprarMascotaHojita",
			},
			{
				Id = "Piedrin",
				Nombre = "Comprar a Piedrín",
				Descripcion = "Un pedacito de montaña con ganas de pasear.",
				Costo = 4000,
				Accion = "ComprarMascotaPiedrin",
			},
			{
				Id = "Lucero",
				Nombre = "Comprar a Lucero",
				Descripcion = "Una estrella caída que ilumina el camino.",
				Costo = 9000,
				Accion = "ComprarMascotaLucero",
			},
			{
				Id = "Equipar",
				Nombre = "Ver mis mascotas",
				Descripcion = "Elegí cuál te acompaña.",
				Costo = 0,
				Accion = "Coleccion",
			},
		},
		Parametros = { Mascotas = "MascotasConfig.Mascotas con Precio; Lumi y Brasa siguen siendo del pase de batalla" },
	},

	--------------------------------------------------------------------
	-- 7. Vida social, casas y minijuegos
	--------------------------------------------------------------------
	Arquitecto = {
		Numero = 33,
		Nombre = "Arquitecto de Viviendas",
		Categoria = "Social",
		Descripcion = "Vende, alquila y registra las parcelas del barrio.",
		Interfaces = { "IVendor", "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Parcial",
		Sistema = "ParcelaManager y ConstruccionManager; falta la subasta con pujas",
		Vende = {
			{ ItemId = "SemillaHierba", Precio = 8 },
			{ ItemId = "SemillaCocina", Precio = 12 },
			{ ItemId = "SemillaLino", Precio = 15 },
			{ ItemId = "SemillaLunar", Precio = 25 },
		} :: { Oferta },
		Color = GRIS,
		Servicios = {
			{
				Id = "ParcelasAbrir",
				Nombre = "Ver las parcelas",
				Descripcion = "Comprar, pagar el alquiler, dar permisos y fusionar.",
				Costo = 0,
				Accion = "ParcelasAbrir",
			},
			{
				Id = "ParcelasConstruir",
				Nombre = "Construir en mi parcela",
				Descripcion = "Muebles, paredes, canteros y patio de mascotas.",
				Costo = 0,
				Accion = "ParcelasConstruir",
			},
		} :: { Servicio },
		Parametros = {
			Barrios = { "Barrio Norte", "La Ribera", "Claro del Bosque" },
			Alquiler = "150 de oro por día; 7 días vienen con la compra",
			Construccion = "10 piezas, hasta 40 por parcela; huerta con 4 cultivos",
			Falta = { "Subasta con pujas", "Alquilar entre jugadores" },
		},
	},
	Chef = {
		Numero = 34,
		Nombre = "Chef",
		Categoria = "Social",
		Descripcion = "Maestro culinario: ingredientes y comidas que duran 20 minutos.",
		Interfaces = { "IVendor", "ICrafter" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = NARANJA,
		Estacion = "Fogon",
		Vende = {
			{ ItemId = "Sal", Precio = 3 },
			{ ItemId = "HierbasCocina", Precio = 6 },
			{ ItemId = "AguaManantial", Precio = 3 },
		} :: { Oferta },
		Parametros = {
			Profesion = "Cocina (ProfesionesConfig)",
			Comidas = "Una comida activa a la vez, 20 minutos",
			Fogon = 'Part con tag EstacionCrafteo y atributo Estacion = "Fogon"',
		},
	},
	MaestroPesca = {
		Numero = 35,
		Nombre = "Maestro de Pesca",
		Categoria = "Social",
		Descripcion = "Vende la caña, compra lo que pesques y te dice dónde pican.",
		Interfaces = { "IVendor", "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = CELESTE,
		Vende = { { ItemId = "CanaPescar", Precio = 30 } } :: { Oferta },
		Compra = { Factor = 1.2, Tipos = { "Material" } },
		Servicios = {
			{
				Id = "DondePescar",
				Nombre = "¿Dónde pican hoy?",
				Descripcion = "Te dice qué orillas hay cerca y qué nivel piden.",
				Costo = 0,
				Accion = "DondePescar",
			},
		} :: { Servicio },
		Parametros = {
			Profesion = "Pesca (ProfesionesConfig.Nodos)",
			Paga = "20% más que el Comerciante por los materiales (incluye peces)",
			Futuro = { "Cebos por bioma", "Peces raros por temporada" },
		},
	},
	Crupier = {
		Numero = 36,
		Nombre = "Crupier",
		Categoria = "Social",
		Descripcion = "Maestro de juegos: dados, cartas y carreras en tabernas.",
		Interfaces = { "IServiceProvider" },
		Facciones = NEUTRAL,
		Estado = "Listo",
		Color = Color3.fromRGB(60, 110, 70),
		Servicios = {
			{
				Id = "JuegoRunas",
				Nombre = "Memoria de Runas",
				Descripcion = "Repetí la secuencia; cada ronda agrega una runa.",
				Costo = 0,
				Accion = "JuegoRunas",
			},
			{
				Id = "JuegoPares",
				Nombre = "Encontrá los Pares",
				Descripcion = "16 cartas, 8 pares, 16 intentos.",
				Costo = 0,
				Accion = "JuegoPares",
			},
		} :: { Servicio },
		Parametros = {
			Juegos = { "Memoria de Runas", "Encontrá los Pares" },
			-- Roblox no permite apuestas con nada que se compre con Robux: las
			-- recompensas tienen que ser informales (títulos, emotes), sin oro.
			Recompensas = "Títulos y récord personal; no se apuesta ni se paga oro",
			Futuro = { "Carreras en la taberna", "Tablero de récords del servidor" },
		},
	},

	--------------------------------------------------------------------
	-- 8. PvP y guerra
	--------------------------------------------------------------------
	IntendenteGuerra = {
		Numero = 37,
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
		Numero = 38,
		Nombre = "Reclutador de Arenas",
		Categoria = "PvP",
		Descripcion = "Inscribe jugadores o grupos en partidas clasificatorias.",
		Interfaces = { "IServiceProvider" },
		Facciones = TODAS,
		Estado = "Listo",
		Color = BORDO,
		Servicios = {
			{
				Id = "Arena1v1",
				Nombre = "Anotarme en 1v1",
				Descripcion = "Duelo a tres rondas. Gana el que gane dos.",
				Costo = 0,
				Accion = "Arena1v1",
			},
			{
				Id = "Arena2v2",
				Nombre = "Anotarme en 2v2",
				Descripcion = "De a dos. Con grupo de 2, entra el grupo entero.",
				Costo = 0,
				Accion = "Arena2v2",
			},
			{
				Id = "Arena3v3",
				Nombre = "Anotarme en 3v3",
				Descripcion = "De a tres. Con grupo de 3, entra el grupo entero.",
				Costo = 0,
				Accion = "Arena3v3",
			},
			{
				Id = "ArenaCancelar",
				Nombre = "Sacarme de la cola",
				Descripcion = "Deja de buscar rivales.",
				Costo = 0,
				Accion = "ArenaCancelar",
			},
		} :: { Servicio },
		Parametros = {
			Modos = { "1v1", "2v2", "3v3" },
			Rating = "Elo por modo, arranca en 1000",
			Premio = "Honor por partida con tope diario",
		},
	},
	EstrategaAsedio = {
		Numero = 39,
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

	-- Cambista: oro que da por cada punto de honor. Es de una sola vía (no vende
	-- honor) y está por debajo de lo que rinde gastar el honor en el Intendente
	-- y revender, así que no abre ningún circuito de ganancia.
	Cambio = { OroPorHonor = 0.5 },

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
		{ Arquetipo = "AlquimistaExperimental", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 42) },
		{ Arquetipo = "BaristaTes", Faccion = "Neutral", Posicion = Vector3.new(-25, 0, 42) },
		{ Arquetipo = "ReparadorArmaduras", Faccion = "Neutral", Posicion = Vector3.new(-35, 0, 42) },
		{ Arquetipo = "Desencantador", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 42) },
		{ Arquetipo = "ReforjadorAtributos", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 52) },
		{ Arquetipo = "MaestroEncantador", Faccion = "Neutral", Posicion = Vector3.new(-25, 0, 52) },
		{ Arquetipo = "Fundidor", Faccion = "Neutral", Posicion = Vector3.new(-35, 0, 52) },
		{ Arquetipo = "BanqueroClan", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 52) },
		{ Arquetipo = "Prestamista", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 62) },
		{ Arquetipo = "Cartografo", Faccion = "Neutral", Posicion = Vector3.new(-25, 0, 62) },
		{ Arquetipo = "GuardianPiedraTeleport", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 62) },
		{ Arquetipo = "MaestroEstablo", Faccion = "Neutral", Posicion = Vector3.new(-35, 0, 72) },
		{ Arquetipo = "Tabernero", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 72) },
		{ Arquetipo = "EmisarioFaccion", Faccion = "Rojo", Posicion = Vector3.new(-25, 0, 72) },
		{ Arquetipo = "EmisarioFaccion", Faccion = "Azul", Posicion = Vector3.new(-45, 0, 72) },
		{ Arquetipo = "Barbero", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 82) },
		{ Arquetipo = "Transfigurador", Faccion = "Neutral", Posicion = Vector3.new(-25, 0, 82) },
		{ Arquetipo = "VendedorMascotas", Faccion = "Neutral", Posicion = Vector3.new(-35, 0, 82) },
		{ Arquetipo = "Transfigurador", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 82) },
		{ Arquetipo = "ReclutadorArenas", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 92) },
		{ Arquetipo = "Chef", Faccion = "Neutral", Posicion = Vector3.new(-30, 0, 92) },
		{ Arquetipo = "MaestroPesca", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 92) },
		{ Arquetipo = "Crupier", Faccion = "Neutral", Posicion = Vector3.new(-15, 0, 102) },
		{ Arquetipo = "Arquitecto", Faccion = "Neutral", Posicion = Vector3.new(-30, 0, 102) },
		{ Arquetipo = "Inscriptor", Faccion = "Neutral", Posicion = Vector3.new(-45, 0, 102) },
	} :: { { Arquetipo: string, Faccion: Faccion, Posicion: Vector3 } },
}
