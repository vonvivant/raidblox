--!strict
-- ForjaConfig: números y reglas de los servicios de herrería sobre un ítem:
-- durabilidad y reparación, desencantar, reforjar y engarzar gemas.
--
-- Las funciones de este módulo son puras (no tocan nada): el servidor las usa
-- para validar y cobrar, y el cliente para mostrar costos y qué ítems sirven
-- para cada operación. El servidor nunca confía en lo que calcule el cliente.
--
-- Todo vive en los metadatos del ítem (`Meta`), así que viaja con él por
-- comercio, subastas, buzón y bóveda:
--   Dur        durabilidad actual (sin valor = entera)
--   Reforjas   cuántas veces se reforjó (encarece la siguiente)
--   Gema1..3   id de la gema engarzada en cada ranura

local ItemCatalog = require(script.Parent.ItemCatalog)
local ItemRarityConfig = require(script.Parent.ItemRarityConfig)

export type Operacion = "Desencantar" | "Reforjar" | "Engarzar"
export type Gema = { Efecto: string, Valor: number, Texto: string }

local ForjaConfig = {}

------------------------------------------------------------------------
-- Durabilidad
------------------------------------------------------------------------

ForjaConfig.Durabilidad = {
	Maxima = 100,
	PorMuerte = 5, -- puntos que pierde cada pieza equipada al morir
	ProbabilidadPorGolpe = 0.04, -- al recibir un golpe, una pieza al azar pierde 1 punto
	AvisoBajo = 20, -- avisa al jugador al bajar de acá
	-- Oro por punto reparado, según la rareza de la pieza.
	CostoPorPunto = { Comun = 0.5, Raro = 1, Epico = 2, Mistico = 3.5, Unico = 5 } :: { [string]: number },
}

-- ¿El ítem se desgasta? Solo el equipo (no las herramientas ni los cosméticos).
function ForjaConfig.TieneDurabilidad(item: any): boolean
	local def = if typeof(item) == "table" then ItemCatalog[item.ItemId] else nil
	return def ~= nil and def.Tipo == "Equipo"
end

-- Durabilidad actual (0 a Maxima). Un ítem sin dato está entero.
function ForjaConfig.DurabilidadDe(item: any): number
	local meta = if typeof(item) == "table" then item.Meta else nil
	local dur = if typeof(meta) == "table" then meta.Dur else nil
	if typeof(dur) ~= "number" then
		return ForjaConfig.Durabilidad.Maxima
	end
	return math.clamp(math.floor(dur), 0, ForjaConfig.Durabilidad.Maxima)
end

-- Un equipo roto no da estadísticas hasta que se repara.
function ForjaConfig.Roto(item: any): boolean
	return ForjaConfig.TieneDurabilidad(item) and ForjaConfig.DurabilidadDe(item) <= 0
end

-- Oro que cuesta dejarlo entero (0 si no hace falta).
function ForjaConfig.CostoReparar(item: any): number
	if not ForjaConfig.TieneDurabilidad(item) then
		return 0
	end
	local faltan = ForjaConfig.Durabilidad.Maxima - ForjaConfig.DurabilidadDe(item)
	if faltan <= 0 then
		return 0
	end
	local porPunto = ForjaConfig.Durabilidad.CostoPorPunto[item.Rareza] or 1
	return math.max(1, math.ceil(faltan * porPunto))
end

------------------------------------------------------------------------
-- Desencantar
------------------------------------------------------------------------

ForjaConfig.Desencantar = {
	Costo = 25,
	-- Lo que devuelve destruir un equipo, según su rareza. El equipo Común no
	-- tiene magia: no se desencanta (el Chatarrero lo desmantela por chatarra).
	Resultado = {
		Raro = { PolvoEncantamiento = 2 },
		Epico = { EsenciaMagica = 2, PolvoEncantamiento = 1 },
		Mistico = { EsenciaMayor = 1, EsenciaMagica = 2 },
		Unico = { FragmentoReliquia = 1, EsenciaMayor = 2 },
	} :: { [string]: { [string]: number } },
}

------------------------------------------------------------------------
-- Reforjar: cambia cuáles son los efectos secundarios del ítem. Conserva la
-- calidad (Mult), la pasiva, las gemas y la durabilidad.
------------------------------------------------------------------------

ForjaConfig.Reforjar = {
	Costo = { Raro = 500, Epico = 1500, Mistico = 4000, Unico = 10000 } :: { [string]: number },
	AumentoPorReforja = 0.25, -- cada reforja previa encarece 25% la siguiente
	MaximoAumento = 3, -- el recargo no pasa de +300%
	Material = "PolvoEncantamiento",
	CantidadMaterial = 2,
}

------------------------------------------------------------------------
-- Gemas
------------------------------------------------------------------------

ForjaConfig.Engarzar = {
	Costo = 300,
	Material = "EsenciaMagica",
	CantidadMaterial = 1,
	RanurasPorRareza = { Comun = 0, Raro = 1, Epico = 2, Mistico = 2, Unico = 3 } :: { [string]: number },
	-- Cada gema suma un efecto fijo (los mismos efectos que los secundarios).
	Gemas = {
		Rubi = { Efecto = "Ataque", Valor = 6, Texto = "+6 ataque" },
		Amatista = { Efecto = "Poder", Valor = 6, Texto = "+6 poder" },
		Zafiro = { Efecto = "Defensa", Valor = 8, Texto = "+8 defensa" },
		Esmeralda = { Efecto = "RegenMana", Valor = 2, Texto = "+2 maná por segundo" },
		Diamante = { Efecto = "Critico", Valor = 3, Texto = "+3% probabilidad de crítico" },
	} :: { [string]: Gema },
}

function ForjaConfig.RanurasGema(item: any): number
	if not ForjaConfig.TieneDurabilidad(item) then
		return 0
	end
	return ForjaConfig.Engarzar.RanurasPorRareza[item.Rareza] or 0
end

-- Ids de las gemas engarzadas, en orden de ranura.
function ForjaConfig.GemasDe(item: any): { string }
	local lista: { string } = {}
	local meta = if typeof(item) == "table" then item.Meta else nil
	if typeof(meta) ~= "table" then
		return lista
	end
	for i = 1, 3 do
		local gema = meta["Gema" .. i]
		if typeof(gema) == "string" and ForjaConfig.Engarzar.Gemas[gema] then
			table.insert(lista, gema)
		end
	end
	return lista
end

------------------------------------------------------------------------
-- Operaciones sobre un ítem de la mochila
------------------------------------------------------------------------

local function esEquipoMagico(item: any): boolean
	if not ForjaConfig.TieneDurabilidad(item) then
		return false
	end
	local rareza = ItemRarityConfig.Rarezas[item.Rareza]
	return rareza ~= nil and rareza.EfectosSecundarios > 0
end

-- ¿La operación se puede hacer sobre ese ítem?
function ForjaConfig.Aplica(operacion: string, item: any): boolean
	if operacion == "Desencantar" then
		return esEquipoMagico(item) and ForjaConfig.Desencantar.Resultado[item.Rareza] ~= nil
	elseif operacion == "Reforjar" then
		return esEquipoMagico(item) and ForjaConfig.Reforjar.Costo[item.Rareza] ~= nil
	elseif operacion == "Engarzar" then
		return #ForjaConfig.GemasDe(item) < ForjaConfig.RanurasGema(item)
	end
	return false
end

-- Oro que cuesta la operación sobre ese ítem.
function ForjaConfig.Costo(operacion: string, item: any): number
	if operacion == "Desencantar" then
		return ForjaConfig.Desencantar.Costo
	elseif operacion == "Engarzar" then
		return ForjaConfig.Engarzar.Costo
	elseif operacion == "Reforjar" then
		local base = ForjaConfig.Reforjar.Costo[item.Rareza] or 0
		local meta = if typeof(item) == "table" then item.Meta else nil
		local previas = if typeof(meta) == "table" and typeof(meta.Reforjas) == "number" then meta.Reforjas else 0
		local recargo = math.min(previas * ForjaConfig.Reforjar.AumentoPorReforja, ForjaConfig.Reforjar.MaximoAumento)
		return math.floor(base * (1 + recargo))
	end
	return 0
end

-- Material (además del oro) que consume la operación: (itemId, cantidad) o nil.
function ForjaConfig.Material(operacion: string): (string?, number)
	if operacion == "Reforjar" then
		return ForjaConfig.Reforjar.Material, ForjaConfig.Reforjar.CantidadMaterial
	elseif operacion == "Engarzar" then
		return ForjaConfig.Engarzar.Material, ForjaConfig.Engarzar.CantidadMaterial
	end
	return nil, 0
end

return ForjaConfig
