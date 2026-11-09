--!strict
-- GuerraConfig: balance de la Guerra de Arquitectos (mapa pasivo Team vs Team,
-- sin PvP directo). Gana el primer equipo que coloca el Estandarte.

export type Recurso = "Madera" | "Piedra" | "Hierro"
export type NombreEtapa = "Fundacion" | "Muros" | "Torres" | "GranSalon" | "Estandarte"

export type Etapa = {
	Id: NombreEtapa,
	Nombre: string,
	Requisitos: { [Recurso]: number }, -- unidades que el equipo tiene que depositar
}

export type Equipo = {
	Id: string,
	Nombre: string,
	Color: BrickColor,
}

export type AspectoSkin = {
	Material: Enum.Material,
	Color: Color3,
	Reflejo: number?, -- Reflectance (0 = mate)
	Transparencia: number?,
	Fisica: { Densidad: number, Friccion: number, Elasticidad: number }?,
}

local GuerraConfig = {
	-- Dónde corre el modo: en el place de la Guerra (ZoneConfig.Zonas.GuerraArquitectos.PlaceId),
	-- en cualquier place cuyo Workspace tenga la carpeta "GuerraArquitectos", o en Studio
	-- si ProbarEnStudio = true (en ese caso se genera una arena de prueba si no existe).
	ProbarEnStudio = true,
	NombreCarpetaMapa = "GuerraArquitectos",

	JugadoresMinimos = 2,
	JugadoresMinimosEnStudio = 1,
	CuentaRegresiva = 5, -- segundos antes de empezar
	DuracionMaxima = 20 * 60, -- si nadie termina, gana el que más avanzó
	PausaEntrePartidas = 15,

	CapacidadCarga = 30, -- unidades totales que puede llevar un jugador
	-- Todo lo depositado va al almacén del equipo y completa automáticamente la
	-- etapa actual y las siguientes: ningún recurso recolectado es inútil.
	MaxDistanciaInteraccion = 14, -- studs (validación propia además del ProximityPrompt)

	Recursos = {
		-- Cada nodo entrega `Cantidad` por recolección y reaparece tras `Respawn` s.
		Madera = { Nombre = "Madera", Cantidad = 5, Respawn = 8, Duracion = 1.0 },
		Piedra = { Nombre = "Piedra", Cantidad = 4, Respawn = 10, Duracion = 1.5 },
		Hierro = { Nombre = "Hierro", Cantidad = 2, Respawn = 15, Duracion = 2.0 },
	} :: { [Recurso]: { Nombre: string, Cantidad: number, Respawn: number, Duracion: number } },

	Etapas = {
		{ Id = "Fundacion", Nombre = "Fundación", Requisitos = { Piedra = 40, Madera = 20 } },
		{ Id = "Muros", Nombre = "Muros", Requisitos = { Piedra = 60, Madera = 30 } },
		{ Id = "Torres", Nombre = "Torres", Requisitos = { Piedra = 40, Madera = 40, Hierro = 10 } },
		{ Id = "GranSalon", Nombre = "Gran Salón", Requisitos = { Madera = 60, Piedra = 30, Hierro = 20 } },
		{ Id = "Estandarte", Nombre = "Estandarte", Requisitos = { Hierro = 20, Madera = 10 } },
	} :: { Etapa },

	-- En Studio, con un solo jugador, los requisitos se dividen por este número
	-- para poder probar una partida completa en pocos minutos.
	DivisorRequisitosEnStudio = 5,
	-- En Studio las recompensas se guardan en tu perfil real si tenés activado el
	-- acceso a API Services. Ponelo en false para probar sin tocar tu perfil.
	DarRecompensasEnStudio = true,

	Equipos = {
		{ Id = "Azul", Nombre = "Reino Azul", Color = BrickColor.new("Bright blue") },
		{ Id = "Rojo", Nombre = "Reino Rojo", Color = BrickColor.new("Bright red") },
	} :: { Equipo },

	Recompensas = {
		Ganador = { Oro = 500, Honor = 100, Titulo = "Gran Arquitecto" },
		Perdedor = { Oro = 100, Honor = 20 },
		-- Solo cobran quienes aportaron al menos esto (evita farmear quedándose AFK).
		AporteMinimo = 5,
	},

	-- Aspecto de los bloques construidos según la skin de quien más aportó a la etapa.
	Skins = {
		Ninguna = { Material = Enum.Material.Cobblestone, Color = Color3.fromRGB(150, 145, 135) },
		Gotica = { Material = Enum.Material.Slate, Color = Color3.fromRGB(55, 50, 60) },
		Hielo = { Material = Enum.Material.Glacier, Color = Color3.fromRGB(175, 220, 255) },
		Jade = { Material = Enum.Material.Marble, Color = Color3.fromRGB(80, 170, 120) },
	} :: { [string]: AspectoSkin },

	ColorHolograma = Color3.fromRGB(90, 200, 255),
	-- Id de sonido al completar una etapa (vacío = sin sonido). Poné uno de tu Creator Store.
	SonidoEtapa = "",
}

return GuerraConfig
