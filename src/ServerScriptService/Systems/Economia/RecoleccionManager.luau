--!strict
-- RecoleccionManager: profesiones de recolección (Minería, Herboristería).
--
-- * Nodos: Parts con tag "NodoRecoleccion" y atributo Nodo (id de ProfesionesConfig.Nodos).
-- * Requisitos: herramienta correcta equipada (pico o hoz), nivel de profesión,
--   estar a 12 studs o menos y que el nodo no esté agotado.
-- * Minijuego: una barra se llena en ~2 s y hay que golpear dentro de la zona
--   verde. El servidor sortea la zona y valida el momento del golpe con su propio
--   reloj (con margen por latencia).
-- * Al acertar: recursos (más con nivel alto), XP de profesión y el nodo se
--   agota hasta que reaparece.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pruebas = require(game:GetService("ReplicatedStorage").Modules.Pruebas)
local Workspace = game:GetService("Workspace")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ProfesionesConfig = require(ReplicatedStorage.Configs.ProfesionesConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local CraftingManager = require(script.Parent.CraftingManager)

type DefinicionNodo = ProfesionesConfig.DefinicionNodo

local RecoleccionManager = {}

local TAG_NODO = "NodoRecoleccion"
local AREA_PRUEBA = Vector3.new(100, 0, -60)
local MJ = ProfesionesConfig.Minijuego

type Intento = {
	Token: string,
	Nodo: BasePart,
	Def: DefinicionNodo,
	ZonaInicio: number,
	ZonaFin: number,
	Fin: number,
}

local intentos: { [Player]: Intento } = {}
local agotados: { [BasePart]: boolean } = {}
local azar = Random.new()
local iniciado = false

local function ahora(): number
	return Workspace:GetServerTimeNow()
end

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
end

local function cerca(player: Player, nodo: BasePart): boolean
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return false
	end
	return (raiz.Position - nodo.Position).Magnitude <= ProfesionesConfig.DistanciaNodo + nodo.Size.Magnitude / 2
end

local function herramientaEquipada(player: Player): string?
	local datos = DataManager.GetData(player)
	local item = datos and datos.Equipamiento.Herramienta
	local def = item and ItemCatalog[item.ItemId]
	return if def then def.Herramienta else nil
end

local function agotar(nodo: BasePart, segundos: number)
	agotados[nodo] = true
	nodo.Transparency = 0.75
	local pp = nodo:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.Enabled = false
	end
	task.delay(segundos, function()
		agotados[nodo] = nil
		nodo.Transparency = 0
		local prompt = nodo:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = true
		end
	end)
end

local function iniciarMinijuego(player: Player, nodo: BasePart, def: DefinicionNodo)
	if intentos[player] then
		return -- ya está en un minijuego
	end
	if agotados[nodo] or not cerca(player, nodo) then
		return
	end
	local herramienta = herramientaEquipada(player)
	if herramienta ~= def.Herramienta then
		avisar(
			player,
			`Necesitás tener equipada una {if def.Herramienta == "Pico"
				then "herramienta de minería (pico)"
				else "hoz"}.`
		)
		return
	end
	if DataManager.NivelProfesion(player, def.Profesion) < def.NivelRequerido then
		avisar(
			player,
			`Necesitás nivel {def.NivelRequerido} de {ProfesionesConfig.Profesiones[def.Profesion].Nombre}.`
		)
		return
	end

	-- El servidor sortea dónde cae la zona verde.
	local inicio = ahora() + 0.3 -- margen para que el cliente reciba el evento
	local zonaInicio = inicio + azar:NextNumber(MJ.InicioZonaMin, MJ.InicioZonaMax)
	local intento: Intento = {
		Token = HttpService:GenerateGUID(false),
		Nodo = nodo,
		Def = def,
		ZonaInicio = zonaInicio,
		ZonaFin = zonaInicio + MJ.AnchoZona,
		Fin = inicio + MJ.DuracionBarra,
	}
	intentos[player] = intento
	NetworkBridge.Server.FireClient("MinijuegoRecoleccion", player, {
		Token = intento.Token,
		Nombre = def.Nombre,
		Inicio = inicio,
		ZonaInicio = intento.ZonaInicio,
		ZonaFin = intento.ZonaFin,
		Fin = intento.Fin,
	})
	-- Si no golpea a tiempo, el intento vence.
	task.delay(MJ.DuracionBarra + 1.5, function()
		if intentos[player] == intento then
			intentos[player] = nil
			if player.Parent == Players then
				avisar(player, "Se te pasó el momento.")
			end
		end
	end)
end

-- El cliente manda la hora de servidor que veía al tocar. Se usa esa hora para
-- juzgar el acierto (así la latencia no castiga a nadie), pero solo si es
-- creíble: no puede ser del futuro ni de hace más de LatenciaMaxima segundos.
local function golpe(player: Player, token: string, tiempoCliente: number?)
	local intento = intentos[player]
	if not intento or intento.Token ~= token then
		return
	end
	intentos[player] = nil
	local t = ahora()
	local tol = MJ.ToleranciaLatencia
	local momento = t
	if tiempoCliente then
		local retraso = t - tiempoCliente
		if retraso >= -0.2 and retraso <= MJ.LatenciaMaxima then
			-- La hora del cliente no puede ser más vieja que su latencia real
			-- (medida por el servidor): así no se "estira" la zona verde.
			local ida = math.clamp(player:GetNetworkPing(), 0, MJ.LatenciaMaxima)
			momento = math.max(tiempoCliente, t - (ida * 2 + 0.08))
			tol = 0.05 -- solo el error de sincronización del reloj
		end
	end
	local acierto = momento >= intento.ZonaInicio - tol and momento <= intento.ZonaFin + tol
	if not acierto then
		avisar(player, "¡Fallaste! Probá de nuevo.")
		return
	end
	local nodo, def = intento.Nodo, intento.Def
	-- Revalida: el nodo pudo agotarse, el jugador alejarse o cambiar de herramienta.
	if agotados[nodo] or not cerca(player, nodo) or herramientaEquipada(player) ~= def.Herramienta then
		return
	end
	local nivel = DataManager.NivelProfesion(player, def.Profesion)
	local cantidad = azar:NextInteger(def.CantidadMin, def.CantidadMax) + math.floor(nivel / 10)
	if not DataManager.AddItem(player, def.ItemId, cantidad, "Comun", nil) then
		avisar(player, "Inventario lleno.")
		return
	end
	agotar(nodo, def.Respawn)
	local niveles = DataManager.AddXpProfesion(
		player,
		def.Profesion,
		def.Xp,
		ProfesionesConfig.NivelMaximo,
		CraftingManager.XpPorNivel
	)
	avisar(player, `+{ItemCatalog[def.ItemId].Nombre} x{cantidad}`, "Info")
	if niveles > 0 then
		avisar(
			player,
			`¡{ProfesionesConfig.Profesiones[def.Profesion].Nombre} subió al nivel {DataManager.NivelProfesion(
				player,
				def.Profesion
			)}!`,
			"Oro"
		)
	end
end

------------------------------------------------------------------------
-- Nodos
------------------------------------------------------------------------

local function prepararNodo(objeto: Instance)
	if not objeto:IsA("BasePart") then
		return
	end
	local id = objeto:GetAttribute("Nodo")
	local def = if typeof(id) == "string" then ProfesionesConfig.Nodos[id] else nil
	if not def then
		warn(`[Recoleccion] Nodo {objeto:GetFullName()} sin atributo Nodo válido`)
		return
	end
	local nodo = objeto
	local prompt = nodo:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.Parent = nodo
	prompt.ActionText = "Recolectar"
	prompt.ObjectText = def.Nombre
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ProfesionesConfig.DistanciaNodo
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player: Player)
		iniciarMinijuego(player, nodo, def)
	end)
end

local function crearNodoPrueba(id: string, offset: Vector3)
	local def = ProfesionesConfig.Nodos[id]
	local parte = Instance.new("Part")
	parte.Name = def.Nombre
	parte.Anchored = true
	local esMineral = def.Herramienta == "Pico"
	parte.Size = if esMineral then Vector3.new(4, 3, 4) else Vector3.new(2, 2.5, 2)
	parte.Shape = if esMineral then Enum.PartType.Block else Enum.PartType.Ball
	parte.Material = if esMineral then Enum.Material.Rock else Enum.Material.Grass
	parte.Color = def.Color
	parte.Position = AREA_PRUEBA + offset + Vector3.new(0, parte.Size.Y / 2, 0)
	parte:SetAttribute("Nodo", id)
	parte.Parent = Workspace
	CollectionService:AddTag(parte, TAG_NODO)
end

function RecoleccionManager.Init()
	assert(not iniciado, "RecoleccionManager.Init() se llamó dos veces")
	iniciado = true

	if Pruebas.Activas() and #CollectionService:GetTagged(TAG_NODO) == 0 then
		crearNodoPrueba("VetaHierro", Vector3.new(0, 0, 0))
		crearNodoPrueba("VetaHierro", Vector3.new(8, 0, -6))
		crearNodoPrueba("VetaPlata", Vector3.new(16, 0, 0))
		crearNodoPrueba("HierbaSanadora", Vector3.new(0, 0, -16))
		crearNodoPrueba("HierbaSanadora", Vector3.new(6, 0, -20))
		crearNodoPrueba("FlorLunar", Vector3.new(12, 0, -18))
		crearNodoPrueba("Lino", Vector3.new(-6, 0, -12))
		crearNodoPrueba("Lino", Vector3.new(-10, 0, -18))
	end
	for _, nodo in CollectionService:GetTagged(TAG_NODO) do
		prepararNodo(nodo)
	end
	CollectionService:GetInstanceAddedSignal(TAG_NODO):Connect(prepararNodo)

	NetworkBridge.Server.OnEvent("RecoleccionGolpe", function(player: Player, token: unknown, tiempo: unknown)
		local t = NetworkBridge.Guard.String(token, 64)
		local momento = if tiempo == nil then nil else NetworkBridge.Guard.Number(tiempo, 0, math.huge)
		if t then
			golpe(player, t, momento)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		intentos[player] = nil
	end)
end

return RecoleccionManager
