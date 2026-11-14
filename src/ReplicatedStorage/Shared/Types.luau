--!strict
-- Types: tipos compartidos entre cliente y servidor.
-- Todo lo que cruza la red o se guarda en el perfil se define acá, así ambos lados coinciden.

export type Rareza = "Comun" | "Raro" | "Epico" | "Mistico" | "Unico"

export type Clase =
	"SinClase"
	| "Tanque"
	| "Guerrero"
	| "Mago"
	| "Arquero"
	| "Asesino"
	| "Healer"
	| "Druida"
	| "Buffer"
	| "Chatarrero"

export type SkinEstructura = "Ninguna" | "Gotica" | "Hielo" | "Jade"

export type SlotEquipo =
	"Casco"
	| "Pechera"
	| "ArmaPrincipal"
	| "ArmaSecundaria"
	| "Accesorio1"
	| "Accesorio2"
	| "Herramienta"

export type Profesion = "Herreria" | "Alquimia" | "Sastreria" | "Mineria" | "Herboristeria"

export type ProgresoProfesion = { Nivel: number, Xp: number }

-- Metadatos de un ítem único (durabilidad, encantamientos, stats rolleados...).
-- Solo valores JSON simples: nada de Instances, Vector3 o Color3.
export type ItemMeta = { [string]: string | number | boolean }

-- Una instancia concreta de un ítem en el inventario o equipada.
export type ItemInstancia = {
	Uid: string, -- identificador único de esta copia (GUID)
	ItemId: string, -- referencia al ItemCatalog
	Cantidad: number,
	Rareza: Rareza, -- la rareza vive en el ítem, no en el jugador
	Meta: ItemMeta?,
}

export type Estadisticas = {
	VidaActual: number,
	ManaActual: number,
	Fuerza: number,
	Agilidad: number,
	Inteligencia: number,
}

export type Inventario = {
	MaxSlots: number,
	-- Las ranuras se indexan con texto ("1".."MaxSlots") para que no haya
	-- huecos de array: JSON corta un array en el primer nil.
	Slots: { [string]: ItemInstancia },
}

-- Bóveda global: pestañas "1".."8", cada una con ranuras "1".."30".
export type PestanaVault = { Nombre: string, Icono: string, Slots: { [string]: ItemInstancia } }
export type Vault = { Compradas: number, Pestanas: { [string]: PestanaVault } }

export type Equipamiento = {
	Casco: ItemInstancia?,
	Pechera: ItemInstancia?,
	ArmaPrincipal: ItemInstancia?,
	ArmaSecundaria: ItemInstancia?,
	Accesorio1: ItemInstancia?,
	Accesorio2: ItemInstancia?,
	Herramienta: ItemInstancia?, -- pico, hoz... (no suma stats de combate)
}

export type ProgresoMision = {
	AceptadaEn: number, -- os.time() al aceptarla
	Objetivos: { [string]: number }, -- objetivoId -> progreso actual
}

-- v4: bandos. Violeta es neutral (no se lo puede atacar); Rojo y Azul pelean
-- entre sí en zonas PvP y en la Guerra de Arquitectos.
export type Bando = "Violeta" | "Rojo" | "Azul"
export type Genero = "Avatar" | "Masculino" | "Femenino"
export type CanalVoz = "Proximidad" | "Grupo" | "Hermandad" | "Zona"

export type Ajustes = {
	Genero: Genero, -- "Avatar" = tal cual el avatar de Roblox del jugador
	ChatPosicion: "Izquierda" | "Derecha",
	ChatTamano: "Chico" | "Normal" | "Grande",
	ChatVisible: boolean,
	CanalVoz: CanalVoz?, -- sin valor = "Proximidad"
	-- Ventana de chat propia: posición y tamaño en fracción de la pantalla.
	ChatX: number?,
	ChatY: number?,
	ChatAncho: number?,
	ChatAlto: number?,
	-- Fase 7: interfaz.
	Zurdo: boolean?, -- espeja el HUD
	EscalaUI: number?, -- 0.75 a 1.3 (sin valor = 1)
	TextosCombate: boolean?, -- números flotantes (sin valor = sí)
	Minimapa: boolean?, -- sin valor = sí
	IgnorarGuerra: boolean?, -- no participa ni ve la Guerra de Arquitectos
}

-- v5: diario de operaciones de subasta en curso. Se escribe en el mismo
-- instante en que sale el ítem o el oro del perfil, así un guardado nunca deja
-- el perfil "sin el ítem" y sin rastro de adónde fue. Al entrar se reconcilia
-- contra la subasta (DataStore) y se cierra o se devuelve.
export type PendienteSubasta = { Item: ItemInstancia, Deposito: number, Creado: number }
export type PendienteCompra = { Precio: number, Creado: number }
-- Diario del banco de hermandad (opcional: perfiles viejos no lo tienen).
export type PendienteBanco = {
	Gid: string,
	Tipo: "DepositoItem" | "RetiroItem" | "DepositoOro" | "RetiroOro",
	Item: ItemInstancia?, -- DepositoItem: lo que salió de la mochila
	Oro: number?,
	Creado: number,
}
export type Pendientes = {
	Subastas: { [string]: PendienteSubasta },
	Compras: { [string]: PendienteCompra },
	Banco: { [string]: PendienteBanco }?,
}

export type DatosJugador = {
	Version: number,
	Nivel: number,
	Experiencia: number,
	Clase: Clase,
	Faccion: Bando,
	Estadisticas: Estadisticas,
	Oro: number,
	-- Moneda premium comprada con Robux. Solo la modifica MonetizationManager
	-- desde ProcessReceipt o un gasto validado por el servidor.
	MonedasPremium: number,
	Inventario: Inventario,
	Equipamiento: Equipamiento,
	MisionesActivas: { [string]: ProgresoMision },
	MisionesCompletadas: { [string]: number }, -- questId -> os.time() de entrega
	-- Últimos PurchaseId procesados (idempotencia de DevProducts). Lista acotada.
	RecibosProcesados: { string },
	-- Últimos Id de mensajes del buzón ya entregados (evita pagar dos veces).
	MensajesProcesados: { string },
	-- v2: Guerra de Arquitectos y cosméticos
	PuntosHonor: number,
	Titulos: { string },
	TituloEquipado: string?,
	TituloPersonalizado: string?, -- pase "Título Personalizado" (texto ya filtrado)
	-- Fase 6.2 (opcionales: perfiles viejos no los tienen)
	BoosterXpHasta: number?, -- os.time() hasta cuando dura el 2× de experiencia
	Fichas: { [string]: number }?, -- "Reroll", "Bando"
	PackInicio: boolean?, -- ya compró el Pack de Inicio
	-- Fase 6.3 (opcionales)
	PaseBatalla: { Temporada: string, Xp: number, Gratis: { [string]: boolean }, Premium: { [string]: boolean } }?,
	Mascotas: { string }?, -- mascotas obtenidas
	MascotaEquipada: string?,
	Apariencias: { string }?, -- apariencias (transmog) obtenidas
	Transmog: { [string]: string }?, -- slot de equipo -> apariencia que se muestra
	-- Chatarrero: ids de las habilidades equipadas en sus barras (hasta 16) y
	-- recargas largas en curso (id -> hora del servidor en que quedan listas).
	Barras: { string }?,
	CooldownsLargos: { [string]: number }?,
	CodigosCanjeados: { [string]: number }?, -- código -> os.time()
	Vault: Vault?, -- bóveda global (se crea al usarla por primera vez)
	SkinsEstructura: { SkinEstructura }, -- desbloqueadas
	SkinEstructuraEquipada: SkinEstructura,
	-- v3: profesiones y economía
	Profesiones: { [string]: ProgresoProfesion },
	KitInicialEntregado: boolean,
	-- v4: bando y ajustes del jugador
	Ajustes: Ajustes,
	-- v5: diario de subastas, ids de mensajes de subasta ya entregados (con su
	-- os.time(), se podan a los 30 días) y contador de guardados.
	Pendientes: Pendientes,
	MensajesSubasta: { [string]: number },
	SecuenciaGuardado: number,
}

-- Secciones del perfil que se sincronizan al cliente.
export type SeccionDatos =
	"Nivel"
	| "Oro"
	| "MonedasPremium"
	| "Estadisticas"
	| "Inventario"
	| "Equipamiento"
	| "Misiones"
	| "Honor"
	| "Cosmeticos"
	| "Clase"
	| "Profesiones"
	| "Faccion"
	| "Ajustes"
	| "Vault"

-- Respuesta estándar de todas las RemoteFunctions.
export type CodigoError =
	"TIMEOUT"
	| "RATE_LIMITED"
	| "INVALID_ARGS"
	| "NOT_FOUND"
	| "NOT_ALLOWED"
	| "INSUFFICIENT_FUNDS"
	| "INVENTORY_FULL"
	| "DATA_NOT_LOADED"
	| "INTERNAL_ERROR"

export type Respuesta = {
	Success: boolean,
	ErrorCode: CodigoError?,
	Data: any,
}

return nil
