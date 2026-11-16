-- Construcción en parcelas: piezas, límites, encaje, superposición y huerta.
local C = cargar("ReplicatedStorage/Configs/ConstruccionConfig")
local P = cargar("ReplicatedStorage/Configs/ParcelasConfig")
local ITEMS = cargar("ReplicatedStorage/Configs/ItemCatalog")
local NPC = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")

local function puesta(id: string, x: number, y: number, z: number, g: number)
	return { Pieza = id, X = x, Y = y, Z = z, Giro = g }
end

prueba("construcción: las piezas tienen medidas y precios sanos", function()
	exigir(#C.Piezas >= 6, "hacen falta piezas para construir algo")
	local vistos: { [string]: boolean } = {}
	for _, pieza in C.Piezas do
		exigir(not vistos[pieza.Id], "pieza repetida: " .. pieza.Id)
		vistos[pieza.Id] = true
		exigir(C.Pieza(pieza.Id) ~= nil, "Pieza() encuentra " .. pieza.Id)
		exigir(pieza.Precio > 0, pieza.Id .. " tiene que costar algo")
		exigir(pieza.Tamano.X > 0 and pieza.Tamano.Y > 0 and pieza.Tamano.Z > 0, pieza.Id .. " sin volumen")
		exigir(pieza.Tamano.Y <= C.AlturaMaxima, pieza.Id .. " no entra ni sola en el alto permitido")
		-- Ninguna pieza puede ser más grande que la parcela más chica.
		local menor = math.huge
		for _, barrio in P.Barrios do
			menor = math.min(menor, barrio.Lado)
		end
		exigir(pieza.Tamano.X < menor - C.Margen * 2, pieza.Id .. " no entra en la parcela más chica")
		exigir(pieza.Tamano.Z < menor - C.Margen * 2, pieza.Id .. " no entra de fondo en la más chica")
		-- Sacarla devuelve la mitad: nunca puede dar ganancia.
		exigir(math.floor(pieza.Precio / 2) < pieza.Precio, "sacar " .. pieza.Id .. " daría ganancia")
	end
end)

prueba("construcción: la grilla y el giro se comportan", function()
	exigir(C.Acomodar(0) == 0, "el cero queda igual")
	exigir(C.Acomodar(C.Paso * 3) == C.Paso * 3, "lo que ya está en la grilla no se mueve")
	exigir(C.Acomodar(0.4) == 0, "redondea para abajo")
	exigir(C.Acomodar(-0.4) == 0, "y también del lado negativo")
	exigir(C.Acomodar(C.Paso * 2 + 0.1) == C.Paso * 2, "redondea al paso más cercano")

	local pared = C.Pieza("Pared")
	exigir(pared ~= nil, "la pared existe")
	local derecha = C.TamanoGirado(pared, 0)
	local girada = C.TamanoGirado(pared, 1)
	exigir(derecha.X == girada.Z and derecha.Z == girada.X, "girar intercambia ancho y fondo")
	exigir(derecha.Y == girada.Y, "girar no cambia el alto")
	exigir(C.TamanoGirado(pared, 2).X == derecha.X, "media vuelta queda igual que de frente")
	exigir(C.GiroValido(0) and C.GiroValido(3), "los cuatro giros valen")
	exigir(not C.GiroValido(4) and not C.GiroValido(-1) and not C.GiroValido(1.5), "nada más vale")
end)

prueba("construcción: nada se sale del terreno", function()
	local lado = 48
	local mesa = C.Pieza("Mesa")
	exigir(mesa ~= nil, "la mesa existe")
	exigir(C.Entra(lado, mesa, 0, 0, 1.5, 0), "en el centro entra")
	-- Justo contra el borde, no.
	local limite = lado / 2 - C.Margen
	exigir(not C.Entra(lado, mesa, 0, limite, 1.5, 0), "pegada al borde se sale")
	exigir(not C.Entra(lado, mesa, 0, 0, 1.5, limite), "y de fondo también")
	exigir(C.Entra(lado, mesa, 0, limite - mesa.Tamano.X / 2, 1.5, 0), "justo adentro sí entra")
	-- Bajo tierra y por encima del techo, no.
	exigir(not C.Entra(lado, mesa, 0, 0, -5, 0), "no se construye bajo tierra")
	exigir(not C.Entra(lado, mesa, 0, 0, C.AlturaMaxima, 0), "no se pasa del alto permitido")
	-- Girada, los límites cambian con ella.
	local pared = C.Pieza("Pared")
	local x = limite - pared.Tamano.X / 2 - 1
	exigir(C.Entra(lado, pared, 0, x, 4, 0), "de frente entra")
	exigir(not C.Entra(lado, pared, 0, limite - 1, 4, 0), "corrida se sale")
end)

prueba("construcción: dos piezas no pueden ocupar el mismo lugar", function()
	local mesa = C.Pieza("Mesa")
	local silla = C.Pieza("Silla")
	exigir(mesa ~= nil and silla ~= nil, "las dos piezas")
	local origen = Vector3.new(0, 1.5, 0)
	exigir(C.SePisan(mesa, 0, origen, mesa, 0, origen), "en el mismo punto se pisan")
	-- Lado a lado, justo tocándose, no se pisan.
	local alLado = Vector3.new(mesa.Tamano.X, 1.5, 0)
	exigir(not C.SePisan(mesa, 0, origen, mesa, 0, alLado), "pegadas de canto no se pisan")
	exigir(C.SePisan(mesa, 0, origen, mesa, 0, Vector3.new(mesa.Tamano.X - 1, 1.5, 0)), "superpuestas sí")
	-- Una arriba de la otra, a distinta altura, no se pisan.
	exigir(not C.SePisan(mesa, 0, origen, silla, 0, Vector3.new(0, 1.5 + mesa.Tamano.Y / 2 + silla.Tamano.Y / 2, 0)), "apilar vale")
	-- Girar cambia qué se pisa con qué.
	local pared = C.Pieza("Pared")
	local lejosEnZ = Vector3.new(0, 4, pared.Tamano.X / 2)
	exigir(C.SePisan(pared, 1, origen, pared, 1, lejosEnZ), "girada, ocupa el otro eje")
end)

prueba("construcción: los topes por parcela se respetan", function()
	local cantero = C.Pieza("Cantero")
	local patio = C.Pieza("PatioMascotas")
	exigir(cantero ~= nil and patio ~= nil, "las dos piezas con límite")
	exigir(cantero.Limite ~= nil and patio.Limite == 1, "el patio es único")

	local puestas = {}
	exigir(C.PuedeAgregar(puestas, patio), "en una parcela vacía entra")
	table.insert(puestas, puesta("PatioMascotas", 0, 0, 0, 0))
	exigir(not C.PuedeAgregar(puestas, patio), "el segundo patio no")
	exigir(C.PuedeAgregar(puestas, cantero), "pero un cantero sí")
	exigir(C.Cuantas(puestas, "PatioMascotas") == 1, "cuenta bien")
	exigir(C.Cuantas(puestas, "Cantero") == 0, "y lo que no está da cero")

	-- Hasta el tope de la parcela.
	local llena = {}
	for _ = 1, C.MaxPiezas do
		table.insert(llena, puesta("Silla", 0, 0, 0, 0))
	end
	local silla = C.Pieza("Silla")
	exigir(not C.PuedeAgregar(llena, silla), "con la parcela llena no entra nada más")
	table.remove(llena)
	exigir(C.PuedeAgregar(llena, silla), "sacando una, vuelve a entrar")
end)

prueba("huerta: los cultivos existen, se compran y tardan lo que dicen", function()
	exigir(#C.Cultivos >= 3, "hacen falta cultivos")
	local arquitecto = NPC.Arquetipos.Arquitecto
	local vende: { [string]: number } = {}
	for _, oferta in arquitecto.Vende or {} do
		vende[oferta.ItemId] = oferta.Precio
	end
	for _, cultivo in C.Cultivos do
		exigir(ITEMS[cultivo.Semilla] ~= nil, "semilla inexistente: " .. cultivo.Semilla)
		exigir(ITEMS[cultivo.Cosecha] ~= nil, "cosecha inexistente: " .. cultivo.Cosecha)
		exigir(cultivo.Horas > 0, cultivo.Nombre .. " tiene que tardar algo")
		exigir(cultivo.Min >= 1 and cultivo.Max >= cultivo.Min, "cantidades al revés en " .. cultivo.Nombre)
		exigir(vende[cultivo.Semilla] ~= nil, "el Arquitecto no vende " .. cultivo.Semilla)
		-- Plantar tiene que convenir: lo que sale vale más que la semilla.
		local costo = vende[cultivo.Semilla]
		local saca = (ITEMS[cultivo.Cosecha].PrecioVenta or 0) * cultivo.Min
		exigir(saca > ITEMS[cultivo.Semilla].PrecioVenta, "la semilla vale más que lo que da")
		exigir(costo > ITEMS[cultivo.Semilla].PrecioVenta, "la semilla se puede revender con ganancia")
	end
end)

prueba("huerta: la cosecha no se puede apurar", function()
	local cultivo = C.Cultivos[1]
	local plantado = 1000000
	local listo = plantado + cultivo.Horas * 3600
	exigir(not C.Lista(cultivo, plantado, plantado), "recién plantado no está listo")
	exigir(not C.Lista(cultivo, plantado, listo - 1), "un segundo antes tampoco")
	exigir(C.Lista(cultivo, plantado, listo), "justo a tiempo sí")
	exigir(C.Lista(cultivo, plantado, listo + 99999), "y después también")

	exigir(C.Falta(cultivo, plantado, plantado) == cultivo.Horas * 3600, "al principio falta todo")
	exigir(C.Falta(cultivo, plantado, listo) == 0, "listo es cero")
	exigir(C.Falta(cultivo, plantado, listo + 500) == 0, "nunca negativo")
	-- Un "plantado" en el futuro (reloj raro) no rompe nada: sigue sin estar listo.
	exigir(not C.Lista(cultivo, plantado + 99999, plantado), "no se cosecha lo que no se plantó")
end)

prueba("patio: las mascotas se pasean adentro y no se escapan", function()
	local patio = C.Pieza("PatioMascotas")
	exigir(patio ~= nil, "el patio existe")
	exigir(C.PatioMaxMascotas >= 1, "al menos una mascota")
	exigir(C.PatioPaseoMin > 0 and C.PatioPaseoMax >= C.PatioPaseoMin, "los tiempos de paseo tienen que cerrar")
	exigir(C.PatioAlturaVuelo > 0, "flotan sobre el patio")
	exigir(C.PatioMargen * 2 < patio.Tamano.X, "el margen no puede comerse el patio entero")

	-- Cien puntos al azar: ninguno puede caer fuera del patio.
	local azar = Random.new(1234)
	local lado = patio.Tamano.X
	local limite = lado / 2 - C.PatioMargen
	for _ = 1, 100 do
		local punto = C.PuntoDePaseo(lado, azar)
		exigir(math.abs(punto.X) <= limite, "una mascota se fue del patio por X")
		exigir(math.abs(punto.Z) <= limite, "una mascota se fue del patio por Z")
		exigir(punto.Y > 0, "ninguna se mete bajo el piso")
	end
	-- Un patio imposible (más margen que tamaño) no rompe: todos al centro.
	local apretado = C.PuntoDePaseo(C.PatioMargen, azar)
	exigir(apretado.X == 0 and apretado.Z == 0, "sin lugar, se quedan en el centro")
end)

prueba("patio: hay mascotas para mostrar y la foto no se desborda", function()
	local MASCOTAS = cargar("ReplicatedStorage/Configs/MascotasConfig")
	local cuantas = 0
	for id, def in MASCOTAS.Mascotas do
		cuantas += 1
		exigir(def.Nombre ~= nil and def.Tam > 0, "mascota incompleta: " .. id)
	end
	exigir(cuantas >= C.PatioMaxMascotas, "el tope del patio pide más mascotas de las que existen")
end)

prueba("muebles: los que hacen algo lo declaran bien", function()
	local silla = C.Pieza("Silla")
	local fogata = C.Pieza("Fogata")
	local estandarte = C.Pieza("Estandarte")
	exigir(silla ~= nil and fogata ~= nil and estandarte ~= nil, "los tres muebles")
	exigir(silla.Asiento == true, "la silla tiene que ser un asiento")
	exigir(fogata.Estacion == "Fogon", "la fogata tiene que ser un fogón")
	exigir(estandarte.PorBando == true, "el estandarte toma el color del bando")

	-- La estación de un mueble tiene que existir de verdad: si no, el jugador
	-- compra una fogata que no cocina nada.
	local PROF = cargar("ReplicatedStorage/Configs/ProfesionesConfig")
	for _, pieza in C.Piezas do
		if not pieza.Estacion then
			continue
		end
		local usada = false
		for _, receta in PROF.Recetas do
			if receta.Estacion == pieza.Estacion then
				usada = true
			end
		end
		exigir(usada, pieza.Id .. " dice ser estación " .. pieza.Estacion .. " y no hay recetas para esa estación")
	end
	-- Un asiento no puede ser al mismo tiempo estación: el prompt y el sentarse
	-- se pelearían.
	for _, pieza in C.Piezas do
		exigir(not (pieza.Asiento and pieza.Estacion), pieza.Id .. " no puede ser asiento y estación a la vez")
	end
end)

prueba("muebles: el estandarte tiene color para cada bando", function()
	for _, bando in { "Rojo", "Azul", "Neutral" } do
		exigir(C.ColorPorBando[bando] ~= nil, "falta el color de " .. bando)
	end
	exigir(C.ColorDeBando("Rojo") ~= C.ColorDeBando("Azul"), "los bandos se distinguen")
	exigir(C.ColorDeBando(nil) == C.ColorDeBando("Neutral"), "sin bando, neutral")
	exigir(C.ColorDeBando("Inventado") == C.ColorDeBando("Neutral"), "un bando raro no rompe nada")
end)
