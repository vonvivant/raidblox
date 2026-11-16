--!strict
-- Pergaminos del Inscriptor (NPC-005).
--
-- Tres pergaminos, cada uno resolviendo algo que el jugador ya quería hacer:
-- volver a casa, reforzar al grupo antes de una pelea, y juntarse con los
-- compañeros sin cruzar el mapa.
--
-- Reglas puras: qué hace cada uno, cuándo no se puede usar y cuánto tarda en
-- poder usarse de nuevo. Lo demás lo hace PergaminoManager en el servidor.

export type Pergamino = {
	Id: string, -- ItemId del pergamino
	Nombre: string,
	Efecto: "Regreso" | "Fortaleza" | "Reunion",
	Descripcion: string,
	Cooldown: number, -- segundos entre usos del mismo pergamino
	Castea: number, -- cuánto hay que quedarse quieto antes de que surta efecto
}

local Config = {}

-- Ningún pergamino se puede usar en combate: son para antes o para después.
Config.ProhibidoEnCombate = true
-- Ni en la Guerra de Arquitectos, ni en una arena, ni en una mazmorra: ahí
-- irse o traer gente gratis rompería el modo.
Config.ModosCerrados = { "Guerra", "Arena", "Mazmorra" }

Config.RadioGrupo = 60 -- a qué distancia alcanza el buff de grupo
Config.DistanciaReunion = 10 -- a qué distancia del líder te deja
Config.DuracionFortaleza = 600 -- 10 minutos (la define ConsumiblesConfig.BuffFortaleza)
Config.BuffFortaleza = "BuffFortaleza" -- id del buff, distinto del ItemId

Config.Pergaminos = {
	{
		Id = "PergaminoRegreso",
		Nombre = "Pergamino de Regreso",
		Efecto = "Regreso",
		Descripcion = "Te devuelve a la capital de tu bando (o a la ciudad, si sos neutral).",
		Cooldown = 300,
		Castea = 4,
	},
	{
		Id = "PergaminoFortaleza",
		Nombre = "Pergamino de Fortaleza",
		Efecto = "Fortaleza",
		Descripcion = "+10% de defensa a todo tu grupo cercano, 10 minutos.",
		Cooldown = 60,
		Castea = 0,
	},
	{
		Id = "PergaminoReunion",
		Nombre = "Pergamino de Reunión",
		Efecto = "Reunion",
		Descripcion = "Te lleva junto al líder de tu grupo, si está en la misma zona.",
		Cooldown = 180,
		Castea = 6,
	},
} :: { Pergamino }

function Config.Pergamino(itemId: string): Pergamino?
	for _, pergamino in Config.Pergaminos do
		if pergamino.Id == itemId then
			return pergamino
		end
	end
	return nil
end

function Config.Es(itemId: string): boolean
	return Config.Pergamino(itemId) ~= nil
end

-- A qué zona vuelve cada bando con el Pergamino de Regreso.
Config.CasaPorBando = {
	Rojo = "CapitalRoja",
	Azul = "CapitalAzul",
	Neutral = "CiudadPrincipal",
}

function Config.Casa(bando: string?): string
	return Config.CasaPorBando[bando or "Neutral"] or "CiudadPrincipal"
end

-- ¿Ya puede volver a usar ese pergamino?
function Config.Listo(pergamino: Pergamino, ultimoUso: number?, ahora: number): boolean
	if ultimoUso == nil then
		return true
	end
	return ahora - ultimoUso >= pergamino.Cooldown
end

function Config.Faltan(pergamino: Pergamino, ultimoUso: number?, ahora: number): number
	if ultimoUso == nil then
		return 0
	end
	return math.max(0, pergamino.Cooldown + ultimoUso - ahora)
end

return Config
