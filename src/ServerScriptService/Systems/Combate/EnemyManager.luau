--!strict
-- EnemyManager: NPCs enemigos con IA basada en amenaza.
--
-- * Cada NPC lleva una tabla de amenaza: el daño que recibe suma amenaza a quien
--   lo hizo (x3 si es Tanque) y las curas suman amenaza al sanador.
-- * Ataca a quien más amenaza tiene, salvo que esté provocado.
-- * Pierde de vista a los invisibles.
-- * Si lo alejan demasiado de su spawn, vuelve y se cura (correa).
-- * Al morir reparte XP, oro y botín personal a todos los que aportaron.
--
-- RaidBloxManager usa EnemyManager.Crear para los jefes y agrega sus mecánicas
-- con los callbacks AlTick y AlMorir.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EnemigosConfig = require(ReplicatedStorage.Configs.EnemigosConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Signal = require(ReplicatedStorage.Modules.Signal)
local DataManager = require(script.Parent.Parent.DataManager)
local CombatManager = require(script.Parent.CombatManager)
local Estadisticas = require(script.Parent.Estadisticas)
local LootManager = require(script.Parent.LootManager)

type Combatiente = CombatManager.Combatiente

export type ParametrosNpc = {
	Nombre: string,
	Nivel: number,
	Vida: number,
	Danio: number,
	Defensa: number,
	RangoAtaque: number,
	CadenciaAtaque: number,
	Velocidad: number,
	RadioAgro: number,
	RadioCorrea: number,
	Escala: number,
	Color: Color3,
	Pasivo: boolean?,
	Posicion: Vector3,
}

export type Npc = {
	Params: ParametrosNpc,
	Combatiente: Combatiente,
	Modelo: Model,
	Spawn: Vector3,
	Amenaza: { [Combatiente]: number },
	Aportes: { [number]: number }, -- UserId -> daño + curas aportadas en esta pelea
	ProximoAtaque: number,
	Volviendo: boolean,
	Muerto: boolean,
	-- Callbacks opcionales (jefes)
	AlTick: ((npc: Npc) -> ())?,
	AlMorir: ((npc: Npc) -> ())?,
	AlReiniciar: ((npc: Npc) -> ())?,
}

local EnemyManager = {}

-- (tipoEnemigo, jugadores que participaron): para las misiones de "Matar".
EnemyManager.Derrotado = Signal.new() :: Signal.Signal<string, { Player }>

local npcs: { [Combatiente]: Npc } = {}
local carpeta: Folder? = nil
local iniciado = false

local function ahora(): number
	return Workspace:GetServerTimeNow()
end

local function carpetaEnemigos(): Folder
	local c = carpeta
	if c and c.Parent then
		return c
	end
	local nueva = Instance.new("Folder")
	nueva.Name = "Enemigos"
	nueva.Parent = Workspace
	carpeta = nueva
	return nueva
end

------------------------------------------------------------------------
-- Construcción del modelo
------------------------------------------------------------------------

local function modeloSimple(color: Color3): Model
	-- Respaldo si no se puede crear un rig desde HumanoidDescription.
	local modelo = Instance.new("Model")
	local raiz = Instance.new("Part")
	raiz.Name = "HumanoidRootPart"
	raiz.Size = Vector3.new(2, 2, 1)
	raiz.Color = color
	raiz.Parent = modelo
	local cabeza = Instance.new("Part")
	cabeza.Name = "Head"
	cabeza.Size = Vector3.new(1.5, 1.5, 1.5)
	cabeza.Color = color
	cabeza.CFrame = raiz.CFrame * CFrame.new(0, 1.75, 0)
	cabeza.Parent = modelo
	local union = Instance.new("WeldConstraint")
	union.Part0 = raiz
	union.Part1 = cabeza
	union.Parent = raiz
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2
	humanoid.RequiresNeck = false -- este rig no tiene cuello: sin esto moriría al aparecer
	humanoid.Parent = modelo
	modelo.PrimaryPart = raiz
	return modelo
end

local function crearModelo(params: ParametrosNpc): Model
	local ok, resultado = pcall(function()
		local descripcion = Instance.new("HumanoidDescription")
		descripcion.HeadColor = params.Color
		descripcion.TorsoColor = params.Color
		descripcion.LeftArmColor = params.Color
		descripcion.RightArmColor = params.Color
		descripcion.LeftLegColor = params.Color
		descripcion.RightLegColor = params.Color
		return Players:CreateHumanoidModelFromDescription(descripcion, Enum.HumanoidRigType.R15)
	end)
	local modelo = if ok
			and typeof(resultado) == "Instance"
			and resultado:IsA("Model")
		then resultado
		else modeloSimple(params.Color)
	modelo.Name = params.Nombre
	if params.Escala ~= 1 then
		modelo:ScaleTo(params.Escala)
	end
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = `{params.Nombre} (Nv. {params.Nivel})`
		humanoid.WalkSpeed = params.Velocidad
		humanoid.BreakJointsOnDeath = false
	end
	return modelo
end

------------------------------------------------------------------------
-- Amenaza y objetivo
------------------------------------------------------------------------

local function maximoAmenaza(npc: Npc): (Combatiente?, number)
	local mejor: Combatiente? = nil
	local valor = -1
	for c, a in npc.Amenaza do
		if a > valor then
			mejor, valor = c, a
		end
	end
	return mejor, valor
end

local function limpiarAmenaza(npc: Npc)
	local limite = npc.Params.RadioCorrea * 1.5
	for c in table.clone(npc.Amenaza) do
		if
			not CombatManager.EstaVivo(c)
			or CombatManager.EsInvisible(c)
			or (c.Raiz.Position - npc.Spawn).Magnitude > limite
		then
			npc.Amenaza[c] = nil
		end
	end
end

local function reiniciar(npc: Npc)
	table.clear(npc.Amenaza)
	table.clear(npc.Aportes)
	npc.Volviendo = true
	CombatManager.Restaurar(npc.Combatiente)
	local alReiniciar = npc.AlReiniciar
	if alReiniciar then
		alReiniciar(npc)
	end
end

local function elegirObjetivo(npc: Npc): Combatiente?
	local c = npc.Combatiente
	local provocador = c.ProvocadoPor
	if provocador and CombatManager.EstaVivo(provocador) then
		return provocador
	end
	local objetivo = maximoAmenaza(npc)
	return objetivo
end

local function detenerse(npc: Npc)
	local h = npc.Combatiente.Humanoid
	h:MoveTo(npc.Combatiente.Raiz.Position)
end

------------------------------------------------------------------------
-- IA
------------------------------------------------------------------------

local function pensar(npc: Npc): nil
	local c = npc.Combatiente
	if npc.Muerto or not CombatManager.EstaVivo(c) or npc.Params.Pasivo then
		return nil
	end
	if not CombatManager.PuedeActuar(c) then
		detenerse(npc) -- aturdido
		return nil
	end
	local p = npc.Params
	local pos = c.Raiz.Position

	-- Vuelta al spawn tras perder la pelea o alejarse demasiado.
	if npc.Volviendo then
		if (pos - npc.Spawn).Magnitude < 4 then
			npc.Volviendo = false
			detenerse(npc)
		else
			c.Humanoid:MoveTo(npc.Spawn)
		end
		return nil
	end
	if (pos - npc.Spawn).Magnitude > p.RadioCorrea then
		reiniciar(npc)
		return nil
	end

	limpiarAmenaza(npc)
	if next(npc.Amenaza) == nil and p.RadioAgro > 0 then
		-- Detecta al jugador visible más cercano dentro del radio de agro.
		local cercano: Combatiente? = nil
		local mejor = p.RadioAgro
		for _, jugador in CombatManager.Jugadores() do
			local d = (jugador.Raiz.Position - pos).Magnitude
			if d <= mejor and not CombatManager.EsInvisible(jugador) then
				cercano, mejor = jugador, d
			end
		end
		if cercano then
			npc.Amenaza[cercano] = 1
		end
	end

	local objetivo = elegirObjetivo(npc)
	if not objetivo then
		-- Perdió a todos (murieron o se volvieron invisibles): si estaba peleando,
		-- se reinicia por completo (vida, furia y aportes). Así un jefe no se
		-- puede desgastar a lo largo de varios intentos.
		local h = c.Humanoid
		if next(npc.Aportes) ~= nil or h.Health < h.MaxHealth then
			reiniciar(npc)
		elseif (pos - npc.Spawn).Magnitude > 6 then
			npc.Volviendo = true
		end
		return nil
	end

	local alTick = npc.AlTick
	if alTick then
		alTick(npc)
	end

	local destino = objetivo.Raiz.Position
	local d = (destino - pos).Magnitude
	local alcance = p.RangoAtaque + (if p.Escala > 1 then p.Escala * 1.5 else 0)
	if d > alcance then
		c.Humanoid:MoveTo(destino)
		return nil
	end
	detenerse(npc)
	-- Mirar al objetivo.
	local plano = Vector3.new(destino.X, pos.Y, destino.Z)
	if (plano - pos).Magnitude > 0.1 then
		c.Raiz.CFrame = CFrame.lookAt(pos, plano)
	end
	local t = ahora()
	if t >= npc.ProximoAtaque then
		npc.ProximoAtaque = t + p.CadenciaAtaque
		-- Aviso visible antes del golpe: es la señal para hacer parry.
		CombatManager.Anunciar(c, "¡!")
		task.delay(EnemigosConfig.AvisoAtaque, function()
			if npc.Muerto or not CombatManager.PuedeActuar(c) or not CombatManager.EstaVivo(objetivo) then
				return
			end
			local distancia = (objetivo.Raiz.Position - c.Raiz.Position).Magnitude
			if distancia <= alcance + 3 then
				CombatManager.AtaqueNpc(c, objetivo, 1)
			end
		end)
	end
	return nil
end

------------------------------------------------------------------------
-- API
------------------------------------------------------------------------

-- Crea un NPC enemigo en el mundo. Devuelve nil si no se pudo.
function EnemyManager.Crear(params: ParametrosNpc): Npc?
	local modelo = crearModelo(params)
	modelo:PivotTo(CFrame.new(params.Posicion + Vector3.new(0, 3 * params.Escala, 0)))
	modelo.Parent = carpetaEnemigos()

	local raiz = modelo:FindFirstChild("HumanoidRootPart")
	if raiz and raiz:IsA("BasePart") then
		if params.Pasivo then
			raiz.Anchored = true
		else
			raiz:SetNetworkOwner(nil) -- la física del NPC la decide el servidor
		end
	end

	local stats = Estadisticas.DeEnemigo(params.Vida, params.Danio, params.Defensa)
	local c = CombatManager.RegistrarNpc(modelo, params.Nombre, params.Nivel, stats)
	if not c then
		modelo:Destroy()
		return nil
	end
	local npc: Npc = {
		Params = params,
		Combatiente = c,
		Modelo = modelo,
		Spawn = params.Posicion,
		Amenaza = {},
		Aportes = {},
		ProximoAtaque = 0,
		Volviendo = false,
		Muerto = false,
		AlTick = nil,
		AlMorir = nil,
		AlReiniciar = nil,
	}
	npcs[c] = npc
	return npc
end

function EnemyManager.Obtener(c: Combatiente): Npc?
	return npcs[c]
end

-- Recompensa estándar: XP, oro y botín personal para cada jugador que aportó.
-- `tipo` es el id del enemigo (EnemigosConfig.Enemigos o RaidBloxConfig.Jefes):
-- las misiones de "Matar" lo usan.
function EnemyManager.Recompensar(
	npc: Npc,
	xp: number,
	oro: number,
	botin: { EnemigosConfig.EntradaBotin },
	origen: string,
	tipo: string?
)
	local posicion = npc.Combatiente.Raiz.Position
	local participantes: { Player } = {}
	for userId, aporte in npc.Aportes do
		local player = Players:GetPlayerByUserId(userId)
		if not player or aporte <= 0 then
			continue
		end
		if xp > 0 then
			local niveles = DataManager.AddExperience(player, xp)
			if niveles > 0 then
				local datos = DataManager.GetData(player)
				local nivel = if datos then datos.Nivel else 0
				NetworkBridge.Server.FireClient("Notificacion", player, `¡Subiste al nivel {nivel}!`, "Oro")
			end
		end
		if oro > 0 then
			DataManager.AddGold(player, oro)
		end
		local items = LootManager.TirarTabla(botin)
		if #items > 0 then
			LootManager.Soltar(player, posicion, items, origen)
		end
		table.insert(participantes, player)
	end
	if tipo and #participantes > 0 then
		EnemyManager.Derrotado:Fire(tipo, participantes)
	end
end

------------------------------------------------------------------------
-- Spawns configurados
------------------------------------------------------------------------

local function crearDeSpawn(spawn: EnemigosConfig.Spawn, def: EnemigosConfig.DefinicionEnemigo, indice: number)
	local angulo = (indice / math.max(1, spawn.Cantidad)) * math.pi * 2
	local radio = if spawn.Cantidad > 1 then spawn.Dispersion else 0
	local posicion = spawn.Posicion + Vector3.new(math.cos(angulo) * radio, 0, math.sin(angulo) * radio)
	local npc = EnemyManager.Crear({
		Nombre = def.Nombre,
		Nivel = def.Nivel,
		Vida = def.Vida,
		Danio = def.Danio,
		Defensa = def.Defensa,
		RangoAtaque = def.RangoAtaque,
		CadenciaAtaque = def.CadenciaAtaque,
		Velocidad = def.Velocidad,
		RadioAgro = def.RadioAgro,
		RadioCorrea = def.RadioCorrea,
		Escala = def.Escala,
		Color = def.Color,
		Pasivo = def.Pasivo,
		Posicion = posicion,
	})
	if not npc then
		return
	end
	npc.AlMorir = function(n: Npc)
		EnemyManager.Recompensar(n, def.Xp, def.Oro, def.Botin, def.Nombre, spawn.Enemigo)
		task.delay(spawn.Reaparicion, crearDeSpawn, spawn, def, indice)
	end
end

function EnemyManager.CrearSpawnsDeZona(zona: string)
	for _, spawn in EnemigosConfig.Spawns do
		if spawn.Zona ~= zona then
			continue
		end
		local def = EnemigosConfig.Enemigos[spawn.Enemigo]
		if not def then
			warn(`[Enemigos] Enemigo desconocido en spawn: {spawn.Enemigo}`)
			continue
		end
		for i = 1, spawn.Cantidad do
			task.spawn(crearDeSpawn, spawn, def, i)
		end
	end
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function EnemyManager.Init(zona: string?)
	assert(not iniciado, "EnemyManager.Init() se llamó dos veces")
	iniciado = true

	CombatManager.DanioAplicado:Connect(
		function(fuente: Combatiente?, objetivo: Combatiente, cantidad: number, amenaza: number)
			local npc = npcs[objetivo]
			if not npc or not fuente or not fuente.Player or npc.Params.Pasivo then
				return -- los muñecos de práctica no llevan amenaza ni aportes
			end
			npc.Amenaza[fuente] = (npc.Amenaza[fuente] or 0) + amenaza
			local uid = (fuente.Player :: Player).UserId
			npc.Aportes[uid] = (npc.Aportes[uid] or 0) + cantidad
		end
	)

	-- Curar a alguien que está peleando con un NPC genera amenaza en ese NPC.
	CombatManager.CuraAplicada:Connect(function(fuente: Combatiente, objetivo: Combatiente, cantidad: number)
		local player = fuente.Player
		if not player then
			return
		end
		local afectados: { Npc } = {}
		for _, npc in npcs do
			if npc.Amenaza[objetivo] then
				table.insert(afectados, npc)
			end
		end
		if #afectados == 0 then
			return
		end
		local porNpc = cantidad * EnemigosConfig.AmenazaPorCura / #afectados
		for _, npc in afectados do
			npc.Amenaza[fuente] = (npc.Amenaza[fuente] or 0) + porNpc
			npc.Aportes[player.UserId] = (npc.Aportes[player.UserId] or 0) + cantidad / #afectados
		end
	end)

	CombatManager.Provocado:Connect(function(objetivo: Combatiente, fuente: Combatiente)
		local npc = npcs[objetivo]
		if npc then
			local _, maximo = maximoAmenaza(npc)
			npc.Amenaza[fuente] = math.max(npc.Amenaza[fuente] or 0, maximo) * 1.1 + 1
		end
	end)

	CombatManager.InvisibilidadIniciada:Connect(function(c: Combatiente)
		for _, npc in npcs do
			npc.Amenaza[c] = nil
		end
	end)

	CombatManager.Murio:Connect(function(c: Combatiente)
		-- Nadie guarda referencias a combatientes muertos en su tabla de amenaza.
		for _, otro in npcs do
			otro.Amenaza[c] = nil
		end
		local npc = npcs[c]
		if not npc or npc.Muerto then
			return
		end
		npc.Muerto = true
		npcs[c] = nil
		local alMorir = npc.AlMorir
		if alMorir then
			task.spawn(alMorir, npc)
		end
		task.delay(3, function()
			npc.Modelo:Destroy()
		end)
	end)

	local acumulado = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acumulado += dt
		if acumulado < EnemigosConfig.TickIA then
			return
		end
		acumulado = 0
		for _, npc in table.clone(npcs) do
			local ok, err = pcall(pensar, npc)
			if not ok then
				warn(`[Enemigos] Error en IA de {npc.Params.Nombre}: {err}`)
			end
		end
	end)

	if zona then
		EnemyManager.CrearSpawnsDeZona(zona)
	end
end

return EnemyManager
