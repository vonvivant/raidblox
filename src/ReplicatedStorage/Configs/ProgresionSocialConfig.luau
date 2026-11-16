--!strict
-- ProgresionSocialConfig: descanso del Tabernero, misiones diarias del Tablón
-- y reputación de facción del Emisario (Grupo E de los 39 NPC).
--
-- Son reglas puras: el servidor las usa para validar y cobrar, y el cliente
-- para mostrar. Lo que decide siempre es el servidor.

export type NivelReputacion = { Nombre: string, Desde: number }
export type OfertaReputacion = {
	Nombre: string,
	Descripcion: string,
	Reputacion: number, -- reputación mínima con tu bando
	Costo: number, -- puntos de honor
	Titulo: string?, -- título que otorga
	ItemId: string?, -- o ítem que entrega
	Cantidad: number?,
}

local Config = {}

------------------------------------------------------------------------
-- Descanso (NPC-025 Tabernero)
------------------------------------------------------------------------

-- El jugador compra una habitación y acumula "experiencia descansada": la
-- siguiente experiencia que gane rinde más, hasta agotar el saldo.
Config.Descanso = {
	Costo = 50, -- oro por habitación
	Bonus = 0.5, -- +50% a la experiencia mientras tenga saldo
	PorCompra = 2000, -- saldo que suma cada habitación
	Maximo = 12000, -- tope acumulable
}

-- Cuánto rinde `xp` con `saldo` de descanso: devuelve la experiencia final y
-- cuánto saldo se consumió. El extra sale del saldo, así que nunca da más de
-- lo que el jugador compró.
function Config.AplicarDescanso(xp: number, saldo: number): (number, number)
	if xp <= 0 or saldo <= 0 then
		return math.max(0, math.floor(xp)), 0
	end
	local extra = math.min(math.floor(xp * Config.Descanso.Bonus), math.floor(saldo))
	return math.floor(xp) + extra, extra
end

------------------------------------------------------------------------
-- Misiones diarias (NPC-026 Tablón de Anuncios)
------------------------------------------------------------------------

Config.Diarias = {
	PorDia = 3, -- cuántas se pueden tomar por día
	-- El día cambia a esta hora UTC (19:00 UTC = 16:00 en Buenos Aires).
	HoraReinicio = 19,
	-- Las diarias dan más oro y experiencia que una misión normal igual.
	MultiplicadorRecompensa = 2,
}

-- Número de día de una fecha (os.time()), contando el reinicio a HoraReinicio.
function Config.DiaDe(ahora: number): number
	return math.floor((ahora - Config.Diarias.HoraReinicio * 3600) / 86400)
end

-- Segundos hasta el próximo reinicio.
function Config.FaltaParaReinicio(ahora: number): number
	local proximo = (Config.DiaDe(ahora) + 1) * 86400 + Config.Diarias.HoraReinicio * 3600
	return math.max(0, proximo - ahora)
end

------------------------------------------------------------------------
-- Reputación de facción (NPC-027 Emisario)
------------------------------------------------------------------------

-- Se gana con la Guerra de Arquitectos y derrotando jugadores del bando rival.
Config.Reputacion = {
	PorVictoriaGuerra = 150,
	PorDerrotaGuerra = 50,
	PorJugadorRival = 10,
	MaximoPorDia = 1500, -- tope diario para que no se farmee sin límite
	Maximo = 50000,
}

Config.Niveles = {
	{ Nombre = "Neutral", Desde = 0 },
	{ Nombre = "Amistoso", Desde = 1000 },
	{ Nombre = "Honorable", Desde = 5000 },
	{ Nombre = "Reverenciado", Desde = 15000 },
	{ Nombre = "Exaltado", Desde = 35000 },
} :: { NivelReputacion }

-- Nombre del nivel y cuánto falta para el siguiente (0 si está al máximo).
function Config.NivelDe(reputacion: number): (string, number)
	local nombre = Config.Niveles[1].Nombre
	local falta = 0
	for i, nivel in Config.Niveles do
		if reputacion >= nivel.Desde then
			nombre = nivel.Nombre
			local siguiente = Config.Niveles[i + 1]
			falta = if siguiente then siguiente.Desde - reputacion else 0
		end
	end
	return nombre, falta
end

-- Lo que vende el Emisario, por puntos de honor y con reputación mínima.
Config.Ofertas = {
	{
		Nombre = "Título: Soldado",
		Descripcion = "Un título para mostrar de qué lado estás.",
		Reputacion = 1000,
		Costo = 200,
		Titulo = "Soldado",
	},
	{
		Nombre = "Título: Veterano",
		Descripcion = "Para quien ya peleó unas cuantas guerras.",
		Reputacion = 5000,
		Costo = 800,
		Titulo = "Veterano",
	},
	{
		Nombre = "Título: Campeón del Bando",
		Descripcion = "Reservado a los más leales.",
		Reputacion = 15000,
		Costo = 2500,
		Titulo = "Campeón del Bando",
	},
	{
		Nombre = "Núcleo de Obsidiana",
		Descripcion = "Material de guerra para las mejores recetas.",
		Reputacion = 5000,
		Costo = 400,
		ItemId = "NucleoObsidiana",
		Cantidad = 1,
	},
	{
		Nombre = "Diamante de Guerra",
		Descripcion = "Para engarzar en tu equipo (crítico).",
		Reputacion = 15000,
		Costo = 900,
		ItemId = "Diamante",
		Cantidad = 1,
	},
} :: { OfertaReputacion }

return Config
