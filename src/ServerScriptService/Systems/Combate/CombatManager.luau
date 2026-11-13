--!strict
-- CombatManager: motor de combate tab-targeting, 100% en el servidor.
--
-- * Combatientes: personajes de jugadores y NPCs (enemigos y RaidBlox).
-- * Máquina de estados por combatiente:
--     Idle -> Casting -> Attacking -> Idle
--     cualquier estado -> Stunned -> Idle, cualquier estado -> Dead
--   Solo se puede lanzar una habilidad en Idle. Stunned y Dead no pueden actuar.
-- * Cooldowns y tiempos con workspace:GetServerTimeNow(), nunca con task.wait.
-- * Distancia al objetivo validada en el servidor con margen por latencia.
-- * Parry: ventana de 0.5 s que anula el golpe cuerpo a cuerpo, devuelve el daño
--   y aturde al agresor.
-- * Efectos: daño, cura, daño/cura en el tiempo, aturdir, provocar, auras e invisibilidad.
-- * Amenaza: cada daño suma amenaza (x3 para el Tanque); lo usa EnemyManager.
--
-- El cliente solo manda "usar habilidad N sobre este modelo" y "parry".
-- Todo lo demás (costos, daño, rango, cooldown, estado) lo decide el servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Pruebas = require(game:GetService("ReplicatedStorage").Modules.Pruebas)
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local ClassConfig = require(ReplicatedStorage.Configs.ClassConfig)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Signal = require(ReplicatedStorage.Modules.Signal)
local DataManager = require(script.Parent.Parent.DataManager)
local BandoManager = require(script.Parent.Parent.BandoManager)
local Estadisticas = require(script.Parent.Estadisticas)

type Habilidad = ClassConfig.Habilidad
type Efecto = ClassConfig.Efecto
type Stat = ClassConfig.Stat
type Stats = Estadisticas.Stats

export type Bando = "Jugadores" | "Enemigos"
export type Estado = "Idle" | "Casting" | "Attacking" | "Stunned" | "Dead"
type Escuela = "Fisico" | "Magico"

type Buff = { Fuente: string, Stat: Stat, Porcentaje: number, Hasta: number }
type Periodico = {
	Tipo: "Cura" | "Danio",
	Cantidad: number,
	Escuela: Escuela,
	Fuente: Combatiente?,
	Siguiente: number,
	Hasta: number,
	Intervalo: number,
}
type Casteo = {
	Id: number,
	Habilidad: Habilidad,
	Indice: number,
	Objetivo: Combatiente?,
	Punto: Vector3?, -- modo apuntado: hacia dónde apuntaba la mira
	PosInicio: Vector3,
	Fin: number,
}

export type Combatiente = {
	Modelo: Model,
	Humanoid: Humanoid,
	Raiz: BasePart,
	Player: Player?,
	Bando: Bando,
	Nombre: string,
	Nivel: number,
	Stats: Stats,
	Mana: number,
	Estado: Estado,
	BloqueoHasta: number,
	AturdidoHasta: number,
	ParryHasta: number,
	ParryListo: number,
	InvisibleHasta: number,
	InmuneAturdirHasta: number, -- rendimientos decrecientes: tras un aturdimiento, unos segundos de inmunidad
	ReduccionAturdir: number, -- 1 = normal; los jefes 0.5
	TransparenciasOriginales: { [Instance]: number }?,
	Casteo: Casteo?,
	Cooldowns: { [string]: number },
	Buffs: { Buff },
	Periodicos: { Periodico },
	UltimoCombate: number,
	MultiplicadorDanio: number, -- Furia de los RaidBlox
	ProvocadoPor: Combatiente?,
	ProvocadoHasta: number,
	Escudo: number, -- daño que todavía absorbe
	EscudoHasta: number,
	SilenciadoHasta: number,
	IgnoraArmaduraHasta: number,
	ReduccionDanio: number, -- 0..1
	ReduccionHasta: number,
	Conexiones: { RBXScriptConnection },
}

-- Mecánica propia de una habilidad (Habilidad.Especial). `Puede` devuelve el
-- motivo por el que no se puede usar (o nil); `Hacer` corre al ejecutarla,
-- después de cobrar el recurso y aplicar los efectos normales.
export type Especial = {
	Puede: ((c: Combatiente, hab: Habilidad, objetivo: Combatiente?) -> string?)?,
	Hacer: (c: Combatiente, hab: Habilidad, objetivo: Combatiente?) -> (),
}

local CombatManager = {}

-- Señales para otros sistemas (amenaza, aportes a jefes, recompensas).
CombatManager.DanioAplicado = Signal.new() :: Signal.Signal<Combatiente?, Combatiente, number, number>
CombatManager.CuraAplicada = Signal.new() :: Signal.Signal<Combatiente, Combatiente, number>
CombatManager.Murio = Signal.new() :: Signal.Signal<Combatiente, Combatiente?>
CombatManager.Provocado = Signal.new() :: Signal.Signal<Combatiente, Combatiente, number>
CombatManager.InvisibilidadIniciada = Signal.new() :: Signal.Signal<Combatiente>
-- (npc, quien lo confundió, segundos): el NPC deja de perseguirlo.
CombatManager.AgroPerdido = Signal.new() :: Signal.Signal<Combatiente, Combatiente, number>

local especiales: { [string]: Especial } = {}
-- Recargas largas (ClassConfig.CooldownLargo o más): sobreviven a morir.
local cooldownsLargos: { [Player]: { [string]: number } } = {}
-- Paredes que cortan las habilidades a distancia.
local obstaculos: { Instance } = {}
-- Inmovilizados: velocidad a devolver y hasta cuándo.
local inmoviles: { [Combatiente]: { Hasta: number, Velocidad: number } } = {}

local combatientes: { [Model]: Combatiente } = {}
local porJugador: { [Player]: Combatiente } = {}
local contadorCasteos = 0
local iniciado = false

local DISTANCIA_EVENTOS = 150 -- studs: quién recibe los números flotantes

local function ahora(): number
	return Workspace:GetServerTimeNow()
end

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function vivo(c: Combatiente): boolean
	return c.Estado ~= "Dead" and c.Humanoid.Health > 0 and c.Modelo.Parent ~= nil
end

local function statEfectivo(c: Combatiente, stat: Stat): number
	local valor = c.Stats[stat]
	local t = ahora()
	local extra = 0
	for _, buff in c.Buffs do
		if buff.Stat == stat and buff.Hasta > t then
			extra += buff.Porcentaje
		end
	end
	return valor * (1 + extra / 100)
end

local function distancia(a: Combatiente, b: Combatiente): number
	return (a.Raiz.Position - b.Raiz.Position).Magnitude
end

-- Envía un evento visual a los jugadores cercanos a una posición.
local function emitir(posicion: Vector3, tipo: string, modelo: Model, valor: any, extra: any?)
	local destinatarios: { Player } = {}
	for _, player in Players:GetPlayers() do
		local personaje = player.Character
		local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
		if raiz and raiz:IsA("BasePart") and (raiz.Position - posicion).Magnitude <= DISTANCIA_EVENTOS then
			table.insert(destinatarios, player)
		end
	end
	NetworkBridge.Server.FireList("CombateEvento", destinatarios, tipo, modelo, valor, extra)
end

local function avisar(player: Player?, texto: string)
	if player then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, "Error")
	end
end

-- Lazy: resuelve transiciones por tiempo (fin de aturdimiento y de GCD).
local function actualizarEstado(c: Combatiente)
	if not vivo(c) then
		c.Estado = "Dead"
		return
	end
	local t = ahora()
	if c.Estado == "Stunned" and t >= c.AturdidoHasta then
		c.Estado = "Idle"
	end
	if c.Estado == "Attacking" and t >= c.BloqueoHasta then
		c.Estado = "Idle"
	end
	-- Red de seguridad: un casteo nunca puede quedar colgado.
	local casteo = c.Casteo
	if c.Estado == "Casting" and (not casteo or t > casteo.Fin + 1) then
		c.Estado = "Idle"
		c.Casteo = nil
	end
end

local function sincronizarMana(c: Combatiente)
	local player = c.Player
	if player then
		player:SetAttribute("Mana", math.floor(c.Mana))
		player:SetAttribute("ManaMax", c.Stats.ManaMax)
	end
end

-- Nombre del recurso de la clase del jugador ("maná" o "stamina").
local function nombreRecurso(c: Combatiente): string
	local player = c.Player
	local datos = player and DataManager.GetData(player)
	local def = datos and ClassConfig.Clases[datos.Clase]
	return string.lower((def and def.Recurso) or "Maná")
end

local function marcarCombate(c: Combatiente)
	c.UltimoCombate = ahora()
end

------------------------------------------------------------------------
-- Invisibilidad
------------------------------------------------------------------------

local function aplicarTransparencia(c: Combatiente, invisible: boolean)
	if invisible then
		-- Guarda la transparencia original de cada parte para restaurarla igual.
		local originales: { [Instance]: number } = c.TransparenciasOriginales or {}
		for _, objeto in c.Modelo:GetDescendants() do
			local visible = (objeto:IsA("BasePart") and objeto.Name ~= "HumanoidRootPart") or objeto:IsA("Decal")
			if visible then
				local parte = objeto :: any -- BasePart o Decal: ambos tienen Transparency
				if originales[objeto] == nil then
					originales[objeto] = parte.Transparency
				end
				parte.Transparency = math.max(parte.Transparency, 0.75)
			end
		end
		c.TransparenciasOriginales = originales
	else
		local originales = c.TransparenciasOriginales
		if originales then
			for objeto, valor in originales do
				if objeto.Parent and (objeto:IsA("BasePart") or objeto:IsA("Decal")) then
					(objeto :: any).Transparency = valor
				end
			end
		end
		c.TransparenciasOriginales = nil
	end
end

local function terminarInvisibilidad(c: Combatiente)
	if c.InvisibleHasta > 0 then
		c.InvisibleHasta = 0
		aplicarTransparencia(c, false)
	end
end

-- Texto flotante sobre un combatiente (ej. el aviso antes de un golpe).
function CombatManager.Anunciar(c: Combatiente, texto: string)
	emitir(c.Raiz.Position, "Estado", c.Modelo, texto)
end

function CombatManager.EsInvisible(c: Combatiente): boolean
	return c.InvisibleHasta > ahora()
end

------------------------------------------------------------------------
-- Daño y cura
------------------------------------------------------------------------

local aplicarDanio: (
	fuente: Combatiente?,
	objetivo: Combatiente,
	cantidad: number,
	escuela: Escuela,
	critico: boolean,
	parryable: boolean,
	bruto: number?
) -> ()

local function morir(c: Combatiente, asesino: Combatiente?)
	if c.Estado == "Dead" then
		return
	end
	c.Estado = "Dead"
	c.Casteo = nil
	table.clear(c.Periodicos)
	table.clear(c.Buffs)
	CombatManager.Murio:Fire(c, asesino)
end

local function curar(fuente: Combatiente, objetivo: Combatiente, cantidad: number, critico: boolean)
	if not vivo(objetivo) then
		return
	end
	local h = objetivo.Humanoid
	local real = math.min(math.floor(cantidad), math.floor(h.MaxHealth - h.Health))
	if real <= 0 then
		return
	end
	h.Health += real
	emitir(objetivo.Raiz.Position, "Cura", objetivo.Modelo, real, critico)
	CombatManager.CuraAplicada:Fire(fuente, objetivo, real)
end

aplicarDanio = function(
	fuente: Combatiente?,
	objetivo: Combatiente,
	cantidad: number,
	escuela: Escuela,
	critico: boolean,
	parryable: boolean,
	bruto: number?
)
	if not vivo(objetivo) then
		return
	end
	local t = ahora()

	-- Parry: anula el golpe, devuelve el daño y aturde al agresor.
	if parryable and fuente and objetivo.ParryHasta > t and vivo(fuente) then
		objetivo.ParryHasta = 0
		emitir(objetivo.Raiz.Position, "Estado", objetivo.Modelo, "¡PARRY!")
		-- El golpe devuelto se mitiga con la defensa del agresor, no con la del que paró.
		local defensaFuente = statEfectivo(fuente, "Defensa")
		local devuelto = (bruto or cantidad) * (1 - defensaFuente / (defensaFuente + 100))
		aplicarDanio(objetivo, fuente, devuelto, escuela, false, false)
		CombatManager.Aturdir(fuente, ClassConfig.AturdimientoParry)
		return
	end

	if objetivo.ReduccionHasta > t then
		cantidad *= 1 - objetivo.ReduccionDanio
	end
	if objetivo.Escudo > 0 then
		if objetivo.EscudoHasta <= t then
			objetivo.Escudo = 0
		else
			local absorbido = math.min(objetivo.Escudo, cantidad)
			objetivo.Escudo -= absorbido
			cantidad -= absorbido
			if cantidad < 1 then
				marcarCombate(objetivo)
				if fuente then
					marcarCombate(fuente)
				end
				emitir(objetivo.Raiz.Position, "Estado", objetivo.Modelo, "Absorbido")
				-- El golpe cuenta para la amenaza aunque no haya sacado vida.
				CombatManager.DanioAplicado:Fire(fuente, objetivo, 0, absorbido)
				return
			end
		end
	end

	local final = math.max(1, math.floor(cantidad))
	local h = objetivo.Humanoid
	h.Health = math.max(0, h.Health - final)
	marcarCombate(objetivo)
	emitir(objetivo.Raiz.Position, "Danio", objetivo.Modelo, final, { Escuela = escuela, Critico = critico })

	local amenaza = final
	if fuente then
		marcarCombate(fuente)
		amenaza = final * fuente.Stats.MultiplicadorAmenaza
		if fuente.Stats.RoboVida > 0 then
			curar(fuente, fuente, final * fuente.Stats.RoboVida, false)
		end
	end
	CombatManager.DanioAplicado:Fire(fuente, objetivo, final, amenaza)

	if h.Health <= 0 then
		morir(objetivo, fuente)
	end
end

-- ¿La fuente está detrás del objetivo? (para el Asesino)
local function porLaEspalda(fuente: Combatiente, objetivo: Combatiente): boolean
	local haciaFuente = fuente.Raiz.Position - objetivo.Raiz.Position
	if haciaFuente.Magnitude < 0.1 then
		return false
	end
	return objetivo.Raiz.CFrame.LookVector:Dot(haciaFuente.Unit) < -0.3
end

-- Daño de una habilidad con todos los modificadores.
-- Antes de un golpe directo: ¿falla por diferencia de nivel o lo esquivan?
-- Devuelve el estado a mostrar ("Fallo" / "Esquivado") o nil si pega.
local function evitado(fuente: Combatiente, objetivo: Combatiente, escuela: Escuela): string?
	local diferencia = objetivo.Nivel - fuente.Nivel
	if diferencia > 0 then
		local p = math.min(ClassConfig.FalloMaximo, diferencia * ClassConfig.FalloPorNivel)
		if math.random() < p then
			return "Fallo"
		end
	end
	if escuela == "Fisico" and math.random() < objetivo.Stats.Esquiva then
		return "Esquivado"
	end
	return nil
end

local function golpeEvitado(fuente: Combatiente, objetivo: Combatiente, escuela: Escuela): boolean
	local estado = evitado(fuente, objetivo, escuela)
	if not estado then
		return false
	end
	marcarCombate(fuente)
	marcarCombate(objetivo)
	emitir(objetivo.Raiz.Position, "Estado", objetivo.Modelo, estado)
	return true
end

local function calcularDanio(
	fuente: Combatiente,
	objetivo: Combatiente,
	base: number,
	escala: Stat,
	factor: number
): (number, boolean)
	local bruto = base + statEfectivo(fuente, escala) * factor
	local critico = math.random() < fuente.Stats.Critico
	local mult = fuente.MultiplicadorDanio

	local espalda = fuente.Stats.MultiplicadorEspalda
	if espalda and porLaEspalda(fuente, objetivo) then
		critico = true
		mult *= espalda
	end
	if critico then
		mult *= ClassConfig.MultiplicadorCritico
	end
	local pasivas = fuente.Stats.Pasivas
	if pasivas.Ejecutor and objetivo.Humanoid.Health < objetivo.Humanoid.MaxHealth * 0.3 then
		mult *= 1.25
	end
	if pasivas.Furia and fuente.Humanoid.Health < fuente.Humanoid.MaxHealth * 0.5 then
		mult *= 1.15
	end

	local defensa = statEfectivo(objetivo, "Defensa")
	local mitigacion = if fuente.IgnoraArmaduraHasta > ahora() then 0 else defensa / (defensa + 100)
	return bruto * mult * (1 - mitigacion), critico
end

------------------------------------------------------------------------
-- Control
------------------------------------------------------------------------

function CombatManager.Aturdir(c: Combatiente, duracion: number)
	if not vivo(c) then
		return
	end
	local t = ahora()
	-- Rendimientos decrecientes: tras un aturdimiento hay una ventana de inmunidad,
	-- así nadie (ni un jefe) puede quedar aturdido para siempre.
	if t < c.InmuneAturdirHasta and t >= c.AturdidoHasta then
		emitir(c.Raiz.Position, "Estado", c.Modelo, "Inmune")
		return
	end
	c.AturdidoHasta = math.max(c.AturdidoHasta, t + duracion * c.ReduccionAturdir)
	c.InmuneAturdirHasta = c.AturdidoHasta + ClassConfig.InmunidadAturdir
	c.Estado = "Stunned"
	c.Casteo = nil -- el aturdimiento interrumpe el casteo
	emitir(c.Raiz.Position, "Estado", c.Modelo, "Aturdido")
	local player = c.Player
	if player then
		NetworkBridge.Server.FireClient("HabilidadEstado", player, { Cancelado = true })
	end
end

------------------------------------------------------------------------
-- Efectos visibles (Fase 7): el marco de objetivo muestra buffs y debuffs con
-- su cuenta regresiva. Se publican en el atributo "Efectos" del modelo como
-- "Nombre|Hasta|B" (o D) separados por ";"; solo se reescribe si cambió.
------------------------------------------------------------------------

local NOMBRES_STAT: { [string]: string } = {
	Ataque = "Ataque",
	Poder = "Poder",
	Defensa = "Defensa",
	Critico = "Crítico",
}

local function publicarEfectos(c: Combatiente)
	local t = ahora()
	local partes: { string } = {}
	local function agregar(nombre: string, hasta: number, bueno: boolean)
		if hasta > t then
			table.insert(partes, `{nombre}|{math.floor(hasta * 10 + 0.5) / 10}|{if bueno then "B" else "D"}`)
		end
	end
	agregar("Aturdido", c.AturdidoHasta, false)
	agregar("Provocado", if c.ProvocadoPor then c.ProvocadoHasta else 0, false)
	agregar("Invisible", c.InvisibleHasta, true)
	agregar("Silenciado", c.SilenciadoHasta, false)
	agregar("Escudo", if c.Escudo > 0 then c.EscudoHasta else 0, true)
	agregar("Perforante", c.IgnoraArmaduraHasta, true)
	agregar("Blindado", c.ReduccionHasta, true)
	local inmovil = inmoviles[c]
	agregar("Inmóvil", if inmovil then inmovil.Hasta else 0, false)
	for _, b in c.Buffs do
		local signo = if b.Porcentaje >= 0 then "+" else ""
		agregar(`{signo}{b.Porcentaje}% {NOMBRES_STAT[b.Stat] or b.Stat}`, b.Hasta, b.Porcentaje >= 0)
	end
	for _, p in c.Periodicos do
		if p.Tipo == "Cura" then
			agregar("Regeneración", p.Hasta, true)
		else
			agregar(if p.Escuela == "Magico" then "Quemadura" else "Sangrado", p.Hasta, false)
		end
	end
	local texto = table.concat(partes, ";")
	if c.Modelo:GetAttribute("Efectos") ~= texto then
		c.Modelo:SetAttribute("Efectos", texto)
	end
end

------------------------------------------------------------------------
-- Efectos de habilidades
------------------------------------------------------------------------

local function aplicarEfecto(fuente: Combatiente, objetivo: Combatiente, efecto: Efecto, idHabilidad: string)
	local t = ahora()
	if efecto.Tipo == "Danio" then
		if golpeEvitado(fuente, objetivo, efecto.Escuela) then
			return
		end
		local cantidad, critico = calcularDanio(fuente, objetivo, efecto.Base, efecto.Escala, efecto.Factor)
		aplicarDanio(fuente, objetivo, cantidad, efecto.Escuela, critico, false)
	elseif efecto.Tipo == "Cura" then
		local critico = math.random() < fuente.Stats.Critico
		local cantidad = (efecto.Base + statEfectivo(fuente, "Poder") * efecto.Factor)
			* (if critico then ClassConfig.MultiplicadorCritico else 1)
		curar(fuente, objetivo, cantidad, critico)
	elseif efecto.Tipo == "CuraTiempo" then
		table.insert(objetivo.Periodicos, {
			Tipo = "Cura",
			Cantidad = efecto.Base + statEfectivo(fuente, "Poder") * efecto.Factor,
			Escuela = "Magico",
			Fuente = fuente,
			Siguiente = t + efecto.Intervalo,
			Hasta = t + efecto.Duracion + 0.05,
			Intervalo = efecto.Intervalo,
		})
	elseif efecto.Tipo == "DanioTiempo" then
		local defensa = statEfectivo(objetivo, "Defensa")
		local porTick = (efecto.Base + statEfectivo(fuente, efecto.Escala) * efecto.Factor)
			* fuente.MultiplicadorDanio
			* (1 - defensa / (defensa + 100))
		table.insert(objetivo.Periodicos, {
			Tipo = "Danio",
			Cantidad = porTick,
			Escuela = efecto.Escuela,
			Fuente = fuente,
			Siguiente = t + efecto.Intervalo,
			Hasta = t + efecto.Duracion + 0.05,
			Intervalo = efecto.Intervalo,
		})
	elseif efecto.Tipo == "Aturdir" then
		CombatManager.Aturdir(objetivo, efecto.Duracion)
	elseif efecto.Tipo == "Provocar" then
		if objetivo.Player == nil then
			objetivo.ProvocadoPor = fuente
			objetivo.ProvocadoHasta = t + efecto.Duracion
			CombatManager.Provocado:Fire(objetivo, fuente, efecto.Duracion)
			emitir(objetivo.Raiz.Position, "Estado", objetivo.Modelo, "Provocado")
		end
	elseif efecto.Tipo == "Aura" then
		-- La misma habilidad no se acumula: renueva su propio buff.
		for i = #objetivo.Buffs, 1, -1 do
			if objetivo.Buffs[i].Fuente == idHabilidad and objetivo.Buffs[i].Stat == efecto.Stat then
				table.remove(objetivo.Buffs, i)
			end
		end
		table.insert(objetivo.Buffs, {
			Fuente = idHabilidad,
			Stat = efecto.Stat,
			Porcentaje = efecto.Porcentaje,
			Hasta = t + efecto.Duracion,
		})
		emitir(
			objetivo.Raiz.Position,
			"Estado",
			objetivo.Modelo,
			`{if efecto.Porcentaje >= 0 then "+" else ""}{efecto.Porcentaje}% {efecto.Stat}`
		)
	elseif efecto.Tipo == "Invisible" then
		objetivo.InvisibleHasta = t + efecto.Duracion
		aplicarTransparencia(objetivo, true)
		CombatManager.InvisibilidadIniciada:Fire(objetivo)
	elseif efecto.Tipo == "Empujar" then
		-- Solo monstruos comunes: la física de los jugadores es de su cliente y
		-- los jefes no se dejan mover.
		if objetivo.Player == nil and objetivo.ReduccionAturdir >= 1 and not objetivo.Raiz.Anchored then
			local d = objetivo.Raiz.Position - fuente.Raiz.Position
			local plano = Vector3.new(d.X, 0, d.Z)
			if plano.Magnitude > 0.1 then
				objetivo.Raiz.AssemblyLinearVelocity = plano.Unit * efecto.Fuerza
					+ Vector3.new(0, efecto.Fuerza * 0.35, 0)
			end
		end
	elseif efecto.Tipo == "Interrumpir" then
		if objetivo.Estado == "Casting" then
			objetivo.Casteo = nil
			objetivo.Estado = "Idle"
			emitir(objetivo.Raiz.Position, "CasteoFin", objetivo.Modelo, nil)
			emitir(objetivo.Raiz.Position, "Estado", objetivo.Modelo, "Interrumpido")
			local po = objetivo.Player
			if po then
				NetworkBridge.Server.FireClient("HabilidadEstado", po, { Cancelado = true })
			end
		end
	elseif efecto.Tipo == "Recurso" then
		objetivo.Mana = math.min(objetivo.Stats.ManaMax, objetivo.Mana + efecto.Cantidad)
		sincronizarMana(objetivo)
	elseif efecto.Tipo == "Escudo" then
		CombatManager.DarEscudo(objetivo, efecto.Base, efecto.Duracion)
	elseif efecto.Tipo == "IgnorarArmadura" then
		objetivo.IgnoraArmaduraHasta = t + efecto.Duracion
	elseif efecto.Tipo == "Reduccion" then
		objetivo.ReduccionDanio = math.clamp(efecto.Porcentaje / 100, 0, 0.9)
		objetivo.ReduccionHasta = t + efecto.Duracion
	elseif efecto.Tipo == "Silenciar" then
		objetivo.SilenciadoHasta = math.max(objetivo.SilenciadoHasta, t + efecto.Duracion)
		if objetivo.Estado == "Casting" then
			objetivo.Casteo = nil
			objetivo.Estado = "Idle"
			emitir(objetivo.Raiz.Position, "CasteoFin", objetivo.Modelo, nil)
			local po = objetivo.Player
			if po then
				NetworkBridge.Server.FireClient("HabilidadEstado", po, { Cancelado = true })
			end
		end
		emitir(objetivo.Raiz.Position, "Estado", objetivo.Modelo, "Silenciado")
	elseif efecto.Tipo == "PerderAgro" then
		if objetivo.Player == nil then
			CombatManager.AgroPerdido:Fire(objetivo, fuente, efecto.Duracion)
		end
	elseif efecto.Tipo == "Inmovilizar" then
		CombatManager.Inmovilizar(objetivo, efecto.Duracion)
	end
	publicarEfectos(objetivo)
end

-- Para otros sistemas (trampas, torretas): aplica un efecto como si viniera de
-- una habilidad de `fuente`. No cobra recurso ni revisa rango.
function CombatManager.AplicarEfecto(fuente: Combatiente, objetivo: Combatiente, efecto: Efecto, id: string)
	if vivo(objetivo) then
		aplicarEfecto(fuente, objetivo, efecto, id)
	end
end

function CombatManager.DarEscudo(c: Combatiente, cantidad: number, duracion: number)
	local t = ahora()
	local actual = if c.EscudoHasta > t then c.Escudo else 0
	c.Escudo = math.max(actual, math.floor(cantidad))
	c.EscudoHasta = t + duracion
	emitir(c.Raiz.Position, "Estado", c.Modelo, `Escudo {c.Escudo}`)
	publicarEfectos(c)
end

-- Deja al combatiente sin poder caminar (sí atacar). Los jefes son inmunes.
function CombatManager.Inmovilizar(c: Combatiente, duracion: number)
	if not vivo(c) or c.ReduccionAturdir < 1 then
		return
	end
	local t = ahora()
	local previo = inmoviles[c]
	local velocidad = if previo then previo.Velocidad else c.Humanoid.WalkSpeed
	inmoviles[c] = { Hasta = math.max(if previo then previo.Hasta else 0, t + duracion), Velocidad = velocidad }
	c.Humanoid.WalkSpeed = 0
	emitir(c.Raiz.Position, "Estado", c.Modelo, "Inmóvil")
	publicarEfectos(c)
end

function CombatManager.Liberar(c: Combatiente)
	local previo = inmoviles[c]
	if previo then
		inmoviles[c] = nil
		if c.Humanoid.WalkSpeed == 0 then
			c.Humanoid.WalkSpeed = previo.Velocidad
		end
		publicarEfectos(c)
	end
end

function CombatManager.Silenciado(c: Combatiente): boolean
	return c.SilenciadoHasta > ahora()
end

function CombatManager.RegistrarEspecial(nombre: string, especial: Especial)
	especiales[nombre] = especial
end

-- Una pared: las habilidades a distancia no la atraviesan mientras exista.
function CombatManager.RegistrarObstaculo(parte: BasePart)
	table.insert(obstaculos, parte)
	parte.Destroying:Connect(function()
		local i = table.find(obstaculos, parte)
		if i then
			table.remove(obstaculos, i)
		end
	end)
end

local paramsObstaculo = RaycastParams.new()
paramsObstaculo.FilterType = Enum.RaycastFilterType.Include

local function hayObstaculo(desde: Vector3, hasta: Vector3): boolean
	if #obstaculos == 0 then
		return false
	end
	paramsObstaculo.FilterDescendantsInstances = obstaculos
	return Workspace:Raycast(desde, hasta - desde, paramsObstaculo) ~= nil
end

local function esOfensiva(hab: Habilidad): boolean
	return hab.Objetivo == "Enemigo" or hab.Objetivo == "AreaEnemigos"
end

-- Combatientes de un bando dentro de un radio.
-- Bandos de jugadores (Rojo/Azul/Violeta): un jugador puede ser enemigo de
-- otro jugador solo con las reglas de PvP de BandoManager.
local function puedeAtacar(c: Combatiente, o: Combatiente): boolean
	if c.Bando ~= o.Bando then
		return true -- jugador contra NPC
	end
	local pc, po = c.Player, o.Player
	return pc ~= nil and po ~= nil and BandoManager.PuedeAtacar(pc, po)
end

-- ¿No puede ayudar (curar o potenciar) a ese jugador? Rivales, o un Violeta
-- intocable que ayuda a alguien que está peleando en PvP.
local function sonRivales(c: Combatiente, o: Combatiente): boolean
	local pc, po = c.Player, o.Player
	if pc == nil or po == nil or pc == po then
		return false
	end
	if BandoManager.SonRivales(pc, po) then
		return true
	end
	return BandoManager.De(pc) == "Violeta" and BandoManager.De(po) ~= "Violeta" and BandoManager.EnZonaPvP(po)
end

local function enRadio(centro: Vector3, radio: number, bando: Bando): { Combatiente }
	local lista: { Combatiente } = {}
	for _, c in combatientes do
		if c.Bando == bando and vivo(c) and (c.Raiz.Position - centro).Magnitude <= radio then
			table.insert(lista, c)
		end
	end
	return lista
end

local function bandoOpuesto(b: Bando): Bando
	return if b == "Jugadores" then "Enemigos" else "Jugadores"
end

-- Enemigos de un combatiente en un radio: los del bando opuesto y, para
-- jugadores, los jugadores rivales con los que vale el PvP en ese momento.
local function enemigosEnRadio(c: Combatiente, centro: Vector3, radio: number): { Combatiente }
	local lista = enRadio(centro, radio, bandoOpuesto(c.Bando))
	local pc = c.Player
	if pc then
		for _, o in enRadio(centro, radio, c.Bando) do
			local po = o.Player
			if po and BandoManager.SonHostiles(pc, po) then
				table.insert(lista, o)
			end
		end
	end
	return lista
end

-- Aliados en un radio: mismo bando, sin los jugadores rivales.
local function aliadosEnRadio(c: Combatiente, centro: Vector3, radio: number): { Combatiente }
	local lista: { Combatiente } = {}
	for _, o in enRadio(centro, radio, c.Bando) do
		if not sonRivales(c, o) then
			table.insert(lista, o)
		end
	end
	return lista
end

------------------------------------------------------------------------
-- Habilidades: validación, casteo y ejecución
------------------------------------------------------------------------

-- Resuelve el objetivo según el tipo de habilidad. Devuelve (ok, objetivo, motivo).
local function resolverObjetivo(c: Combatiente, hab: Habilidad, pedido: Combatiente?): (boolean, Combatiente?, string?)
	local alcance = hab.Rango + ClassConfig.ToleranciaRango
	local centro: string? = hab.Centro
	local tipo: string = hab.Objetivo
	if tipo == "Propio" then
		return true, c, nil
	elseif tipo == "Aliado" or (tipo == "AreaAliados" and centro == "Objetivo") then
		if pedido == nil or pedido.Bando ~= c.Bando or sonRivales(c, pedido) or not vivo(pedido) then
			return true, c, nil -- sin aliado válido: se lanza sobre uno mismo
		end
		if distancia(c, pedido) > alcance then
			return false, nil, "Tu aliado está demasiado lejos."
		end
		return true, pedido, nil
	elseif tipo == "Enemigo" or (tipo == "AreaEnemigos" and centro == "Objetivo") then
		if pedido == nil or not puedeAtacar(c, pedido) or not vivo(pedido) then
			if hab.ObjetivoOpcional then
				return true, nil, nil
			end
			if pedido and pedido.Player and c.Player and pedido ~= c then
				local bp = BandoManager.De(pedido.Player)
				return false,
					nil,
					if bp == "Violeta"
						then "Ese jugador es neutral (Violeta): no se lo puede atacar."
						elseif BandoManager.De(c.Player) == bp then "Es de tu mismo bando."
						else "Solo se puede pelear entre bandos en zonas PvP o en la Guerra."
			end
			return false, nil, "Necesitás un enemigo seleccionado."
		end
		if CombatManager.EsInvisible(pedido) then
			return false, nil, "No podés ver a ese objetivo."
		end
		if distancia(c, pedido) > alcance then
			return false, nil, "Fuera de alcance."
		end
		if hab.Rango > ClassConfig.RangoCuerpoACuerpo and hayObstaculo(c.Raiz.Position, pedido.Raiz.Position) then
			return false, nil, "Hay una pared en el medio."
		end
		return true, pedido, nil
	end
	return true, nil, nil -- área centrada en uno mismo
end

-- Modo apuntado: el jugador manda el punto del mundo bajo su mira y el servidor
-- decide a quién le pega. Devuelve (ok, objetivo, motivo, centro, lista):
--   * cuerpo a cuerpo ("Enemigo" con rango corto): todos los enemigos en un
--     cono hacia la mira (lista); el objetivo es el más cercano.
--   * a distancia: el primer enemigo (o aliado) cerca de la línea de la mira.
--   * área sobre un objetivo: centrada en el punto, acotado al rango.
-- `preferido`: el objetivo elegido al empezar un casteo (si sigue valiendo, se mantiene).
local paramsMira = RaycastParams.new()
paramsMira.FilterType = Enum.RaycastFilterType.Exclude
paramsMira.RespectCanCollide = true

local function resolverApuntado(
	c: Combatiente,
	hab: Habilidad,
	punto: Vector3,
	preferido: Combatiente?
): (boolean, Combatiente?, string?, Vector3?, { Combatiente }?)
	local tipo: string = hab.Objetivo
	local alcance = hab.Rango + ClassConfig.ToleranciaRango
	local ojo = c.Raiz.Position + Vector3.new(0, 1.5, 0)
	local hacia = punto - ojo
	if hacia.Magnitude < 0.1 then
		hacia = c.Raiz.CFrame.LookVector
	end
	local dir = hacia.Unit

	if tipo == "Propio" or ((tipo == "AreaEnemigos" or tipo == "AreaAliados") and hab.Centro ~= "Objetivo") then
		local ok, o, motivo = resolverObjetivo(c, hab, nil)
		return ok, o, motivo, nil, nil
	end

	if (tipo == "AreaEnemigos" or tipo == "AreaAliados") and hab.Centro == "Objetivo" then
		-- Sin atravesar paredes: si hay algo entre el ojo y el punto, el área cae ahí.
		local ignorar: { Instance } = {}
		for _, otro in combatientes do
			table.insert(ignorar, otro.Modelo)
		end
		paramsMira.FilterDescendantsInstances = ignorar
		local choque = Workspace:Raycast(ojo, punto - ojo, paramsMira)
		if choque then
			punto = choque.Position
		end
		local desdeRaiz = punto - c.Raiz.Position
		local centro = if desdeRaiz.Magnitude > hab.Rango then c.Raiz.Position + desdeRaiz.Unit * hab.Rango else punto
		return true, nil, nil, centro, nil
	end

	if tipo == "Enemigo" and hab.Rango <= ClassConfig.RangoCuerpoACuerpo then
		local plano = Vector3.new(dir.X, 0, dir.Z)
		plano = if plano.Magnitude > 0.01 then plano.Unit else c.Raiz.CFrame.LookVector
		local coseno = math.cos(math.rad(ClassConfig.MedioAnguloCono))
		local lista: { Combatiente } = {}
		local masCerca: Combatiente? = nil
		local menor = math.huge
		for _, o in enemigosEnRadio(c, c.Raiz.Position, alcance) do
			if CombatManager.EsInvisible(o) then
				continue
			end
			local v = o.Raiz.Position - c.Raiz.Position
			local vPlano = Vector3.new(v.X, 0, v.Z)
			local d = vPlano.Magnitude
			if d < 2.5 or vPlano.Unit:Dot(plano) >= coseno then
				table.insert(lista, o)
				if d < menor then
					masCerca, menor = o, d
				end
			end
		end
		if #lista == 0 then
			return false, nil, "No hay enemigos adelante.", nil, nil
		end
		-- Hasta 5, los más cercanos primero.
		table.sort(lista, function(a: Combatiente, b: Combatiente): boolean
			return (a.Raiz.Position - c.Raiz.Position).Magnitude < (b.Raiz.Position - c.Raiz.Position).Magnitude
		end)
		while #lista > 5 do
			table.remove(lista)
		end
		return true, masCerca, nil, nil, lista
	end

	-- A distancia: si el objetivo del casteo sigue valiendo, se mantiene.
	if preferido then
		local ok, o = resolverObjetivo(c, hab, preferido)
		if ok and o == preferido then
			return true, o, nil, nil, nil
		end
	end
	local candidatos: { Combatiente } = if tipo == "Enemigo"
		then enemigosEnRadio(c, c.Raiz.Position, alcance)
		else aliadosEnRadio(c, c.Raiz.Position, alcance)
	local elegido: Combatiente? = nil
	local menor = math.huge
	for _, o in candidatos do
		if o == c or (tipo == "Enemigo" and CombatManager.EsInvisible(o)) then
			continue
		end
		local v = o.Raiz.Position - ojo
		local largo = v:Dot(dir)
		if largo > 0 and largo <= alcance + 2 and (v - dir * largo).Magnitude <= ClassConfig.ToleranciaMira then
			if largo < menor then
				elegido, menor = o, largo
			end
		end
	end
	if tipo == "Enemigo" then
		if not elegido then
			if hab.ObjetivoOpcional then
				return true, nil, nil, nil, nil
			end
			return false, nil, "No hay ningún enemigo en la mira (o está fuera de alcance).", nil, nil
		end
		if hayObstaculo(c.Raiz.Position, elegido.Raiz.Position) then
			return false, nil, "Hay una pared en el medio.", nil, nil
		end
		return true, elegido, nil, nil, nil
	end
	-- Aliado: sin nadie en la mira, sobre uno mismo.
	return true, elegido or c, nil, nil, nil
end

local function ejecutar(
	c: Combatiente,
	hab: Habilidad,
	indice: number,
	objetivo: Combatiente?,
	centroForzado: Vector3?,
	listaForzada: { Combatiente }?
)
	local t = ahora()
	if c.Mana < hab.CostoMana then
		avisar(c.Player, `No tenés {nombreRecurso(c)} suficiente.`)
		c.Estado = "Idle"
		return
	end
	c.Mana -= hab.CostoMana
	sincronizarMana(c)
	c.Cooldowns[hab.Id] = t + hab.Cooldown
	local duenio = c.Player
	if duenio and hab.Cooldown >= ClassConfig.CooldownLargo then
		local largos = cooldownsLargos[duenio] or {}
		cooldownsLargos[duenio] = largos
		largos[hab.Id] = t + hab.Cooldown
		DataManager.SetCooldownLargo(duenio, hab.Id, t + hab.Cooldown)
	end
	c.Estado = "Attacking"
	c.BloqueoHasta = t + ClassConfig.GCD
	c.Casteo = nil
	if esOfensiva(hab) then
		terminarInvisibilidad(c) -- atacar revela
		marcarCombate(c)
	end

	local objetivos: { Combatiente } = {}
	if listaForzada then
		objetivos = listaForzada
	elseif hab.Objetivo == "AreaEnemigos" or hab.Objetivo == "AreaAliados" then
		local centro = centroForzado
			or (if hab.Centro == "Objetivo" and objetivo then objetivo.Raiz.Position else c.Raiz.Position)
		objetivos = if hab.Objetivo == "AreaEnemigos"
			then enemigosEnRadio(c, centro, hab.Radio or 10)
			else aliadosEnRadio(c, centro, hab.Radio or 10)
		-- Cono hacia adelante (áreas centradas en quien lanza).
		local cono = hab.Cono
		if cono then
			local frente = c.Raiz.CFrame.LookVector
			local plano = Vector3.new(frente.X, 0, frente.Z)
			local coseno = math.cos(math.rad(cono))
			local dentro: { Combatiente } = {}
			for _, o in objetivos do
				local v = o.Raiz.Position - c.Raiz.Position
				local vp = Vector3.new(v.X, 0, v.Z)
				if vp.Magnitude < 2.5 or (plano.Magnitude > 0.01 and vp.Unit:Dot(plano.Unit) >= coseno) then
					table.insert(dentro, o)
				end
			end
			objetivos = dentro
		end
	elseif objetivo then
		objetivos = { objetivo }
	end

	-- Un Violeta que ataca a un jugador toma el bando contrario al de su víctima.
	local pc = c.Player
	if pc and esOfensiva(hab) then
		for _, o in objetivos do
			local po = o.Player
			if po then
				BandoManager.AlAtacar(pc, po)
			end
		end
	end

	for _, o in objetivos do
		for _, efecto in hab.Efectos do
			-- Golpe en cono (modo apuntado): los demás del cono solo reciben el
			-- daño; aturdir, provocar y demás efectos van al objetivo principal.
			if listaForzada and o ~= objetivo and (efecto.Tipo :: string) ~= "Danio" then
				continue
			end
			if vivo(o) or efecto.Tipo == "Aura" then
				aplicarEfecto(c, o, efecto, hab.Id)
			end
		end
	end

	local propios = hab.EfectosPropios
	if propios then
		for _, efecto in propios do
			aplicarEfecto(c, c, efecto, hab.Id)
		end
	end
	local especial = if hab.Especial then especiales[hab.Especial] else nil
	if especial then
		local hacer = especial.Hacer
		local okEspecial, err = pcall(function(): nil
			hacer(c, hab, objetivo)
			return nil
		end)
		if not okEspecial then
			warn(`[Combate] Error en la habilidad {hab.Id}: {err}`)
		end
	end

	local player = c.Player
	if player then
		NetworkBridge.Server.FireClient("HabilidadEstado", player, {
			Indice = indice,
			ListoEn = c.Cooldowns[hab.Id],
			GcdHasta = c.BloqueoHasta,
		})
	end
	-- Visual para los clientes cercanos: animación, proyectil, impacto o área.
	local centroArea: Vector3? = nil
	if hab.Objetivo == "AreaEnemigos" or hab.Objetivo == "AreaAliados" then
		centroArea = centroForzado
			or (if hab.Centro == "Objetivo" and objetivo then objetivo.Raiz.Position else c.Raiz.Position)
	end
	local alcanzados: { Model } = {}
	for _, o in objetivos do
		table.insert(alcanzados, o.Modelo)
	end
	emitir(c.Raiz.Position, "Accion", c.Modelo, hab.Id, {
		Objetivo = if objetivo then objetivo.Modelo else nil,
		Centro = centroArea,
		Radio = hab.Radio,
		Alcanzados = alcanzados,
	})
end

-- Cancela un casteo en curso y avisa al jugador.
local function cancelarCasteo(c: Combatiente, motivo: string)
	c.Casteo = nil
	c.Estado = "Idle"
	emitir(c.Raiz.Position, "CasteoFin", c.Modelo, nil)
	local player = c.Player
	avisar(player, motivo)
	if player then
		NetworkBridge.Server.FireClient("HabilidadEstado", player, { Cancelado = true })
	end
end

-- Termina un casteo: valida que siga en pie y ejecuta la habilidad.
local function completarCasteo(c: Combatiente, id: number, hab: Habilidad, _player: Player?): nil
	local casteo = c.Casteo
	local estadoActual: Estado = c.Estado
	if not casteo or casteo.Id ~= id or estadoActual ~= "Casting" or not vivo(c) then
		return nil -- interrumpido (aturdido, muerto o reemplazado)
	end
	local cancelar: string? = nil
	local centro: Vector3? = nil
	local lista: { Combatiente }? = nil
	if (c.Raiz.Position - casteo.PosInicio).Magnitude > ClassConfig.MovimientoMaxCasteo then
		cancelar = "Te moviste: se canceló el hechizo."
	else
		local okFinal, objetivoFinal, motivoFinal
		local punto = casteo.Punto
		if punto then
			okFinal, objetivoFinal, motivoFinal, centro, lista = resolverApuntado(c, hab, punto, casteo.Objetivo)
		else
			okFinal, objetivoFinal, motivoFinal = resolverObjetivo(c, hab, casteo.Objetivo)
		end
		if not okFinal then
			cancelar = motivoFinal or "Objetivo inválido."
		else
			casteo.Objetivo = objetivoFinal
		end
	end
	if cancelar then
		cancelarCasteo(c, cancelar)
		return nil
	end
	ejecutar(c, hab, casteo.Indice, casteo.Objetivo, centro, lista)
	return nil
end

local function intentarHabilidad(c: Combatiente, indice: number, pedido: Combatiente?, punto: Vector3?)
	local player = c.Player
	local datos = player and DataManager.GetData(player)
	local def = datos and ClassConfig.Clases[datos.Clase]
	if not def then
		avisar(player, "Primero elegí una clase.")
		return
	end
	local hab = def.Habilidades[indice]
	if not hab then
		return
	end
	-- Clases con barras: solo se usan las habilidades equipadas.
	if def.Barras and datos and not table.find(DataManager.Barras(datos), hab.Id) then
		avisar(player, "Esa habilidad no está en tus barras.")
		return
	end

	actualizarEstado(c)
	if c.Estado == "Stunned" then
		avisar(player, "Estás aturdido.")
		return
	elseif c.Estado ~= "Idle" then
		return -- casteando o en GCD: se ignora en silencio
	end
	local t = ahora()
	if t < c.SilenciadoHasta then
		avisar(player, "Estás silenciado.")
		return
	end
	if t < (c.Cooldowns[hab.Id] or 0) then
		return
	end
	if c.Mana < hab.CostoMana then
		avisar(player, `No tenés {nombreRecurso(c)} suficiente.`)
		return
	end
	local ok, objetivo, motivo, centro, lista
	if punto then
		ok, objetivo, motivo, centro, lista = resolverApuntado(c, hab, punto, nil)
	else
		ok, objetivo, motivo = resolverObjetivo(c, hab, pedido)
	end
	if not ok then
		avisar(player, motivo or "No se puede usar ahora.")
		return
	end
	local especial = if hab.Especial then especiales[hab.Especial] else nil
	if especial and especial.Puede then
		local impedimento = especial.Puede(c, hab, objetivo)
		if impedimento then
			avisar(player, impedimento)
			return
		end
	end

	if hab.TiempoCasteo <= 0 then
		ejecutar(c, hab, indice, objetivo, centro, lista)
		return
	end

	contadorCasteos += 1
	local id = contadorCasteos
	c.Estado = "Casting"
	c.Casteo = {
		Id = id,
		Habilidad = hab,
		Indice = indice,
		Objetivo = objetivo,
		Punto = punto,
		PosInicio = c.Raiz.Position,
		Fin = t + hab.TiempoCasteo,
	}
	emitir(c.Raiz.Position, "Casteo", c.Modelo, hab.Id, { Duracion = hab.TiempoCasteo })
	if player then
		NetworkBridge.Server.FireClient("HabilidadEstado", player, {
			Indice = indice,
			CasteoHasta = t + hab.TiempoCasteo,
			Nombre = hab.Nombre,
		})
	end

	task.delay(hab.TiempoCasteo, function()
		local okCasteo, err = pcall(completarCasteo, c, id, hab, player)
		if not okCasteo then
			warn(`[Combate] Error completando casteo: {err}`)
			local casteo = c.Casteo
			if casteo and casteo.Id == id then
				c.Casteo = nil
				c.Estado = "Idle"
			end
		end
	end)
end

local function intentarParry(c: Combatiente)
	actualizarEstado(c)
	if c.Estado ~= "Idle" and c.Estado ~= "Attacking" then
		return
	end
	local t = ahora()
	if t < c.ParryListo then
		return
	end
	c.ParryHasta = t + ClassConfig.VentanaParry
	c.ParryListo = t + ClassConfig.CooldownParry
	emitir(c.Raiz.Position, "Estado", c.Modelo, "Guardia")
	local player = c.Player
	if player then
		NetworkBridge.Server.FireClient("HabilidadEstado", player, { Indice = 0, ListoEn = c.ParryListo })
	end
end

------------------------------------------------------------------------
-- Registro de combatientes
------------------------------------------------------------------------

local function nuevoCombatiente(
	modelo: Model,
	humanoid: Humanoid,
	raiz: BasePart,
	bando: Bando,
	nombre: string,
	nivel: number,
	stats: Stats,
	player: Player?
): Combatiente
	local c: Combatiente = {
		Modelo = modelo,
		Humanoid = humanoid,
		Raiz = raiz,
		Player = player,
		Bando = bando,
		Nombre = nombre,
		Nivel = nivel,
		Stats = stats,
		Mana = stats.ManaMax,
		Estado = "Idle",
		BloqueoHasta = 0,
		AturdidoHasta = 0,
		ParryHasta = 0,
		ParryListo = 0,
		InvisibleHasta = 0,
		InmuneAturdirHasta = 0,
		ReduccionAturdir = 1,
		TransparenciasOriginales = nil,
		Casteo = nil,
		Cooldowns = {},
		Buffs = {},
		Periodicos = {},
		UltimoCombate = 0,
		MultiplicadorDanio = 1,
		ProvocadoPor = nil,
		ProvocadoHasta = 0,
		Escudo = 0,
		EscudoHasta = 0,
		SilenciadoHasta = 0,
		IgnoraArmaduraHasta = 0,
		ReduccionDanio = 0,
		ReduccionHasta = 0,
		Conexiones = {},
	}
	humanoid.MaxHealth = stats.VidaMax
	humanoid.Health = stats.VidaMax
	modelo:SetAttribute("NombreCombate", nombre)
	modelo:SetAttribute("Nivel", nivel)
	modelo:SetAttribute("Bando", bando)
	combatientes[modelo] = c
	table.insert(
		c.Conexiones,
		humanoid.Died:Connect(function()
			morir(c, nil)
		end)
	)
	table.insert(
		c.Conexiones,
		modelo.Destroying:Connect(function()
			CombatManager.Quitar(modelo)
		end)
	)
	return c
end

function CombatManager.Quitar(modelo: Model)
	local c = combatientes[modelo]
	if not c then
		return
	end
	for _, conexion in c.Conexiones do
		conexion:Disconnect()
	end
	combatientes[modelo] = nil
	inmoviles[c] = nil
	local player = c.Player
	if player and porJugador[player] == c then
		porJugador[player] = nil
	end
end

-- Registra un NPC (enemigo o RaidBlox).
function CombatManager.RegistrarNpc(modelo: Model, nombre: string, nivel: number, stats: Stats): Combatiente?
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	local raiz = modelo:FindFirstChild("HumanoidRootPart")
	if not humanoid or not raiz or not raiz:IsA("BasePart") then
		warn(`[Combate] {modelo:GetFullName()} no tiene Humanoid/HumanoidRootPart`)
		return nil
	end
	return nuevoCombatiente(modelo, humanoid, raiz, "Enemigos", nombre, nivel, stats, nil)
end

-- Recalcula las estadísticas de un jugador manteniendo el porcentaje de vida y maná.
function CombatManager.RecalcularJugador(player: Player)
	local c = porJugador[player]
	local datos = DataManager.GetData(player)
	if not c or not datos then
		return
	end
	local fraccionVida = if c.Humanoid.MaxHealth > 0 then c.Humanoid.Health / c.Humanoid.MaxHealth else 1
	local fraccionMana = if c.Stats.ManaMax > 0 then c.Mana / c.Stats.ManaMax else 1
	c.Stats = Estadisticas.DeJugador(datos)
	c.Nivel = datos.Nivel
	c.Humanoid.MaxHealth = c.Stats.VidaMax
	if c.Estado ~= "Dead" then
		c.Humanoid.Health = math.max(1, c.Stats.VidaMax * fraccionVida)
	end
	c.Mana = c.Stats.ManaMax * fraccionMana
	c.Modelo:SetAttribute("Nivel", datos.Nivel)
	player:SetAttribute("Clase", datos.Clase)
	sincronizarMana(c)
end

-- Copia al combatiente las recargas largas que siguen corriendo y se las
-- manda al cliente (después de morir, de entrar o de cambiar de clase).
local function restaurarCooldowns(player: Player, c: Combatiente, conDemora: boolean)
	local datos = DataManager.GetData(player)
	if not datos then
		return
	end
	local largos = cooldownsLargos[player]
	if not largos then
		local guardados: { [string]: number } = datos.CooldownsLargos or {}
		local nuevos: { [string]: number } = table.clone(guardados)
		largos = nuevos
		cooldownsLargos[player] = nuevos
	end
	local t = ahora()
	local def = ClassConfig.Clases[datos.Clase]
	local pendientes: { { Indice: number, ListoEn: number } } = {}
	for id, hasta in largos do
		if hasta <= t then
			largos[id] = nil
			continue
		end
		c.Cooldowns[id] = hasta
		if def then
			for indice, hab in def.Habilidades do
				if hab.Id == id then
					table.insert(pendientes, { Indice = indice, ListoEn = hasta })
				end
			end
		end
	end
	if #pendientes > 0 then
		task.delay(if conDemora then 1 else 0.3, function()
			if player.Parent == Players then
				for _, p in pendientes do
					NetworkBridge.Server.FireClient("HabilidadEstado", player, p)
				end
			end
		end)
	end
end

local function alAparecer(player: Player, personaje: Model)
	local datos = DataManager.WaitForData(player, 70)
	if not datos or player.Character ~= personaje then
		return
	end
	local humanoid = personaje:WaitForChild("Humanoid", 10)
	local raiz = personaje:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not raiz or not raiz:IsA("BasePart") then
		return
	end
	-- La regeneración la maneja el combate (se quita el script "Health" por defecto).
	if player.Character ~= personaje then
		return -- reapareció mientras esperábamos: lo registra el hilo del personaje nuevo
	end
	local salud = personaje:FindFirstChild("Health")
	if salud and salud:IsA("Script") then
		salud:Destroy()
	end
	local anterior = porJugador[player]
	if anterior then
		CombatManager.Quitar(anterior.Modelo)
	end
	local c = nuevoCombatiente(
		personaje,
		humanoid,
		raiz,
		"Jugadores",
		player.DisplayName,
		datos.Nivel,
		Estadisticas.DeJugador(datos),
		player
	)
	porJugador[player] = c
	player:SetAttribute("Clase", datos.Clase)
	sincronizarMana(c)
	restaurarCooldowns(player, c, true)
end

-- API para otros sistemas.
function CombatManager.Ahora(): number
	return ahora()
end

function CombatManager.EnemigosEnRadio(c: Combatiente, centro: Vector3, radio: number): { Combatiente }
	return enemigosEnRadio(c, centro, radio)
end

function CombatManager.AliadosEnRadio(c: Combatiente, centro: Vector3, radio: number): { Combatiente }
	return aliadosEnRadio(c, centro, radio)
end

-- Pone en cero las recargas de las habilidades que cumplan `filtro`.
function CombatManager.ReiniciarCooldowns(c: Combatiente, filtro: (Habilidad) -> boolean)
	local player = c.Player
	local datos = player and DataManager.GetData(player)
	local def = datos and ClassConfig.Clases[datos.Clase]
	if not player or not def then
		return
	end
	local largos = cooldownsLargos[player]
	for indice, hab in def.Habilidades do
		if filtro(hab) and (c.Cooldowns[hab.Id] or 0) > ahora() then
			c.Cooldowns[hab.Id] = 0
			if largos then
				largos[hab.Id] = nil
			end
			DataManager.SetCooldownLargo(player, hab.Id, nil)
			NetworkBridge.Server.FireClient("HabilidadEstado", player, { Indice = indice, ListoEn = 0 })
		end
	end
end

-- ¿La habilidad está en recarga? (para no dejar cambiarla de barra)
function CombatManager.EnRecarga(player: Player, idHabilidad: string): boolean
	local c = porJugador[player]
	local largos = cooldownsLargos[player]
	local t = ahora()
	return (c ~= nil and (c.Cooldowns[idHabilidad] or 0) > t) or (largos ~= nil and (largos[idHabilidad] or 0) > t)
end

------------------------------------------------------------------------
-- API de consulta (para IA, jefes y UI)
------------------------------------------------------------------------

function CombatManager.Obtener(modelo: Model): Combatiente?
	return combatientes[modelo]
end

function CombatManager.DeJugador(player: Player): Combatiente?
	return porJugador[player]
end

function CombatManager.EstaVivo(c: Combatiente): boolean
	return vivo(c)
end

function CombatManager.PuedeActuar(c: Combatiente): boolean
	actualizarEstado(c)
	return c.Estado == "Idle" or c.Estado == "Attacking"
end

function CombatManager.Jugadores(): { Combatiente }
	local lista: { Combatiente } = {}
	for _, c in porJugador do
		if vivo(c) then
			table.insert(lista, c)
		end
	end
	return lista
end

-- Recupera un porcentaje de vida o maná de un jugador (pociones).
-- Devuelve false si no hacía falta (ya estaba lleno) o está muerto.
function CombatManager.RecuperarJugador(player: Player, recurso: "Vida" | "Mana", porcentaje: number): boolean
	local c = porJugador[player]
	if not c or not vivo(c) then
		return false
	end
	if recurso == "Vida" then
		-- Cura directa: no dispara CuraAplicada (una poción no genera amenaza)
		-- y no se gasta si falta menos de 1 punto de vida.
		local h = c.Humanoid
		local real = math.min(math.floor(h.MaxHealth * porcentaje / 100), math.floor(h.MaxHealth - h.Health))
		if real < 1 then
			return false
		end
		h.Health += real
		emitir(c.Raiz.Position, "Cura", c.Modelo, real, false)
		return true
	end
	if c.Mana >= c.Stats.ManaMax then
		return false
	end
	c.Mana = math.min(c.Stats.ManaMax, c.Mana + c.Stats.ManaMax * porcentaje / 100)
	sincronizarMana(c)
	return true
end

-- Golpe cuerpo a cuerpo de un NPC (se puede hacer parry).
function CombatManager.AtaqueNpc(npc: Combatiente, objetivo: Combatiente, multiplicador: number)
	if not vivo(npc) or not vivo(objetivo) then
		return
	end
	if golpeEvitado(npc, objetivo, "Fisico") then
		emitir(npc.Raiz.Position, "Accion", npc.Modelo, "AtaqueNpc", { Objetivo = objetivo.Modelo })
		return
	end
	local defensa = statEfectivo(objetivo, "Defensa")
	local critico = math.random() < npc.Stats.Critico
	local bruto = npc.Stats.Ataque
		* multiplicador
		* npc.MultiplicadorDanio
		* (if critico then ClassConfig.MultiplicadorCritico else 1)
	marcarCombate(npc)
	emitir(npc.Raiz.Position, "Accion", npc.Modelo, "AtaqueNpc", { Objetivo = objetivo.Modelo })
	aplicarDanio(npc, objetivo, bruto * (1 - defensa / (defensa + 100)), "Fisico", critico, true, bruto)
end

-- Daño de área de un jefe (no se puede hacer parry).
function CombatManager.DanioArea(fuente: Combatiente, objetivo: Combatiente, multiplicador: number)
	if not vivo(objetivo) then
		return
	end
	local defensa = statEfectivo(objetivo, "Defensa")
	local bruto = fuente.Stats.Ataque * multiplicador * fuente.MultiplicadorDanio
	aplicarDanio(fuente, objetivo, bruto * (1 - defensa / (defensa + 100)), "Magico", false, false)
end

-- Restaura vida, maná y estado (enemigos que vuelven a su spawn).
function CombatManager.Restaurar(c: Combatiente)
	c.Humanoid.Health = c.Humanoid.MaxHealth
	c.Mana = c.Stats.ManaMax
	c.Estado = "Idle"
	c.Casteo = nil
	table.clear(c.Periodicos)
	table.clear(c.Buffs)
	c.ProvocadoPor = nil
end

------------------------------------------------------------------------
-- Ciclo periódico: efectos en el tiempo, regeneración y expiraciones
------------------------------------------------------------------------

local acumuladorSegundo = 0

local function tick(dt: number): nil
	local t = ahora()
	acumuladorSegundo += dt
	local cadaSegundo = acumuladorSegundo >= 1
	if cadaSegundo then
		acumuladorSegundo -= 1
	end

	for _, c in table.clone(combatientes) do
		if not vivo(c) then
			continue
		end
		actualizarEstado(c)

		-- Efectos periódicos.
		for i = #c.Periodicos, 1, -1 do
			local p = c.Periodicos[i]
			-- Daño en el tiempo entre jugadores: se corta si dejan de poder
			-- pelear (por ejemplo, la víctima salió de la zona PvP).
			local fp = p.Fuente and p.Fuente.Player
			local vp = c.Player
			if p.Tipo == "Danio" and fp and vp and not BandoManager.SonHostiles(fp, vp) then
				table.remove(c.Periodicos, i)
				continue
			end
			while p.Siguiente <= t and p.Siguiente <= p.Hasta and vivo(c) do
				p.Siguiente += p.Intervalo
				local fuente = p.Fuente
				if p.Tipo == "Cura" and fuente then
					curar(fuente, c, p.Cantidad, false)
				elseif p.Tipo == "Danio" then
					aplicarDanio(fuente, c, p.Cantidad, p.Escuela, false, false)
				end
			end
			if p.Siguiente > p.Hasta then
				table.remove(c.Periodicos, i)
			end
		end

		-- Moverse durante un casteo lo cancela en el momento (no solo al final).
		local casteo = c.Casteo
		if
			c.Estado == "Casting"
			and casteo
			and (c.Raiz.Position - casteo.PosInicio).Magnitude > ClassConfig.MovimientoMaxCasteo
		then
			cancelarCasteo(c, "Te moviste: se canceló el hechizo.")
		end

		if c.InvisibleHasta > 0 and c.InvisibleHasta <= t then
			terminarInvisibilidad(c)
		end
		if c.ProvocadoPor and c.ProvocadoHasta <= t then
			c.ProvocadoPor = nil
		end
		local inmovil = inmoviles[c]
		if inmovil and inmovil.Hasta <= t then
			CombatManager.Liberar(c)
		end

		if cadaSegundo then
			publicarEfectos(c)
		end

		if cadaSegundo and c.Player and vivo(c) then
			for i = #c.Buffs, 1, -1 do
				if c.Buffs[i].Hasta <= t then
					table.remove(c.Buffs, i)
				end
			end
			if c.Mana < c.Stats.ManaMax then
				c.Mana = math.min(c.Stats.ManaMax, c.Mana + c.Stats.RegenMana)
				sincronizarMana(c)
			end
			local h = c.Humanoid
			if t - c.UltimoCombate >= ClassConfig.SegundosParaFueraDeCombate and h.Health < h.MaxHealth then
				h.Health = math.min(h.MaxHealth, h.Health + h.MaxHealth * ClassConfig.RegenVidaFueraCombate)
			end
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function CombatManager.Init()
	assert(not iniciado, "CombatManager.Init() se llamó dos veces")
	iniciado = true

	-- Para "volver a neutral": no se puede si peleó hace poco.
	BandoManager.SetEnCombate(function(player: Player): boolean
		local c = porJugador[player]
		return c ~= nil and ahora() - c.UltimoCombate < GameConfig.Bandos.EsperaFueraDeCombate
	end)

	local function alEntrar(player: Player)
		player.CharacterAdded:Connect(function(personaje: Model)
			alAparecer(player, personaje)
		end)
		if player.Character then
			task.spawn(alAparecer, player, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		alEntrar(player)
	end
	Players.PlayerAdded:Connect(alEntrar)
	Players.PlayerRemoving:Connect(function(player: Player)
		local c = porJugador[player]
		if c then
			CombatManager.Quitar(c.Modelo)
		end
		cooldownsLargos[player] = nil
	end)

	-- Si el perfil tardó más que la espera inicial, se registra al terminar de cargar.
	DataManager.PerfilCargado:Connect(function(player: Player)
		local personaje = player.Character
		if personaje and not porJugador[player] then
			task.spawn(alAparecer, player, personaje)
		end
	end)

	-- Cambios de nivel, clase o equipo recalculan las estadísticas.
	DataManager.DatosCambiados:Connect(function(player: Player, seccion: Types.SeccionDatos)
		if seccion == "Nivel" or seccion == "Equipamiento" or seccion == "Clase" then
			CombatManager.RecalcularJugador(player)
		end
	end)

	-- Remotes
	NetworkBridge.Server.OnEvent(
		"UsarHabilidad",
		function(player: Player, indice: unknown, objetivo: unknown, punto: unknown)
			local n = NetworkBridge.Guard.Integer(indice, 1, 40)
			local c = porJugador[player]
			if not n or not c or not vivo(c) then
				return
			end
			local pedido: Combatiente? = nil
			if objetivo ~= nil then
				local modelo = NetworkBridge.Guard.InstanceOf(objetivo, "Model")
				pedido = if modelo then combatientes[modelo :: Model] else nil
			end
			-- Modo apuntado: un punto del mundo (finito y a menos de 600 studs).
			local apuntado: Vector3? = nil
			if typeof(punto) == "Vector3" then
				local v = punto :: Vector3
				if v == v and (v - c.Raiz.Position).Magnitude <= 600 then
					apuntado = v
				end
			end
			intentarHabilidad(c, n, pedido, apuntado)
		end
	)

	NetworkBridge.Server.OnEvent("Parry", function(player: Player)
		local c = porJugador[player]
		if c and vivo(c) then
			intentarParry(c)
		end
	end)

	NetworkBridge.Server.OnInvoke("ElegirClase", function(player: Player, clase: unknown): Types.Respuesta
		local id = NetworkBridge.Guard.OneOf(clase, ClassConfig.Clases)
		local datos = DataManager.GetData(player)
		if not id or not datos then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		-- Elegir es gratis la primera vez; en pruebas se puede cambiar libremente.
		if datos.Clase ~= "SinClase" and not Pruebas.Activas() then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		DataManager.SetClase(player, id :: any)
		local c = porJugador[player]
		if c then
			table.clear(c.Cooldowns)
			c.Humanoid.Health = c.Humanoid.MaxHealth
			c.Mana = c.Stats.ManaMax
			sincronizarMana(c)
			restaurarCooldowns(player, c, false) -- las recargas largas no se saltean cambiando de clase
		end
		return NetworkBridge.Ok(id)
	end)

	NetworkBridge.Server.OnInvoke("EquiparItem", function(player: Player, uid: unknown): Types.Respuesta
		local id = NetworkBridge.Guard.String(uid, 64)
		if not id then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		local ok, codigo = DataManager.EquiparItem(player, id)
		return if ok
			then NetworkBridge.Ok(nil)
			else NetworkBridge.Fail((codigo or "INTERNAL_ERROR") :: Types.CodigoError)
	end)

	NetworkBridge.Server.OnInvoke("DesequiparItem", function(player: Player, slot: unknown): Types.Respuesta
		local s = NetworkBridge.Guard.String(slot, 20)
		if not s then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		local ok, codigo = DataManager.DesequiparItem(player, s)
		return if ok
			then NetworkBridge.Ok(nil)
			else NetworkBridge.Fail((codigo or "INTERNAL_ERROR") :: Types.CodigoError)
	end)

	local acumulado = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acumulado += dt
		if acumulado < 0.25 then
			return
		end
		local paso = acumulado
		acumulado = 0
		local ok, err = pcall(tick, paso)
		if not ok then
			warn(`[Combate] Error en el ciclo: {err}`)
		end
	end)
end

return CombatManager
