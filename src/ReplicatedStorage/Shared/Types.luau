--!strict
-- Types: tipos compartidos entre cliente y servidor.
-- Todo lo que cruza la red o se guarda en el perfil se define acá, así ambos lados coinciden.

export type Rareza = "Comun" | "Raro" | "Epico" | "Mistico" | "Unico"

export type Clase = "SinClase" | "Tanque" | "Guerrero" | "Mago" | "Arquero" | "Asesino" | "Healer" | "Druida" | "Buffer"

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

export type DatosJugador = {
	Version: number,
	Nivel: number,
	Experiencia: number,
	Clase: Clase,
	Faccion: string,
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
	SkinsEstructura: { SkinEstructura }, -- desbloqueadas
	SkinEstructuraEquipada: SkinEstructura,
	-- v3: profesiones y economía
	Profesiones: { [string]: ProgresoProfesion },
	KitInicialEntregado: boolean,
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
