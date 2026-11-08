--!strict
-- ZoneConfig: zonas y reinos del juego. Cada zona es un Place distinto dentro
-- de la misma experiencia (Asset Manager > Places en Studio).
--
-- PlaceId = 0 significa "todavía no creado": el portal avisa que la zona no
-- está disponible. Reemplazá los 0 por los PlaceId reales cuando crees los places.
--
-- Los portales del mapa son Parts con el tag "Portal" (CollectionService) y el
-- atributo "Destino" = clave de esta tabla (ej. "Bosque"). Opcional: atributo
-- "Spawn" con el nombre del punto de aparición en el destino.

export type Zona = {
	Nombre: string,
	PlaceId: number,
	NivelMinimo: number,
	Tema: string, -- texto de la pantalla de carga
	ColorTema: Color3,
}

local ZoneConfig = {
	-- Nombre del Folder en Workspace (de cada place) con los puntos de aparición
	-- (Parts) a los que puede llegar un jugador teletransportado.
	CarpetaSpawns = "PuntosDeLlegada",
	ReintentosTeleport = 3,
	-- En Studio TeleportService no funciona: se simula con la pantalla de carga.
	SimularEnStudio = true,
	-- En Studio, si no hay portales en el mapa, se crean dos de prueba.
	CrearPortalesDePruebaEnStudio = true,

	Zonas = {
		CiudadPrincipal = {
			Nombre = "Ciudad Principal",
			PlaceId = 0,
			NivelMinimo = 1,
			Tema = "Las campanas de la ciudad te dan la bienvenida...",
			ColorTema = Color3.fromRGB(230, 190, 90),
		},
		Bosque = {
			Nombre = "Bosque Susurrante",
			PlaceId = 0,
			NivelMinimo = 1,
			Tema = "Los árboles antiguos murmuran tu nombre...",
			ColorTema = Color3.fromRGB(90, 170, 90),
		},
		ReinoFuego = {
			Nombre = "Reino de Fuego",
			PlaceId = 0,
			NivelMinimo = 20,
			Tema = "El aire arde. Solo los veteranos sobreviven aquí.",
			ColorTema = Color3.fromRGB(220, 80, 40),
		},
		GuerraArquitectos = {
			Nombre = "Guerra de Arquitectos",
			PlaceId = 0,
			NivelMinimo = 5,
			Tema = "Dos reinos. Un estandarte. Construí más rápido.",
			ColorTema = Color3.fromRGB(80, 200, 255),
		},
	} :: { [string]: Zona },
}

return ZoneConfig
