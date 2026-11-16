--!strict
-- Construcción en parcelas: muebles, huerta y patio de mascotas.
-- Es la segunda mitad del pedido de parcelas (ver ParcelasConfig).
--
-- Reglas puras: qué se puede poner, cuánto mide, cuánto cuesta, dónde entra y
-- cuánto tarda en crecer lo que se planta. Quién puede construir lo decide
-- ParcelaManager (dueño o socio).
--
-- Las posiciones se guardan **relativas al centro de la parcela**, así una
-- parcela se puede mudar o fusionar sin que lo construido se desarme.

export type Categoria = "Estructura" | "Mueble" | "Huerta" | "Mascotas"

export type Pieza = {
	Id: string,
	Nombre: string,
	Categoria: Categoria,
	Descripcion: string,
	Precio: number,
	Tamano: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Limite: number?, -- cuántas de estas entran en una parcela (nil = sin límite propio)
}

export type Cultivo = {
	Semilla: string, -- ItemId de la semilla
	Nombre: string,
	Cosecha: string, -- ItemId de lo que sale
	Min: number,
	Max: number,
	Horas: number, -- cuánto tarda en estar listo
}

local Config = {}

Config.MaxPiezas = 40
Config.Paso = 2 -- la grilla a la que se acomodan las piezas, en studs
Config.AlturaMaxima = 24
Config.Margen = 2 -- cuánto hay que dejar libre contra el borde de la parcela
Config.DistanciaConstruir = 60 -- desde dónde se puede poner o sacar una pieza

Config.Piezas = {
	-- Estructura
	{
		Id = "Piso",
		Nombre = "Piso de madera",
		Categoria = "Estructura",
		Descripcion = "Una plataforma para armar encima.",
		Precio = 120,
		Tamano = Vector3.new(8, 1, 8),
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.WoodPlanks,
	},
	{
		Id = "Pared",
		Nombre = "Pared",
		Categoria = "Estructura",
		Descripcion = "Pared de piedra de ocho de largo.",
		Precio = 160,
		Tamano = Vector3.new(8, 8, 1),
		Color = Color3.fromRGB(165, 160, 150),
		Material = Enum.Material.Concrete,
	},
	{
		Id = "Techo",
		Nombre = "Techo",
		Categoria = "Estructura",
		Descripcion = "Para que la lluvia caiga afuera.",
		Precio = 200,
		Tamano = Vector3.new(10, 1, 10),
		Color = Color3.fromRGB(120, 60, 50),
		Material = Enum.Material.Slate,
	},
	{
		Id = "Puerta",
		Nombre = "Marco de puerta",
		Categoria = "Estructura",
		Descripcion = "Un hueco con marco, para entrar.",
		Precio = 180,
		Tamano = Vector3.new(4, 8, 1),
		Color = Color3.fromRGB(110, 80, 55),
		Material = Enum.Material.Wood,
	},
	-- Muebles
	{
		Id = "Mesa",
		Nombre = "Mesa",
		Categoria = "Mueble",
		Descripcion = "Una mesa larga de taberna.",
		Precio = 90,
		Tamano = Vector3.new(6, 3, 3),
		Color = Color3.fromRGB(140, 100, 65),
		Material = Enum.Material.Wood,
	},
	{
		Id = "Silla",
		Nombre = "Silla",
		Categoria = "Mueble",
		Descripcion = "Para sentarse de verdad.",
		Precio = 45,
		Tamano = Vector3.new(2, 4, 2),
		Color = Color3.fromRGB(130, 95, 60),
		Material = Enum.Material.Wood,
	},
	{
		Id = "Fogata",
		Nombre = "Fogata",
		Categoria = "Mueble",
		Descripcion = "Luz, calor y un lugar donde juntarse.",
		Precio = 140,
		Tamano = Vector3.new(4, 2, 4),
		Color = Color3.fromRGB(90, 70, 60),
		Material = Enum.Material.Slate,
	},
	{
		Id = "Estandarte",
		Nombre = "Estandarte",
		Categoria = "Mueble",
		Descripcion = "Un estandarte con el color de tu bando.",
		Precio = 250,
		Tamano = Vector3.new(1, 10, 1),
		Color = Color3.fromRGB(80, 75, 90),
		Material = Enum.Material.Fabric,
	},
	-- Huerta
	{
		Id = "Cantero",
		Nombre = "Cantero",
		Categoria = "Huerta",
		Descripcion = "Se planta una semilla y se cosecha cuando está lista.",
		Precio = 300,
		Tamano = Vector3.new(6, 2, 6),
		Color = Color3.fromRGB(95, 70, 45),
		Material = Enum.Material.Ground,
		Limite = 6,
	},
	-- Mascotas
	{
		Id = "PatioMascotas",
		Nombre = "Patio de mascotas",
		Categoria = "Mascotas",
		Descripcion = "Tus mascotas compradas se pasean acá cuando no las llevás.",
		Precio = 800,
		Tamano = Vector3.new(12, 1, 12),
		Color = Color3.fromRGB(110, 140, 95),
		Material = Enum.Material.Grass,
		Limite = 1,
	},
} :: { Pieza }

-- Lo que se puede plantar en un cantero.
Config.Cultivos = {
	{
		Semilla = "SemillaHierba",
		Nombre = "Hierba sanadora",
		Cosecha = "HierbaSanadora",
		Min = 3,
		Max = 5,
		Horas = 1,
	},
	{
		Semilla = "SemillaCocina",
		Nombre = "Hierbas de cocina",
		Cosecha = "HierbasCocina",
		Min = 3,
		Max = 6,
		Horas = 2,
	},
	{
		Semilla = "SemillaLunar",
		Nombre = "Flor lunar",
		Cosecha = "FlorLunar",
		Min = 2,
		Max = 4,
		Horas = 6,
	},
	{
		Semilla = "SemillaLino",
		Nombre = "Lino",
		Cosecha = "Lino",
		Min = 4,
		Max = 7,
		Horas = 4,
	},
} :: { Cultivo }

function Config.Pieza(id: string): Pieza?
	for _, pieza in Config.Piezas do
		if pieza.Id == id then
			return pieza
		end
	end
	return nil
end

function Config.Cultivo(semilla: string): Cultivo?
	for _, cultivo in Config.Cultivos do
		if cultivo.Semilla == semilla then
			return cultivo
		end
	end
	return nil
end

-- Redondea a la grilla, para que lo construido quede prolijo y sea más difícil
-- encajar piezas en huecos imposibles.
function Config.Acomodar(valor: number): number
	return math.round(valor / Config.Paso) * Config.Paso
end

-- Medidas de la pieza ya girada (solo se gira de a 90°, así que girar impar
-- intercambia ancho y profundidad).
function Config.TamanoGirado(pieza: Pieza, giro: number): Vector3
	if giro % 2 == 1 then
		return Vector3.new(pieza.Tamano.Z, pieza.Tamano.Y, pieza.Tamano.X)
	end
	return pieza.Tamano
end

function Config.GiroValido(giro: number): boolean
	return giro == math.floor(giro) and giro >= 0 and giro <= 3
end

-- ¿La pieza entra en una parcela de ese lado, puesta en esa posición relativa?
-- `alto` es la altura del centro de la pieza sobre el piso de la parcela.
function Config.Entra(lado: number, pieza: Pieza, giro: number, x: number, alto: number, z: number): boolean
	local tamano = Config.TamanoGirado(pieza, giro)
	local limite = lado / 2 - Config.Margen
	if math.abs(x) + tamano.X / 2 > limite then
		return false
	end
	if math.abs(z) + tamano.Z / 2 > limite then
		return false
	end
	if alto - tamano.Y / 2 < -0.5 then
		return false -- no se construye bajo tierra
	end
	if alto + tamano.Y / 2 > Config.AlturaMaxima then
		return false
	end
	return true
end

-- ¿Dos piezas puestas se pisan? (cajas alineadas a los ejes)
function Config.SePisan(
	piezaA: Pieza,
	giroA: number,
	posA: Vector3,
	piezaB: Pieza,
	giroB: number,
	posB: Vector3
): boolean
	local a = Config.TamanoGirado(piezaA, giroA)
	local b = Config.TamanoGirado(piezaB, giroB)
	-- Se tocan de canto no cuenta: hace falta superposición real.
	local margen = 0.01
	return math.abs(posA.X - posB.X) < (a.X + b.X) / 2 - margen
		and math.abs(posA.Y - posB.Y) < (a.Y + b.Y) / 2 - margen
		and math.abs(posA.Z - posB.Z) < (a.Z + b.Z) / 2 - margen
end

-- ¿Ya está lista la cosecha?
function Config.Lista(cultivo: Cultivo, plantadoEn: number, ahora: number): boolean
	return ahora >= plantadoEn + cultivo.Horas * 3600
end

-- Cuánto falta, en segundos (0 si ya está).
function Config.Falta(cultivo: Cultivo, plantadoEn: number, ahora: number): number
	return math.max(0, plantadoEn + cultivo.Horas * 3600 - ahora)
end

-- Lo mínimo que esta config necesita saber de una pieza puesta. El registro
-- real (ParcelaManager.Puesta) trae más campos, y entra igual acá.
export type Colocada = { Pieza: string, [string]: any }

-- Cuántas piezas de ese tipo hay ya puestas.
function Config.Cuantas(puestas: { Colocada }, piezaId: string): number
	local cuenta = 0
	for _, puesta in puestas do
		if puesta.Pieza == piezaId then
			cuenta += 1
		end
	end
	return cuenta
end

-- ¿Se puede agregar otra de estas? (límite propio y tope de la parcela)
function Config.PuedeAgregar(puestas: { Colocada }, pieza: Pieza): boolean
	if #puestas >= Config.MaxPiezas then
		return false
	end
	if pieza.Limite and Config.Cuantas(puestas, pieza.Id) >= pieza.Limite then
		return false
	end
	return true
end

return Config
