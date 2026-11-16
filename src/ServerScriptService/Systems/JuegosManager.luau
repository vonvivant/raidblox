--!strict
-- JuegosManager: los minijuegos del Crupier (NPC-036). Sin apuestas: jugar es
-- gratis y lo único que se gana son títulos y el récord personal.
--
-- Reglas que importan:
--   * Una partida por jugador a la vez, y hay que estar junto al Crupier para
--     empezarla (después se puede caminar: la partida es una ventana, no un
--     lugar).
--   * En "Pares" el tablero vive en el servidor y solo se revela lo que el
--     jugador toca: ni leyendo la memoria del cliente se puede adivinar.
--   * En "Runas" la secuencia se le manda al cliente para que la muestre (así
--     funciona el juego), así que un cliente modificado podría responder
--     perfecto. Como no hay premios de oro ni de combate, el que hace trampa
--     se hace trampa a sí mismo; está anotado en la documentación.
--   * Cada paso tiene su reloj: si se te pasa el tiempo, la partida termina.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage.Configs.JuegosConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.DataManager)
local NpcManager = require(script.Parent.NpcManager)

type Juego = CFG.Juego

type Partida = {
	Juego: Juego,
	-- Runas
	Secuencia: { number },
	Ronda: number,
	Indice: number,
	Mostrando: boolean,
	-- Pares
	Tablero: { number }, -- carta -> símbolo
	Resueltas: { [number]: boolean },
	Vuelta: number?, -- carta dada vuelta esperando la segunda
	Intentos: number,
	-- Común
	Hasta: number, -- os.clock() límite de la jugada en curso
	Fin: boolean,
}

local JuegosManager = {}

local iniciado = false
local azar = Random.new()
local partidas: { [Player]: Partida } = {}
local ultima: { [Player]: number } = {}

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function recordsDe(datos: Types.DatosJugador): { [string]: any }
	local libre: { [string]: any } = datos :: any
	local juegos: { [string]: any } = libre.Juegos or {}
	return juegos
end

function JuegosManager.Record(player: Player, juegoId: string): (number, number)
	local datos = DataManager.GetData(player)
	if not datos then
		return 0, 0
	end
	local mio = recordsDe(datos)[juegoId]
	if typeof(mio) ~= "table" then
		return 0, 0
	end
	local mejor = if typeof(mio.Mejor) == "number" then mio.Mejor else 0
	local partidasJugadas = if typeof(mio.Partidas) == "number" then mio.Partidas else 0
	return mejor, partidasJugadas
end

------------------------------------------------------------------------
-- Estado que ve el cliente
------------------------------------------------------------------------

-- Qué cartas ve el jugador: las resueltas con su símbolo, la que acaba de dar
-- vuelta, y el resto tapadas (`false`).
local function vistaTablero(partida: Partida): { any }
	local vista: { any } = {}
	for carta = 1, #partida.Tablero do
		if partida.Resueltas[carta] or partida.Vuelta == carta then
			vista[carta] = partida.Tablero[carta]
		else
			vista[carta] = false
		end
	end
	return vista
end

local function enviar(player: Player, extra: { [string]: any }?)
	local partida = partidas[player]
	if not partida then
		NetworkBridge.Server.FireClient("JuegoEstado", player, nil)
		return
	end
	local mejor = JuegosManager.Record(player, partida.Juego.Id)
	local estado: { [string]: any } = {
		Juego = partida.Juego.Id,
		Nombre = partida.Juego.Nombre,
		Unidad = partida.Juego.Unidad,
		Record = mejor,
		Segundos = math.max(0, math.floor(partida.Hasta - os.clock())),
	}
	if partida.Juego.Id == "Runas" then
		estado.Ronda = partida.Ronda
		estado.Mostrando = partida.Mostrando
		estado.Colores = CFG.Runas.Colores
		estado.Secuencia = if partida.Mostrando then partida.Secuencia else nil
		estado.Paso = partida.Indice
	else
		estado.Cartas = vistaTablero(partida)
		estado.Intentos = partida.Intentos
		estado.IntentosMaximos = CFG.Pares.IntentosMaximos
		estado.Resueltos = 0
		for _ in partida.Resueltas do
			estado.Resueltos += 1
		end
	end
	local extras: { [string]: any } = extra or {}
	for clave, valor in extras do
		estado[clave] = valor
	end
	NetworkBridge.Server.FireClient("JuegoEstado", player, estado)
end

------------------------------------------------------------------------
-- Terminar una partida: récord y títulos
------------------------------------------------------------------------

local function terminar(player: Player, resultado: number, motivo: string)
	local partida = partidas[player]
	if not partida or partida.Fin then
		return
	end
	partida.Fin = true
	local juego = partida.Juego
	local mejorAntes = JuegosManager.Record(player, juego.Id)
	local esRecord = CFG.EsMejor(juego, resultado, mejorAntes)

	DataManager.Mutar(player, "Juegos", function(d)
		local libre: { [string]: any } = d :: any
		local juegos = recordsDe(d)
		local mio: { [string]: any } = juegos[juego.Id] or {}
		mio.Partidas = (if typeof(mio.Partidas) == "number" then mio.Partidas else 0) + 1
		if esRecord then
			mio.Mejor = resultado
		end
		juegos[juego.Id] = mio
		libre.Juegos = juegos
	end)

	local nuevos: { string } = {}
	for _, premio in CFG.PremiosDe(juego, resultado) do
		if DataManager.AddTitulo(player, premio.Titulo) then
			table.insert(nuevos, premio.Titulo)
		end
	end

	local cola = if esRecord then " ¡Récord personal!" else ""
	avisar(player, `{motivo} {resultado} {juego.Unidad}.{cola}`, if esRecord then "Exito" else "Info")
	for _, titulo in nuevos do
		avisar(player, `¡Título nuevo: {titulo}!`, "Oro")
	end

	partidas[player] = nil
	ultima[player] = os.clock()
	NetworkBridge.Server.FireClient("JuegoEstado", player, {
		Juego = juego.Id,
		Nombre = juego.Nombre,
		Fase = "Fin",
		Resultado = resultado,
		Unidad = juego.Unidad,
		Record = JuegosManager.Record(player, juego.Id),
		EsRecord = esRecord,
		Titulos = nuevos,
		Motivo = motivo,
	})
end

-- Si el reloj de la jugada se vence, se cierra la partida con lo logrado.
local function vigilar(player: Player, partida: Partida)
	task.delay(math.max(0, partida.Hasta - os.clock()) + 0.5, function()
		if partidas[player] ~= partida or partida.Fin then
			return
		end
		if os.clock() < partida.Hasta then
			return -- la jugada se renovó; el reloj nuevo tiene su propio vigía
		end
		if partida.Juego.Id == "Runas" then
			terminar(player, partida.Ronda - 1, "Se te pasó el tiempo.")
		else
			terminar(player, 0, "Se acabó el tiempo.")
		end
	end)
end

local function plazo(player: Player, partida: Partida, segundos: number)
	partida.Hasta = os.clock() + segundos
	vigilar(player, partida)
end

------------------------------------------------------------------------
-- Runas
------------------------------------------------------------------------

local function siguienteRonda(player: Player, partida: Partida)
	partida.Ronda += 1
	partida.Indice = 1
	partida.Mostrando = true
	table.insert(partida.Secuencia, azar:NextInteger(1, CFG.Runas.Colores))
	plazo(player, partida, CFG.TiempoMostrar(#partida.Secuencia) + CFG.TiempoRespuesta(#partida.Secuencia))
	enviar(player)
	-- Mientras el cliente muestra la secuencia no se aceptan toques.
	task.delay(CFG.TiempoMostrar(#partida.Secuencia), function()
		if partidas[player] ~= partida or partida.Fin then
			return
		end
		partida.Mostrando = false
		plazo(player, partida, CFG.TiempoRespuesta(#partida.Secuencia))
		enviar(player)
	end)
end

local function tocarRuna(player: Player, partida: Partida, runa: number): Types.Respuesta
	if partida.Mostrando then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if runa < 1 or runa > CFG.Runas.Colores then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if partida.Secuencia[partida.Indice] ~= runa then
		terminar(player, partida.Ronda - 1, "Esa no era.")
		return NetworkBridge.Ok({ Estado = "Error" })
	end
	partida.Indice += 1
	if partida.Indice > #partida.Secuencia then
		if partida.Ronda >= CFG.Runas.RondaMaxima then
			terminar(player, partida.Ronda, "¡Llegaste al final!")
			return NetworkBridge.Ok({ Estado = "Fin" })
		end
		siguienteRonda(player, partida)
		return NetworkBridge.Ok({ Estado = "Ronda" })
	end
	enviar(player)
	return NetworkBridge.Ok({ Estado = "Bien" })
end

------------------------------------------------------------------------
-- Pares
------------------------------------------------------------------------

local function mezclarTablero(): { number }
	local cartas: { number } = {}
	for simbolo = 1, CFG.Pares.Pares do
		table.insert(cartas, simbolo)
		table.insert(cartas, simbolo)
	end
	for i = #cartas, 2, -1 do
		local j = azar:NextInteger(1, i)
		cartas[i], cartas[j] = cartas[j], cartas[i]
	end
	return cartas
end

local function tocarCarta(player: Player, partida: Partida, carta: number): Types.Respuesta
	if carta < 1 or carta > #partida.Tablero or partida.Resueltas[carta] then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if partida.Vuelta == nil then
		partida.Vuelta = carta
		enviar(player)
		return NetworkBridge.Ok({ Estado = "Vuelta" })
	end
	local primera = partida.Vuelta
	if primera == carta then
		return NetworkBridge.Fail("INVALID_ARGS") -- la misma carta dos veces
	end
	partida.Intentos += 1
	local iguales = partida.Tablero[primera] == partida.Tablero[carta]
	if iguales then
		partida.Resueltas[primera] = true
		partida.Resueltas[carta] = true
		partida.Vuelta = nil
		local resueltos = 0
		for _ in partida.Resueltas do
			resueltos += 1
		end
		if resueltos >= #partida.Tablero then
			terminar(player, partida.Intentos, "¡Tablero limpio!")
			return NetworkBridge.Ok({ Estado = "Fin" })
		end
		enviar(player, { Par = true })
		return NetworkBridge.Ok({ Estado = "Par" })
	end
	-- No eran pareja: el cliente las muestra un instante y el servidor las tapa.
	local mostrar = vistaTablero(partida)
	mostrar[carta] = partida.Tablero[carta]
	if partida.Intentos >= CFG.Pares.IntentosMaximos then
		enviar(player, { Cartas = mostrar, Par = false })
		terminar(player, 0, "Se te acabaron los intentos.")
		return NetworkBridge.Ok({ Estado = "Fin" })
	end
	partida.Vuelta = nil
	-- `Cartas` muestra las dos un instante; `Tapadas` es la verdad a la que el
	-- cliente vuelve después, así no tiene que adivinar qué estaba resuelto.
	enviar(player, { Cartas = mostrar, Tapadas = vistaTablero(partida), Par = false })
	return NetworkBridge.Ok({ Estado = "Fallo" })
end

------------------------------------------------------------------------
-- Empezar y salir
------------------------------------------------------------------------

local function empezar(player: Player, juegoId: string): boolean
	local juego = CFG.Juego(juegoId)
	if not juego then
		return false
	end
	if partidas[player] then
		avisar(player, "Terminá la partida que tenés en curso.", "Aviso")
		return false
	end
	local espera = CFG.Cooldown - (os.clock() - (ultima[player] or -math.huge))
	if espera > 0 then
		avisar(player, `Esperá {math.ceil(espera)} segundos para la próxima.`, "Aviso")
		return false
	end

	local partida: Partida = {
		Juego = juego,
		Secuencia = {},
		Ronda = 0,
		Indice = 1,
		Mostrando = false,
		Tablero = {},
		Resueltas = {},
		Vuelta = nil,
		Intentos = 0,
		Hasta = os.clock(),
		Fin = false,
	}
	partidas[player] = partida
	if juego.Id == "Runas" then
		siguienteRonda(player, partida)
	else
		partida.Tablero = mezclarTablero()
		plazo(player, partida, CFG.Pares.Duracion)
		enviar(player)
	end
	return true
end

------------------------------------------------------------------------
-- API
------------------------------------------------------------------------

function JuegosManager.Init()
	if iniciado then
		return
	end
	iniciado = true

	for _, juego in CFG.Juegos do
		NpcManager.RegistrarAccion(`Juego{juego.Id}`, function(player: Player): boolean
			return empezar(player, juego.Id)
		end)
	end

	NetworkBridge.Server.OnInvoke("JuegoJugar", function(player: Player, valor: unknown): Types.Respuesta
		local partida = partidas[player]
		if not partida or partida.Fin then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		local n = NetworkBridge.Guard.Integer(valor, 1, CFG.Cartas())
		if not n then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if os.clock() > partida.Hasta then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		if partida.Juego.Id == "Runas" then
			return tocarRuna(player, partida, n)
		end
		return tocarCarta(player, partida, n)
	end)

	NetworkBridge.Server.OnEvent("JuegoSalir", function(player: Player)
		local partida = partidas[player]
		if not partida then
			return
		end
		-- Abandonar cuenta lo logrado hasta ahí (en Pares, nada).
		local resultado = if partida.Juego.Id == "Runas" then partida.Ronda - 1 else 0
		terminar(player, resultado, "Dejaste la partida.")
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		partidas[player] = nil
		ultima[player] = nil
	end)
end

return JuegosManager
