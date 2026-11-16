--!strict
-- Stencils: calcomanías que se le ponen a una pieza de un arma o armadura
-- desde el personalizador, con su escala y su opacidad.
--
-- Vienen en **tres libros**. Cada libro es un ítem consumible: al usarlo se
-- desbloquean para siempre los stencils de ese libro (y el libro se gasta).
-- Lo desbloqueado vive en el perfil, así que vale para todos los ítems.
--
-- IMPORTANTE: las texturas las tiene que subir el usuario a Roblox. Mientras
-- `Textura` sea 0, el stencil figura como "próximamente" y el servidor lo
-- rechaza, igual que los peinados del barbero. Nada se rompe: simplemente no
-- se puede elegir hasta que haya arte.

export type Stencil = {
	Id: string,
	Nombre: string,
	Libro: string,
	Grupo: string, -- para la lista agrupada del NPC Cosméticos
	Textura: number, -- rbxassetid; 0 = todavía no hay arte
}

-- Un relieve es un grabado con normal map. En Roblox eso es un
-- `SurfaceAppearance`, que **solo funciona sobre MeshParts** y **reemplaza el
-- aspecto del material** de esa pieza (por eso no conviven con el material
-- elegido: mientras hay relieve, manda el relieve).
export type Relieve = {
	Id: string,
	Nombre: string,
	Libro: string,
	ColorMap: number, -- rbxassetid; 0 = todavía no hay arte
	NormalMap: number,
	Rugosidad: number, -- 0 = espejo, 1 = mate
}

export type Libro = {
	Id: string,
	Nombre: string,
	Item: string, -- ItemId del libro consumible
	Descripcion: string,
}

local Config = {}

Config.MaxPorItem = 3 -- cuántas piezas de un mismo ítem pueden llevar stencil
Config.EscalaMin = 20 -- % del tamaño de la pieza
Config.EscalaMax = 100
Config.EscalaPaso = 10
Config.OpacidadMin = 20 -- % de opacidad (100 = opaco)
Config.OpacidadMax = 100
Config.OpacidadPaso = 10
Config.CostoPorStencil = 75 -- oro, se suma al precio del ítem o del retoque

-- Textura de relleno para poder probar el sistema ANTES de subir el arte.
-- Solo se usa en Studio o con GameConfig.ModoPruebas, y solo para los stencils
-- que todavía tienen Textura = 0. Es una imagen cualquiera de Roblox: alcanza
-- para ver que la escala, la opacidad y el cobro funcionan.
Config.TexturaPrueba = 6023426923

Config.CostoPorRelieve = 200 -- más caro que una calcomanía: son dos texturas
Config.MaxRelievesPorItem = 2

-- Los decals se muestran agrupados por tipo, no por libro: el jugador busca
-- "un rasguño" o "un adorno", no "algo del libro de runas".
Config.Grupos = {
	{ Id = "Rasgunos", Nombre = "Rasguños" },
	{ Id = "Adornos", Nombre = "Adornos" },
	{ Id = "Simbolos", Nombre = "Símbolos" },
	{ Id = "Bestias", Nombre = "Bestias" },
}

Config.Libros = {
	{
		Id = "Runas",
		Nombre = "Libro de Runas",
		Item = "LibroRunas",
		Descripcion = "Marcas antiguas para grabar en el metal.",
	},
	{
		Id = "Heraldica",
		Nombre = "Libro Heráldico",
		Item = "LibroHeraldica",
		Descripcion = "Escudos y blasones de las casas que fueron.",
	},
	{
		Id = "Bestias",
		Nombre = "Libro de Bestias",
		Item = "LibroBestias",
		Descripcion = "Siluetas de lo que vive en los bosques y en las cuevas.",
	},
} :: { Libro }

Config.Stencils = {
	-- Rasguños y desgaste
	{ Id = "RasgunoLargo", Nombre = "Rasguño Largo", Libro = "Runas", Grupo = "Rasgunos", Textura = 0 },
	{ Id = "RasgunoCruzado", Nombre = "Rasguños Cruzados", Libro = "Bestias", Grupo = "Rasgunos", Textura = 0 },
	{ Id = "Mellas", Nombre = "Mellas de Combate", Libro = "Heraldica", Grupo = "Rasgunos", Textura = 0 },
	-- Adornos
	{ Id = "FiligranaBorde", Nombre = "Filigrana de Borde", Libro = "Heraldica", Grupo = "Adornos", Textura = 0 },
	{ Id = "LirioDoble", Nombre = "Lirio Doble", Libro = "Heraldica", Grupo = "Adornos", Textura = 0 },
	{ Id = "CadenaFina", Nombre = "Cadena Fina", Libro = "Runas", Grupo = "Adornos", Textura = 0 },
	-- Símbolos
	{ Id = "RunaFuerza", Nombre = "Runa de Fuerza", Libro = "Runas", Grupo = "Simbolos", Textura = 0 },
	{ Id = "RunaVida", Nombre = "Runa de Vida", Libro = "Runas", Grupo = "Simbolos", Textura = 0 },
	{ Id = "RunaTormenta", Nombre = "Runa de Tormenta", Libro = "Runas", Grupo = "Simbolos", Textura = 0 },
	{ Id = "EscudoPartido", Nombre = "Escudo Partido", Libro = "Heraldica", Grupo = "Simbolos", Textura = 0 },
	{ Id = "TorreYSol", Nombre = "Torre y Sol", Libro = "Heraldica", Grupo = "Simbolos", Textura = 0 },
	-- Bestias
	{ Id = "GarraLobo", Nombre = "Garra de Lobo", Libro = "Bestias", Grupo = "Bestias", Textura = 0 },
	{ Id = "AlaCuervo", Nombre = "Ala de Cuervo", Libro = "Bestias", Grupo = "Bestias", Textura = 0 },
	{ Id = "OjoSerpiente", Nombre = "Ojo de Serpiente", Libro = "Bestias", Grupo = "Bestias", Textura = 0 },
} :: { Stencil }

-- Relieves (grabados con normal map). Van por los mismos libros que las
-- calcomanías: quien aprendió el libro puede usar las dos cosas.
Config.Relieves = {
	{ Id = "RelieveRunico", Nombre = "Grabado Rúnico", Libro = "Runas", ColorMap = 0, NormalMap = 0, Rugosidad = 0.6 },
	{
		Id = "RelieveBlason",
		Nombre = "Blasón en Relieve",
		Libro = "Heraldica",
		ColorMap = 0,
		NormalMap = 0,
		Rugosidad = 0.5,
	},
	{ Id = "RelieveEscama", Nombre = "Escamas", Libro = "Bestias", ColorMap = 0, NormalMap = 0, Rugosidad = 0.8 },
} :: { Relieve }

function Config.Relieve(id: string): Relieve?
	for _, relieve in Config.Relieves do
		if relieve.Id == id then
			return relieve
		end
	end
	return nil
end

function Config.RelievesDelLibro(libroId: string): { Relieve }
	local lista: { Relieve } = {}
	for _, relieve in Config.Relieves do
		if relieve.Libro == libroId then
			table.insert(lista, relieve)
		end
	end
	return lista
end

-- Un relieve necesita las dos texturas subidas. No tiene relleno de prueba:
-- un normal map falso se vería mal y confundiría más de lo que ayuda.
function Config.RelieveDisponible(relieve: Relieve): boolean
	return relieve.ColorMap > 0 and relieve.NormalMap > 0
end

function Config.RelievePermitido(id: string, librosDesbloqueados: { string }): boolean
	local relieve = Config.Relieve(id)
	if not relieve or not Config.RelieveDisponible(relieve) then
		return false
	end
	return table.find(librosDesbloqueados, relieve.Libro) ~= nil
end

function Config.CostoRelieves(cuantos: number): number
	return Config.CostoPorRelieve * math.clamp(math.floor(cuantos), 0, Config.MaxRelievesPorItem)
end

function Config.Stencil(id: string): Stencil?
	for _, stencil in Config.Stencils do
		if stencil.Id == id then
			return stencil
		end
	end
	return nil
end

function Config.Libro(id: string): Libro?
	for _, libro in Config.Libros do
		if libro.Id == id then
			return libro
		end
	end
	return nil
end

-- El libro que corresponde a un ítem consumible, si es un libro.
function Config.LibroDeItem(itemId: string): Libro?
	for _, libro in Config.Libros do
		if libro.Item == itemId then
			return libro
		end
	end
	return nil
end

function Config.Grupo(id: string): { Id: string, Nombre: string }?
	for _, grupo in Config.Grupos do
		if grupo.Id == id then
			return grupo
		end
	end
	return nil
end

-- Los decals de un grupo, con los que el jugador no desbloqueó marcados por
-- quien llame (acá no se filtra: la interfaz muestra todo y aclara qué falta).
function Config.DelGrupo(grupoId: string): { Stencil }
	local lista: { Stencil } = {}
	for _, stencil in Config.Stencils do
		if stencil.Grupo == grupoId then
			table.insert(lista, stencil)
		end
	end
	return lista
end

function Config.DelLibro(libroId: string): { Stencil }
	local lista: { Stencil } = {}
	for _, stencil in Config.Stencils do
		if stencil.Libro == libroId then
			table.insert(lista, stencil)
		end
	end
	return lista
end

-- ¿Hay arte para este stencil? `enPruebas` lo da por disponible usando la
-- textura de relleno, así se puede probar el flujo completo sin subir nada.
function Config.Disponible(stencil: Stencil, enPruebas: boolean?): boolean
	return stencil.Textura > 0 or enPruebas == true
end

-- El id de imagen que hay que dibujar (0 si no hay ninguno).
function Config.TexturaDe(stencil: Stencil, enPruebas: boolean?): number
	if stencil.Textura > 0 then
		return stencil.Textura
	end
	return if enPruebas == true then Config.TexturaPrueba else 0
end

-- ¿El jugador puede usarlo? Hace falta el libro desbloqueado y que haya arte.
function Config.Permitido(id: string, librosDesbloqueados: { string }, enPruebas: boolean?): boolean
	local stencil = Config.Stencil(id)
	if not stencil or not Config.Disponible(stencil, enPruebas) then
		return false
	end
	return table.find(librosDesbloqueados, stencil.Libro) ~= nil
end

-- Acomoda escala y opacidad a los pasos permitidos, dentro de los límites.
function Config.AcomodarEscala(valor: number): number
	local paso = Config.EscalaPaso
	local acomodado = math.round(valor / paso) * paso
	return math.clamp(acomodado, Config.EscalaMin, Config.EscalaMax)
end

function Config.AcomodarOpacidad(valor: number): number
	local paso = Config.OpacidadPaso
	local acomodado = math.round(valor / paso) * paso
	return math.clamp(acomodado, Config.OpacidadMin, Config.OpacidadMax)
end

function Config.EscalaValida(valor: number): boolean
	return valor == Config.AcomodarEscala(valor)
end

function Config.OpacidadValida(valor: number): boolean
	return valor == Config.AcomodarOpacidad(valor)
end

-- Lo que suman los stencils al precio.
function Config.Costo(cuantos: number): number
	return Config.CostoPorStencil * math.clamp(math.floor(cuantos), 0, Config.MaxPorItem)
end

return Config
