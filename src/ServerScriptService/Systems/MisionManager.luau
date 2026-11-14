--!strict
-- MisionManager: misiones (Fase 5.2). El servidor decide todo:
--
--   * Aceptar: cerca del NPC que la da, con nivel, con la misión previa
--     completada, sin tenerla activa (ni completada, salvo las repetibles) y
--     con lugar (máximo MisionesConfig.MaxActivas).
--   * Progreso: "Matar" suma cuando muere el enemigo para todos los que
--     participaron (EnemyManager.Derrotado); "Hablar" se cumple al hablarle al
--     NPC; "Recolectar" se cuenta en la mochila al entregar.
--   * Entregar: cerca del NPC de entrega y con todo cumplido. Los ítems de
--     "Recolectar" se quitan (todo o nada) y se dan XP, oro e ítems (si no
--     entran en la mochila, van al buzón).
--
-- El cliente solo pide (MisionAceptar / MisionEntregar / MisionAbandonar).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MisionesConfig = require(ReplicatedStorage.Configs.MisionesConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local DataManager = require(script.Parent.DataManager)
local Buzon = require(script.Parent.Buzon)
local Bonos = require(script.Parent.Monetizacion.Bonos)
local PaseBatallaManager = require(script.Parent.Monetizacion.PaseBatallaManager)
local PaseBatallaConfig = require(game:GetService("ReplicatedStorage").Configs.PaseBatallaConfig)
local NpcFactory = require(script.Parent.NpcFactory)
local EnemyManager = require(script.Parent.Combate.EnemyManager)

type Mision = MisionesConfig.Mision
type Respuesta = Types.Respuesta

local TAG_NPC = "NpcMision"

local MisionManager = {}

local raicesNpc: { [string]: BasePart } = {} -- npcId -> parte para medir distancia
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function cercaDeNpc(player: Player, npcId: string): boolean
	local raizNpc = raicesNpc[npcId]
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raizNpc or not raiz or not raiz:IsA("BasePart") then
		return false
	end
	return (raiz.Position - raizNpc.Position).Magnitude <= MisionesConfig.DistanciaNpc
end

-- ¿Está cumplido el objetivo? (para Recolectar, mira la mochila)
local function cumplido(player: Player, progreso: Types.ProgresoMision, obj: MisionesConfig.Objetivo): boolean
	if obj.Tipo == "Recolectar" then
		return DataManager.CountItem(player, obj.Objetivo) >= obj.Cantidad
	end
	return (progreso.Objetivos[obj.Id] or 0) >= obj.Cantidad
end

-- Motivo por el que no puede aceptar la misión (nil = puede).
local function motivoNoAceptar(player: Player, id: string, mision: Mision): string?
	local datos = DataManager.GetData(player)
	if not datos then
		return "Tus datos todavía no cargaron."
	end
	if datos.MisionesActivas[id] then
		return "Ya tenés esa misión."
	end
	if datos.MisionesCompletadas[id] and not mision.Repetible then
		return "Ya completaste esa misión."
	end
	if datos.Nivel < mision.NivelRequerido then
		return `Necesitás nivel {mision.NivelRequerido}.`
	end
	if mision.Previa and not datos.MisionesCompletadas[mision.Previa] then
		local previa = MisionesConfig.Misiones[mision.Previa]
		return `Primero completá "{if previa then previa.Nombre else mision.Previa}".`
	end
	local activas = 0
	for _ in datos.MisionesActivas do
		activas += 1
	end
	if activas >= MisionesConfig.MaxActivas then
		return `Podés tener hasta {MisionesConfig.MaxActivas} misiones activas.`
	end
	return nil
end

local function aceptar(player: Player, id: string): Respuesta
	local mision = MisionesConfig.Misiones[id]
	if not mision then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if not cercaDeNpc(player, mision.Npc) then
		avisar(player, "Acercate a quien da la misión.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local motivo = motivoNoAceptar(player, id, mision)
	if motivo then
		avisar(player, motivo, "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not DataManager.AceptarMision(player, id) then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	-- Los objetivos de "Hablar" con el mismo NPC que la da se cumplen enseguida.
	for _, obj in mision.Objetivos do
		if obj.Tipo == "Hablar" and obj.Objetivo == mision.Npc then
			DataManager.ProgresoMision(player, id, obj.Id, 1)
		end
	end
	avisar(player, `Nueva misión: {mision.Nombre}`, "Oro")
	return NetworkBridge.Ok(nil)
end

local function entregar(player: Player, id: string): Respuesta
	local mision = MisionesConfig.Misiones[id]
	local datos = DataManager.GetData(player)
	local progreso = datos and datos.MisionesActivas[id]
	if not mision or not datos or not progreso then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local npcEntrega = mision.NpcEntrega or mision.Npc
	if not cercaDeNpc(player, npcEntrega) then
		avisar(player, "Acercate a quien recibe la misión.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	for _, obj in mision.Objetivos do
		if not cumplido(player, progreso, obj) then
			avisar(player, `Todavía falta: {obj.Texto}.`, "Error")
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
	end
	-- Ítems a entregar: todo o nada (se verificó arriba y no hay pausas en medio).
	local quitados: { { Id: string, Cantidad: number } } = {}
	for _, obj in mision.Objetivos do
		if obj.Tipo == "Recolectar" then
			if not DataManager.RemoveItem(player, obj.Objetivo, obj.Cantidad) then
				for _, q in quitados do
					DataManager.AddItem(player, q.Id, q.Cantidad)
				end
				return NetworkBridge.Fail("INTERNAL_ERROR")
			end
			table.insert(quitados, { Id = obj.Objetivo, Cantidad = obj.Cantidad })
		end
	end
	local completadaEn = os.time()
	DataManager.CompletarMision(player, id)
	PaseBatallaManager.SumarXp(player, PaseBatallaConfig.Xp.Mision)

	-- Recompensas.
	local r = mision.Recompensas
	if r.Xp > 0 then
		local niveles = DataManager.AddExperience(player, Bonos.Xp(player, r.Xp))
		if niveles > 0 then
			local nuevo = DataManager.GetData(player)
			avisar(player, `¡Subiste al nivel {if nuevo then nuevo.Nivel else "?"}!`, "Oro")
		end
	end
	if r.Oro > 0 then
		Buzon.DarOro(player, Bonos.Oro(player, r.Oro), `Misión: {mision.Nombre}`)
	end
	local items: { MisionesConfig.RecompensaItem } = r.Items or {}
	for i, item in items do
		local rareza: Types.Rareza = (item.Rareza or "Comun") :: any
		if ItemCatalog[item.ItemId] and not DataManager.AddItem(player, item.ItemId, item.Cantidad, rareza) then
			-- No entra en la mochila: al buzón, con id fijo.
			Buzon.EnviarItem(
				player.UserId,
				{ ItemId = item.ItemId, Cantidad = item.Cantidad, Rareza = rareza },
				`Misión: {mision.Nombre}`,
				`mision:{player.UserId}:{id}:{completadaEn}:{i}`
			)
		end
	end
	avisar(player, `¡Misión completada: {mision.Nombre}! +{r.Xp} XP, +{r.Oro} de oro`, "Oro")
	return NetworkBridge.Ok(nil)
end

local function abandonar(player: Player, id: string): Respuesta
	if not DataManager.AbandonarMision(player, id) then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local mision = MisionesConfig.Misiones[id]
	avisar(player, `Abandonaste "{if mision then mision.Nombre else id}".`)
	return NetworkBridge.Ok(nil)
end

-- Al hablarle a un NPC: cumple los objetivos "Hablar" y abre el diálogo.
local function alHablar(player: Player, npcId: string)
	if not cercaDeNpc(player, npcId) then
		return
	end
	local datos = DataManager.GetData(player)
	if datos then
		for id, progreso in datos.MisionesActivas do
			local mision = MisionesConfig.Misiones[id]
			if not mision then
				continue
			end
			for _, obj in mision.Objetivos do
				if obj.Tipo == "Hablar" and obj.Objetivo == npcId and (progreso.Objetivos[obj.Id] or 0) < 1 then
					DataManager.ProgresoMision(player, id, obj.Id, 1)
					local npc = MisionesConfig.Npcs[npcId]
					avisar(player, `Hablaste con {if npc then npc.Nombre else npcId}.`)
				end
			end
		end
	end
	NetworkBridge.Server.FireClient("MisionDialogo", player, npcId)
end

-- Enemigo derrotado: suma a las misiones de "Matar" de cada participante.
local function alDerrotar(tipo: string, participantes: { Player })
	for _, player in participantes do
		local datos = DataManager.GetData(player)
		if not datos then
			continue
		end
		for id, progreso in datos.MisionesActivas do
			local mision = MisionesConfig.Misiones[id]
			if not mision then
				continue
			end
			for _, obj in mision.Objetivos do
				if obj.Tipo == "Matar" and obj.Objetivo == tipo then
					local actual = progreso.Objetivos[obj.Id] or 0
					if actual < obj.Cantidad then
						DataManager.ProgresoMision(player, id, obj.Id, actual + 1)
						if actual + 1 >= obj.Cantidad then
							avisar(player, `{mision.Nombre}: objetivo cumplido. Volvé a entregarla.`, "Oro")
						end
					end
				end
			end
		end
	end
end

local function registrarNpc(modelo: Instance)
	if not modelo:IsA("Model") then
		return
	end
	local npcId = modelo:GetAttribute("NpcId")
	local raiz = modelo:FindFirstChild("HumanoidRootPart") or modelo.PrimaryPart
	if typeof(npcId) ~= "string" or not raiz or not raiz:IsA("BasePart") then
		return
	end
	raicesNpc[npcId] = raiz
	local prompt = raiz:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	if not prompt.Parent then
		prompt.ActionText = "Hablar"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = raiz
	end
	prompt.Triggered:Connect(function(player: Player)
		alHablar(player, npcId)
	end)
end

function MisionManager.Init()
	assert(not iniciado, "MisionManager.Init() se llamó dos veces")
	iniciado = true

	-- NPCs de la zona de pruebas (en los mapas reales vienen con la etiqueta).
	if Pruebas.Activas() and #CollectionService:GetTagged(TAG_NPC) == 0 then
		for npcId, def in MisionesConfig.Npcs do
			local _, _, modelo =
				NpcFactory.Crear(`Npc_{npcId}`, `{def.Nombre} ({def.Titulo})`, def.Posicion, def.Color, "Hablar")
			modelo:SetAttribute("NpcId", npcId)
			CollectionService:AddTag(modelo, TAG_NPC)
		end
	end
	for _, modelo in CollectionService:GetTagged(TAG_NPC) do
		registrarNpc(modelo)
	end
	CollectionService:GetInstanceAddedSignal(TAG_NPC):Connect(registrarNpc)

	EnemyManager.Derrotado:Connect(alDerrotar)

	local function idValido(valor: unknown): string?
		return NetworkBridge.Guard.OneOf(valor, MisionesConfig.Misiones)
	end
	NetworkBridge.Server.OnInvoke("MisionAceptar", function(player: Player, id: unknown): Respuesta
		local m = idValido(id)
		return if m then aceptar(player, m) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	NetworkBridge.Server.OnInvoke("MisionEntregar", function(player: Player, id: unknown): Respuesta
		local m = idValido(id)
		return if m then entregar(player, m) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	NetworkBridge.Server.OnInvoke("MisionAbandonar", function(player: Player, id: unknown): Respuesta
		local m = idValido(id)
		return if m then abandonar(player, m) else NetworkBridge.Fail("INVALID_ARGS")
	end)
end

return MisionManager
