-- Arenas clasificatorias (NPC-038): reglas puras de emparejamiento, rating y premios.
local A = cargar("ReplicatedStorage/Configs/ArenasConfig")
local NPC = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")

prueba("arenas: los modos son coherentes y el NPC ofrece uno por modo", function()
	exigir(#A.Modos == 3, "tres modos")
	local vistos: { [string]: boolean } = {}
	for _, modo in A.Modos do
		exigir(not vistos[modo.Id], "modo repetido: " .. modo.Id)
		vistos[modo.Id] = true
		exigir(modo.PorEquipo >= 1 and modo.PorEquipo == math.floor(modo.PorEquipo), "tamaño entero")
		exigir(A.Modo(modo.Id) ~= nil, "Modo() encuentra " .. modo.Id)
	end
	exigir(A.Modo("5v5") == nil, "no inventa modos")

	local arquetipo = NPC.Arquetipos.ReclutadorArenas
	exigir(arquetipo ~= nil and arquetipo.Numero == 38, "el reclutador es el 038")
	exigir(arquetipo.Estado == "Listo", "el reclutador está listo")
	local servicios = arquetipo.Servicios
	exigir(servicios ~= nil, "tiene servicios")
	-- Cada modo tiene su servicio, y cada servicio apunta a una acción real.
	local porAccion: { [string]: boolean } = {}
	for _, servicio in servicios do
		exigir(servicio.Accion ~= nil, "el servicio " .. servicio.Id .. " no tiene acción")
		exigir(servicio.Costo == 0, "anotarse no cuesta oro")
		porAccion[servicio.Accion] = true
	end
	for _, modo in A.Modos do
		exigir(porAccion["Arena" .. modo.Id], "falta el servicio de " .. modo.Id)
	end
	exigir(porAccion.ArenaCancelar, "falta cómo salir de la cola")
end)

prueba("arenas: la ventana de rating se abre con la espera", function()
	exigir(A.Ventana(0) == A.VentanaInicial, "arranca cerrada")
	exigir(A.Ventana(-5) == A.VentanaInicial, "una espera negativa no abre nada")
	exigir(A.Ventana(A.SegundosPorPaso) == A.VentanaInicial + A.VentanaPorPaso, "un paso")
	exigir(A.Ventana(A.SegundosPorPaso * 3) > A.Ventana(A.SegundosPorPaso), "crece")
	exigir(A.Ventana(100000) == A.VentanaMaxima, "tiene techo")

	exigir(A.Compatibles(1000, 1100, 0, 0), "100 de diferencia entra en la ventana inicial")
	exigir(not A.Compatibles(1000, 1400, 0, 0), "400 de diferencia no entra al principio")
	exigir(A.Compatibles(1000, 1400, 0, 600), "pero sí después de esperar")
	exigir(A.Compatibles(1400, 1000, 600, 0), "vale la ventana del que esperó más, de los dos lados")
end)

prueba("arenas: el rating se mueve como Elo y nunca queda negativo", function()
	exigir(A.Delta(1000, 1000, true) > 0 and A.Delta(1000, 1000, false) < 0, "parejos: suma o resta")
	exigir(A.Delta(1000, 1000, true) + A.Delta(1000, 1000, false) == 0, "parejos: simétrico")
	-- Ganarle a alguien mejor da más que ganarle a alguien peor.
	exigir(A.Delta(1000, 1600, true) > A.Delta(1000, 400, true), "ganarle al mejor paga más")
	exigir(A.Delta(1000, 1600, false) > A.Delta(1000, 400, false), "perder con el mejor duele menos")
	exigir(A.Delta(2500, 100, true) >= 1, "ganar siempre suma al menos 1")
	exigir(A.Delta(100, 2500, false) <= -1, "perder siempre resta al menos 1")
	exigir(math.abs(A.Delta(1000, 1000, true)) <= A.K, "nunca se mueve más que K")

	exigir(A.AplicarDelta(5, -40) == A.RatingMinimo, "el rating no baja del mínimo")
	exigir(A.AplicarDelta(1000, 12) == 1012, "suma normal")
	exigir(A.Promedio({}) == A.RatingInicial, "sin datos, el promedio es el rating inicial")
	exigir(A.Promedio({ 1000, 1200 }) == 1100, "promedio")
end)

prueba("arenas: los rangos están ordenados y cubren cualquier rating", function()
	local anterior = -1
	for _, rango in A.Rangos do
		exigir(rango.Desde > anterior, "los rangos tienen que subir: " .. rango.Nombre)
		anterior = rango.Desde
	end
	exigir(A.Rangos[1].Desde == 0, "el primer rango arranca en 0")
	exigir(A.RangoDe(0) == A.Rangos[1].Nombre, "rating 0")
	exigir(A.RangoDe(99999) == A.Rangos[#A.Rangos].Nombre, "rating altísimo")
	exigir(A.RangoDe(A.RatingInicial) ~= nil, "el rating inicial tiene rango")
end)

prueba("arenas: el honor tiene tope diario y la racha no lo rompe", function()
	local pago, total = A.Honor(true, 0, 0)
	exigir(pago == A.HonorVictoria, "victoria sin racha")
	exigir(total == pago, "lo pagado es lo anotado")
	exigir(A.Honor(false, 0, 0) == A.HonorDerrota, "derrota")
	exigir(A.Honor(true, 3, 0) > A.Honor(true, 0, 0), "la racha suma")
	exigir(A.Honor(true, 99, 0) == A.Honor(true, A.RachaMaxima, 0), "la racha tiene techo")

	local casi = A.TopeHonorDiario - 5
	local pagoTope, totalTope = A.Honor(true, 0, casi)
	exigir(pagoTope == 5, "solo paga lo que falta para el tope")
	exigir(totalTope == A.TopeHonorDiario, "y queda justo en el tope")
	exigir(A.Honor(true, 5, A.TopeHonorDiario) == 0, "en el tope ya no paga")
	exigir(A.Honor(false, 0, A.TopeHonorDiario + 999) == 0, "nunca paga de más")

	local dia = A.DiaDe(os.time())
	exigir(A.DiaDe(os.time() + 86400) == dia + 1, "el día avanza de a uno")
	exigir(A.DiaDe(os.time() + 60) == dia, "un minuto después sigue siendo el mismo día")
end)

prueba("arenas: la partida y el mapa tienen números sanos", function()
	exigir(A.RondasParaGanar * 2 > A.RondasMaximas, "al mejor de tres no puede empatarse por rondas ganadas")
	exigir(A.RondasMaximas >= A.RondasParaGanar, "no se pueden pedir más rondas de las que se juegan")
	exigir(A.Preparacion > 0 and A.DuracionRonda > A.Preparacion, "la ronda dura más que la cuenta atrás")
	exigir(A.PartidasSimultaneas >= 1, "al menos una partida a la vez")
	-- Las plataformas no pueden pisarse entre ellas ni dejar al jugador afuera.
	local mayor = math.max(A.Mapa.Tamano.X, A.Mapa.Tamano.Z)
	exigir(A.Mapa.Separacion > mayor, "las plataformas se superponen")
	exigir(A.Mapa.Spawn * 2 < A.Mapa.Tamano.X, "los puntos de salida caen fuera de la plataforma")
	local masAncho = 0
	for _, modo in A.Modos do
		masAncho = math.max(masAncho, modo.PorEquipo)
	end
	exigir((masAncho - 1) * A.Mapa.SeparacionCompanero < A.Mapa.Tamano.Z, "el equipo más grande no entra de ancho")
end)
