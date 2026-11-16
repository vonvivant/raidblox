--!strict
-- ArenaManager: arenas clasificatorias del Reclutador de Arenas (NPC-038).
--
-- Cómo funciona, de arriba hacia abajo:
--
-- 1. El jugador habla con el NPC y se anota en 1v1, 2v2 o 3v3. En 2v2 y 3v3,
--    si tiene grupo del tamaño justo, se anota todo el grupo junto.
-- 2. Cada dos segundos el emparejador busca dos lados del mismo tamaño con
--    rating parecido. La ventana de rating se abre con la espera.
-- 3. La partida se juega en una plataforma generada lejos de la ciudad: tres
--    rondas, gana el que gane dos. Cada ronda empieza con todos vivos y
--    quietos unos segundos, y termina cuando un lado queda sin nadie en pie o
--    cuando se acaba el tiempo (ahí gana el lado con más vida restante).
-- 4. Al final se mueve el rating (Elo), se paga honor con tope diario y cada
--    uno vuelve exactamente al lugar desde donde se anotó.
--
-- Reglas que importan: el servidor decide todo, el jugador no puede anotarse
-- dos veces, irse de la partida es rendirse, y si el servidor se cae con una
-- partida en curso nadie queda encerrado (el perfil no guarda nada "en
-- partida", solo el rating).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CFG = require(ReplicatedStorage.Configs.ArenasConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local AntiCheat = require(script.Parent.Parent.AntiCheat)
local BandoManager = require(script.Parent.Parent.BandoManager)
local DataManager = require(script.Parent.Parent.DataManager)
local GrupoManager = require(script.Parent.Parent.GrupoManager)
local NpcManager = require(script.Parent.Parent.NpcManager)
local CombatManager = require(script.Parent.Parent.Combate.CombatManager)

type Modo = CFG.Modo

-- Un lado de la cola: uno o varios jugadores que entran juntos.
type Entrada = {
	Jugadores: { Player },
	Rating: number,
	Desde: number, -- os.clock() en que se anotó
}

type Lado = {
	Numero: number, -- 1 o 2
	Jugadores: { Player },
	Rating: number,
	Rondas: number,
	Vivos: { [Player]: boolean },
}

type Partida = {
	Id: string,
	Modo: Modo,
	Lugar: number, -- índice de plataforma
	Origen: Vector3,
	Carpeta: Folder,
	Lados: { Lado },
	Ronda: number,
	Fase: "Preparacion" | "Jugando" | "Pausa" | "Fin",
	Hasta: number, -- os.clock() en que termina la fase
	Retornos: { [Player]: CFrame },
	Terminada: boolean,
}

local ArenaManager = {}

local iniciado = false
local colas: { [string]: { Entrada } } = {}
local partidas: { [string]: Partida } = {}
local partidaDe: { [Player]: Partida } = {}
local ladoDe: { [Player]: Lado } = {}
local enCola: { [Player]: string } = {}
local ultimoIntento: { [Player]: number } = {}
local lugaresUsados: { [number]: boolean } = {}
local secuencia = 0

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

------------------------------------------------------------------------
-- Rating y premios (lo que se guarda en el perfil)
------------------------------------------------------------------------

local function pvpDe(datos: Types.DatosJugador): { [string]: any }
	local pvp: { [string]: any } = (datos :: any).Pvp or {}
	return pvp
end

local function ratingDe(player: Player, modo: string): number
	local datos = DataManager.GetData(player)
	if not datos then
		return CFG.RatingInicial
	end
	local pvp = pvpDe(datos)
	local porModo: { [string]: any } = pvp.Modos or {}
	local mio = porModo[modo]
	if typeof(mio) == "table" and typeof(mio.Rating) == "number" then
		return mio.Rating
	end
	return CFG.RatingInicial
end

local function ratingDeLado(jugadores: { Player }, modo: string): number
	local ratings: { number } = {}
	for _, player in jugadores do
		table.insert(ratings, ratingDe(player, modo))
	end
	return CFG.Promedio(ratings)
end

-- Anota el resultado: rating, racha, honor (con tope diario) y el historial
-- chico que muestra la interfaz.
local function anotarResultado(player: Player, modo: string, gano: boolean, delta: number)
	local pagado = 0
	DataManager.Mutar(player, "Pvp", function(d)
		local pvp = pvpDe(d)
		local porModo: { [string]: any } = pvp.Modos or {}
		local mio: { [string]: any } = porModo[modo] or {}
		local rating = if typeof(mio.Rating) == "number" then mio.Rating else CFG.RatingInicial
		local racha = if typeof(mio.Racha) == "number" then mio.Racha else 0

		mio.Rating = CFG.AplicarDelta(rating, delta)
		mio.Ganadas = (if typeof(mio.Ganadas) == "number" then mio.Ganadas else 0) + (if gano then 1 else 0)
		mio.Perdidas = (if typeof(mio.Perdidas) == "number" then mio.Perdidas else 0) + (if gano then 0 else 1)
		mio.Racha = if gano then racha + 1 else 0
		mio.Mejor = math.max(if typeof(mio.Mejor) == "number" then mio.Mejor else 0, mio.Rating)

		local dia = CFG.DiaDe(os.time())
		local hoyDia = if typeof(pvp.Dia) == "number" then pvp.Dia else -1
		local ganadoHoy = if hoyDia == dia and typeof(pvp.HonorHoy) == "number" then pvp.HonorHoy else 0
		local pago, nuevoTotal = CFG.Honor(gano, racha, ganadoHoy)
		pagado = pago
		pvp.Dia = dia
		pvp.HonorHoy = nuevoTotal

		porModo[modo] = mio
		pvp.Modos = porModo
		local libre: { [string]: any } = d :: any
		libre.Pvp = pvp
	end)
	if pagado > 0 then
		DataManager.AddHonor(player, pagado)
	end
	return pagado
end

------------------------------------------------------------------------
-- El mapa: una plataforma por partida, generada al vuelo
------------------------------------------------------------------------

local function parte(props: { [string]: any }, padre: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local libre: { [string]: any } = p :: any
	for clave, valor in props do
		libre[clave] = valor
	end
	p.Parent = padre
	return p
end

local function colorLado(numero: number): Color3
	return if numero == 1 then Color3.fromRGB(220, 70, 70) else Color3.fromRGB(70, 120, 235)
end

local function construir(partida: Partida)
	local mapa = CFG.Mapa
	local centro = partida.Origen
	parte({
		Name = "Piso",
		Size = mapa.Tamano,
		Position = centro,
		Color = Color3.fromRGB(120, 110, 100),
		Material = Enum.Material.Slate,
	}, partida.Carpeta)

	-- Cuatro muros para que nadie se caiga ni escape de la plataforma.
	local mitadX, mitadZ = mapa.Tamano.X / 2, mapa.Tamano.Z / 2
	local alto = mapa.AlturaMuro
	local muros = {
		{ Size = Vector3.new(mapa.Tamano.X, alto, 2), Offset = Vector3.new(0, alto / 2, -mitadZ) },
		{ Size = Vector3.new(mapa.Tamano.X, alto, 2), Offset = Vector3.new(0, alto / 2, mitadZ) },
		{ Size = Vector3.new(2, alto, mapa.Tamano.Z), Offset = Vector3.new(-mitadX, alto / 2, 0) },
		{ Size = Vector3.new(2, alto, mapa.Tamano.Z), Offset = Vector3.new(mitadX, alto / 2, 0) },
	}
	for i, muro in muros do
		parte({
			Name = `Muro{i}`,
			Size = muro.Size,
			Position = centro + muro.Offset,
			Color = Color3.fromRGB(70, 65, 60),
			Material = Enum.Material.Brick,
			Transparency = 0.35,
		}, partida.Carpeta)
	end

	-- Dos plataformas de salida, una por lado, con su color.
	for _, lado in partida.Lados do
		local signo = if lado.Numero == 1 then -1 else 1
		parte({
			Name = `Salida{lado.Numero}`,
			Size = Vector3.new(16, 1, 16),
			Position = centro + Vector3.new(signo * CFG.Mapa.Spawn, 0.6, 0),
			Color = colorLado(lado.Numero),
			Material = Enum.Material.Neon,
			Transparency = 0.5,
		}, partida.Carpeta)
	end
end

local function puntoSalida(partida: Partida, lado: Lado, indice: number): CFrame
	local signo = if lado.Numero == 1 then -1 else 1
	local corrimiento = (indice - 1 - (#lado.Jugadores - 1) / 2) * CFG.Mapa.SeparacionCompanero
	local posicion = partida.Origen + Vector3.new(signo * CFG.Mapa.Spawn, 4, corrimiento)
	return CFrame.lookAt(posicion, Vector3.new(partida.Origen.X, posicion.Y, posicion.Z))
end

local function lugarLibre(): number?
	for i = 1, CFG.PartidasSimultaneas do
		if not lugaresUsados[i] then
			return i
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Estado que ve el cliente
------------------------------------------------------------------------

local function enviarEstado(player: Player)
	local partida = partidaDe[player]
	if partida then
		local mio = ladoDe[player]
		local rival = if partida.Lados[1] == mio then partida.Lados[2] else partida.Lados[1]
		local vivosMios, vivosRival = 0, 0
		for _, p in mio.Jugadores do
			if mio.Vivos[p] then
				vivosMios += 1
			end
		end
		for _, p in rival.Jugadores do
			if rival.Vivos[p] then
				vivosRival += 1
			end
		end
		NetworkBridge.Server.FireClient("ArenaEstado", player, {
			Modo = partida.Modo.Id,
			Nombre = partida.Modo.Nombre,
			Fase = partida.Fase,
			Ronda = partida.Ronda,
			Rondas = CFG.RondasMaximas,
			MisRondas = mio.Rondas,
			RondasRival = rival.Rondas,
			Vivos = vivosMios,
			VivosRival = vivosRival,
			Segundos = math.max(0, math.floor(partida.Hasta - os.clock())),
		})
		return
	end
	local modo = enCola[player]
	if modo then
		local espera = 0
		local cola: { Entrada } = colas[modo] or {}
		for _, entrada in cola do
			if table.find(entrada.Jugadores, player) then
				espera = math.floor(os.clock() - entrada.Desde)
			end
		end
		NetworkBridge.Server.FireClient("ArenaEstado", player, {
			Modo = modo,
			Fase = "Cola",
			Espera = espera,
			Rating = ratingDe(player, modo),
			Rango = CFG.RangoDe(ratingDe(player, modo)),
		})
		return
	end
	NetworkBridge.Server.FireClient("ArenaEstado", player, nil)
end

------------------------------------------------------------------------
-- Cola
------------------------------------------------------------------------

local function sacarDeCola(player: Player, avisarle: boolean)
	local modo = enCola[player]
	if not modo then
		return
	end
	local cola = colas[modo]
	if cola then
		for i = #cola, 1, -1 do
			if table.find(cola[i].Jugadores, player) then
				-- Si entró con grupo, el grupo entero sale.
				for _, companero in cola[i].Jugadores do
					enCola[companero] = nil
					if companero ~= player and avisarle then
						avisar(companero, "Tu grupo salió de la cola de arena.", "Aviso")
					end
					if companero ~= player then
						enviarEstado(companero)
					end
				end
				table.remove(cola, i)
			end
		end
	end
	enCola[player] = nil
	if avisarle then
		avisar(player, "Saliste de la cola de arena.", "Info")
	end
	enviarEstado(player)
end

local function anotar(player: Player, modoId: string): boolean
	local modo = CFG.Modo(modoId)
	if not modo then
		return false
	end
	if partidaDe[player] then
		avisar(player, "Ya estás en una partida de arena.", "Error")
		return false
	end
	local ahora = os.clock()
	if ahora - (ultimoIntento[player] or 0) < CFG.CooldownInscripcion then
		avisar(player, "Esperá unos segundos antes de volver a anotarte.", "Aviso")
		return false
	end
	if enCola[player] then
		avisar(player, `Ya estás en la cola de {enCola[player]}. Cancelá primero.`, "Aviso")
		return false
	end

	-- Con quién entra: solo, o con el grupo si tiene el tamaño justo.
	local jugadores: { Player } = { player }
	if modo.PorEquipo > 1 then
		local grupo = GrupoManager.GrupoDe(player)
		if grupo and #grupo.Miembros == modo.PorEquipo then
			if grupo.Lider ~= player then
				avisar(player, "Solo el líder del grupo anota al equipo.", "Aviso")
				return false
			end
			jugadores = {}
			for _, miembro in grupo.Miembros do
				if miembro.Parent ~= Players then
					continue
				end
				if partidaDe[miembro] or enCola[miembro] then
					avisar(player, `{miembro.DisplayName} ya está anotado en una arena.`, "Error")
					return false
				end
				table.insert(jugadores, miembro)
			end
			if #jugadores ~= modo.PorEquipo then
				avisar(player, "Falta algún compañero del grupo.", "Error")
				return false
			end
		elseif grupo and #grupo.Miembros > modo.PorEquipo then
			avisar(player, `Tu grupo es de {#grupo.Miembros}; para {modo.Id} entran {modo.PorEquipo}.`, "Error")
			return false
		end
	end

	ultimoIntento[player] = ahora
	colas[modoId] = colas[modoId] or {}
	table.insert(colas[modoId], {
		Jugadores = jugadores,
		Rating = ratingDeLado(jugadores, modoId),
		Desde = ahora,
	})
	for _, p in jugadores do
		enCola[p] = modoId
		avisar(p, `Anotado en {modo.Nombre}. Buscando rivales…`, "Exito")
		enviarEstado(p)
	end
	return true
end

------------------------------------------------------------------------
-- Partida
------------------------------------------------------------------------

local function ubicar(partida: Partida, lado: Lado)
	for i, player in lado.Jugadores do
		local personaje = player.Character
		if not personaje then
			continue
		end
		local combatiente = CombatManager.DeJugador(player)
		if combatiente then
			CombatManager.Restaurar(combatiente)
		end
		AntiCheat.Gracia(player, 4)
		personaje:PivotTo(puntoSalida(partida, lado, i))
	end
end

local function difundir(partida: Partida)
	for _, lado in partida.Lados do
		for _, player in lado.Jugadores do
			if player.Parent == Players then
				enviarEstado(player)
			end
		end
	end
end

local function devolver(partida: Partida, player: Player)
	partidaDe[player] = nil
	ladoDe[player] = nil
	player:SetAttribute("EnArena", nil)
	player:SetAttribute("ArenaLado", nil)
	local retorno = partida.Retornos[player]
	local personaje = player.Character
	if retorno and personaje and player.Parent == Players then
		AntiCheat.Gracia(player, 4)
		personaje:PivotTo(retorno)
		local combatiente = CombatManager.DeJugador(player)
		if combatiente then
			CombatManager.Restaurar(combatiente)
		end
	end
	partida.Retornos[player] = nil
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("ArenaEstado", player, nil)
	end
end

local function limpiar(partida: Partida)
	partidas[partida.Id] = nil
	lugaresUsados[partida.Lugar] = nil
	partida.Carpeta:Destroy()
end

-- Cierra la partida: mueve rating, paga honor y devuelve a todos.
local function terminar(partida: Partida, ganador: Lado?, motivo: string)
	if partida.Terminada then
		return
	end
	partida.Terminada = true
	partida.Fase = "Fin"
	partida.Hasta = os.clock() + CFG.Celebracion

	local modoId = partida.Modo.Id
	for _, lado in partida.Lados do
		local rival = if partida.Lados[1] == lado then partida.Lados[2] else partida.Lados[1]
		local gano = ganador == lado
		for _, player in lado.Jugadores do
			if player.Parent ~= Players then
				continue
			end
			local delta = if ganador == nil then 0 else CFG.Delta(ratingDe(player, modoId), rival.Rating, gano)
			local honor = if ganador == nil then 0 else anotarResultado(player, modoId, gano, delta)
			local resultado = if ganador == nil then "Empate" elseif gano then "¡Ganaron!" else "Perdieron"
			local signo = if delta >= 0 then "+" else ""
			avisar(
				player,
				`{resultado} {motivo} Rating {signo}{delta}{if honor > 0 then ` · +{honor} honor` else ""}`,
				if gano then "Exito" else "Info"
			)
		end
	end
	difundir(partida)

	task.delay(CFG.Celebracion, function()
		for _, lado in partida.Lados do
			for _, player in lado.Jugadores do
				devolver(partida, player)
			end
		end
		limpiar(partida)
	end)
end

local function empezarRonda(partida: Partida)
	partida.Ronda += 1
	partida.Fase = "Preparacion"
	partida.Hasta = os.clock() + CFG.Preparacion
	for _, lado in partida.Lados do
		table.clear(lado.Vivos)
		for _, player in lado.Jugadores do
			if player.Parent == Players then
				lado.Vivos[player] = true
			end
		end
		ubicar(partida, lado)
	end
	difundir(partida)
end

-- Cierra la ronda y decide si sigue la partida.
local function terminarRonda(partida: Partida, ganador: Lado?, motivo: string)
	if ganador then
		ganador.Rondas += 1
	end
	if ganador and ganador.Rondas >= CFG.RondasParaGanar then
		terminar(partida, ganador, motivo)
		return
	end
	if partida.Ronda >= CFG.RondasMaximas then
		local a, b = partida.Lados[1], partida.Lados[2]
		local mejor: Lado? = if a.Rondas > b.Rondas then a elseif b.Rondas > a.Rondas then b else nil
		terminar(partida, mejor, "Se jugaron las tres rondas.")
		return
	end
	partida.Fase = "Pausa"
	partida.Hasta = os.clock() + CFG.EntreRondas
	difundir(partida)
end

-- Vida total del lado, para resolver una ronda por tiempo.
local function vidaDe(lado: Lado): number
	local total = 0
	for _, player in lado.Jugadores do
		if not lado.Vivos[player] then
			continue
		end
		local combatiente = CombatManager.DeJugador(player)
		if combatiente then
			total += math.max(0, combatiente.Humanoid.Health)
		end
	end
	return total
end

local function vivos(lado: Lado): number
	local cuenta = 0
	for player, esta in lado.Vivos do
		if esta and player.Parent == Players then
			cuenta += 1
		end
	end
	return cuenta
end

local function revisarRonda(partida: Partida)
	local a, b = partida.Lados[1], partida.Lados[2]
	local va, vb = vivos(a), vivos(b)
	if va > 0 and vb > 0 then
		return
	end
	if va == 0 and vb == 0 then
		terminarRonda(partida, nil, "Cayeron todos.")
	else
		terminarRonda(partida, if va > 0 then a else b, `Ronda {partida.Ronda}.`)
	end
end

local function caer(player: Player)
	local partida = partidaDe[player]
	local lado = ladoDe[player]
	if not partida or not lado or partida.Fase ~= "Jugando" then
		return
	end
	if not lado.Vivos[player] then
		return
	end
	lado.Vivos[player] = nil
	difundir(partida)
	revisarRonda(partida)
end

-- Irse de la partida (o del juego) es rendirse.
local function abandonar(player: Player)
	local partida = partidaDe[player]
	local lado = ladoDe[player]
	if not partida or not lado then
		return
	end
	lado.Vivos[player] = nil
	local quedan = 0
	for _, p in lado.Jugadores do
		if p.Parent == Players and p ~= player then
			quedan += 1
		end
	end
	if quedan == 0 and not partida.Terminada then
		local rival = if partida.Lados[1] == lado then partida.Lados[2] else partida.Lados[1]
		terminar(partida, rival, "El rival abandonó.")
		return
	end
	if partida.Fase == "Jugando" then
		revisarRonda(partida)
	end
end

local function crearPartida(modo: Modo, ladoA: { Player }, ladoB: { Player }): boolean
	local lugar = lugarLibre()
	if not lugar then
		return false
	end
	secuencia += 1
	local carpeta = Instance.new("Folder")
	carpeta.Name = `Arena_{secuencia}`
	carpeta.Parent = Workspace

	local partida: Partida = {
		Id = `arena{secuencia}`,
		Modo = modo,
		Lugar = lugar,
		Origen = CFG.Mapa.Origen + Vector3.new((lugar - 1) * CFG.Mapa.Separacion, 0, 0),
		Carpeta = carpeta,
		Lados = {
			{ Numero = 1, Jugadores = ladoA, Rating = ratingDeLado(ladoA, modo.Id), Rondas = 0, Vivos = {} },
			{ Numero = 2, Jugadores = ladoB, Rating = ratingDeLado(ladoB, modo.Id), Rondas = 0, Vivos = {} },
		},
		Ronda = 0,
		Fase = "Preparacion",
		Hasta = os.clock() + CFG.Preparacion,
		Retornos = {},
		Terminada = false,
	}
	lugaresUsados[lugar] = true
	partidas[partida.Id] = partida
	construir(partida)

	for _, lado in partida.Lados do
		for _, player in lado.Jugadores do
			enCola[player] = nil
			partidaDe[player] = partida
			ladoDe[player] = lado
			player:SetAttribute("EnArena", partida.Id)
			player:SetAttribute("ArenaLado", lado.Numero)
			local personaje = player.Character
			local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
			if raiz and raiz:IsA("BasePart") then
				partida.Retornos[player] = raiz.CFrame
			end
			avisar(player, `¡{modo.Nombre}! Preparate: la ronda 1 arranca en {CFG.Preparacion} segundos.`, "Exito")
		end
	end
	empezarRonda(partida)
	return true
end

------------------------------------------------------------------------
-- Emparejador
------------------------------------------------------------------------

-- Saca de la cola a los que ya no están, y devuelve la cola limpia.
local function limpiarCola(modoId: string): { Entrada }
	local cola = colas[modoId] or {}
	for i = #cola, 1, -1 do
		local entrada = cola[i]
		local completos = true
		for _, player in entrada.Jugadores do
			if player.Parent ~= Players then
				completos = false
			end
		end
		if not completos then
			for _, player in entrada.Jugadores do
				enCola[player] = nil
			end
			table.remove(cola, i)
		end
	end
	colas[modoId] = cola
	return cola
end

-- Junta entradas de la cola hasta llenar un lado del tamaño pedido.
-- Devuelve los índices usados, o nil si no alcanza con ventana compatible.
local function armarLado(cola: { Entrada }, desde: number, tamano: number, usados: { [number]: boolean }): { number }?
	local base = cola[desde]
	if not base or usados[desde] then
		return nil
	end
	local elegidos = { desde }
	local total = #base.Jugadores
	if total > tamano then
		return nil
	end
	local ahora = os.clock()
	for i = 1, #cola do
		if total == tamano then
			break
		end
		if i == desde or usados[i] then
			continue
		end
		local otra = cola[i]
		if total + #otra.Jugadores > tamano then
			continue
		end
		if not CFG.Compatibles(base.Rating, otra.Rating, ahora - base.Desde, ahora - otra.Desde) then
			continue
		end
		table.insert(elegidos, i)
		total += #otra.Jugadores
	end
	if total ~= tamano then
		return nil
	end
	return elegidos
end

local function jugadoresDe(cola: { Entrada }, indices: { number }): ({ Player }, number)
	local jugadores: { Player } = {}
	local ratings: { number } = {}
	for _, i in indices do
		for _, player in cola[i].Jugadores do
			table.insert(jugadores, player)
		end
		table.insert(ratings, cola[i].Rating)
	end
	return jugadores, CFG.Promedio(ratings)
end

local function emparejar(modo: Modo)
	local cola = limpiarCola(modo.Id)
	-- Los que esperan más primero.
	table.sort(cola, function(a, b)
		return a.Desde < b.Desde
	end)
	local intentos = 0
	while intentos < CFG.PartidasSimultaneas do
		intentos += 1
		local usados: { [number]: boolean } = {}
		local primero: { number }? = nil
		for i = 1, #cola do
			primero = armarLado(cola, i, modo.PorEquipo, usados)
			if primero then
				break
			end
		end
		if not primero then
			return
		end
		for _, i in primero do
			usados[i] = true
		end
		local segundo: { number }? = nil
		for i = 1, #cola do
			segundo = armarLado(cola, i, modo.PorEquipo, usados)
			if segundo then
				break
			end
		end
		if not segundo then
			return
		end

		local ladoA, ratingA = jugadoresDe(cola, primero)
		local ladoB, ratingB = jugadoresDe(cola, segundo)
		if not CFG.Compatibles(ratingA, ratingB, 0, 0) then
			-- Los lados existen pero no son parejos: esperamos a que la
			-- ventana se abra sola con el tiempo.
			return
		end
		if not crearPartida(modo, ladoA, ladoB) then
			return -- no hay plataforma libre; se intenta en el próximo tick
		end
		local quitar: { number } = {}
		for _, i in primero do
			table.insert(quitar, i)
		end
		for _, i in segundo do
			table.insert(quitar, i)
		end
		table.sort(quitar, function(a, b)
			return a > b
		end)
		for _, i in quitar do
			table.remove(cola, i)
		end
	end
end

------------------------------------------------------------------------
-- Ciclo
------------------------------------------------------------------------

local function tick(): nil
	local ahora = os.clock()
	for _, modo in CFG.Modos do
		if #(colas[modo.Id] or {}) > 0 then
			emparejar(modo)
		end
	end
	for _, partida in partidas do
		if partida.Terminada or ahora < partida.Hasta then
			continue
		end
		if partida.Fase == "Preparacion" then
			partida.Fase = "Jugando"
			partida.Hasta = ahora + CFG.DuracionRonda
			difundir(partida)
		elseif partida.Fase == "Jugando" then
			local a, b = partida.Lados[1], partida.Lados[2]
			local va, vb = vidaDe(a), vidaDe(b)
			local mejor: Lado? = if va > vb then a elseif vb > va then b else nil
			terminarRonda(partida, mejor, "Se acabó el tiempo.")
		elseif partida.Fase == "Pausa" then
			empezarRonda(partida)
		end
	end
	return nil
end

------------------------------------------------------------------------
-- API
------------------------------------------------------------------------

function ArenaManager.EnArena(player: Player): boolean
	return partidaDe[player] ~= nil
end

-- Para BandoManager: con quién puede pelear el que está en un arena.
function ArenaManager.Rival(a: Player, b: Player): boolean
	local pa, pb = partidaDe[a], partidaDe[b]
	if not pa or pa ~= pb then
		return false
	end
	return ladoDe[a] ~= ladoDe[b]
end

function ArenaManager.Init()
	if iniciado then
		return
	end
	iniciado = true

	BandoManager.SetArena(function(player: Player): boolean
		return partidaDe[player] ~= nil
	end, ArenaManager.Rival)

	for _, modo in CFG.Modos do
		colas[modo.Id] = {}
		NpcManager.RegistrarAccion(`Arena{modo.Id}`, function(player: Player): boolean
			return anotar(player, modo.Id)
		end)
	end
	NpcManager.RegistrarAccion("ArenaCancelar", function(player: Player): boolean
		if not enCola[player] then
			avisar(player, "No estás en ninguna cola.", "Aviso")
			return false
		end
		sacarDeCola(player, true)
		return true
	end)

	NetworkBridge.Server.OnEvent("ArenaSalirCola", function(player: Player)
		sacarDeCola(player, true)
	end)

	CombatManager.Murio:Connect(function(victima)
		local player = victima.Player
		if player then
			caer(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		sacarDeCola(player, false)
		abandonar(player)
		partidaDe[player] = nil
		ladoDe[player] = nil
		enCola[player] = nil
		ultimoIntento[player] = nil
	end)

	-- Si el personaje muere fuera del combate (caída, por ejemplo) también
	-- cuenta como caído en la ronda.
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(personaje: Model)
			local humanoid = personaje:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					caer(player)
				end)
			end
			-- Si murió en la arena, vuelve al punto de salida de su lado.
			local partida = partidaDe[player]
			local lado = ladoDe[player]
			if partida and lado and not partida.Terminada then
				task.defer(function()
					local indice = table.find(lado.Jugadores, player) or 1
					AntiCheat.Gracia(player, 4)
					personaje:PivotTo(puntoSalida(partida, lado, indice))
				end)
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(CFG.TickEmparejar)
			local ok, err = pcall(tick)
			if not ok then
				warn(`[Arena] tick: {err}`)
			end
		end
	end)

	if RunService:IsStudio() then
		print(`[Arena] listo: {#CFG.Modos} modos, hasta {CFG.PartidasSimultaneas} partidas a la vez`)
	end
end
return ArenaManager
