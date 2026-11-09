--!strict
-- AspectoPiedra: valores editables de la piedra del castillo (lo usan el NPC
-- editor en el servidor y la ventana en el cliente).
--
-- Solo incluye lo que un juego puede cambiar mientras corre: material, color,
-- reflejo, transparencia y propiedades físicas. Los mapas de metalicidad y
-- rugosidad (MaterialVariant / SurfaceAppearance) solo se pueden cambiar en
-- Studio, no desde un script del juego.

local CollectionService = game:GetService("CollectionService")

local AspectoPiedra = {}

-- Etiqueta de las partes que usan la piedra del castillo (las construidas con
-- la skin "Ninguna" y la muestra junto al NPC).
AspectoPiedra.Etiqueta = "PiedraCastillo"

export type Valores = {
	Material: string, -- nombre de Enum.Material
	Color: { number }, -- {R, G, B} de 0 a 255
	Reflejo: number, -- 0 a 1 (Reflectance: brillo tipo espejo/metal)
	Transparencia: number,
	Densidad: number,
	Friccion: number,
	Elasticidad: number,
}

-- Materiales que se pueden elegir (nombre del Enum -> nombre en pantalla).
AspectoPiedra.Materiales = {
	{ "Cobblestone", "Adoquín" },
	{ "Slate", "Pizarra" },
	{ "Brick", "Ladrillo" },
	{ "Granite", "Granito" },
	{ "Basalt", "Basalto" },
	{ "Limestone", "Caliza" },
	{ "Marble", "Mármol" },
	{ "Rock", "Roca" },
	{ "Sandstone", "Arenisca" },
	{ "Concrete", "Concreto" },
	{ "Pavement", "Pavimento" },
	{ "Pebble", "Canto rodado" },
	{ "Glacier", "Glaciar" },
	{ "CrackedLava", "Lava agrietada" },
	{ "Metal", "Metal" },
	{ "DiamondPlate", "Chapa" },
	{ "CorrodedMetal", "Metal oxidado" },
	{ "Wood", "Madera" },
	{ "SmoothPlastic", "Liso" },
}

AspectoPiedra.Rangos = {
	Reflejo = { 0, 1 },
	Transparencia = { 0, 0.5 }, -- más de 0,5 y la piedra casi no se ve
	Densidad = { 0.1, 20 },
	Friccion = { 0, 2 },
	Elasticidad = { 0, 1 },
}

local enumPorNombre: { [string]: Enum.Material } = {}
for _, par in AspectoPiedra.Materiales do
	local ok, valor = pcall(function(): Enum.Material
		return (Enum.Material :: any)[par[1]]
	end)
	if ok and valor then
		enumPorNombre[par[1]] = valor
	end
end

function AspectoPiedra.Enum(nombre: string): Enum.Material
	return enumPorNombre[nombre] or Enum.Material.Cobblestone
end

-- Valores iniciales a partir de un material y un color.
function AspectoPiedra.Desde(material: Enum.Material, color: Color3): Valores
	local fisica = PhysicalProperties.new(material)
	return {
		Material = material.Name,
		Color = { math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255) },
		Reflejo = 0,
		Transparencia = 0,
		Densidad = fisica.Density,
		Friccion = fisica.Friction,
		Elasticidad = fisica.Elasticity,
	}
end

local function numero(v: unknown, rango: { number }): number?
	if typeof(v) ~= "number" or v ~= v then
		return nil
	end
	return math.clamp(v :: number, rango[1], rango[2])
end

-- Valida lo que llega por la red (o del DataStore). nil si algo no cierra.
function AspectoPiedra.Validar(v: unknown): Valores?
	if typeof(v) ~= "table" then
		return nil
	end
	local t = v :: { [string]: unknown }
	local material = t.Material
	local color = t.Color
	if typeof(material) ~= "string" or not enumPorNombre[material :: string] or typeof(color) ~= "table" then
		return nil
	end
	local rgb: { number } = {}
	for i = 1, 3 do
		local c = (color :: { unknown })[i]
		if typeof(c) ~= "number" or c ~= c then
			return nil
		end
		rgb[i] = math.clamp(math.round(c :: number), 0, 255)
	end
	local R = AspectoPiedra.Rangos
	local reflejo = numero(t.Reflejo, R.Reflejo)
	local transparencia = numero(t.Transparencia, R.Transparencia)
	local densidad = numero(t.Densidad, R.Densidad)
	local friccion = numero(t.Friccion, R.Friccion)
	local elasticidad = numero(t.Elasticidad, R.Elasticidad)
	if not reflejo or not transparencia or not densidad or not friccion or not elasticidad then
		return nil
	end
	return {
		Material = material :: string,
		Color = rgb,
		Reflejo = reflejo,
		Transparencia = transparencia,
		Densidad = densidad,
		Friccion = friccion,
		Elasticidad = elasticidad,
	}
end

function AspectoPiedra.Color(v: Valores): Color3
	return Color3.fromRGB(v.Color[1], v.Color[2], v.Color[3])
end

-- Aplica los valores a una parte. La física solo la aplica el servidor.
function AspectoPiedra.Aplicar(parte: BasePart, v: Valores, conFisica: boolean)
	parte.Material = AspectoPiedra.Enum(v.Material)
	parte.Color = AspectoPiedra.Color(v)
	parte.Reflectance = v.Reflejo
	parte.Transparency = v.Transparencia
	if conFisica then
		parte.CustomPhysicalProperties = PhysicalProperties.new(v.Densidad, v.Friccion, v.Elasticidad)
	end
end

function AspectoPiedra.AplicarATodas(v: Valores, conFisica: boolean)
	for _, objeto in CollectionService:GetTagged(AspectoPiedra.Etiqueta) do
		if objeto:IsA("BasePart") then
			AspectoPiedra.Aplicar(objeto, v, conFisica)
		end
	end
end

local function dos(n: number): string
	return string.format("%.2f", n)
end

-- Texto para pegar en GuerraConfig.Skins.Ninguna (o mandárselo al programador).
function AspectoPiedra.Codigo(v: Valores): string
	return `Ninguna = \{ Material = Enum.Material.{v.Material}, Color = Color3.fromRGB({v.Color[1]}, {v.Color[2]}, {v.Color[3]}), `
		.. `Reflejo = {dos(v.Reflejo)}, Transparencia = {dos(v.Transparencia)}, `
		.. `Fisica = \{ Densidad = {dos(v.Densidad)}, Friccion = {dos(v.Friccion)}, Elasticidad = {dos(v.Elasticidad)} } },`
end

return AspectoPiedra
