--!strict
-- PersonalizadorConfig: números y formato de datos del NPC vendedor y
-- personalizador de armas y armaduras.
--
-- El catálogo NO está acá: se lee de los modelos que haya en
-- ReplicatedStorage.CustomizableItems.Armas y .Armaduras (ver docs/personalizador.md).
--
-- Las funciones de este módulo son puras; las usan el servidor (para validar,
-- cobrar y guardar) y el cliente (para mostrar). Nada de lo que calcule el
-- cliente es autoridad.
--
-- Personalización guardada en el ítem (`Meta.Pers`): un texto compacto con solo
-- las piezas que cambian respecto del modelo original:
--     "1|Hoja=Metal,A0B1C2|Guarda=Wood,7F5533"
--      ^ versión del esquema    ^ id de pieza = Material,color RRGGBB

export type Pieza = { Material: string, Color: string } -- Color: "RRGGBB"
export type Personalizacion = { [string]: Pieza } -- id de pieza -> material y color

local Config = {}

Config.Version = 1
Config.Carpeta = "CustomizableItems"
-- Subcarpeta -> tipo de ítem
Config.Subcarpetas = { Armas = "Arma", Armaduras = "Armadura" } :: { [string]: string }
Config.TagNpc = "NpcPersonalizador"

Config.DistanciaMaxima = 15 -- studs al NPC para abrir y para comprar
Config.MaxPiezas = 32 -- piezas editables por modelo (y entradas que acepta el servidor)
Config.LargoIdPieza = 64
Config.LargoRequestId = 64
Config.ComprasRecordadas = 20 -- últimas compras guardadas en el perfil (reintentos)

-- Precio = BasePrice del modelo + CostoPorPieza por cada pieza modificada.
Config.CostoPorPieza = 25

-- Cámara del probador
Config.Camara = {
	Distancia = 9,
	DistanciaMinima = 5,
	DistanciaMaxima = 14,
	Altura = 1.5,
	CampoVision = 50,
	Transicion = 0.6, -- segundos del movimiento de entrada
	GradosPorPixel = 0.4,
}

-- Paleta rápida (además del RGB y el hexadecimal)
Config.Paleta = {
	"FFFFFF",
	"C8C8C8",
	"8C8C8C",
	"3C3C3C",
	"141414",
	"7A4A2A",
	"C0392B",
	"E67E22",
	"F1C40F",
	"2ECC71",
	"1ABC9C",
	"3498DB",
	"2C3E90",
	"8E44AD",
	"E84393",
	"D4AF37",
	"B87333",
	"A5AAB4",
} :: { string }

-- Dónde se monta cada slot si el modelo no lo dice (atributo `Anclaje`).
Config.AnclajePorSlot = {
	ArmaPrincipal = "ManoDerecha",
	ArmaSecundaria = "ManoIzquierda",
	Casco = "Cabeza",
	Pechera = "Torso",
} :: { [string]: string }

-- Anclajes con nombre propio -> partes del cuerpo (R15 primero, después R6).
-- Como `Anclaje` también se acepta el nombre directo de una parte del cuerpo
-- (por ejemplo "LeftFoot" para una bota).
Config.Anclajes = {
	ManoDerecha = { "RightHand", "Right Arm" },
	ManoIzquierda = { "LeftHand", "Left Arm" },
	Cabeza = { "Head" },
	Torso = { "UpperTorso", "Torso" },
} :: { [string]: { string } }

------------------------------------------------------------------------
-- Validadores y formato (puros)
------------------------------------------------------------------------

-- ¿Es un color "RRGGBB"?
function Config.HexValido(valor: any): boolean
	return typeof(valor) == "string" and #valor == 6 and string.match(valor, "^%x%x%x%x%x%x$") ~= nil
end

-- Id de pieza: ruta relativa dentro del modelo ("Hoja", "Guarda/Gema#2").
-- No puede llevar los separadores del formato guardado.
function Config.IdPiezaValido(valor: any): boolean
	return typeof(valor) == "string"
		and #valor >= 1
		and #valor <= Config.LargoIdPieza
		and string.match(valor, "^[%w_ /#%-%.]+$") ~= nil
end

-- Nombre de material: solo letras y números (los nombres de Enum.Material).
function Config.NombreMaterialValido(valor: any): boolean
	return typeof(valor) == "string" and #valor >= 1 and #valor <= 40 and string.match(valor, "^%w+$") ~= nil
end

function Config.RequestIdValido(valor: any): boolean
	return typeof(valor) == "string"
		and #valor >= 8
		and #valor <= Config.LargoRequestId
		and string.match(valor, "^[%w%-]+$") ~= nil
end

-- Texto compacto para guardar en el ítem. Las piezas van ordenadas por id, así
-- la misma personalización siempre da el mismo texto.
function Config.Codificar(personalizacion: Personalizacion): string
	local ids: { string } = {}
	for id in personalizacion do
		table.insert(ids, id)
	end
	table.sort(ids)
	local partes: { string } = { tostring(Config.Version) }
	for _, id in ids do
		local pieza = personalizacion[id]
		table.insert(partes, `{id}={pieza.Material},{string.upper(pieza.Color)}`)
	end
	return table.concat(partes, "|")
end

-- Inversa de Codificar. Devuelve nil si el texto no tiene el formato esperado
-- (versión desconocida, piezas de más, ids o colores inválidos).
function Config.Decodificar(texto: any): Personalizacion?
	if typeof(texto) ~= "string" or #texto > 4096 then
		return nil
	end
	local partes = string.split(texto, "|")
	if tonumber(partes[1]) ~= Config.Version or #partes - 1 > Config.MaxPiezas then
		return nil
	end
	local resultado: Personalizacion = {}
	for i = 2, #partes do
		local id, material, color = string.match(partes[i], "^(.-)=(%w+),(%x+)$")
		if
			not id
			or not Config.IdPiezaValido(id)
			or not Config.NombreMaterialValido(material)
			or not Config.HexValido(color)
			or resultado[id] ~= nil
		then
			return nil
		end
		resultado[id] = { Material = material :: string, Color = string.upper(color :: string) }
	end
	return resultado
end

-- Precio final de un modelo con `modificadas` piezas cambiadas.
function Config.Precio(base: number, modificadas: number): number
	return math.floor(base) + Config.CostoPorPieza * math.max(0, math.floor(modificadas))
end

-- Componentes 0..255 de un color "RRGGBB" (o nil si no es válido).
function Config.DeHex(hex: any): (number?, number?, number?)
	if not Config.HexValido(hex) then
		return nil, nil, nil
	end
	return tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16)
end

-- "RRGGBB" a partir de componentes; nil si alguno no es un número finito.
-- Los valores se redondean y se limitan a 0..255.
function Config.AHex(r: any, g: any, b: any): string?
	local salida: { number } = {}
	for _, v in { r, g, b } do
		if typeof(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
			return nil
		end
		table.insert(salida, math.clamp(math.floor(v + 0.5), 0, 255))
	end
	if #salida ~= 3 then
		return nil
	end
	return string.format("%02X%02X%02X", salida[1], salida[2], salida[3])
end

return Config
