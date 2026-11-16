--!strict
-- ExploracionConfig: piedras de teletransporte (viaje rápido) y puntos de
-- interés del mapa.
--
-- * Piedras: hay que activarlas una vez tocándolas; después se puede viajar
--   entre las activadas, pagando oro, siempre que el jugador esté junto a una.
-- * Puntos de interés: se descubren caminando cerca o se los revela el
--   Cartógrafo. Aparecen en el mapa del mundo.
--
-- En los mapas reales, cada piedra es una parte con el tag "PiedraTeleport" y
-- el atributo `Piedra` (la clave de `Piedras`). Las de la lista que no estén en
-- el mapa se crean solas en la zona de pruebas.

export type Piedra = {
	Nombre: string,
	Zona: string, -- clave de ZoneConfig.Zonas, o "Pruebas"
	Posicion: Vector3,
	NivelMinimo: number?,
}

export type PuntoInteres = {
	Nombre: string,
	Zona: string,
	Posicion: Vector3,
	Icono: string,
	Descripcion: string,
}

local Config = {}

Config.TagPiedra = "PiedraTeleport"
Config.TagPoi = "PuntoInteres"
Config.Distancia = 14 -- studs para activar una piedra y para viajar desde ella
Config.RadioDescubrir = 35 -- caminando a menos de esto, el punto de interés se descubre
Config.IntervaloDescubrir = 2 -- segundos entre chequeos

-- Costo de un viaje entre piedras de la misma zona; entre zonas se suma el
-- costo del Guardián de Portales (NpcArquetiposConfig.Viajes).
Config.CostoViaje = 30
Config.CostoPorZona = 60

Config.Piedras = {
	PiedraPlaza = { Nombre = "Piedra de la Plaza", Zona = "Pruebas", Posicion = Vector3.new(14, 0, 10) },
	PiedraNpc = { Nombre = "Piedra de los Mercaderes", Zona = "Pruebas", Posicion = Vector3.new(-30, 0, 4) },
	PiedraMinas = { Nombre = "Piedra de las Minas", Zona = "Pruebas", Posicion = Vector3.new(90, 0, -60) },
	PiedraBosque = { Nombre = "Piedra del Claro", Zona = "Pruebas", Posicion = Vector3.new(-60, 0, -90) },
} :: { [string]: Piedra }

Config.Interes = {
	VetasHierro = {
		Nombre = "Vetas de hierro",
		Zona = "Pruebas",
		Posicion = Vector3.new(100, 0, -70),
		Icono = "⛏",
		Descripcion = "Un filón de hierro y plata entre las rocas.",
	},
	ClaroHierbas = {
		Nombre = "Claro de hierbas",
		Zona = "Pruebas",
		Posicion = Vector3.new(-70, 0, -100),
		Icono = "🌿",
		Descripcion = "Hierbas sanadoras y flores de luna.",
	},
	CampoPractica = {
		Nombre = "Campo de práctica",
		Zona = "Pruebas",
		Posicion = Vector3.new(40, 0, -30),
		Icono = "⚔",
		Descripcion = "Muñecos y enemigos de prueba.",
	},
	PlazaMercaderes = {
		Nombre = "Plaza de mercaderes",
		Zona = "Pruebas",
		Posicion = Vector3.new(-30, 0, 37),
		Icono = "⚖",
		Descripcion = "Vendedores, artesanos, banco y subastas.",
	},
	TorreGuerra = {
		Nombre = "Arena de la Guerra",
		Zona = "Pruebas",
		Posicion = Vector3.new(120, 0, 120),
		Icono = "🏰",
		Descripcion = "Donde se juega la Guerra de Arquitectos.",
	},
} :: { [string]: PuntoInteres }

-- Lo que vende o revela el Cartógrafo, por zona: todos los puntos de interés
-- de esa zona que el jugador no tenga.
Config.PrecioMapa = 200

-- Piedras y puntos de una zona (ordenados por nombre, para que la lista no baile).
local function deZona(tabla: { [string]: any }, zona: string): { string }
	local ids: { string } = {}
	for id, dato in tabla do
		if dato.Zona == zona then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a: string, b: string): boolean
		return tabla[a].Nombre < tabla[b].Nombre
	end)
	return ids
end

function Config.PiedrasDe(zona: string): { string }
	return deZona(Config.Piedras, zona)
end

function Config.InteresDe(zona: string): { string }
	return deZona(Config.Interes, zona)
end

-- Costo de viajar de una piedra a otra.
function Config.Costo(desde: Piedra, hasta: Piedra): number
	return if desde.Zona == hasta.Zona then Config.CostoViaje else Config.CostoViaje + Config.CostoPorZona
end

return Config
