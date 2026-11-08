--!strict
-- ArchitectWarManager: lógica de la Guerra de Arquitectos (Team vs Team sin PvP).
--
-- Ciclo de una partida:
--   Esperando -> (hay jugadores suficientes) -> Cuenta -> EnCurso -> Terminada -> Esperando
--
-- * Los jugadores recolectan Madera/Piedra/Hierro en nodos (ProximityPrompt con
--   tiempo de mantener presionado) y los llevan encima hasta CapacidadCarga.
-- * En el depósito de su base entregan TODO lo que llevan al almacén del equipo.
--   El almacén completa automáticamente la etapa actual y las siguientes.
-- * Al completar una etapa, el holograma se vuelve sólido con la skin de
--   estructura de quien más depositó desde la etapa anterior.
-- * Gana el primer equipo en colocar el Estandarte (etapa 5). Si se acaba el
--   tiempo, gana el que más avanzó. Si un equipo queda vacío, la partida se
--   cancela sin recompensas (fuera de Studio). Solo cobra quien aportó.
--
-- Todo se valida en el servidor: equipo, distancia, tiempo de recolección,
-- capacidad y fase de la partida.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Pruebas = require(game:GetService("ReplicatedStorage").Modules.Pruebas)
local Teams = game:GetService("Teams")

local GuerraConfig = require(ReplicatedStorage.Configs.GuerraConfig)
local ZoneConfig = require(ReplicatedStorage.Configs.ZoneConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local BandoManager = require(script.Parent.Parent.BandoManager)
local AntiCheat = require(script.Parent.Parent.AntiCheat)
local ArenaGuerra = require(script.Parent.ArenaGuerra)

type Fase = "Esperando" | "Cuenta" | "EnCurso" | "Terminada"
type Carga = { [string]: number }

type EstadoEquipo = {
	Def: GuerraConfig.Equipo,
	Team: Team,
	Base: ArenaGuerra.Base,
	Etapa: number, -- etapa en construcción (1..5); 6 = terminado
	Depositado: { [string]: number }, -- aplicado a la etapa actual
	Almacen: { [string]: number }, -- sobrante para etapas siguientes
	-- Aportes por UserId: sobreviven si el jugador sale y vuelve a entrar.
	AportesEtapa: { [number]: number },
	AportesTotal: { [number]: number },
}

local RECURSOS = { "Madera", "Piedra", "Hierro" }

local ArchitectWarManager = {}

local equipos: { [string]: EstadoEquipo } = {}
local ordenEquipos: { string } = {}
local fase: Fase = "Esperando"
local finCuenta = 0
local finPartida = 0
local ganador: string? = nil -- id del equipo, "Empate", "Cancelada" o nil
local cargas: { [Player]: Carga } = {}
local equipoPorUsuario: { [number]: string } = {} -- para volver al mismo equipo al reingresar
local nodosAgotados: { [BasePart]: boolean } = {}
local inicioPresion: { [Player]: { [ProximityPrompt]: number } } = {}
local ultimaRecoleccion: { [Player]: number } = {}
local iniciado = false

local TOTAL_ETAPAS = #GuerraConfig.Etapas

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function enStudio(): boolean
	return RunService:IsStudio()
end

-- Studio o ModoPruebas: arena generada y requisitos reducidos.
local function modoPrueba(): boolean
	return Pruebas.Activas()
end

local function requisitos(etapa: number): { [string]: number }
	local def = GuerraConfig.Etapas[etapa]
	local resultado: { [string]: number } = {}
	if not def then
		return resultado
	end
	local divisor = if modoPrueba() then GuerraConfig.DivisorRequisitosEnStudio else 1
	for recurso, cantidad in def.Requisitos do
		resultado[recurso] = math.max(1, math.ceil(cantidad / divisor))
	end
	return resultado
end

local function totalCarga(carga: Carga): number
	local total = 0
	for _, n in carga do
		total += n
	end
	return total
end

local function cargaDe(player: Player): Carga
	local carga = cargas[player]
	if not carga then
		carga = { Madera = 0, Piedra = 0, Hierro = 0 }
		if player.Parent == Players then
			cargas[player] = carga
		end
	end
	return carga
end

local function enviarCarga(player: Player)
	NetworkBridge.Server.FireClient("GuerraCarga", player, cargaDe(player), GuerraConfig.CapacidadCarga)
end

local function avisarTodos(texto: string)
	NetworkBridge.Server.FireAll("Notificacion", texto, "Guerra")
end

local function avisar(player: Player, texto: string)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, "Guerra")
end

local function equipoDe(player: Player): EstadoEquipo?
	for _, estado in equipos do
		if player.Team == estado.Team then
			return estado
		end
	end
	return nil
end

local function cerca(player: Player, objetivo: BasePart): boolean
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return false
	end
	local limite = GuerraConfig.MaxDistanciaInteraccion + objetivo.Size.Magnitude / 2
	return (raiz.Position - objetivo.Position).Magnitude <= limite
end

-- Progreso total como número (etapas completas + fracción de la actual).
local function puntaje(estado: EstadoEquipo): number
	if estado.Etapa > TOTAL_ETAPAS then
		return TOTAL_ETAPAS
	end
	local req = requisitos(estado.Etapa)
	local necesario, hecho = 0, 0
	for recurso, cantidad in req do
		necesario += cantidad
		hecho += math.min(cantidad, estado.Depositado[recurso] or 0)
	end
	return (estado.Etapa - 1) + (if necesario > 0 then hecho / necesario else 0)
end

------------------------------------------------------------------------
-- Estado para los clientes
------------------------------------------------------------------------

local function snapshot(): { [string]: any }
	local listaEquipos = {}
	for _, id in ordenEquipos do
		local estado = equipos[id]
		local etapaDef = GuerraConfig.Etapas[math.min(estado.Etapa, TOTAL_ETAPAS)]
		table.insert(listaEquipos, {
			Id = id,
			Nombre = estado.Def.Nombre,
			Color = estado.Def.Color.Color,
			Etapa = estado.Etapa,
			EtapaNombre = if estado.Etapa > TOTAL_ETAPAS then "¡Completo!" else etapaDef.Nombre,
			Depositado = estado.Depositado,
			Almacen = estado.Almacen,
			Requisitos = requisitos(estado.Etapa),
			Jugadores = #estado.Team:GetPlayers(),
		})
	end
	local ahora = os.clock()
	local restante: number? = nil
	if fase == "Cuenta" then
		restante = math.max(0, math.ceil(finCuenta - ahora))
	elseif fase == "EnCurso" then
		restante = math.max(0, math.ceil(finPartida - ahora))
	end
	return {
		Fase = fase,
		TiempoRestante = restante,
		TotalEtapas = TOTAL_ETAPAS,
		Equipos = listaEquipos,
		Ganador = ganador,
		JugadoresMinimos = if modoPrueba()
			then GuerraConfig.JugadoresMinimosEnStudio
			else GuerraConfig.JugadoresMinimos,
	}
end

local function difundir()
	NetworkBridge.Server.FireAll("GuerraEstado", snapshot())
end

------------------------------------------------------------------------
-- Equipos
------------------------------------------------------------------------

local function ponerEnEquipo(player: Player, estado: EstadoEquipo)
	player.Team = estado.Team
	player.Neutral = false
	-- Fuerza el spawn de la base (si no, Roblox también usa spawns neutrales del mapa).
	player.RespawnLocation = estado.Base.Spawn
	equipoPorUsuario[player.UserId] = estado.Def.Id
end

-- Equipo que corresponde por bando: Rojo y Azul juegan para su reino.
local function equipoDeBando(player: Player): EstadoEquipo?
	local bando = BandoManager.De(player)
	return if bando ~= "Violeta" then equipos[bando] else nil
end

local function asignarEquipo(player: Player)
	local porBando = equipoDeBando(player)
	if porBando then
		ponerEnEquipo(player, porBando)
		return
	end
	-- Violeta: si ya jugaba esta partida y volvió a entrar, vuelve a su equipo.
	local previo = equipoPorUsuario[player.UserId]
	if previo and equipos[previo] then
		ponerEnEquipo(player, equipos[previo])
		return
	end
	local menor: EstadoEquipo? = nil
	for _, id in ordenEquipos do
		local estado = equipos[id]
		if not menor or #estado.Team:GetPlayers() < #menor.Team:GetPlayers() then
			menor = estado
		end
	end
	if menor then
		ponerEnEquipo(player, menor)
	end
end

local function rebalancear()
	-- Rojos y azules van a su reino; los violetas se reparten para emparejar.
	table.clear(equipoPorUsuario)
	local violetas: { Player } = {}
	for _, player in Players:GetPlayers() do
		local porBando = equipoDeBando(player)
		if porBando then
			ponerEnEquipo(player, porBando)
		else
			table.insert(violetas, player)
		end
	end
	for _, player in violetas do
		asignarEquipo(player)
	end
end

------------------------------------------------------------------------
-- Nodos de recursos
------------------------------------------------------------------------

local function restaurarNodo(nodo: BasePart)
	nodosAgotados[nodo] = nil
	nodo.Transparency = 0
	local pp = nodo:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.Enabled = true
	end
end

local function agotarNodo(nodo: BasePart, segundos: number)
	nodosAgotados[nodo] = true
	nodo.Transparency = 0.7
	local pp = nodo:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.Enabled = false
	end
	task.delay(segundos, function()
		if nodosAgotados[nodo] then
			restaurarNodo(nodo)
		end
	end)
end

local function puedeInteractuar(player: Player, nodo: BasePart): boolean
	return fase == "EnCurso" and not nodosAgotados[nodo] and equipoDe(player) ~= nil and cerca(player, nodo)
end

local function alRecolectar(player: Player, nodo: BasePart, pp: ProximityPrompt)
	local presiones = inicioPresion[player]
	local inicio = presiones and presiones[pp]
	if presiones then
		presiones[pp] = nil
	end
	if not puedeInteractuar(player, nodo) then
		if fase ~= "EnCurso" then
			avisar(player, "La partida todavía no empezó: esperá la cuenta regresiva.")
		end
		return
	end
	local recurso = nodo:GetAttribute("Recurso")
	local def = if typeof(recurso) == "string" then GuerraConfig.Recursos[recurso :: any] else nil
	if not def or typeof(recurso) ~= "string" then
		return
	end

	-- El tiempo de mantener presionado lo controla el cliente: se verifica acá
	-- que la presión empezó cerca del nodo, hace lo justo (ni muy poco ni hace siglos).
	local ahora = os.clock()
	if def.Duracion > 0 then
		if not inicio then
			warn(`[Guerra] {player.Name}: recolección sin inicio de presión registrado`)
			avisar(player, "Mantené presionado hasta que se complete el círculo.")
			return
		end
		local transcurrido = ahora - inicio
		if transcurrido < def.Duracion * 0.8 or transcurrido > def.Duracion + 1.5 then
			warn(
				`[Guerra] {player.Name}: presión de {string.format("%.2f", transcurrido)} s (se esperaban {def.Duracion})`
			)
			avisar(player, "Mantené presionado hasta que se complete el círculo.")
			return
		end
	end
	if ahora - (ultimaRecoleccion[player] or 0) < 0.5 then
		return
	end
	ultimaRecoleccion[player] = ahora

	local carga = cargaDe(player)
	local espacio = GuerraConfig.CapacidadCarga - totalCarga(carga)
	if espacio <= 0 then
		avisar(player, "Llevás la carga completa. Andá a depositar.")
		return
	end
	local obtenido = math.min(def.Cantidad, espacio)
	carga[recurso] = (carga[recurso] or 0) + obtenido
	agotarNodo(nodo, def.Respawn)
	enviarCarga(player)
end

------------------------------------------------------------------------
-- Construcción
------------------------------------------------------------------------

local function darRecompensas(idGanador: string?)
	if enStudio() and not GuerraConfig.DarRecompensasEnStudio then
		avisarTodos("[Studio] Recompensas desactivadas (GuerraConfig.DarRecompensasEnStudio).")
		return
	end
	local rec = GuerraConfig.Recompensas
	for _, estado in equipos do
		local gano = estado.Def.Id == idGanador
		local premio = if gano then rec.Ganador else rec.Perdedor
		for _, player in estado.Team:GetPlayers() do
			local aporte = estado.AportesTotal[player.UserId] or 0
			if aporte < rec.AporteMinimo then
				avisar(player, "No aportaste recursos suficientes para recibir recompensa.")
				continue
			end
			local partes: { string } = {}
			if DataManager.AddGold(player, premio.Oro) then
				table.insert(partes, `+{premio.Oro} de oro`)
			end
			if DataManager.AddHonor(player, premio.Honor) then
				table.insert(partes, `+{premio.Honor} de honor`)
			end
			if #partes > 0 then
				avisar(player, table.concat(partes, " y "))
			end
			local titulo = (premio :: any).Titulo
			if typeof(titulo) == "string" and DataManager.AddTitulo(player, titulo) then
				avisar(player, `¡Nuevo título: {titulo}!`)
			end
		end
	end
end

local function terminarPartida(idGanador: string?, cancelada: boolean)
	if fase == "Terminada" then
		return
	end
	fase = "Terminada"
	if cancelada then
		ganador = "Cancelada"
		avisarTodos("Partida cancelada: un equipo se quedó sin jugadores. No hay recompensas.")
	else
		ganador = idGanador or "Empate"
		darRecompensas(idGanador)
		if idGanador then
			avisarTodos(`¡{equipos[idGanador].Def.Nombre} colocó el Estandarte y gana la Guerra de Arquitectos!`)
		else
			avisarTodos("¡Tiempo! La guerra terminó en empate.")
		end
	end
	difundir()
end

-- Saca a los jugadores que están dentro de las piezas antes de volverlas sólidas.
local function despejarEtapa(estado: EstadoEquipo, etapa: number)
	for _, modelo in ArenaGuerra.PersonajesDentro(estado.Base, etapa) do
		local player = Players:GetPlayerFromCharacter(modelo)
		if player then
			AntiCheat.Gracia(player, 2)
			modelo:PivotTo(estado.Base.Spawn.CFrame + Vector3.new(0, 4, 0))
		end
	end
end

local function completarEtapa(estado: EstadoEquipo)
	local etapa = estado.Etapa
	local def = GuerraConfig.Etapas[etapa]

	-- Skin de quien más aportó a esta etapa (y sigue en la partida).
	local mejor: Player? = nil
	local mejorAporte = 0
	for userId, aporte in estado.AportesEtapa do
		local player = Players:GetPlayerByUserId(userId)
		if player and player.Team == estado.Team and aporte > mejorAporte then
			mejor, mejorAporte = player, aporte
		end
	end
	local skin = "Ninguna"
	if mejor then
		local datos = DataManager.GetData(mejor)
		if datos then
			skin = datos.SkinEstructuraEquipada
		end
	end

	despejarEtapa(estado, etapa)
	ArenaGuerra.Construir(estado.Base, etapa, skin, estado.Def.Color.Color)
	local textoSkin = if skin ~= "Ninguna" and mejor then ` (estilo {skin} de {mejor.DisplayName})` else ""
	avisarTodos(`{estado.Def.Nombre} completó: {def.Nombre}{textoSkin}`)

	estado.Depositado = {}
	estado.AportesEtapa = {}
	if etapa >= TOTAL_ETAPAS then
		estado.Etapa = TOTAL_ETAPAS + 1
		terminarPartida(estado.Def.Id, false)
		return
	end
	estado.Etapa = etapa + 1
	ArenaGuerra.MostrarPlano(estado.Base, estado.Etapa)
end

-- Pasa del almacén a la etapa actual lo que necesite. Devuelve true si la completó.
local function aplicarAlmacen(estado: EstadoEquipo): boolean
	if estado.Etapa > TOTAL_ETAPAS then
		return false
	end
	local req = requisitos(estado.Etapa)
	local completa = true
	for recurso, necesario in req do
		local falta = necesario - (estado.Depositado[recurso] or 0)
		local usar = math.min(falta, estado.Almacen[recurso] or 0)
		if usar > 0 then
			estado.Depositado[recurso] = (estado.Depositado[recurso] or 0) + usar
			estado.Almacen[recurso] -= usar
		end
		if (estado.Depositado[recurso] or 0) < necesario then
			completa = false
		end
	end
	return completa
end

local function alDepositar(player: Player, estado: EstadoEquipo)
	if fase ~= "EnCurso" then
		avisar(player, "La partida todavía no empezó: esperá la cuenta regresiva.")
		return
	end
	if player.Team ~= estado.Team then
		avisar(player, "Ese no es el depósito de tu equipo.")
		return
	end
	if not cerca(player, estado.Base.Deposito) then
		avisar(player, "Acercate más al depósito.")
		return
	end

	local carga = cargaDe(player)
	local entregado = 0
	for _, recurso in RECURSOS do
		local n = carga[recurso] or 0
		if n > 0 then
			estado.Almacen[recurso] = (estado.Almacen[recurso] or 0) + n
			carga[recurso] = 0
			entregado += n
		end
	end
	if entregado == 0 then
		avisar(player, "No llevás recursos. Recolectá en el centro del mapa.")
		return
	end
	-- Un Violeta que aporta a un reino pasa a ese bando.
	if BandoManager.De(player) == "Violeta" then
		BandoManager.Unirse(player, estado.Def.Id :: any)
	end
	local uid = player.UserId
	estado.AportesEtapa[uid] = (estado.AportesEtapa[uid] or 0) + entregado
	estado.AportesTotal[uid] = (estado.AportesTotal[uid] or 0) + entregado
	enviarCarga(player)

	-- El almacén puede completar varias etapas seguidas.
	while fase == "EnCurso" and aplicarAlmacen(estado) do
		completarEtapa(estado)
	end
	difundir()
end

------------------------------------------------------------------------
-- Ciclo de partida
------------------------------------------------------------------------

local function reiniciar()
	for _, estado in equipos do
		estado.Etapa = 1
		estado.Depositado = {}
		estado.Almacen = {}
		estado.AportesEtapa = {}
		estado.AportesTotal = {}
		ArenaGuerra.MostrarPlano(estado.Base, 1)
	end
	for nodo in table.clone(nodosAgotados) do
		restaurarNodo(nodo)
	end
	table.clear(cargas)
	for _, player in Players:GetPlayers() do
		enviarCarga(player)
	end
	ganador = nil
end

local function iniciarPartida()
	reiniciar()
	rebalancear()
	fase = "EnCurso"
	finPartida = os.clock() + GuerraConfig.DuracionMaxima
	for _, player in Players:GetPlayers() do
		task.spawn(player.LoadCharacterAsync, player) -- aparecen en la base de su equipo
	end
	avisarTodos("¡Empieza la Guerra de Arquitectos! Recolectá recursos y construí tu castillo.")
end

local function minimoJugadores(): number
	return if modoPrueba() then GuerraConfig.JugadoresMinimosEnStudio else GuerraConfig.JugadoresMinimos
end

local function algunEquipoVacio(): boolean
	for _, estado in equipos do
		if #estado.Team:GetPlayers() == 0 then
			return true
		end
	end
	return false
end

local function resolverPorTiempo()
	-- Gana el que más avanzó; empate si están iguales.
	local mejorId: string? = nil
	local mejor, segundo = -1, -1
	for id, estado in equipos do
		local p = puntaje(estado)
		if p > mejor then
			segundo, mejor, mejorId = mejor, p, id
		elseif p > segundo then
			segundo = p
		end
	end
	terminarPartida(if mejor > segundo then mejorId else nil, false)
end

local function tick(): nil
	local ahora = os.clock()
	local cantidad = #Players:GetPlayers()
	if fase == "Esperando" then
		if cantidad >= minimoJugadores() then
			fase = "Cuenta"
			finCuenta = ahora + GuerraConfig.CuentaRegresiva
		end
	elseif fase == "Cuenta" then
		if cantidad < minimoJugadores() then
			fase = "Esperando"
		elseif ahora >= finCuenta then
			iniciarPartida()
		end
	elseif fase == "EnCurso" then
		if cantidad == 0 then
			reiniciar()
			fase = "Esperando"
		elseif not modoPrueba() and algunEquipoVacio() then
			-- Evita ganar solo (por ejemplo, con una cuenta alternativa que se va).
			terminarPartida(nil, true)
		elseif ahora >= finPartida then
			resolverPorTiempo()
		end
	end
	-- Marca quién está jugando la partida: ahí vale el PvP entre bandos.
	for _, player in Players:GetPlayers() do
		local jugando = fase == "EnCurso" and equipoDe(player) ~= nil
		if player:GetAttribute("EnGuerra") ~= jugando then
			player:SetAttribute("EnGuerra", jugando)
		end
	end
	difundir()
	return nil
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

-- ¿Este servidor tiene que correr la Guerra?
function ArchitectWarManager.DebeActivarse(): boolean
	local zona = ZoneConfig.Zonas.GuerraArquitectos
	if zona and zona.PlaceId ~= 0 and game.PlaceId == zona.PlaceId then
		return true
	end
	if workspace:FindFirstChild(GuerraConfig.NombreCarpetaMapa) then
		return true
	end
	return modoPrueba() and GuerraConfig.ProbarEnStudio
end

local function conectarPrompts(m: ArenaGuerra.Mapa)
	for _, nodo in m.Nodos do
		local pp = nodo:FindFirstChildOfClass("ProximityPrompt")
		if not pp then
			continue
		end
		pp.PromptButtonHoldBegan:Connect(function(player: Player)
			-- Solo cuenta una presión que empieza cerca, durante la partida y con el nodo disponible.
			if not puedeInteractuar(player, nodo) then
				return
			end
			local presiones = inicioPresion[player]
			if not presiones then
				presiones = {}
				inicioPresion[player] = presiones
			end
			presiones[pp] = os.clock()
		end)
		pp.PromptButtonHoldEnded:Connect(function(player: Player)
			local presiones = inicioPresion[player]
			local visto = presiones and presiones[pp]
			if presiones and visto then
				-- Con latencia real, Triggered puede llegar un rato después que
				-- HoldEnded: se limpia con margen amplio, y solo si nadie empezó una
				-- presión nueva mientras tanto.
				task.delay(1, function()
					if presiones[pp] == visto then
						presiones[pp] = nil
					end
				end)
			end
		end)
		pp.Triggered:Connect(function(player: Player)
			alRecolectar(player, nodo, pp)
		end)
	end
	for _, estado in equipos do
		local pp = estado.Base.Deposito:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp.Triggered:Connect(function(player: Player)
				alDepositar(player, estado)
			end)
		end
	end
end

function ArchitectWarManager.Init()
	assert(not iniciado, "ArchitectWarManager.Init() se llamó dos veces")
	iniciado = true

	local m = ArenaGuerra.Obtener(modoPrueba() and GuerraConfig.ProbarEnStudio)
	if not m then
		warn("[Guerra] No se encontró un mapa válido; la Guerra de Arquitectos queda desactivada.")
		return
	end

	for _, def in GuerraConfig.Equipos do
		local team = Instance.new("Team")
		team.Name = def.Nombre
		team.TeamColor = def.Color
		team.AutoAssignable = false
		team.Parent = Teams
		equipos[def.Id] = {
			Def = def,
			Team = team,
			Base = m.Bases[def.Id],
			Etapa = 1,
			Depositado = {},
			Almacen = {},
			AportesEtapa = {},
			AportesTotal = {},
		}
		table.insert(ordenEquipos, def.Id)
	end

	conectarPrompts(m)
	reiniciar()

	local function alEntrar(player: Player)
		asignarEquipo(player)
		enviarCarga(player)
		if player.Character then
			task.spawn(player.LoadCharacterAsync, player)
		end
	end
	for _, player in Players:GetPlayers() do
		alEntrar(player)
	end
	Players.PlayerAdded:Connect(alEntrar)
	-- Si alguien cambia de bando (atacando o aportando), pasa al equipo de su reino.
	DataManager.DatosCambiados:Connect(function(player: Player, seccion: Types.SeccionDatos)
		if seccion ~= "Faccion" then
			return
		end
		local porBando = equipoDeBando(player)
		if porBando and player.Team ~= porBando.Team then
			ponerEnEquipo(player, porBando)
		end
	end)
	-- El bando se conoce recién cuando carga el perfil: se reasigna entonces.
	DataManager.PerfilCargado:Connect(function(player: Player)
		local porBando = equipoDeBando(player)
		if porBando and player.Team ~= porBando.Team then
			ponerEnEquipo(player, porBando)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		cargas[player] = nil
		inicioPresion[player] = nil
		ultimaRecoleccion[player] = nil
		-- Aportes y equipo se guardan por UserId hasta el fin de la partida.
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn(`[Guerra] Error en el ciclo: {err}`)
			end
			if fase == "Terminada" then
				task.wait(GuerraConfig.PausaEntrePartidas)
				reiniciar()
				table.clear(equipoPorUsuario)
				fase = "Esperando"
			else
				task.wait(1)
			end
		end
	end)

	print("[Guerra] Guerra de Arquitectos activa")
end

return ArchitectWarManager
