--!strict
-- Parcelas: terrenos que el jugador compra, alquila, comparte y fusiona.
-- Es el pedido de "parcelas" del usuario y el NPC-033 (Arquitecto de Viviendas).
--
-- Acá viven solo las reglas puras: dónde está cada parcela, cuánto cuesta, cómo
-- se cobra el alquiler, quién puede hacer qué y cuáles se pueden fusionar. El
-- dueño de verdad lo guarda `ParcelaManager` en un DataStore global, porque una
-- parcela es de un jugador en todos los servidores a la vez.
--
-- Las parcelas viven en una grilla por barrio: cada una tiene una fila y una
-- columna, y por eso se sabe cuáles son vecinas sin consultar nada.

export type Barrio = {
	Id: string,
	Nombre: string,
	Zona: string, -- id de ZoneConfig.Zonas
	Origen: Vector3, -- centro de la parcela (1,1)
	Filas: number,
	Columnas: number,
	Lado: number, -- cuánto mide el lado de la parcela, en studs
	Calle: number, -- cuánto se deja entre parcela y parcela
	Precio: number, -- lo que cuesta comprarla
	Descripcion: string,
}

-- Lo que puede hacer alguien que no es el dueño.
export type Permiso = "Visita" | "Invitado" | "Socio"

local Config = {}

Config.Barrios = {
	{
		Id = "CiudadNorte",
		Nombre = "Barrio Norte",
		Zona = "CiudadPrincipal",
		Origen = Vector3.new(220, 0, -220),
		Filas = 3,
		Columnas = 4,
		Lado = 48,
		Calle = 12,
		Precio = 12000,
		Descripcion = "Pegado a la plaza: caro y céntrico.",
	},
	{
		Id = "CiudadRibera",
		Nombre = "La Ribera",
		Zona = "CiudadPrincipal",
		Origen = Vector3.new(220, 0, 120),
		Filas = 3,
		Columnas = 4,
		Lado = 48,
		Calle = 12,
		Precio = 7000,
		Descripcion = "Más lejos y más barato, con vista al agua.",
	},
	{
		Id = "BosqueClaro",
		Nombre = "Claro del Bosque",
		Zona = "Bosque",
		Origen = Vector3.new(-180, 0, 180),
		Filas = 2,
		Columnas = 3,
		Lado = 64,
		Calle = 16,
		Precio = 4500,
		Descripcion = "Terrenos grandes, lejos de todo.",
	},
} :: { Barrio }

-- Alquiler: la parcela se compra, pero hay que mantenerla al día.
Config.AlquilerDiario = 150
Config.DiasAlCompar = 7 -- días que vienen pagados con la compra
Config.DiasMaximos = 30 -- no se puede pagar más adelantado que esto
Config.DiasDeGracia = 3 -- vencida, antes de volver al mercado
Config.MaxPorJugador = 2
Config.MaxInvitados = 12
Config.LargoNombre = 28
Config.Distancia = 20 -- para hablar con el Arquitecto o usar el cofre

Config.Permisos = {
	{ Id = "Visita", Nombre = "Visita", Descripcion = "Puede entrar y nada más." },
	{ Id = "Invitado", Nombre = "Invitado", Descripcion = "Entra y usa lo que esté puesto." },
	{ Id = "Socio", Nombre = "Socio", Descripcion = "Construye y abre el cofre de bóveda." },
}

function Config.Barrio(id: string): Barrio?
	for _, barrio in Config.Barrios do
		if barrio.Id == id then
			return barrio
		end
	end
	return nil
end

function Config.CantidadDe(barrio: Barrio): number
	return barrio.Filas * barrio.Columnas
end

-- Id de parcela: "CiudadNorte:7". El número va de 1 a filas × columnas.
function Config.Id(barrioId: string, numero: number): string
	return `{barrioId}:{numero}`
end

-- Parte un id en barrio y número. Devuelve nil si no es un id válido o si el
-- número se sale de la grilla de ese barrio.
function Config.Partir(id: string): (Barrio?, number?)
	local barrioId, texto = string.match(id, "^(%w+):(%d+)$")
	if not barrioId or not texto then
		return nil, nil
	end
	local barrio = Config.Barrio(barrioId)
	if not barrio then
		return nil, nil
	end
	local numero = tonumber(texto)
	if not numero or numero < 1 or numero > Config.CantidadDe(barrio) or numero ~= math.floor(numero) then
		return nil, nil
	end
	return barrio, numero
end

function Config.Valido(id: string): boolean
	local barrio = Config.Partir(id)
	return barrio ~= nil
end

-- Fila y columna de una parcela (ambas desde 1).
function Config.Coordenada(barrio: Barrio, numero: number): (number, number)
	local indice = numero - 1
	return math.floor(indice / barrio.Columnas) + 1, indice % barrio.Columnas + 1
end

function Config.Numero(barrio: Barrio, fila: number, columna: number): number?
	if fila < 1 or fila > barrio.Filas or columna < 1 or columna > barrio.Columnas then
		return nil
	end
	return (fila - 1) * barrio.Columnas + columna
end

-- Centro de la parcela en el mundo.
function Config.Centro(barrio: Barrio, numero: number): Vector3
	local fila, columna = Config.Coordenada(barrio, numero)
	local paso = barrio.Lado + barrio.Calle
	return barrio.Origen + Vector3.new((columna - 1) * paso, 0, (fila - 1) * paso)
end

-- Las que tocan a esta por un lado (no en diagonal).
function Config.Vecinas(barrio: Barrio, numero: number): { number }
	local fila, columna = Config.Coordenada(barrio, numero)
	local vecinas: { number } = {}
	local alrededor = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for _, paso in alrededor do
		local otra = Config.Numero(barrio, fila + paso[1], columna + paso[2])
		if otra then
			table.insert(vecinas, otra)
		end
	end
	return vecinas
end

-- ¿Se pueden fusionar? Tienen que ser del mismo barrio y tocarse por un lado.
function Config.Fusionables(idA: string, idB: string): boolean
	if idA == idB then
		return false
	end
	local barrioA, numeroA = Config.Partir(idA)
	local barrioB, numeroB = Config.Partir(idB)
	if not barrioA or not numeroA or not barrioB or not numeroB then
		return false
	end
	if barrioA.Id ~= barrioB.Id then
		return false
	end
	return table.find(Config.Vecinas(barrioA, numeroA), numeroB) ~= nil
end

function Config.Alquiler(dias: number): number
	return Config.AlquilerDiario * math.max(0, math.floor(dias))
end

-- Cuántos días se pueden pagar sin pasar el máximo adelantado.
function Config.DiasQuePuedePagar(hasta: number, ahora: number): number
	local restantes = math.max(0, math.ceil((hasta - ahora) / 86400))
	return math.max(0, Config.DiasMaximos - restantes)
end

function Config.Vencida(hasta: number, ahora: number): boolean
	return ahora > hasta
end

-- Vencida pero todavía recuperable (no volvió al mercado).
function Config.EnGracia(hasta: number, ahora: number): boolean
	return Config.Vencida(hasta, ahora) and ahora <= hasta + Config.DiasDeGracia * 86400
end

-- Se perdió: cualquiera puede comprarla.
function Config.Libre(hasta: number, ahora: number): boolean
	return Config.Vencida(hasta, ahora) and not Config.EnGracia(hasta, ahora)
end

function Config.PermisoValido(nivel: string): boolean
	for _, permiso in Config.Permisos do
		if permiso.Id == nivel then
			return true
		end
	end
	return false
end

-- ¿Ese nivel alcanza para construir y abrir el cofre?
function Config.PuedeConstruir(nivel: string?): boolean
	return nivel == "Socio"
end

function Config.NombreValido(nombre: string): boolean
	if #nombre == 0 or #nombre > Config.LargoNombre then
		return false
	end
	-- Ojo: %s también acepta saltos de línea y tabulaciones, así que el espacio
	-- va escrito a mano.
	return string.match(nombre, "^[%w '%-áéíóúÁÉÍÓÚñÑüÜ]+$") ~= nil
end

return Config
