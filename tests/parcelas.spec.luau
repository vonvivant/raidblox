-- Parcelas (NPC-033): grilla, vecindad, fusión, alquiler y permisos.
local P = cargar("ReplicatedStorage/Configs/ParcelasConfig")
local ZONAS = cargar("ReplicatedStorage/Configs/ZoneConfig")
local NPC = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")

prueba("parcelas: los barrios apuntan a zonas que existen y no se pisan", function()
	exigir(#P.Barrios >= 1, "hace falta al menos un barrio")
	local vistos: { [string]: boolean } = {}
	for _, barrio in P.Barrios do
		exigir(not vistos[barrio.Id], "barrio repetido: " .. barrio.Id)
		vistos[barrio.Id] = true
		exigir(ZONAS.Zonas[barrio.Zona] ~= nil, barrio.Id .. " vive en una zona que no existe: " .. barrio.Zona)
		exigir(barrio.Filas >= 1 and barrio.Columnas >= 1, barrio.Id .. " necesita una grilla")
		exigir(barrio.Lado > 0 and barrio.Calle > 0, barrio.Id .. " necesita medidas")
		exigir(barrio.Precio > 0, barrio.Id .. " necesita precio")
		-- El id del barrio tiene que sobrevivir a Partir() (solo letras y números).
		exigir(P.Valido(P.Id(barrio.Id, 1)), "el id de " .. barrio.Id .. " no se puede parsear")
	end

	-- Dos parcelas nunca pueden compartir el mismo espacio.
	local ocupado: { [string]: string } = {}
	for _, barrio in P.Barrios do
		for numero = 1, P.CantidadDe(barrio) do
			local centro = P.Centro(barrio, numero)
			local llave = string.format("%d|%d|%d", centro.X, centro.Y, centro.Z)
			exigir(ocupado[llave] == nil, "dos parcelas en el mismo lugar: " .. tostring(ocupado[llave]))
			ocupado[llave] = P.Id(barrio.Id, numero)
		end
	end
end)

prueba("parcelas: los ids se parten bien y rechazan basura", function()
	local barrio = P.Barrios[1]
	local ultima = P.CantidadDe(barrio)
	exigir(P.Valido(P.Id(barrio.Id, 1)) and P.Valido(P.Id(barrio.Id, ultima)), "los extremos valen")
	exigir(not P.Valido(P.Id(barrio.Id, 0)), "el cero no existe")
	exigir(not P.Valido(P.Id(barrio.Id, ultima + 1)), "no se puede pasar del tamaño de la grilla")
	exigir(not P.Valido("Inventado:1"), "un barrio que no existe")
	exigir(not P.Valido("CiudadNorte"), "sin número")
	exigir(not P.Valido("CiudadNorte:x"), "número que no es número")
	exigir(not P.Valido(""), "vacío")
	exigir(not P.Valido("CiudadNorte:1:2"), "basura de más")
end)

prueba("parcelas: la grilla y las coordenadas son consistentes", function()
	for _, barrio in P.Barrios do
		for numero = 1, P.CantidadDe(barrio) do
			local fila, columna = P.Coordenada(barrio, numero)
			exigir(fila >= 1 and fila <= barrio.Filas, "fila fuera de rango en " .. barrio.Id)
			exigir(columna >= 1 and columna <= barrio.Columnas, "columna fuera de rango en " .. barrio.Id)
			exigir(P.Numero(barrio, fila, columna) == numero, "ir y volver tiene que dar lo mismo")
		end
		exigir(P.Numero(barrio, 0, 1) == nil and P.Numero(barrio, 1, 0) == nil, "fuera de la grilla es nil")
		exigir(P.Numero(barrio, barrio.Filas + 1, 1) == nil, "pasarse de filas es nil")
	end
end)

prueba("parcelas: la vecindad es mutua y nunca en diagonal", function()
	for _, barrio in P.Barrios do
		for numero = 1, P.CantidadDe(barrio) do
			local vecinas = P.Vecinas(barrio, numero)
			exigir(#vecinas >= 2 and #vecinas <= 4, "una parcela tiene entre 2 y 4 vecinas")
			for _, otra in vecinas do
				exigir(table.find(P.Vecinas(barrio, otra), numero) ~= nil, "la vecindad tiene que ser mutua")
				local f1, c1 = P.Coordenada(barrio, numero)
				local f2, c2 = P.Coordenada(barrio, otra)
				exigir(math.abs(f1 - f2) + math.abs(c1 - c2) == 1, "las diagonales no son vecinas")
			end
		end
	end
end)

prueba("parcelas: solo se fusionan vecinas del mismo barrio", function()
	local barrio = P.Barrios[1]
	local a = P.Id(barrio.Id, 1)
	local vecina = P.Id(barrio.Id, P.Vecinas(barrio, 1)[1])
	exigir(P.Fusionables(a, vecina), "vecinas del mismo barrio se fusionan")
	exigir(P.Fusionables(vecina, a), "la fusión no depende del orden")
	exigir(not P.Fusionables(a, a), "no se fusiona con sí misma")
	-- Una parcela lejana del mismo barrio no es vecina.
	local lejana = P.Id(barrio.Id, P.CantidadDe(barrio))
	if lejana ~= vecina then
		exigir(not P.Fusionables(a, lejana), "la de la otra punta no es vecina")
	end
	-- Entre barrios distintos, nunca.
	if #P.Barrios >= 2 then
		exigir(not P.Fusionables(a, P.Id(P.Barrios[2].Id, 1)), "no se fusionan barrios distintos")
	end
	exigir(not P.Fusionables(a, "Inventado:1"), "ids inválidos no se fusionan")
end)

prueba("parcelas: el alquiler no se puede pagar de más ni quedar en el aire", function()
	local ahora = 1000000
	exigir(P.Alquiler(0) == 0 and P.Alquiler(-5) == 0, "días inválidos no cuestan nada")
	exigir(P.Alquiler(3) == P.AlquilerDiario * 3, "tres días")

	-- Recién comprada: ya trae días pagos, así que no se puede pagar el máximo.
	local recien = ahora + P.DiasAlCompar * 86400
    local puede = P.DiasQuePuedePagar(recien, ahora)
	exigir(puede == P.DiasMaximos - P.DiasAlCompar, "lo que falta para el techo")
	exigir(puede >= 1, "después de comprar tiene que poder seguir pagando")
	-- Al tope no se puede pagar más.
	exigir(P.DiasQuePuedePagar(ahora + P.DiasMaximos * 86400, ahora) == 0, "en el techo no se paga más")
	-- Vencida hace rato: se puede pagar todo de nuevo.
	exigir(P.DiasQuePuedePagar(ahora - 999999, ahora) == P.DiasMaximos, "vencida vuelve al máximo")

	exigir(not P.Vencida(recien, ahora), "recién comprada no está vencida")
	exigir(P.Vencida(ahora - 1, ahora), "un segundo tarde ya es vencida")
	-- Gracia: vencida pero recuperable.
	local justoVencida = ahora - 10
	exigir(P.EnGracia(justoVencida, ahora) and not P.Libre(justoVencida, ahora), "recién vencida, en gracia")
	local pasadaLaGracia = ahora - (P.DiasDeGracia * 86400 + 60)
	exigir(P.Libre(pasadaLaGracia, ahora), "pasada la gracia vuelve al mercado")
	exigir(not P.EnGracia(pasadaLaGracia, ahora), "ya no hay gracia")
	-- Las tres situaciones son excluyentes.
	for _, hasta in { recien, justoVencida, pasadaLaGracia } do
		local cuantas = 0
		if not P.Vencida(hasta, ahora) then
			cuantas += 1
		end
		if P.EnGracia(hasta, ahora) then
			cuantas += 1
		end
		if P.Libre(hasta, ahora) then
			cuantas += 1
		end
		exigir(cuantas == 1, "al día, en gracia o libre: solo una")
	end
end)

prueba("parcelas: permisos y nombres validados", function()
	for _, permiso in P.Permisos do
		exigir(P.PermisoValido(permiso.Id), "el permiso " .. permiso.Id .. " tiene que validar")
	end
	exigir(not P.PermisoValido("Dueno"), "dueño no es un permiso que se dé")
	exigir(not P.PermisoValido("Admin"), "nada inventado")
	exigir(P.PuedeConstruir("Socio"), "el socio construye")
	exigir(not P.PuedeConstruir("Invitado") and not P.PuedeConstruir("Visita"), "los demás no")
	exigir(not P.PuedeConstruir(nil), "sin permiso no se construye")

	exigir(P.NombreValido("Casa del Lago"), "un nombre normal")
	exigir(P.NombreValido("Refugio Ñandú"), "con acentos y eñe")
	exigir(not P.NombreValido(""), "vacío no")
	exigir(not P.NombreValido(string.rep("a", P.LargoNombre + 1)), "más largo que el tope no")
	exigir(not P.NombreValido("hola<script>"), "sin caracteres raros")
	exigir(not P.NombreValido("casa\nnueva"), "sin saltos de línea")
end)

prueba("parcelas: el Arquitecto abre el panel y no cobra por mirar", function()
	local arquitecto = NPC.Arquetipos.Arquitecto
	exigir(arquitecto.Numero == 33, "el Arquitecto es el 033")
	exigir(arquitecto.Estado == "Parcial", "está a medias a propósito: falta construir")
	local abre = false
	for _, servicio in arquitecto.Servicios or {} do
		exigir(servicio.Costo == 0, "mirar las parcelas no cuesta oro")
		if servicio.Accion == "ParcelasAbrir" then
			abre = true
		end
	end
	exigir(abre, "tiene que poder abrir el panel de parcelas")
	-- El límite por jugador tiene que dejar fusionar al menos un par.
	exigir(P.MaxPorJugador >= 2, "con una sola parcela la fusión no existiría")
end)
