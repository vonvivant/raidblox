--!strict
-- RaidBloxManager: jefes de raid de mundo.
--
-- * Aparecen según RaidBloxConfig (posición y tiempo de reaparición) y se
--   anuncian a todo el servidor.
-- * Vida máxima dinámica: SaludBase * (1 + jugadoresEnCombate * 0.2),
--   recalculada cada 3 s manteniendo el porcentaje de vida actual.
-- * Barra de vida gigante para todos los jugadores cercanos.
-- * Ataques de área anunciados con zonas rojas en el suelo; esquivarlas es
--   saliendo del círculo antes del golpe.
-- * Furia al 20% de vida: +30% de daño, ataques de área más seguidos y con menos aviso.
-- * Botín personal para cada participante con al menos 1% del aporte total.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pruebas = require(game:GetService("ReplicatedStorage").Modules.Pruebas)
local Workspace = game:GetService("Workspace")

local RaidBloxConfig = require(ReplicatedStorage.Configs.RaidBloxConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local CombatManager = require(script.Parent.CombatManager)
local EnemyManager = require(script.Parent.EnemyManager)

type Combatiente = CombatManager.Combatiente
type Npc = EnemyManager.Npc

type Jefe = {
	Id: string,
	Def: RaidBloxConfig.DefinicionRaidBlox,
	Npc: Npc,
	Furia: boolean,
	ProximoAtaque: { [string]: number },
	ProximoEscalado: number,
	Receptores: { [Player]: boolean }, -- quiénes ven la barra
}

local RaidBloxManager = {}

local jefes: { [string]: Jefe } = {}
local iniciado = false

local COLOR_ANUNCIO = Color3.fromRGB(255, 120, 60)

local function ahora(): number
	return Workspace:GetServerTimeNow()
end

local function jugadoresCerca(posicion: Vector3, radio: number): { Combatiente }
	local lista: { Combatiente } = {}
	for _, c in CombatManager.Jugadores() do
		if (c.Raiz.Position - posicion).Magnitude <= radio then
			table.insert(lista, c)
		end
	end
	return lista
end

------------------------------------------------------------------------
-- Escalado y furia
------------------------------------------------------------------------

-- Vida máxima para n jugadores en combate (mínimo 1).
local function vidaMaxima(def: RaidBloxConfig.DefinicionRaidBlox, n: number): number
	return math.floor(def.SaludBase * (1 + math.max(1, n) * RaidBloxConfig.FactorPorJugador))
end

local function escalar(jefe: Jefe)
	local c = jefe.Npc.Combatiente
	local n = #jugadoresCerca(c.Raiz.Position, RaidBloxConfig.RadioCombate)
	local nuevoMax = vidaMaxima(jefe.Def, n)
	local h = c.Humanoid
	if nuevoMax == h.MaxHealth or h.Health <= 0 then
		return
	end
	local fraccion = h.Health / h.MaxHealth
	h.MaxHealth = nuevoMax
	h.Health = math.max(1, nuevoMax * fraccion)
end

local function revisarFuria(jefe: Jefe)
	local c = jefe.Npc.Combatiente
	if jefe.Furia or c.Humanoid.Health > c.Humanoid.MaxHealth * RaidBloxConfig.UmbralFuria then
		return
	end
	jefe.Furia = true
	c.MultiplicadorDanio = RaidBloxConfig.MultiplicadorFuria
	for _, player in Players:GetPlayers() do
		if jefe.Receptores[player] then
			NetworkBridge.Server.FireClient("Notificacion", player, `¡{jefe.Def.Nombre} entra en FURIA!`, "Error")
		end
	end
end

------------------------------------------------------------------------
-- Ataques de área con aviso
------------------------------------------------------------------------

local paramsSuelo = RaycastParams.new()
paramsSuelo.FilterType = Enum.RaycastFilterType.Exclude

local function alturaSuelo(posicion: Vector3, ignorar: { Instance }): number
	paramsSuelo.FilterDescendantsInstances = ignorar
	local resultado = Workspace:Raycast(posicion + Vector3.new(0, 5, 0), Vector3.new(0, -60, 0), paramsSuelo)
	return if resultado then resultado.Position.Y else posicion.Y - 3
end

local function zonaRoja(centro: Vector3, radio: number, ignorar: { Instance }): Part
	local zona = Instance.new("Part")
	zona.Name = "AvisoRaidBlox"
	zona.Shape = Enum.PartType.Cylinder
	zona.Anchored = true
	zona.CanCollide = false
	zona.CanQuery = false
	zona.CanTouch = false
	zona.Material = Enum.Material.Neon
	zona.Color = Color3.fromRGB(255, 40, 30)
	zona.Transparency = 0.45
	zona.Size = Vector3.new(0.3, radio * 2, radio * 2)
	local y = alturaSuelo(centro, ignorar)
	zona.CFrame = CFrame.new(centro.X, y + 0.2, centro.Z) * CFrame.Angles(0, 0, math.rad(90))
	zona.Parent = Workspace
	return zona
end

local function lanzarAtaque(jefe: Jefe, ataque: RaidBloxConfig.AtaqueArea)
	local c = jefe.Npc.Combatiente
	local centro: Vector3
	if ataque.Tipo == "AlrededorDelJefe" then
		centro = c.Raiz.Position
	else
		local candidatos = jugadoresCerca(c.Raiz.Position, RaidBloxConfig.RadioCombate)
		if #candidatos == 0 then
			return
		end
		centro = candidatos[math.random(1, #candidatos)].Raiz.Position
	end

	local aviso = ataque.Aviso * (if jefe.Furia then RaidBloxConfig.AvisoFuria else 1)
	local ignorar: { Instance } = { c.Modelo }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignorar, player.Character)
		end
	end
	local zona = zonaRoja(centro, ataque.Radio, ignorar)

	task.delay(aviso, function()
		zona:Destroy()
		if not CombatManager.EstaVivo(c) then
			return
		end
		for _, objetivo in CombatManager.Jugadores() do
			local d = objetivo.Raiz.Position - centro
			if Vector3.new(d.X, 0, d.Z).Magnitude <= ataque.Radio then
				CombatManager.DanioArea(c, objetivo, ataque.DanioMultiplicador)
			end
		end
	end)
end

------------------------------------------------------------------------
-- Barra de vida para los clientes
------------------------------------------------------------------------

local function difundirEstado(jefe: Jefe)
	local c = jefe.Npc.Combatiente
	local cerca: { [Player]: boolean } = {}
	for _, jugador in jugadoresCerca(c.Raiz.Position, RaidBloxConfig.RadioHUD) do
		local player = jugador.Player
		if player then
			cerca[player] = true
		end
	end
	local estado = {
		Id = jefe.Id,
		Nombre = jefe.Def.Nombre,
		Nivel = jefe.Def.Nivel,
		Vida = math.floor(c.Humanoid.Health),
		VidaMax = math.floor(c.Humanoid.MaxHealth),
		Furia = jefe.Furia,
	}
	for player in cerca do
		NetworkBridge.Server.FireClient("RaidBloxEstado", player, estado)
	end
	for player in jefe.Receptores do
		if not cerca[player] and player.Parent == Players then
			NetworkBridge.Server.FireClient("RaidBloxEstado", player, { Id = jefe.Id, Oculto = true })
		end
	end
	jefe.Receptores = cerca
end

------------------------------------------------------------------------
-- Ciclo de vida
------------------------------------------------------------------------

local aparecer: (id: string, def: RaidBloxConfig.DefinicionRaidBlox) -> ()

local function alMorir(jefe: Jefe)
	local npc = jefe.Npc
	jefes[jefe.Id] = nil
	for player in jefe.Receptores do
		if player.Parent == Players then
			NetworkBridge.Server.FireClient("RaidBloxEstado", player, { Id = jefe.Id, Muerto = true })
		end
	end

	-- Solo cobran quienes aportaron al menos el 1% del total.
	local total = 0
	for _, aporte in npc.Aportes do
		total += aporte
	end
	for userId, aporte in table.clone(npc.Aportes) do
		if total <= 0 or aporte / total < RaidBloxConfig.AporteMinimo then
			npc.Aportes[userId] = nil
			local player = Players:GetPlayerByUserId(userId)
			if player then
				NetworkBridge.Server.FireClient(
					"Notificacion",
					player,
					"Tu aporte no alcanzó el 1% para recibir botín del jefe.",
					"Error"
				)
			end
		end
	end
	EnemyManager.Recompensar(npc, jefe.Def.Xp, jefe.Def.Oro, jefe.Def.Botin, jefe.Def.Nombre)
	NetworkBridge.Server.FireAll("AnuncioGlobal", `¡{jefe.Def.Nombre} fue derrotado!`, COLOR_ANUNCIO)

	local espera = if Pruebas.Activas() then jefe.Def.ReaparicionEnStudio else jefe.Def.Reaparicion
	task.delay(espera, aparecer, jefe.Id, jefe.Def)
end

aparecer = function(id: string, def: RaidBloxConfig.DefinicionRaidBlox)
	local npc = EnemyManager.Crear({
		Nombre = def.Nombre,
		Nivel = def.Nivel,
		Vida = def.SaludBase,
		Danio = def.DanioBase,
		Defensa = def.Defensa,
		RangoAtaque = def.RangoAtaque,
		CadenciaAtaque = def.CadenciaAtaque,
		Velocidad = def.Velocidad,
		RadioAgro = 45,
		RadioCorrea = RaidBloxConfig.RadioCombate,
		Escala = def.Escala,
		Color = def.Color,
		Pasivo = false,
		Posicion = def.Posicion,
	})
	if not npc then
		warn(`[RaidBlox] No se pudo crear {def.Nombre}`)
		return
	end
	npc.Modelo:SetAttribute("RaidBlox", true)
	npc.Combatiente.ReduccionAturdir = 0.5 -- los jefes resisten la mitad de los aturdimientos
	npc.Combatiente.Humanoid.MaxHealth = vidaMaxima(def, 1)
	npc.Combatiente.Humanoid.Health = vidaMaxima(def, 1)

	local t = ahora()
	local jefe: Jefe = {
		Id = id,
		Def = def,
		Npc = npc,
		Furia = false,
		ProximoAtaque = {},
		ProximoEscalado = 0,
		Receptores = {},
	}
	for _, ataque in def.Ataques do
		jefe.ProximoAtaque[ataque.Nombre] = t + ataque.Cada
	end
	jefes[id] = jefe

	npc.AlTick = function()
		local ahoraT = ahora()
		if ahoraT >= jefe.ProximoEscalado then
			jefe.ProximoEscalado = ahoraT + 3
			escalar(jefe)
		end
		revisarFuria(jefe)
		if not CombatManager.PuedeActuar(npc.Combatiente) then
			return
		end
		for _, ataque in def.Ataques do
			if ahoraT >= (jefe.ProximoAtaque[ataque.Nombre] or 0) then
				local cada = ataque.Cada * (if jefe.Furia then RaidBloxConfig.AceleracionFuria else 1)
				jefe.ProximoAtaque[ataque.Nombre] = ahoraT + cada
				lanzarAtaque(jefe, ataque)
			end
		end
	end
	npc.AlReiniciar = function()
		-- Wipe o correa: vuelve a la normalidad con vida completa.
		jefe.Furia = false
		npc.Combatiente.MultiplicadorDanio = 1
		npc.Combatiente.Humanoid.MaxHealth = vidaMaxima(def, 1)
		npc.Combatiente.Humanoid.Health = vidaMaxima(def, 1)
	end
	npc.AlMorir = function()
		alMorir(jefe)
	end

	NetworkBridge.Server.FireAll(
		"AnuncioGlobal",
		`¡{def.Nombre} (Nv. {def.Nivel}) apareció! Reuní a tu grupo.`,
		COLOR_ANUNCIO
	)
end

function RaidBloxManager.Init(zona: string?)
	assert(not iniciado, "RaidBloxManager.Init() se llamó dos veces")
	iniciado = true
	if not zona then
		return
	end
	for id, def in RaidBloxConfig.Jefes do
		if def.Zona == zona then
			task.spawn(aparecer, id, def)
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, jefe in jefes do
				local ok, err = pcall(function(): nil
					difundirEstado(jefe)
					return nil
				end)
				if not ok then
					warn(`[RaidBlox] Error difundiendo estado: {err}`)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		for _, jefe in jefes do
			jefe.Receptores[player] = nil
		end
	end)
end

return RaidBloxManager
