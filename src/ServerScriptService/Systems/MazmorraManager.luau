--!strict
-- MazmorraManager: mazmorras instanciadas para grupos.
--
-- Entrada: el portal de la mazmorra. Solo el líder del grupo (o alguien solo)
-- la abre, y entran juntos los del grupo que estén cerca del portal.
--
--   * Modo local (PlaceId = 0 en MazmorrasConfig, o en Studio): la instancia
--     se arma en un área aparte de este servidor y se lleva ahí a los
--     personajes. Sirve para probar sin places extra.
--   * Modo reservado (PlaceId real): el servidor reserva un servidor privado
--     (ReserveServer), anota en MemoryStore quiénes van y teletransporta al
--     grupo junto. El servidor de la mazmorra lee esa nota (no el TeleportData,
--     que lo puede tocar el cliente), expulsa a quien no esté anotado y al
--     terminar devuelve a todos al place de origen. El servidor reservado se
--     cierra solo cuando queda vacío.
--
-- Dentro: salas con enemigos (las puertas se abren al limpiarlas) y un jefe
-- con mecánicas: golpe alrededor suyo y derrumbe sobre un jugador (ambos con
-- zona roja de aviso) e invocaciones al bajar de cierta vida.
-- Se gana matando al jefe. Se pierde si el grupo muere entero más veces que
-- los intentos o si se acaba el tiempo.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local MazmorrasConfig = require(ReplicatedStorage.Configs.MazmorrasConfig)
local EnemigosConfig = require(ReplicatedStorage.Configs.EnemigosConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local DataManager = require(script.Parent.DataManager)
local AntiCheat = require(script.Parent.AntiCheat)
local GrupoManager = require(script.Parent.GrupoManager)
local CombatManager = require(script.Parent.Combate.CombatManager)
local EnemyManager = require(script.Parent.Combate.EnemyManager)

type Npc = EnemyManager.Npc
type Mazmorra = MazmorrasConfig.Mazmorra
type Estado = "Esperando" | "Jugando" | "Victoria" | "Derrota"

type Instancia = {
	Id: number,
	Lugar: number, -- posición en el modo local
	LiderId: number,
	Clave: string,
	Def: Mazmorra,
	Local: boolean,
	Origen: Vector3,
	Carpeta: Folder,
	Puertas: { BasePart },
	Jugadores: { [Player]: boolean },
	Esperados: { [number]: boolean },
	Retornos: { [Player]: CFrame },
	RetornoPlace: number,
	Sala: number, -- #Salas + 1 = sala del jefe
	Vivos: { [Npc]: boolean },
	Jefe: Npc?,
	Estado: Estado,
	Inicio: number,
	Fin: number?,
	Intentos: number,
	Caido: boolean, -- el grupo está muerto entero (se descuenta un intento una sola vez)
	Invocado: { [string]: boolean },
	ProximaMecanica: { [number]: number },
}

local CFG = MazmorrasConfig
local LARGO_SALA = 55

local MazmorraManager = {}

local instancias: { [number]: Instancia } = {}
local instanciaDe: { [Player]: Instancia } = {}
local ultimoIntento: { [Player]: number } = {}
local contador = 0
local portal: BasePart? = nil
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function avisarTodos(inst: Instancia, texto: string, tipo: string?)
	for player in inst.Jugadores do
		avisar(player, texto, tipo)
	end
end

local function raizDe(player: Player): BasePart?
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

local function vivo(player: Player): boolean
	local personaje = player.Character
	local h = personaje and personaje:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

local function contar(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

------------------------------------------------------------------------
-- Mapa de la instancia
------------------------------------------------------------------------

local function bloque(
	padre: Instance,
	nombre: string,
	tam: Vector3,
	pos: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = nombre
	p.Anchored = true
	p.Size = tam
	p.CFrame = CFrame.new(pos)
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = padre
	return p
end

-- Centro de cada sala (1..#Salas) y de la sala del jefe (#Salas + 1).
local function centroSala(inst: Instancia, i: number): Vector3
	return inst.Origen + Vector3.new(0, 0, 25 + (i - 1) * LARGO_SALA + (if i > #inst.Def.Salas then 20 else 0))
end

-- Donde reaparece el grupo: la entrada de la sala en curso.
local function puntoDeControl(inst: Instancia): Vector3
	local c = centroSala(inst, inst.Sala)
	return c + Vector3.new(0, 4, -LARGO_SALA / 2 + 6)
end

local function construir(inst: Instancia)
	local piedra = Color3.fromRGB(85, 90, 95)
	local salas = #inst.Def.Salas
	local largo = 20 + salas * LARGO_SALA
	-- Pasillo con las salas comunes y la entrada.
	bloque(
		inst.Carpeta,
		"Piso",
		Vector3.new(40, 2, largo),
		inst.Origen + Vector3.new(0, -1, largo / 2 - 10),
		piedra,
		Enum.Material.Slate
	)
	for _, lado in { -1, 1 } do
		bloque(
			inst.Carpeta,
			"Pared",
			Vector3.new(2, 16, largo),
			inst.Origen + Vector3.new(lado * 21, 7, largo / 2 - 10),
			piedra,
			Enum.Material.Cobblestone
		)
	end
	bloque(
		inst.Carpeta,
		"Fondo",
		Vector3.new(40, 16, 2),
		inst.Origen + Vector3.new(0, 7, -11),
		piedra,
		Enum.Material.Cobblestone
	)
	-- Sala del jefe: más grande.
	local jefe = centroSala(inst, salas + 1)
	bloque(inst.Carpeta, "PisoJefe", Vector3.new(80, 2, 80), jefe + Vector3.new(0, -1, 0), piedra, Enum.Material.Basalt)
	for _, d in { Vector3.new(41, 9, 0), Vector3.new(-41, 9, 0), Vector3.new(0, 9, 41) } do
		bloque(
			inst.Carpeta,
			"ParedJefe",
			if d.X ~= 0 then Vector3.new(2, 20, 84) else Vector3.new(84, 20, 2),
			jefe + d,
			piedra,
			Enum.Material.Basalt
		)
	end
	-- Frente de la sala del jefe, a los costados del pasillo (para no caerse).
	for _, lado in { -1, 1 } do
		bloque(
			inst.Carpeta,
			"FrenteJefe",
			Vector3.new(21, 20, 2),
			jefe + Vector3.new(lado * 30.5, 9, -41),
			piedra,
			Enum.Material.Basalt
		)
	end
	-- Puertas: una al final de cada sala común.
	for i = 1, salas do
		local z = centroSala(inst, i).Z + LARGO_SALA / 2 - 1
		local puerta = bloque(
			inst.Carpeta,
			`Puerta{i}`,
			Vector3.new(38, 14, 1.5),
			Vector3.new(inst.Origen.X, inst.Origen.Y + 7, z),
			Color3.fromRGB(255, 120, 60),
			Enum.Material.ForceField
		)
		puerta.Transparency = 0.2
		inst.Puertas[i] = puerta
	end
	-- Antorchas para que no se vea vacío.
	for i = 1, salas + 1 do
		local c = centroSala(inst, i)
		local luz = Instance.new("PointLight")
		luz.Range = 40
		luz.Brightness = 1.4
		luz.Color = Color3.fromRGB(255, 190, 120)
		local soporte = bloque(
			inst.Carpeta,
			"Antorcha",
			Vector3.new(1, 1, 1),
			c + Vector3.new(0, 12, 0),
			Color3.fromRGB(255, 170, 80),
			Enum.Material.Neon
		)
		soporte.CanCollide = false
		luz.Parent = soporte
	end
end

------------------------------------------------------------------------
-- Estado para los clientes
------------------------------------------------------------------------

local function enviarEstado(inst: Instancia)
	local restantes = 0
	for npc in inst.Vivos do
		if not npc.Muerto then
			restantes += 1
		end
	end
	local jefe = inst.Jefe
	local vidaJefe: number? = nil
	if jefe and not jefe.Muerto then
		local h = jefe.Combatiente.Humanoid
		vidaJefe = if h.MaxHealth > 0 then h.Health / h.MaxHealth else 0
	end
	local salas = #inst.Def.Salas
	local estado = {
		Nombre = inst.Def.Nombre,
		Sala = inst.Sala,
		TotalSalas = salas + 1,
		NombreSala = if inst.Sala <= salas then inst.Def.Salas[inst.Sala].Nombre else inst.Def.Jefe.Nombre,
		Restantes = restantes,
		Tiempo = math.max(0, inst.Def.TiempoLimite - (os.clock() - inst.Inicio)),
		Intentos = inst.Intentos,
		Estado = inst.Estado,
		VidaJefe = vidaJefe,
		Salida = if inst.Fin then math.max(0, inst.Fin - os.clock()) else nil,
	}
	for player in inst.Jugadores do
		NetworkBridge.Server.FireClient("MazmorraEstado", player, estado)
	end
end

------------------------------------------------------------------------
-- Enemigos
------------------------------------------------------------------------

-- Solo cobran los del grupo: alguien de afuera que pegue no recibe nada.
local function soloMiembros(inst: Instancia, npc: Npc)
	for userId in npc.Aportes do
		local p = Players:GetPlayerByUserId(userId)
		if not p or not inst.Jugadores[p] then
			npc.Aportes[userId] = nil
		end
	end
end

local revisarSala: (Instancia) -> ()
local victoria: (Instancia) -> ()

local function crearEnemigo(inst: Instancia, id: string, posicion: Vector3): Npc?
	local def = EnemigosConfig.Enemigos[id]
	if not def then
		warn(`[Mazmorra] Enemigo desconocido: {id}`)
		return nil
	end
	local npc = EnemyManager.Crear({
		Nombre = def.Nombre,
		Nivel = def.Nivel,
		Vida = def.Vida,
		Danio = def.Danio,
		Defensa = def.Defensa,
		RangoAtaque = def.RangoAtaque,
		CadenciaAtaque = def.CadenciaAtaque,
		Velocidad = def.Velocidad,
		RadioAgro = math.max(def.RadioAgro, 35),
		RadioCorrea = 70,
		Escala = def.Escala,
		Color = def.Color,
		Pasivo = def.Pasivo,
		Posicion = posicion,
	})
	if not npc then
		return nil
	end
	inst.Vivos[npc] = true
	npc.AlMorir = function(n: Npc)
		soloMiembros(inst, n)
		EnemyManager.Recompensar(n, def.Xp, def.Oro, def.Botin, def.Nombre, id)
		inst.Vivos[n] = nil
		revisarSala(inst)
	end
	return npc
end

local function quitarEnemigos(inst: Instancia)
	local lista: { Npc } = {}
	for npc in inst.Vivos do
		table.insert(lista, npc)
	end
	local jefe = inst.Jefe
	if jefe then
		table.insert(lista, jefe)
	end
	table.clear(inst.Vivos)
	inst.Jefe = nil
	for _, npc in lista do
		npc.AlMorir = nil -- sin recompensa
		if not npc.Muerto then
			npc.Combatiente.Humanoid.Health = 0
		end
	end
end

local function iniciarJefe(inst: Instancia)
	local d = inst.Def.Jefe
	local n = math.max(1, contar(inst.Jugadores))
	local npc = EnemyManager.Crear({
		Nombre = d.Nombre,
		Nivel = d.Nivel,
		Vida = math.floor(d.Vida * (0.7 + 0.3 * n)),
		Danio = d.Danio,
		Defensa = d.Defensa,
		RangoAtaque = d.RangoAtaque,
		CadenciaAtaque = d.CadenciaAtaque,
		Velocidad = d.Velocidad,
		RadioAgro = 45,
		RadioCorrea = 60,
		Escala = d.Escala,
		Color = d.Color,
		Posicion = centroSala(inst, inst.Sala) + Vector3.new(0, 0, 15),
	})
	if not npc then
		return
	end
	inst.Jefe = npc
	local ahora = os.clock()
	for i, m in d.Mecanicas do
		if m.Cada then
			inst.ProximaMecanica[i] = ahora + m.Cada * 0.6
		end
	end
	npc.AlMorir = function(n2: Npc)
		soloMiembros(inst, n2)
		EnemyManager.Recompensar(n2, d.Xp, d.Oro, d.Botin, d.Nombre, inst.Clave)
		victoria(inst)
	end
	avisarTodos(inst, `¡{d.Nombre} despertó!`, "Error")
end

local function iniciarSala(inst: Instancia)
	local salas = #inst.Def.Salas
	if inst.Sala > salas then
		iniciarJefe(inst)
		return
	end
	local sala = inst.Def.Salas[inst.Sala]
	local centro = centroSala(inst, inst.Sala) + Vector3.new(0, 0, 8)
	local total = 0
	for _, g in sala.Enemigos do
		total += g.Cantidad
	end
	local k = 0
	for _, g in sala.Enemigos do
		for _ = 1, g.Cantidad do
			k += 1
			local angulo = k / total * math.pi * 2
			crearEnemigo(inst, g.Enemigo, centro + Vector3.new(math.cos(angulo) * 9, 0, math.sin(angulo) * 9))
		end
	end
	avisarTodos(inst, `{sala.Nombre}: derrotá a todos para abrir la puerta.`)
end

revisarSala = function(inst: Instancia)
	if inst.Estado ~= "Jugando" or inst.Jefe ~= nil or next(inst.Vivos) ~= nil then
		return
	end
	local puerta = inst.Puertas[inst.Sala]
	if puerta then
		puerta:Destroy()
	end
	inst.Sala += 1
	avisarTodos(
		inst,
		if inst.Sala > #inst.Def.Salas
			then "La puerta se abre... algo se mueve al fondo."
			else "¡Sala despejada! La puerta se abrió.",
		"Oro"
	)
	task.delay(2, function()
		if inst.Estado == "Jugando" then
			iniciarSala(inst)
		end
	end)
end

------------------------------------------------------------------------
-- Mecánicas del jefe
------------------------------------------------------------------------

local paramsSuelo = RaycastParams.new()
paramsSuelo.FilterType = Enum.RaycastFilterType.Include

local function zonaRoja(inst: Instancia, centro: Vector3, radio: number): Part
	paramsSuelo.FilterDescendantsInstances = { inst.Carpeta }
	local r = Workspace:Raycast(centro + Vector3.new(0, 5, 0), Vector3.new(0, -30, 0), paramsSuelo)
	local y = if r then r.Position.Y else centro.Y - 3
	local zona = Instance.new("Part")
	zona.Name = "AvisoMazmorra"
	zona.Shape = Enum.PartType.Cylinder
	zona.Anchored = true
	zona.CanCollide = false
	zona.CanQuery = false
	zona.CanTouch = false
	zona.Material = Enum.Material.Neon
	zona.Color = Color3.fromRGB(255, 40, 30)
	zona.Transparency = 0.45
	zona.Size = Vector3.new(0.3, radio * 2, radio * 2)
	zona.CFrame = CFrame.new(centro.X, y + 0.2, centro.Z) * CFrame.Angles(0, 0, math.rad(90))
	zona.Parent = inst.Carpeta
	return zona
end

local function golpeEnArea(inst: Instancia, jefe: Npc, centro: Vector3, m: MazmorrasConfig.Mecanica)
	local radio = m.Radio or 10
	local zona = zonaRoja(inst, centro, radio)
	CombatManager.Anunciar(jefe.Combatiente, m.Nombre)
	task.delay(m.Aviso or 1.5, function()
		zona:Destroy()
		if jefe.Muerto or inst.Estado ~= "Jugando" then
			return
		end
		for player in inst.Jugadores do
			local c = CombatManager.DeJugador(player)
			if c and CombatManager.EstaVivo(c) then
				local d = c.Raiz.Position - centro
				if Vector3.new(d.X, 0, d.Z).Magnitude <= radio then
					CombatManager.DanioArea(jefe.Combatiente, c, m.Multiplicador or 1.5)
				end
			end
		end
	end)
end

local function tickJefe(inst: Instancia)
	local jefe = inst.Jefe
	if not jefe or jefe.Muerto then
		return
	end
	local c = jefe.Combatiente
	local h = c.Humanoid
	local fraccion = if h.MaxHealth > 0 then h.Health / h.MaxHealth else 1
	local enPelea = workspace:GetServerTimeNow() - c.UltimoCombate < 8
	local ahora = os.clock()
	for i, m in inst.Def.Jefe.Mecanicas do
		if m.Tipo == "Invocar" then
			local umbrales: { number } = m.AlPorcentaje or {}
			for _, umbral in umbrales do
				local clave = `{i}:{umbral}`
				if fraccion <= umbral and not inst.Invocado[clave] then
					inst.Invocado[clave] = true
					CombatManager.Anunciar(c, m.Nombre)
					for k = 1, m.Cantidad or 1 do
						local angulo = k / (m.Cantidad or 1) * math.pi * 2
						crearEnemigo(
							inst,
							m.Enemigo or "Lobo",
							c.Raiz.Position + Vector3.new(math.cos(angulo) * 8, 0, math.sin(angulo) * 8)
						)
					end
				end
			end
		elseif enPelea and m.Cada and ahora >= (inst.ProximaMecanica[i] or 0) then
			inst.ProximaMecanica[i] = ahora + m.Cada
			if m.Tipo == "Pisoton" then
				golpeEnArea(inst, jefe, c.Raiz.Position, m)
			else
				local candidatos: { BasePart } = {}
				for player in inst.Jugadores do
					local raiz = raizDe(player)
					if raiz and vivo(player) then
						table.insert(candidatos, raiz)
					end
				end
				if #candidatos > 0 then
					golpeEnArea(inst, jefe, candidatos[math.random(1, #candidatos)].Position, m)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Entrar, salir, terminar
------------------------------------------------------------------------

local function ubicar(inst: Instancia, player: Player)
	local personaje = player.Character
	if not personaje then
		return
	end
	AntiCheat.Gracia(player, 3)
	personaje:PivotTo(CFrame.new(puntoDeControl(inst)))
end

local function limpiar(inst: Instancia)
	quitarEnemigos(inst)
	inst.Carpeta:Destroy()
	instancias[inst.Id] = nil
end

local function sacar(inst: Instancia, player: Player, devolver: boolean)
	if not inst.Jugadores[player] then
		return
	end
	inst.Jugadores[player] = nil
	instanciaDe[player] = nil
	NetworkBridge.Server.FireClient("MazmorraEstado", player, nil)
	if devolver and player.Parent == Players then
		if inst.Local then
			local personaje = player.Character
			local retorno = inst.Retornos[player]
				or (if portal then portal.CFrame + Vector3.new(0, 4, 6) else CFrame.new(0, 10, 0))
			if personaje then
				AntiCheat.Gracia(player, 3)
				personaje:PivotTo(retorno)
			end
		elseif inst.RetornoPlace ~= 0 then
			task.spawn(function()
				for intento = 1, 3 do
					local ok = pcall(function()
						TeleportService:TeleportAsync(inst.RetornoPlace, { player })
					end)
					if ok then
						return
					end
					task.wait(2 * intento)
				end
				if player.Parent == Players then
					player:Kick("No se pudo volver a la ciudad. ¡Volvé a entrar al juego!")
				end
			end)
		else
			player:Kick("La mazmorra terminó. ¡Volvé a entrar al juego!")
		end
	end
	inst.Retornos[player] = nil
	if next(inst.Jugadores) == nil and inst.Local then
		limpiar(inst)
	end
end

local function terminar(inst: Instancia, estado: Estado, segundos: number)
	if inst.Estado == "Victoria" or inst.Estado == "Derrota" then
		return
	end
	inst.Estado = estado
	inst.Fin = os.clock() + segundos
	task.delay(segundos, function()
		local lista: { Player } = {}
		for player in inst.Jugadores do
			table.insert(lista, player)
		end
		for _, player in lista do
			sacar(inst, player, true)
		end
		if inst.Local and instancias[inst.Id] then
			limpiar(inst)
		end
	end)
end

victoria = function(inst: Instancia)
	if inst.Estado ~= "Jugando" then
		return
	end
	inst.Jefe = nil
	quitarEnemigos(inst) -- invocaciones que hayan quedado
	local r = inst.Def.Recompensa
	for player in inst.Jugadores do
		DataManager.AddGold(player, r.Oro)
		DataManager.AddExperience(player, r.Xp)
		avisar(player, `¡Completaste {inst.Def.Nombre}! +{r.Oro} de oro y +{r.Xp} de experiencia.`, "Oro")
	end
	-- Portal de salida para irse antes.
	local salida = bloque(
		inst.Carpeta,
		"PortalSalida",
		Vector3.new(6, 9, 1),
		centroSala(inst, inst.Sala) + Vector3.new(0, 4.5, -25),
		Color3.fromRGB(90, 200, 255),
		Enum.Material.Neon
	)
	salida.Transparency = 0.3
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Salir de la mazmorra"
	prompt.ObjectText = "Portal"
	prompt.MaxActivationDistance = 10
	prompt.Parent = salida
	prompt.Triggered:Connect(function(player: Player)
		if instanciaDe[player] == inst then
			sacar(inst, player, true)
		end
	end)
	terminar(inst, "Victoria", CFG.SegundosParaSalirTrasGanar)
end

local function derrota(inst: Instancia, motivo: string)
	if inst.Estado ~= "Jugando" then
		return
	end
	quitarEnemigos(inst)
	avisarTodos(inst, motivo, "Error")
	terminar(inst, "Derrota", CFG.SegundosParaSalirTrasPerder)
end

local function revisarCaida(inst: Instancia)
	if inst.Estado ~= "Jugando" or next(inst.Jugadores) == nil then
		return
	end
	local alguienVivo = false
	for player in inst.Jugadores do
		if vivo(player) then
			alguienVivo = true
			break
		end
	end
	if alguienVivo then
		inst.Caido = false
		return
	end
	if inst.Caido then
		return
	end
	inst.Caido = true
	inst.Intentos -= 1
	if inst.Intentos <= 0 then
		derrota(inst, "El grupo cayó y no quedan intentos. La mazmorra los expulsa.")
		return
	end
	-- Los enemigos de la sala se recuperan; el grupo reaparece en la entrada de la sala.
	for npc in inst.Vivos do
		if not npc.Muerto then
			CombatManager.Restaurar(npc.Combatiente)
		end
	end
	local jefe = inst.Jefe
	if jefe and not jefe.Muerto then
		CombatManager.Restaurar(jefe.Combatiente) -- las invocaciones no se repiten (no se farmean)
	end
	avisarTodos(inst, `El grupo cayó. Intentos restantes: {inst.Intentos}.`, "Error")
end

local function nuevaInstancia(clave: string, def: Mazmorra, esLocal: boolean, retornoPlace: number): Instancia
	contador += 1
	-- Se reusa el primer lugar libre (así no se alejan cada vez más del origen).
	local lugar = 1
	local ocupados: { [number]: boolean } = {}
	for _, otra in instancias do
		ocupados[otra.Lugar] = true
	end
	while ocupados[lugar] do
		lugar += 1
	end
	local origen = if esLocal then CFG.OrigenLocal + Vector3.new(lugar * CFG.SeparacionLocal, 0, 0) else CFG.OrigenLocal
	local carpeta = Instance.new("Folder")
	carpeta.Name = `Mazmorra_{contador}`
	carpeta.Parent = Workspace
	local inst: Instancia = {
		Id = contador,
		Lugar = lugar,
		LiderId = 0,
		Clave = clave,
		Def = def,
		Local = esLocal,
		Origen = origen,
		Carpeta = carpeta,
		Puertas = {},
		Jugadores = {},
		Esperados = {},
		Retornos = {},
		RetornoPlace = retornoPlace,
		Sala = 1,
		Vivos = {},
		Jefe = nil,
		Estado = "Esperando",
		Inicio = os.clock(),
		Fin = nil,
		Intentos = def.Intentos,
		Caido = false,
		Invocado = {},
		ProximaMecanica = {},
	}
	instancias[inst.Id] = inst
	construir(inst)
	return inst
end

local function empezar(inst: Instancia)
	if inst.Estado ~= "Esperando" then
		return
	end
	inst.Estado = "Jugando"
	inst.Inicio = os.clock()
	local lista: { Player } = {}
	for player in inst.Jugadores do
		table.insert(lista, player)
	end
	if #lista > 1 then
		local lider = Players:GetPlayerByUserId(inst.LiderId)
		GrupoManager.Formar(if lider and inst.Jugadores[lider] then lider else lista[1], lista)
	end
	iniciarSala(inst)
end

------------------------------------------------------------------------
-- Portal de entrada (lado del mundo)
------------------------------------------------------------------------

local function entrar(lider: Player, clave: string)
	local def = MazmorrasConfig.Mazmorras[clave]
	local p = portal
	if not def or not p then
		return
	end
	local ahora = os.clock()
	if ahora - (ultimoIntento[lider] or -math.huge) < 5 then
		return
	end
	ultimoIntento[lider] = ahora
	if instanciaDe[lider] then
		return
	end
	local grupo = GrupoManager.GrupoDe(lider)
	if grupo and grupo.Lider ~= lider then
		avisar(lider, "Solo el líder del grupo puede abrir la mazmorra.", "Error")
		return
	end
	local miembros = GrupoManager.MiembrosDe(lider)
	local faltan: { string } = {}
	for _, m in miembros do
		local raiz = raizDe(m)
		local datos = DataManager.GetData(m)
		if not raiz or not vivo(m) or (raiz.Position - p.Position).Magnitude > CFG.DistanciaGrupo then
			table.insert(faltan, m.DisplayName)
		elseif instanciaDe[m] or m:GetAttribute("EnGuerra") == true then
			avisar(lider, `{m.DisplayName} está ocupado (en otra mazmorra o en la Guerra).`, "Error")
			return
		elseif not Pruebas.Activas() and (not datos or datos.Nivel < def.NivelMinimo) then
			avisar(lider, `{m.DisplayName} necesita nivel {def.NivelMinimo}.`, "Error")
			return
		end
	end
	if #faltan > 0 then
		avisar(lider, `Tienen que estar cerca del portal: {table.concat(faltan, ", ")}.`, "Error")
		return
	end

	local esLocal = def.PlaceId == 0 or RunService:IsStudio()
	if esLocal then
		local inst = nuevaInstancia(clave, def, true, 0)
		inst.LiderId = lider.UserId
		for _, m in miembros do
			inst.Jugadores[m] = true
			instanciaDe[m] = inst
			local raiz = raizDe(m)
			if raiz then
				inst.Retornos[m] = raiz.CFrame
			end
			ubicar(inst, m)
			avisar(m, `Entraste a {def.Nombre}.`, "Oro")
		end
		empezar(inst)
		return
	end

	-- Servidor reservado: se anota quiénes van y se teletransporta al grupo junto.
	local ids: { number } = {}
	for _, m in miembros do
		table.insert(ids, m.UserId)
	end
	local ok, err = pcall(function()
		local codigo, servidorId = TeleportService:ReserveServer(def.PlaceId)
		MemoryStoreService:GetHashMap(CFG.NombreMemoria)
			:SetAsync(
				servidorId,
				{ Mazmorra = clave, Miembros = ids, Lider = lider.UserId, Retorno = game.PlaceId },
				3600
			)
		local opciones: any = Instance.new("TeleportOptions")
		opciones.ReservedServerAccessCode = codigo
		TeleportService:TeleportAsync(def.PlaceId, miembros, opciones)
	end)
	if not ok then
		warn(`[Mazmorra] No se pudo abrir la instancia: {err}`)
		for _, m in miembros do
			avisar(m, "No se pudo abrir la mazmorra. Probá de nuevo en un rato.", "Error")
		end
	end
end

local function crearPortal()
	local p = Instance.new("Part")
	p.Name = "PortalMazmorra"
	p.Anchored = true
	p.Size = Vector3.new(7, 10, 1)
	p.CFrame = CFrame.new(CFG.PosicionPortal + Vector3.new(0, 5, 0))
	p.Color = Color3.fromRGB(150, 90, 255)
	p.Material = Enum.Material.Neon
	p.Transparency = 0.25
	p.CanCollide = false
	local marco = Instance.new("Part")
	marco.Name = "MarcoPortal"
	marco.Anchored = true
	marco.Size = Vector3.new(9, 12, 0.8)
	marco.CFrame = p.CFrame * CFrame.new(0, 0, 0.6)
	marco.Color = Color3.fromRGB(60, 55, 70)
	marco.Material = Enum.Material.Slate
	marco.Parent = p
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Entrar con tu grupo"
	prompt.ObjectText = "Cripta del Guardián"
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	local cartel = Instance.new("BillboardGui")
	cartel.Size = UDim2.fromScale(10, 1.6)
	cartel.StudsOffset = Vector3.new(0, 7.5, 0)
	cartel.MaxDistance = 120
	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.TextColor3 = Color3.fromRGB(220, 190, 255)
	texto.TextStrokeTransparency = 0.3
	texto.Text = "Mazmorra: Cripta del Guardián"
	texto.Parent = cartel
	cartel.Parent = p
	p.Parent = Workspace
	portal = p
	prompt.Triggered:Connect(function(player: Player)
		entrar(player, "CriptaDelGuardian")
	end)
end

------------------------------------------------------------------------
-- Servidor reservado (lado de la mazmorra)
------------------------------------------------------------------------

local function esServidorReservado(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function prepararServidorReservado()
	local nota: any = nil
	for intento = 1, 5 do
		local ok, valor = pcall(function(): any
			return MemoryStoreService:GetHashMap(CFG.NombreMemoria):GetAsync(game.PrivateServerId)
		end)
		if ok and typeof(valor) == "table" then
			nota = valor
			break
		end
		task.wait(intento)
	end
	local clave = nota and nota.Mazmorra
	local def = typeof(clave) == "string" and MazmorrasConfig.Mazmorras[clave] or nil
	if not def or typeof(nota.Miembros) ~= "table" then
		warn("[Mazmorra] Servidor reservado sin nota válida: no hay mazmorra que armar.")
		local function echar(player: Player)
			player:Kick("No se encontró la mazmorra. ¡Volvé a entrar al juego!")
		end
		for _, player in Players:GetPlayers() do
			echar(player)
		end
		Players.PlayerAdded:Connect(echar)
		return
	end
	local inst =
		nuevaInstancia(clave :: string, def, false, if typeof(nota.Retorno) == "number" then nota.Retorno else 0)
	for _, id in nota.Miembros do
		if typeof(id) == "number" then
			inst.Esperados[id] = true
		end
	end
	inst.LiderId = if typeof(nota.Lider) == "number" then nota.Lider else 0
	local function llego(player: Player)
		if not inst.Esperados[player.UserId] then
			player:Kick("Esta mazmorra es de otro grupo.")
			return
		end
		inst.Jugadores[player] = true
		instanciaDe[player] = inst
		if player.Character then
			ubicar(inst, player)
		end
		local todos = true
		for id in inst.Esperados do
			if not Players:GetPlayerByUserId(id) then
				todos = false
			end
		end
		if todos then
			empezar(inst)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(llego, player)
	end
	Players.PlayerAdded:Connect(llego)
	-- Si alguien no llega, se arranca igual a los 30 s.
	task.delay(30, function()
		if next(inst.Jugadores) ~= nil then
			empezar(inst)
		end
	end)
end

------------------------------------------------------------------------
-- API
------------------------------------------------------------------------

function MazmorraManager.EnMazmorra(player: Player): boolean
	return instanciaDe[player] ~= nil
end

function MazmorraManager.Init(zona: string?)
	assert(not iniciado, "MazmorraManager.Init() se llamó dos veces")
	iniciado = true

	NetworkBridge.Server.OnInvoke("MazmorraSalir", function(player: Player): Types.Respuesta
		local inst = instanciaDe[player]
		if not inst then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		sacar(inst, player, true)
		avisar(player, "Saliste de la mazmorra.")
		return NetworkBridge.Ok(nil)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			local inst = instanciaDe[player]
			if inst and inst.Estado ~= "Derrota" then
				task.wait(0.2)
				ubicar(inst, player)
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			local inst = instanciaDe[player]
			if inst and inst.Estado ~= "Derrota" then
				task.wait(0.2)
				ubicar(inst, player)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		ultimoIntento[player] = nil
		local inst = instanciaDe[player]
		if inst then
			sacar(inst, player, false)
		end
	end)

	if esServidorReservado() then
		task.spawn(prepararServidorReservado)
	elseif zona == "Pruebas" or zona == "CiudadPrincipal" then
		crearPortal()
	end

	-- Un solo bucle para todas las instancias.
	local acumulado = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acumulado += dt
		if acumulado < 0.5 then
			return
		end
		acumulado = 0
		for _, inst in instancias do
			if inst.Estado == "Jugando" then
				if os.clock() - inst.Inicio > inst.Def.TiempoLimite then
					derrota(inst, "Se terminó el tiempo. La mazmorra los expulsa.")
				else
					tickJefe(inst)
					revisarCaida(inst)
				end
			end
			enviarEstado(inst)
		end
	end)
end

return MazmorraManager
