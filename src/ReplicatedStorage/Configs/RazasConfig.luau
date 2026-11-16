--!strict
-- Razas: el pedido del usuario era "Humano por defecto y Artesano", con firma
-- de autoría para el Artesano (la bóveda ya busca por `Meta.Autor`).
--
-- La raza no toca el combate: eso es cosa de la clase. Lo que cambia son
-- cosas de oficio y de economía, así que elegir raza nunca es elegir "la que
-- pega más fuerte".

export type Raza = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	Ventajas: { string },
	-- Lo que aplica cada una (0 = no aplica):
	BonusVenta: number, -- % extra de oro cuando un NPC te compra algo
	BonusMasterpiece: number, -- puntos de probabilidad extra de obra maestra (0.05 = +5%)
	DescuentoReparacion: number, -- % menos en el costo de reparar
	Firma: boolean, -- firma con tu nombre el equipo que fabricás
}

local Config = {}

Config.PorDefecto = "Humano"
-- La primera elección es gratis; cambiarla después cuesta.
Config.CostoCambio = 5000
Config.EsperaEntreCambios = 3600 -- segundos
Config.LargoAutorMaximo = 24

Config.Razas = {
	{
		Id = "Humano",
		Nombre = "Humano",
		Descripcion = "Gente de ciudad: negocia bien y se adapta a todo.",
		Ventajas = { "+10% de oro cuando le vendés a un NPC" },
		BonusVenta = 0.1,
		BonusMasterpiece = 0,
		DescuentoReparacion = 0,
		Firma = false,
	},
	{
		Id = "Artesano",
		Nombre = "Artesano",
		Descripcion = "Criados entre yunques y telares: lo que hacen lleva su nombre.",
		Ventajas = {
			"Firma con tu nombre el equipo que fabricás",
			"+5% de probabilidad de obra maestra",
			"25% menos en reparaciones",
		},
		BonusVenta = 0,
		BonusMasterpiece = 0.05,
		DescuentoReparacion = 0.25,
		Firma = true,
	},
} :: { Raza }

function Config.Raza(id: string?): Raza
	for _, raza in Config.Razas do
		if raza.Id == id then
			return raza
		end
	end
	-- Sin raza (o una raza vieja que ya no existe) se juega como la por defecto.
	for _, raza in Config.Razas do
		if raza.Id == Config.PorDefecto then
			return raza
		end
	end
	return Config.Razas[1]
end

function Config.Valida(id: unknown): boolean
	if typeof(id) ~= "string" then
		return false
	end
	for _, raza in Config.Razas do
		if raza.Id == id then
			return true
		end
	end
	return false
end

-- Lo que paga un NPC por algo, con el bono de la raza.
function Config.PagoConBono(pagoBase: number, raza: string?): number
	local def = Config.Raza(raza)
	return math.floor(pagoBase * (1 + def.BonusVenta))
end

-- Lo que cuesta reparar, con el descuento de la raza.
function Config.CostoConDescuento(costoBase: number, raza: string?): number
	local def = Config.Raza(raza)
	return math.max(0, math.floor(costoBase * (1 - def.DescuentoReparacion)))
end

-- Probabilidad de obra maestra, con el bono de la raza (sin pasarse del tope).
function Config.MasterpieceConBono(probabilidad: number, raza: string?, tope: number): number
	local def = Config.Raza(raza)
	return math.min(tope, probabilidad + def.BonusMasterpiece)
end

-- ¿Ya puede volver a cambiar de raza? `ultimo` es os.time() del último cambio.
function Config.PuedeCambiar(ultimo: number?, ahora: number): boolean
	if ultimo == nil then
		return true
	end
	return ahora - ultimo >= Config.EsperaEntreCambios
end

function Config.FaltaParaCambiar(ultimo: number?, ahora: number): number
	if ultimo == nil then
		return 0
	end
	return math.max(0, Config.EsperaEntreCambios + ultimo - ahora)
end

-- Cuánto cuesta el cambio: la primera vez (sin raza elegida) es gratis.
function Config.Costo(yaEligio: boolean): number
	return if yaEligio then Config.CostoCambio else 0
end

return Config
