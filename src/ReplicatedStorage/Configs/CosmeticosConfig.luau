--!strict
-- NPC Cosméticos: un solo lugar para la estética del equipo que tenés puesto.
--
-- Absorbe lo que antes estaba repartido entre el Transfigurador (#30, cambiar
-- la visual del arma) y el Tintorero (#31, colores), y la parte de grabado del
-- Inscriptor (#5), que queda solo con pergaminos y libros.
--
-- Cuatro pestañas, todas sobre los ítems **equipados**:
--   1. Visual   — le cambia el aspecto al arma sin tocar sus estadísticas.
--                 Las apariencias son prediseñadas: las que desbloqueás al
--                 tener el ítem, más las skins que se compran con Robux.
--   2. Colores  — el color de cada pieza del objeto.
--   3. Decals   — calcomanías de color, agrupadas por tipo.
--   4. Marcas   — grabados con normal map (relieve).
--
-- Al abrir, el NPC muestra la ventana con una cámara mirando al personaje: lo
-- que se ve es exactamente lo que se va a aplicar.
--
-- Qué se paga: aplicar lo que ya tenés desbloqueado es gratis. Lo que cuesta
-- es **deshacer**: el primer arrepentimiento es gratis y de ahí en adelante
-- cada uno vale el doble del anterior. Es caro a propósito, para que la
-- decisión se tome mirando el preview y no probando a ciegas.

export type Pestana = "Visual" | "Colores" | "Decals" | "Marcas"

local Config = {}

Config.Pestanas = { "Visual", "Colores", "Decals", "Marcas" } :: { Pestana }

Config.NombrePestana = {
	Visual = "Visual",
	Colores = "Colores",
	Decals = "Decals",
	Marcas = "Marcas",
}

Config.Distancia = 16 -- hasta dónde se puede estar del NPC
Config.LargoRequestId = 48

-- Deshacer: el primero gratis, el segundo Base, el tercero Base × Factor, y así.
Config.DeshacerGratis = 1
Config.DeshacerBase = 2500
Config.DeshacerFactor = 2
Config.DeshacerTope = 320000 -- techo, para que no se vuelva un número absurdo

-- Cámara del preview: orbita al personaje.
Config.Camara = {
	Distancia = 12,
	Altura = 3,
	AnguloInicial = 35, -- grados, desde el frente
	DistanciaMin = 6,
	DistanciaMax = 22,
	VelocidadGiro = 0.4,
}

-- Cuánto cuesta el próximo deshacer, sabiendo cuántos ya hizo el jugador.
-- 0, 1, 2, 3 previos -> gratis, Base, Base×2, Base×4...
function Config.CostoDeshacer(deshechosPrevios: number): number
	local previos = math.max(0, math.floor(deshechosPrevios))
	if previos < Config.DeshacerGratis then
		return 0
	end
	local pasos = previos - Config.DeshacerGratis
	local costo = Config.DeshacerBase * Config.DeshacerFactor ^ pasos
	return math.min(Config.DeshacerTope, math.floor(costo))
end

-- Texto corto para la interfaz ("gratis" o el precio).
function Config.TextoDeshacer(deshechosPrevios: number): string
	local costo = Config.CostoDeshacer(deshechosPrevios)
	return if costo <= 0 then "gratis" else `{costo} de oro`
end

-- ¿Esta pestaña trabaja sobre la personalización del ítem (Meta.Pers) o sobre
-- el transmog del slot? Sirve para no mezclar las dos cosas en el servidor.
function Config.EsDePersonalizacion(pestana: string): boolean
	return pestana == "Colores" or pestana == "Decals" or pestana == "Marcas"
end

function Config.PestanaValida(pestana: unknown): boolean
	if typeof(pestana) ~= "string" then
		return false
	end
	return table.find(Config.Pestanas, pestana :: any) ~= nil
end

return Config
