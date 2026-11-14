-- NPC personalizador: validadores y formato de la personalización (reglas puras).
local P = cargar("ReplicatedStorage/Configs/PersonalizadorConfig")

local NAN = 0 / 0

prueba("personalizador: colores hexadecimales", function()
	exigir(P.HexValido("A0B1C2") and P.HexValido("ffffff"), "hex válidos")
	for _, malo in { "", "FFF", "GGGGGG", "A0B1C2D", "#A0B1C", 123456, false, {} } do
		exigir(not P.HexValido(malo), "aceptó un color inválido: " .. tostring(malo))
	end
	exigir(P.AHex(255, 0, 128) == "FF0080", "AHex")
	exigir(P.AHex(300, -5, 127.6) == "FF0080", "AHex limita a 0..255 y redondea")
	exigir(P.AHex(NAN, 0, 0) == nil, "rechaza NaN")
	exigir(P.AHex(math.huge, 0, 0) == nil and P.AHex(0, -math.huge, 0) == nil, "rechaza infinitos")
	exigir(P.AHex("255", 0, 0) == nil and P.AHex(nil, 0, 0) == nil, "rechaza tipos incorrectos")
	local r, g, b = P.DeHex("FF0080")
	exigir(r == 255 and g == 0 and b == 128, "DeHex")
	exigir(P.DeHex("nada") == nil, "DeHex inválido")
end)

prueba("personalizador: ids de pieza, materiales y pedidos", function()
	exigir(P.IdPiezaValido("Hoja") and P.IdPiezaValido("Guarda/Gema#2") and P.IdPiezaValido("Pomo 1.b_c-d"), "ids válidos")
	for _, malo in { "", "Hoja=1", "a|b", "a,b", string.rep("x", P.LargoIdPieza + 1), 5, {} } do
		exigir(not P.IdPiezaValido(malo), "aceptó un id inválido")
	end
	exigir(P.NombreMaterialValido("SmoothPlastic"), "material válido")
	for _, malo in { "", "Metal,", "Me tal", "Metal|x", 3 } do
		exigir(not P.NombreMaterialValido(malo), "aceptó un material inválido")
	end
	exigir(P.RequestIdValido("0b6c2f3e-1111-2222-3333-444455556666"), "GUID válido")
	for _, malo in { "corto", string.rep("a", P.LargoRequestId + 1), "con espacio 123", "a|b|c|d|e", 12345678 } do
		exigir(not P.RequestIdValido(malo), "aceptó un id de pedido inválido")
	end
end)

prueba("personalizador: codificar y decodificar dan lo mismo, en orden estable", function()
	local pers = {
		Hoja = { Material = "Metal", Color = "a0b1c2" },
		["Guarda/Gema#2"] = { Material = "Neon", Color = "FF0000" },
	}
	local texto = P.Codificar(pers)
	exigir(texto == "1|Guarda/Gema#2=Neon,FF0000|Hoja=Metal,A0B1C2", "texto: " .. texto)
	local vuelta = P.Decodificar(texto)
	exigir(vuelta and vuelta.Hoja.Material == "Metal" and vuelta.Hoja.Color == "A0B1C2", "Hoja")
	exigir(vuelta["Guarda/Gema#2"].Material == "Neon", "pieza con ruta")
	exigir(P.Codificar(vuelta) == texto, "ida y vuelta")
	exigir(P.Codificar({}) == "1", "sin cambios")
	local vacia = P.Decodificar("1")
	exigir(vacia ~= nil and next(vacia) == nil, "decodificar sin cambios")
end)

prueba("personalizador: decodificar rechaza datos corruptos o demasiado grandes", function()
	for _, malo in {
		"", "2|Hoja=Metal,A0B1C2", "1|Hoja", "1|Hoja=Metal", "1|Hoja=Metal,ZZZZZZ", "1|=Metal,A0B1C2",
		"1|Hoja=Me tal,A0B1C2", "1|Hoja=Metal,A0B1C2|Hoja=Wood,112233", 5, false,
		string.rep("x", 5000),
	} do
		exigir(P.Decodificar(malo) == nil, "aceptó: " .. tostring(malo))
	end
	local muchas = { "1" }
	for i = 1, P.MaxPiezas + 1 do
		table.insert(muchas, "P" .. i .. "=Metal,000000")
	end
	exigir(P.Decodificar(table.concat(muchas, "|")) == nil, "aceptó más piezas que el máximo")
end)

prueba("personalizador: el precio es la base más un extra por pieza modificada", function()
	exigir(P.Precio(100, 0) == 100, "sin cambios")
	exigir(P.Precio(100, 3) == 100 + 3 * P.CostoPorPieza, "con 3 piezas")
	exigir(P.Precio(100.9, -2) == 100, "no acepta cantidades negativas ni decimales")
end)
