-- Juegos del Crupier (NPC-036): reglas puras de récords, premios y tiempos.
local J = cargar("ReplicatedStorage/Configs/JuegosConfig")
local NPC = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")

prueba("juegos: los dos juegos están declarados y el Crupier los ofrece", function()
	exigir(#J.Juegos == 2, "dos juegos")
	exigir(J.Juego("Runas") ~= nil and J.Juego("Pares") ~= nil, "Juego() los encuentra")
	exigir(J.Juego("Dados") == nil, "no inventa juegos")
	for _, juego in J.Juegos do
		exigir(juego.Mejor == "Mas" or juego.Mejor == "Menos", juego.Id .. " necesita saber qué es mejor")
		exigir(#juego.Premios >= 1, juego.Id .. " no da ningún título")
		local vistos: { [string]: boolean } = {}
		for _, premio in juego.Premios do
			exigir(premio.Marca > 0, "marca inválida en " .. juego.Id)
			exigir(not vistos[premio.Titulo], "título repetido: " .. premio.Titulo)
			vistos[premio.Titulo] = true
		end
	end

	local crupier = NPC.Arquetipos.Crupier
	exigir(crupier.Numero == 36 and crupier.Estado == "Listo", "el Crupier está listo")
	-- Nada de apuestas: los servicios no cobran y el NPC no vende ni compra.
	exigir(crupier.Vende == nil and crupier.Compra == nil, "el Crupier no comercia")
	local acciones: { [string]: boolean } = {}
	for _, servicio in crupier.Servicios or {} do
		exigir(servicio.Costo == 0, "jugar no puede costar oro: " .. servicio.Id)
		exigir(servicio.Accion ~= nil, servicio.Id .. " no tiene acción")
		acciones[servicio.Accion] = true
	end
	for _, juego in J.Juegos do
		exigir(acciones["Juego" .. juego.Id], "falta el servicio de " .. juego.Id)
	end
end)

prueba("juegos: los títulos no se repiten entre juegos", function()
	local dueno: { [string]: string } = {}
	for _, juego in J.Juegos do
		for _, premio in juego.Premios do
			exigir(dueno[premio.Titulo] == nil, "dos juegos dan el mismo título: " .. premio.Titulo)
			dueno[premio.Titulo] = juego.Id
		end
	end
end)

prueba("juegos: el récord se mide en la dirección correcta", function()
	local runas = J.Juego("Runas")
	local pares = J.Juego("Pares")
	exigir(runas ~= nil and pares ~= nil, "los dos juegos")
	exigir(runas.Mejor == "Mas", "en runas, más rondas es mejor")
	exigir(pares.Mejor == "Menos", "en pares, menos intentos es mejor")

	-- Sin récord previo, cualquier resultado válido es récord.
	exigir(J.EsMejor(runas, 1, 0), "primera partida de runas")
	exigir(J.EsMejor(pares, 16, 0), "primera partida de pares")
	-- Un resultado de cero (abandonó o se quedó sin intentos) no es récord.
	exigir(not J.EsMejor(runas, 0, 0), "cero no es récord")
	exigir(not J.EsMejor(pares, 0, 0), "cero no es récord en pares")
	exigir(not J.EsMejor(pares, -3, 5), "un resultado negativo tampoco")

	exigir(J.EsMejor(runas, 8, 7) and not J.EsMejor(runas, 7, 8), "runas sube")
	exigir(J.EsMejor(pares, 9, 12) and not J.EsMejor(pares, 12, 9), "pares baja")
	exigir(not J.EsMejor(runas, 7, 7) and not J.EsMejor(pares, 9, 9), "empatar no es récord")
end)

prueba("juegos: los premios se dan según la marca de cada juego", function()
	local runas = J.Juego("Runas")
	local pares = J.Juego("Pares")
	exigir(runas ~= nil and pares ~= nil, "los dos juegos")

	exigir(J.Alcanza(runas, 5, 5) and J.Alcanza(runas, 20, 5), "en runas alcanza con llegar o pasar")
	exigir(not J.Alcanza(runas, 4, 5), "no alcanza con menos rondas")
	exigir(J.Alcanza(pares, 11, 11) and J.Alcanza(pares, 9, 11), "en pares alcanza con igual o menos intentos")
	exigir(not J.Alcanza(pares, 12, 11), "no alcanza con más intentos")
	exigir(not J.Alcanza(pares, 0, 16), "no terminar el tablero no gana nada")

	-- Un buen resultado acumula todos los títulos que ya superó.
	exigir(#J.PremiosDe(runas, 0) == 0, "sin rondas no hay títulos")
	exigir(#J.PremiosDe(runas, 20) == #runas.Premios, "el máximo gana todo")
	exigir(#J.PremiosDe(pares, 9) == #pares.Premios, "el mejor tablero gana todo")
	exigir(#J.PremiosDe(pares, 0) == 0, "no terminar no gana nada")
	-- Los premios de pares no pueden pedir más intentos de los permitidos.
	for _, premio in pares.Premios do
		exigir(premio.Marca <= J.Pares.IntentosMaximos, "premio imposible: " .. premio.Titulo)
	end
	-- Los de runas, no más rondas de las que se juegan.
	for _, premio in runas.Premios do
		exigir(premio.Marca <= J.Runas.RondaMaxima, "premio imposible: " .. premio.Titulo)
	end
end)

prueba("juegos: el tablero y los tiempos cierran", function()
	exigir(J.Cartas() == J.Pares.Pares * 2, "las cartas son dos por par")
	exigir(J.Pares.IntentosMaximos >= J.Pares.Pares, "con menos intentos que pares es imposible ganar")
	exigir(#J.SimbolosCarta >= J.Pares.Pares, "faltan símbolos para las cartas")
	exigir(#J.ColoresRuna >= J.Runas.Colores, "faltan colores para las runas")
	exigir(J.Pares.Duracion > 0 and J.Cooldown >= 0, "tiempos sanos")

	-- Cuanto más larga la secuencia, más tiempo para mostrarla y para responder.
	exigir(J.TiempoRespuesta(3) > J.TiempoRespuesta(1), "más runas, más tiempo")
	exigir(J.TiempoMostrar(3) > J.TiempoMostrar(1), "mostrar más runas tarda más")
	exigir(J.TiempoRespuesta(0) > 0 and J.TiempoMostrar(0) > 0, "nunca cero")
	-- Responder tiene que dar más margen que mirar: si no, es injugable.
	exigir(J.TiempoRespuesta(J.Runas.RondaMaxima) > J.TiempoMostrar(J.Runas.RondaMaxima), "poco tiempo para responder")
end)
