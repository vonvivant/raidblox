--!strict
-- ItemInfo: formatea la información de un ítem para mostrarla (nombre con color
-- de rareza, atributos ya multiplicados, efectos secundarios, pasiva y calidad).
-- Lo usan inventario, subastas, comercio y crafteo.

local ItemCatalog = require(script.Parent.Parent.Configs.ItemCatalog)
local ItemRarityConfig = require(script.Parent.Parent.Configs.ItemRarityConfig)

local ItemInfo = {}

function ItemInfo.Nombre(item: any): string
	local def = if typeof(item) == "table" then ItemCatalog[item.ItemId] else nil
	return if def then def.Nombre else "?"
end

function ItemInfo.Color(item: any): Color3
	local rareza = if typeof(item) == "table" then ItemRarityConfig.Rarezas[item.Rareza] else nil
	return if rareza then rareza.Color else Color3.new(1, 1, 1)
end

function ItemInfo.EsMasterpiece(item: any): boolean
	return typeof(item) == "table" and typeof(item.Meta) == "table" and item.Meta.Masterpiece == true
end

-- Texto de una línea: "Espada de Hierro x1 (Épico)".
function ItemInfo.Corto(item: any): string
	if typeof(item) ~= "table" then
		return ""
	end
	local rareza = ItemRarityConfig.Rarezas[item.Rareza]
	local estrella = if ItemInfo.EsMasterpiece(item) then "★ " else ""
	local cantidad = if typeof(item.Cantidad) == "number" and item.Cantidad > 1 then ` x{item.Cantidad}` else ""
	return `{estrella}{ItemInfo.Nombre(item)}{cantidad}{if rareza and item.Rareza ~= "Comun"
		then ` ({rareza.Nombre})`
		else ""}`
end

-- Detalle de varias líneas para el panel de información.
function ItemInfo.Detalle(item: any): string
	if typeof(item) ~= "table" then
		return ""
	end
	local def = ItemCatalog[item.ItemId]
	if not def then
		return "Ítem desconocido"
	end
	local rareza = ItemRarityConfig.Rarezas[item.Rareza]
	local meta = if typeof(item.Meta) == "table" then item.Meta else nil
	local mult = if meta and typeof(meta.Mult) == "number"
		then meta.Mult
		else (if rareza then rareza.Multiplicador else 1)

	local lineas: { string } = {}
	table.insert(lineas, `{if rareza then rareza.Nombre else ""} · {def.Tipo}`)
	if ItemInfo.EsMasterpiece(item) then
		table.insert(lineas, "★ Calidad Masterpiece (+10%)")
	end
	if def.SlotEquipo then
		table.insert(lineas, `Se equipa en: {def.SlotEquipo}`)
	end
	local atributos = def.Atributos
	if atributos then
		for _, nombre in { "Fuerza", "Agilidad", "Inteligencia" } do
			local valor = (atributos :: any)[nombre]
			if typeof(valor) == "number" then
				table.insert(lineas, `+{math.floor(valor * mult * 10 + 0.5) / 10} {nombre}`)
			end
		end
	end
	if meta then
		for clave, valor in meta do
			if typeof(clave) == "string" and string.sub(clave, 1, 7) == "Efecto_" and typeof(valor) == "number" then
				local efecto = ItemRarityConfig.Efectos[string.sub(clave, 8)]
				if efecto then
					table.insert(lineas, string.format(efecto.Formato, valor))
				end
			end
		end
		local pasiva = meta.Pasiva
		if typeof(pasiva) == "string" and ItemRarityConfig.Pasivas[pasiva] then
			local p = ItemRarityConfig.Pasivas[pasiva]
			table.insert(lineas, `Pasiva {p.Nombre}: {p.Descripcion}`)
		end
		if meta.Aura == true then
			table.insert(lineas, "Aura dorada")
		end
	end
	if def.Descripcion then
		table.insert(lineas, def.Descripcion)
	end
	table.insert(lineas, `Valor: {def.PrecioVenta} de oro`)
	return table.concat(lineas, "\n")
end

return ItemInfo
