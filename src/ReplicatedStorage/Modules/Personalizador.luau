--!strict
-- Personalizador: lógica compartida entre cliente y servidor del NPC vendedor
-- y personalizador (materiales válidos, catálogo de modelos, ids de piezas,
-- aplicar una personalización y montar un modelo sobre un personaje).
--
-- El cliente lo usa para la vista previa; el servidor, para validar la compra
-- y para dibujar el equipo real. Que los dos usen el mismo código garantiza
-- que lo que se ve en el probador es lo que se entrega.
--
-- Contrato de un modelo de ReplicatedStorage.CustomizableItems (docs/personalizador.md):
--   Atributos:  ItemID (clave de ItemCatalog), BasePrice; opcionales DisplayName,
--               Description, ItemType, EquipSlot, RequiredLevel, Anclaje.
--   Handle:     una BasePart llamada "Handle" (o la PrimaryPart). Es el punto de
--               montaje: se alinea con la mano, la cabeza o el torso.
--   Piezas:     toda BasePart visible es editable, salvo "Handle" y las que
--               tengan el atributo NoEditable = true.
--   Submodelos: un Model hijo con atributo `Anclaje` y su propio "Handle" se
--               monta en otra parte del cuerpo (hombreras, guantes, botas).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Configs.PersonalizadorConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)

export type InfoPieza = {
	Id: string, -- ruta canónica dentro del modelo
	Nombre: string,
	Parte: BasePart, -- la pieza de la PLANTILLA (no modificar)
	Material: string, -- material original
	Color: string, -- color original "RRGGBB"
}

export type Entrada = {
	ItemId: string,
	Modelo: Model, -- plantilla: siempre se clona, nunca se modifica
	Tipo: string, -- "Arma" | "Armadura"
	Nombre: string,
	Descripcion: string,
	Precio: number, -- BasePrice
	Slot: string,
	Nivel: number,
	Piezas: { InfoPieza },
	PorId: { [string]: InfoPieza },
}

local Personalizador = {}

------------------------------------------------------------------------
-- Materiales
------------------------------------------------------------------------

local materiales: { string }? = nil
local materialPorNombre: { [string]: Enum.Material } = {}

-- Nombres de los materiales que acepta una pieza, ordenados. Sale de
-- Enum.Material (sin lista fija): se descartan Air y Water y cualquiera que
-- una Part rechace.
function Personalizador.Materiales(): { string }
	if materiales then
		return materiales
	end
	local lista: { string } = {}
	local prueba = Instance.new("Part")
	for _, material in Enum.Material:GetEnumItems() do
		if material == Enum.Material.Air or material == Enum.Material.Water then
			continue
		end
		local ok = pcall(function()
			prueba.Material = material
		end)
		if ok and prueba.Material == material then
			table.insert(lista, material.Name)
			materialPorNombre[material.Name] = material
		end
	end
	prueba:Destroy()
	table.sort(lista)
	materiales = lista
	return lista
end

function Personalizador.Material(nombre: any): Enum.Material?
	Personalizador.Materiales()
	return if typeof(nombre) == "string" then materialPorNombre[nombre] else nil
end

------------------------------------------------------------------------
-- Colores
------------------------------------------------------------------------

function Personalizador.HexDeColor(color: Color3): string
	return Config.AHex(color.R * 255, color.G * 255, color.B * 255) or "FFFFFF"
end

function Personalizador.ColorDeHex(hex: any): Color3?
	local r, g, b = Config.DeHex(hex)
	if not r or not g or not b then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

------------------------------------------------------------------------
-- Piezas
------------------------------------------------------------------------

local function nombreValido(nombre: string): boolean
	return #nombre >= 1 and string.match(nombre, "^[%w_ %-%.]+$") ~= nil
end

-- El Handle de un modelo o submodelo: su PrimaryPart o un hijo "Handle".
local function handleDe(modelo: Model): BasePart?
	local principal = modelo.PrimaryPart
	if principal then
		return principal
	end
	local hijo = modelo:FindFirstChild("Handle")
	return if hijo and hijo:IsA("BasePart") then hijo else nil
end

local function esEditable(parte: BasePart, handles: { [BasePart]: boolean }): boolean
	return not handles[parte] and parte:GetAttribute("NoEditable") ~= true and parte.Transparency < 1
end

-- Piezas editables con su id canónico. El id es la ruta de nombres dentro del
-- modelo; si hay varias piezas con la misma ruta se numeran ("Gema", "Gema#2")
-- en un orden que no depende de cómo se cargó el modelo: por posición.
function Personalizador.Piezas(modelo: Model): ({ InfoPieza }?, string?)
	local raiz = handleDe(modelo)
	if not raiz then
		return nil, 'falta la pieza "Handle" (o definir PrimaryPart)'
	end
	local handles: { [BasePart]: boolean } = { [raiz] = true }
	for _, d in modelo:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Anclaje") ~= nil then
			local h = handleDe(d)
			if not h then
				return nil, `el submodelo "{d.Name}" tiene Anclaje pero le falta su "Handle"`
			end
			handles[h] = true
		end
	end

	local porRuta: { [string]: { BasePart } } = {}
	local rutas: { string } = {}
	for _, d in modelo:GetDescendants() do
		if not d:IsA("BasePart") or not esEditable(d, handles) then
			continue
		end
		local nombres: { string } = {}
		local actual: Instance? = d
		while actual and actual ~= modelo do
			if not nombreValido(actual.Name) then
				return nil, `nombre no permitido: "{actual.Name}" (solo letras, números, espacio, guion, punto y _)`
			end
			table.insert(nombres, 1, actual.Name)
			actual = actual.Parent
		end
		local ruta = table.concat(nombres, "/")
		if not porRuta[ruta] then
			porRuta[ruta] = {}
			table.insert(rutas, ruta)
		end
		table.insert(porRuta[ruta], d)
	end
	table.sort(rutas)

	local inversa = raiz.CFrame:Inverse()
	local function clave(parte: BasePart): (number, number, number)
		local p = inversa * parte.Position
		return math.round(p.X * 100), math.round(p.Y * 100), math.round(p.Z * 100)
	end
	local piezas: { InfoPieza } = {}
	for _, ruta in rutas do
		local grupo = porRuta[ruta]
		table.sort(grupo, function(a: BasePart, b: BasePart): boolean
			local ax, ay, az = clave(a)
			local bx, by, bz = clave(b)
			if ax ~= bx then
				return ax < bx
			elseif ay ~= by then
				return ay < by
			end
			return az < bz
		end)
		for i, parte in grupo do
			local id = if i == 1 then ruta else `{ruta}#{i}`
			if not Config.IdPiezaValido(id) then
				return nil, `la ruta de la pieza "{ruta}" es demasiado larga`
			end
			table.insert(piezas, {
				Id = id,
				Nombre = if i == 1 then parte.Name else `{parte.Name} {i}`,
				Parte = parte,
				Material = parte.Material.Name,
				Color = Personalizador.HexDeColor(parte.Color),
			})
		end
	end
	if #piezas == 0 then
		return nil, "no tiene ninguna pieza visible para personalizar"
	end
	if #piezas > Config.MaxPiezas then
		return nil, `tiene {#piezas} piezas editables (máximo {Config.MaxPiezas}); marcá algunas con NoEditable`
	end
	return piezas, nil
end

------------------------------------------------------------------------
-- Catálogo
------------------------------------------------------------------------

local function numero(valor: any): number?
	if typeof(valor) ~= "number" or valor ~= valor or valor == math.huge or valor == -math.huge then
		return nil
	end
	return valor
end

-- Valida un modelo y arma su entrada de catálogo, o devuelve el motivo del rechazo.
function Personalizador.Analizar(modelo: Model, tipo: string): (Entrada?, string?)
	local itemId = modelo:GetAttribute("ItemID")
	if typeof(itemId) ~= "string" or itemId == "" then
		return nil, "falta el atributo ItemID (texto)"
	end
	local def = ItemCatalog[itemId]
	if not def or def.Tipo ~= "Equipo" or not def.SlotEquipo then
		return nil, `ItemID "{itemId}" no es un equipo de ItemCatalog`
	end
	local precio = numero(modelo:GetAttribute("BasePrice"))
	if not precio or precio < 0 or precio > 10_000_000 then
		return nil, "BasePrice tiene que ser un número entre 0 y 10.000.000"
	end
	local tipoDeclarado = modelo:GetAttribute("ItemType")
	if tipoDeclarado ~= nil and tipoDeclarado ~= tipo then
		return nil, `ItemType dice "{tostring(tipoDeclarado)}" pero está en la carpeta de {tipo}`
	end
	local slot = modelo:GetAttribute("EquipSlot")
	if slot ~= nil and slot ~= def.SlotEquipo then
		return nil, `EquipSlot dice "{tostring(slot)}" pero ItemCatalog dice "{def.SlotEquipo}"`
	end
	local nivelDeclarado = modelo:GetAttribute("RequiredLevel")
	local nivel = numero(nivelDeclarado)
	if nivelDeclarado ~= nil and (not nivel or nivel < 1 or nivel > 1000) then
		return nil, "RequiredLevel tiene que ser un número entre 1 y 1000"
	end
	local anclaje = modelo:GetAttribute("Anclaje")
	if anclaje == nil and not Config.AnclajePorSlot[def.SlotEquipo] then
		return nil,
			`el slot "{def.SlotEquipo}" no tiene montaje por defecto: agregá el atributo Anclaje (por ejemplo "LeftFoot")`
	end
	if anclaje ~= nil and typeof(anclaje) ~= "string" then
		return nil, "Anclaje tiene que ser texto"
	end
	for _, d in modelo:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			return nil, `contiene un script ("{d.Name}"): las plantillas no pueden tener scripts`
		end
	end
	local piezas, motivo = Personalizador.Piezas(modelo)
	if not piezas then
		return nil, motivo
	end
	local porId: { [string]: InfoPieza } = {}
	for _, pieza in piezas do
		porId[pieza.Id] = pieza
	end
	local nombre = modelo:GetAttribute("DisplayName")
	local descripcion = modelo:GetAttribute("Description")
	local entrada: Entrada = {
		ItemId = itemId,
		Modelo = modelo,
		Tipo = tipo,
		Nombre = if typeof(nombre) == "string" and nombre ~= "" then nombre else def.Nombre,
		Descripcion = if typeof(descripcion) == "string" then descripcion else (def.Descripcion or ""),
		Precio = math.floor(precio),
		Slot = def.SlotEquipo,
		Nivel = if nivel then math.floor(nivel) else 1,
		Piezas = piezas,
		PorId = porId,
	}
	return entrada, nil
end

local catalogo: { [string]: Entrada }? = nil
local observando = false

-- Catálogo vigente: ItemID -> entrada. Lee los modelos de las carpetas cada vez
-- que cambian (no hay que registrar nada en el código). Los modelos mal
-- configurados quedan afuera; `avisar` recibe el motivo de cada uno.
function Personalizador.Catalogo(avisar: ((modelo: Model, motivo: string) -> ())?): { [string]: Entrada }
	if catalogo then
		return catalogo
	end
	local nuevo: { [string]: Entrada } = {}
	local carpeta = ReplicatedStorage:FindFirstChild(Config.Carpeta)
	if not carpeta then
		return nuevo -- todavía no existe: no se guarda en caché
	end
	if not observando then
		observando = true
		carpeta.DescendantAdded:Connect(function()
			catalogo = nil
		end)
		carpeta.DescendantRemoving:Connect(function()
			catalogo = nil
		end)
	end
	local repetidos: { [string]: boolean } = {}
	for subcarpeta, tipo in Config.Subcarpetas do
		local origen = carpeta:FindFirstChild(subcarpeta)
		if not origen then
			continue
		end
		for _, hijo in origen:GetChildren() do
			if not hijo:IsA("Model") then
				continue
			end
			local entrada, motivo = Personalizador.Analizar(hijo, tipo)
			if not entrada then
				if avisar then
					avisar(hijo, motivo or "modelo inválido")
				end
			elseif nuevo[entrada.ItemId] or repetidos[entrada.ItemId] then
				-- ItemID repetido: no se vende ninguno de los dos (no hay cómo saber cuál vale).
				repetidos[entrada.ItemId] = true
				nuevo[entrada.ItemId] = nil
				if avisar then
					avisar(hijo, `ItemID repetido: "{entrada.ItemId}"`)
				end
			else
				nuevo[entrada.ItemId] = entrada
			end
		end
	end
	catalogo = nuevo
	return nuevo
end

------------------------------------------------------------------------
-- Personalización
------------------------------------------------------------------------

-- Valida una personalización que viene de afuera (el cliente o un ítem
-- guardado) contra el modelo real. Devuelve solo las piezas que de verdad
-- cambian respecto del original, o nil y el motivo si algo no es válido.
function Personalizador.Normalizar(entrada: Entrada, datos: any): (Config.Personalizacion?, string?)
	if typeof(datos) ~= "table" then
		return nil, "formato inválido"
	end
	local resultado: Config.Personalizacion = {}
	local cantidad = 0
	for id, valor in datos do
		cantidad += 1
		if cantidad > Config.MaxPiezas then
			return nil, "demasiadas piezas"
		end
		if typeof(id) ~= "string" or not Config.IdPiezaValido(id) then
			return nil, "pieza inválida"
		end
		local pieza = entrada.PorId[id]
		if not pieza then
			return nil, `la pieza "{id}" no existe o no se puede editar`
		end
		if typeof(valor) ~= "table" then
			return nil, "formato inválido"
		end
		-- Solo se aceptan los dos campos esperados.
		for campo in valor do
			if campo ~= "Material" and campo ~= "Color" then
				return nil, "propiedad no permitida"
			end
		end
		local material, color = valor.Material, valor.Color
		if not Config.NombreMaterialValido(material) or not Personalizador.Material(material) then
			return nil, "material inválido"
		end
		if not Config.HexValido(color) then
			return nil, "color inválido"
		end
		color = string.upper(color)
		if material ~= pieza.Material or color ~= pieza.Color then
			resultado[id] = { Material = material, Color = color }
		end
	end
	return resultado, nil
end

-- Cuántas piezas cambia una personalización ya normalizada.
function Personalizador.Modificadas(personalizacion: Config.Personalizacion): number
	local n = 0
	for _ in personalizacion do
		n += 1
	end
	return n
end

-- Piezas editables de un CLON, por id. Hay que pedirlo ANTES de montar el clon
-- (mientras sus piezas están donde las dejó la plantilla).
function Personalizador.Mapa(clon: Model): { [string]: BasePart }
	local mapa: { [string]: BasePart } = {}
	local piezas = Personalizador.Piezas(clon)
	if piezas then
		for _, pieza in piezas do
			mapa[pieza.Id] = pieza.Parte
		end
	end
	return mapa
end

-- Aplica la personalización a las piezas de un clon (`mapa` = Personalizador.Mapa).
-- Las piezas que no figuran quedan como en el original.
function Personalizador.Aplicar(entrada: Entrada, mapa: { [string]: BasePart }, personalizacion: Config.Personalizacion)
	for id, parte in mapa do
		local original = entrada.PorId[id]
		if not original then
			continue
		end
		local cambio = personalizacion[id]
		local material = Personalizador.Material(if cambio then cambio.Material else original.Material)
		local color = Personalizador.ColorDeHex(if cambio then cambio.Color else original.Color)
		if material then
			parte.Material = material
		end
		if color then
			parte.Color = color
		end
	end
end

------------------------------------------------------------------------
-- Montaje sobre un personaje
------------------------------------------------------------------------

-- Parte del cuerpo de un anclaje y el ajuste fino para ese cuerpo (R15 o R6).
local function parteDelCuerpo(personaje: Model, anclaje: string): (BasePart?, CFrame)
	local nombres: { string } = Config.Anclajes[anclaje] or { anclaje }
	for _, nombre in nombres do
		local parte = personaje:FindFirstChild(nombre)
		if parte and parte:IsA("BasePart") then
			local ajuste = CFrame.identity
			if anclaje == "ManoDerecha" or anclaje == "ManoIzquierda" then
				-- La mano de R15 es corta; el brazo de R6 llega más abajo.
				ajuste = CFrame.new(0, if nombre == "RightHand" or nombre == "LeftHand" then -0.15 else -1, 0)
			elseif anclaje == "Torso" and nombre == "UpperTorso" then
				ajuste = CFrame.new(0, -0.1, 0)
			end
			return parte, ajuste
		end
	end
	return nil, CFrame.identity
end

-- Suelda un CLON del modelo al personaje: cada Handle se alinea con su parte
-- del cuerpo y las demás piezas conservan su posición relativa. Las piezas
-- quedan sin colisión, sin masa y sin contacto: no afectan al personaje.
-- `slot`: slot donde va puesto (un arma en ArmaSecundaria va a la otra mano).
-- Devuelve false y el motivo si falta la parte del cuerpo o el montaje.
function Personalizador.Montar(clon: Model, personaje: Model, slot: string): (boolean, string?)
	local raiz = handleDe(clon)
	if not raiz then
		return false, 'falta la pieza "Handle"'
	end
	local declarado = clon:GetAttribute("Anclaje")
	local anclajeRaiz: string? = if slot == "ArmaSecundaria"
		then "ManoIzquierda"
		elseif typeof(declarado) == "string" then declarado
		else Config.AnclajePorSlot[slot]
	if not anclajeRaiz then
		return false, `no hay montaje definido para el slot "{slot}"`
	end

	-- Grupo de montaje de cada pieza: el submodelo más cercano con Anclaje, o el modelo.
	local function grupoDe(parte: BasePart): (BasePart?, string)
		local actual: Instance? = parte.Parent
		while actual and actual ~= clon do
			local anclaje = actual:GetAttribute("Anclaje")
			if actual:IsA("Model") and typeof(anclaje) == "string" then
				return handleDe(actual), anclaje
			end
			actual = actual.Parent
		end
		return raiz, anclajeRaiz :: string
	end

	-- Primero se calcula todo; recién si no falta nada se mueven las piezas.
	local destinos: { { Parte: BasePart, Cuerpo: BasePart, CFrame: CFrame } } = {}
	for _, d in clon:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local handle, anclaje = grupoDe(d)
		if not handle then
			return false, `a un submodelo con Anclaje "{anclaje}" le falta su "Handle"`
		end
		local cuerpo, ajuste = parteDelCuerpo(personaje, anclaje)
		if not cuerpo then
			return false, `el personaje no tiene la parte "{anclaje}"`
		end
		table.insert(
			destinos,
			{ Parte = d, Cuerpo = cuerpo, CFrame = cuerpo.CFrame * ajuste * handle.CFrame:ToObjectSpace(d.CFrame) }
		)
	end
	for _, destino in destinos do
		local parte = destino.Parte
		parte.Anchored = false
		parte.CanCollide = false
		parte.CanTouch = false
		parte.CanQuery = false
		parte.Massless = true
		parte.CFrame = destino.CFrame
		local soldadura = Instance.new("WeldConstraint")
		soldadura.Part0 = destino.Cuerpo
		soldadura.Part1 = parte
		soldadura.Parent = parte
	end
	return true, nil
end

return Personalizador
