--!strict
-- GameConfig: constantes globales de balance y sistemas. Visible para el cliente:
-- no pongas acá nada secreto (listas de admins, claves, webhooks).

local GameConfig = {
	-- Contenido de prueba también en servidores publicados (zona de práctica,
	-- estaciones, nodos, Casa de Subastas, arena de la Guerra y cambio libre de
	-- clase). Para probar con amigos. Apagalo cuando estén los mapas reales.
	ModoPruebas = true,

	Datos = {
		NombreStore = "RaidBlox_Jugadores_v1",
		VersionEsquema = 3,
		MaxRecibosGuardados = 50,
		MaxMensajesGuardados = 100,
		-- Si el perfil no carga en este tiempo (caída de DataStores), se expulsa al jugador.
		TimeoutCarga = 60,
	},

	Inventario = {
		SlotsBase = 30,
		SlotsConPase = 50,
		MaxStackPorDefecto = 99,
	},

	Progresion = {
		NivelMaximo = 60,
		-- XP necesaria para pasar del nivel n al n+1: Base * n ^ Exponente
		XpBase = 100,
		XpExponente = 1.5,
	},

	EstadisticasIniciales = {
		VidaActual = 100,
		ManaActual = 50,
		Fuerza = 5,
		Agilidad = 5,
		Inteligencia = 5,
	},

	Red = {
		TimeoutInvoke = 5, -- segundos
		-- Canales críticos (ataques, uso de ítems): 10 peticiones por segundo.
		RateCritico = 10,
		BurstCritico = 10,
		-- Canales normales (abrir menús, consultas).
		RateNormal = 5,
		BurstNormal = 8,
	},

	Subastas = {
		NombreStore = "RaidBlox_Subastas_v1",
		NombreIndice = "RaidBlox_SubastasIndice_v1", -- MemoryStore SortedMap
		Deposito = 0.05, -- se cobra (y se quema) al publicar
		Impuesto = 0.10, -- se retiene (y se quema) del precio al vender
		MaxPublicaciones = 5, -- 15 con el pase "Subasta Extra" (Fase 6)
		DuracionHoras = 48,
		DuracionEnStudioMinutos = 30,
		PrecioMinimo = 1,
		PrecioMaximo = 100_000_000,
		CacheBusquedaSegundos = 3,
	},

	Comercio = {
		DistanciaMaxima = 15, -- studs: más lejos, se cancela
		EsperaConfirmacion = 3, -- segundos entre que ambos bloquean y se puede confirmar
		MaxItemsPorLado = 8,
		ExpiraInvitacion = 20, -- segundos
	},

	Consumibles = {
		CooldownPociones = 10, -- segundos compartidos entre pociones
	},

	AntiCheat = {
		IntervaloMuestreo = 1, -- segundos entre muestras de posición
		VelocidadBase = 16, -- WalkSpeed por defecto de Roblox
		MultiplicadorTolerancia = 1.5, -- margen por latencia y física
		ToleranciaFijaStuds = 6,
		TiempoMaxEnAire = 3, -- segundos suspendido sin montura/vuelo
		AlturaMinimaSospechosa = 10, -- studs sobre el suelo para contar como "en el aire"
		AlturaEnSuelo = 4, -- a menos de esto se considera apoyado (punto seguro para devolverlo)
		CaidaMinimaPorSegundo = 4, -- studs que tiene que bajar por segundo para contar como cayendo
		GraciaTrasReaparecer = 3, -- segundos sin chequeos tras spawn/teleport
		StrikesParaReaparecer = 3, -- infracciones de vuelo seguidas antes de forzar respawn
		VentanaStrikes = 30, -- segundos que dura una infracción en el historial
	},
}

return GameConfig
