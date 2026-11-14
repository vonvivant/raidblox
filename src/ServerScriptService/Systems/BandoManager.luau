--!strict
-- BandoManager: bandos de los jugadores y reglas de PvP.
--
--   * Violeta: neutral. NADIE lo puede atacar.
--   * Rojo y Azul: se pueden atacar entre sí, pero solo si ambos están en
--     contexto PvP (dentro de una parte con la etiqueta "ZonaPvP", en una zona
--     con PvP = true en ZoneConfig, o jugando una partida de la Guerra).
--   * Un Violeta que ataca a un Rojo pasa a ser Azul; si ataca a un Azul, pasa a
--     ser Rojo. En la Guerra, un Violeta que aporta a un reino pasa a ese bando.
--   * El jugador también elige su bando (Violeta, Rojo o Azul) desde el panel
--     Personaje: gratis, pero no en combate ni durante la Guerra, y con una
--     espera entre cambios (GameConfig.Bandos.EsperaEntreCambios).
--
-- Este módulo no depende de CombatManager (evita dependencias circulares): el
-- combate le pasa su función "en combate" con SetEnCombate.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local ZoneConfig = require(ReplicatedStorage.Configs.ZoneConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local DataManager = require(script.Parent.DataManager)

type Bando = Types.Bando

local CFG = GameConfig.Bandos

local BandoManager = {}

local zonaActual: string? = nil
local enCombate: (Player) -> boolean = function(_player: Player): boolean
	return false
end
local iniciado = false
local ultimoCambio: { [Player]: number } = {} -- os.clock() del último cambio elegido

function BandoManager.SetEnCombate(fn: (Player) -> boolean)
	enCombate = fn
end

function BandoManager.De(player: Player): Bando
	local datos = DataManager.GetData(player)
	return if datos then datos.Faccion else "Violeta"
end

local function dentroDe(parte: BasePart, posicion: Vector3): boolean
	local local_ = parte.CFrame:PointToObjectSpace(posicion)
	local medio = parte.Size / 2
	-- Hacia arriba se cuenta un margen amplio: la parte suele ser el piso de la arena.
	return math.abs(local_.X) <= medio.X
		and math.abs(local_.Z) <= medio.Z
		and local_.Y >= -medio.Y - 2
		and local_.Y <= medio.Y + 40
end

-- ¿El jugador está en un lugar donde vale el PvP?
function BandoManager.EnZonaPvP(player: Player): boolean
	if player:GetAttribute("EnGuerra") == true then
		return true
	end
	local zona = if zonaActual then ZoneConfig.Zonas[zonaActual] else nil
	if zona and (zona :: any).PvP == true then
		return true
	end
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return false
	end
	for _, parte in CollectionService:GetTagged(CFG.TagZonaPvP) do
		if parte:IsA("BasePart") and dentroDe(parte, raiz.Position) then
			return true
		end
	end
	return false
end

-- Rojo contra Azul (sin importar dónde estén).
function BandoManager.SonRivales(a: Player, b: Player): boolean
	local ba, bb = BandoManager.De(a), BandoManager.De(b)
	return ba ~= "Violeta" and bb ~= "Violeta" and ba ~= bb
end

-- Rivales y ambos en contexto PvP: se pueden dañar (lo usan las áreas).
function BandoManager.SonHostiles(a: Player, b: Player): boolean
	return BandoManager.SonRivales(a, b) and BandoManager.EnZonaPvP(a) and BandoManager.EnZonaPvP(b)
end

-- ¿Puede el atacante elegir al objetivo como enemigo? (incluye al Violeta que
-- va a convertirse al atacar).
function BandoManager.PuedeAtacar(atacante: Player, objetivo: Player): boolean
	if atacante == objetivo then
		return false
	end
	local bo = BandoManager.De(objetivo)
	if bo == "Violeta" then
		return false -- el neutral es intocable
	end
	if not BandoManager.EnZonaPvP(atacante) or not BandoManager.EnZonaPvP(objetivo) then
		return false
	end
	-- En la Guerra no se pega a un compañero de equipo (ni siquiera un Violeta).
	if
		atacante:GetAttribute("EnGuerra") == true
		and objetivo:GetAttribute("EnGuerra") == true
		and atacante.Team ~= nil
		and atacante.Team == objetivo.Team
	then
		return false
	end
	local ba = BandoManager.De(atacante)
	return ba == "Violeta" or ba ~= bo
end

-- Se llama cuando el ataque se concreta: el Violeta toma el bando contrario
-- al de su víctima.
function BandoManager.AlAtacar(atacante: Player, objetivo: Player)
	if BandoManager.De(atacante) ~= "Violeta" then
		return
	end
	local bo = BandoManager.De(objetivo)
	local nuevo: Bando = if bo == "Rojo" then "Azul" elseif bo == "Azul" then "Rojo" else "Violeta"
	if nuevo ~= "Violeta" and DataManager.SetFaccion(atacante, nuevo) then
		NetworkBridge.Server.FireClient(
			"Notificacion",
			atacante,
			`¡Atacaste a un {string.lower(bo)}! Ahora sos del bando {string.upper(nuevo)}.`,
			"Info"
		)
	end
end

-- La Guerra lo llama cuando un Violeta aporta a un reino.
function BandoManager.Unirse(player: Player, bando: Bando): boolean
	if BandoManager.De(player) ~= "Violeta" or bando == "Violeta" then
		return false
	end
	if DataManager.SetFaccion(player, bando) then
		NetworkBridge.Server.FireClient(
			"Notificacion",
			player,
			`Aportaste al Reino {bando}: ahora sos del bando {string.upper(bando)}.`,
			"Info"
		)
		return true
	end
	return false
end

-- El jugador elige su bando desde el panel Personaje. Es gratis, pero no se
-- puede en combate, durante una partida de la Guerra, ni más seguido que
-- GameConfig.Bandos.EsperaEntreCambios.
local function elegir(player: Player, bando: Bando): Types.Respuesta
	local function rechazar(texto: string): Types.Respuesta
		NetworkBridge.Server.FireClient("Notificacion", player, texto, "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if BandoManager.De(player) == bando then
		return NetworkBridge.Ok(nil)
	end
	if enCombate(player) then
		return rechazar("No podés cambiar de bando en combate.")
	end
	if player:GetAttribute("EnGuerra") == true then
		return rechazar("No podés cambiar de bando durante la Guerra.")
	end
	local ahora = os.clock()
	local espera = (ultimoCambio[player] or -math.huge) + CFG.EsperaEntreCambios - ahora
	if espera > 0 then
		return rechazar(`Podés volver a cambiar de bando en {math.ceil(espera)} s.`)
	end
	if not DataManager.SetFaccion(player, bando) then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	ultimoCambio[player] = ahora
	NetworkBridge.Server.FireClient("Notificacion", player, `Ahora sos del bando {string.upper(bando)}.`, "Info")
	return NetworkBridge.Ok(nil)
end

-- Arena PvP de prueba (solo con Pruebas.Activas() y si el mapa no tiene una).
local function crearArenaPrueba()
	local carpeta = Instance.new("Folder")
	carpeta.Name = "ArenaPvP"
	local piso = Instance.new("Part")
	piso.Name = "ZonaPvP"
	piso.Anchored = true
	piso.Size = Vector3.new(50, 1, 50)
	piso.Position = Vector3.new(-75, 0.5, -45)
	piso.Color = Color3.fromRGB(120, 30, 40)
	piso.Material = Enum.Material.Slate
	piso.Parent = carpeta
	CollectionService:AddTag(piso, CFG.TagZonaPvP)
	-- Postes en las esquinas, con luz roja.
	for _, esquina in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		local poste = Instance.new("Part")
		poste.Anchored = true
		poste.Size = Vector3.new(2, 10, 2)
		poste.Position = piso.Position + Vector3.new(esquina.X * 24, 5.5, esquina.Z * 24)
		poste.Color = Color3.fromRGB(255, 60, 60)
		poste.Material = Enum.Material.Neon
		poste.Parent = carpeta
	end
	local cartel = Instance.new("BillboardGui")
	cartel.Size = UDim2.fromScale(16, 3)
	cartel.StudsOffset = Vector3.new(0, 9, 0)
	cartel.MaxDistance = 150
	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBlack
	texto.TextColor3 = Color3.fromRGB(255, 90, 90)
	texto.TextStrokeTransparency = 0.2
	texto.Text = "ARENA PvP — Rojo vs Azul (el Violeta es intocable)"
	texto.Parent = cartel
	cartel.Parent = piso
	carpeta.Parent = Workspace
end

function BandoManager.Init(zona: string?)
	assert(not iniciado, "BandoManager.Init() se llamó dos veces")
	iniciado = true
	zonaActual = zona
	if Pruebas.Activas() and #CollectionService:GetTagged(CFG.TagZonaPvP) == 0 then
		crearArenaPrueba()
	end
	NetworkBridge.Server.OnInvoke("BandoElegir", function(player: Player, bando: unknown): Types.Respuesta
		local elegido = NetworkBridge.Guard.OneOf(bando, CFG.Colores)
		if not elegido then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return elegir(player, elegido :: Bando)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		ultimoCambio[player] = nil
	end)
end

return BandoManager
