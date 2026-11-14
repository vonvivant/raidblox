--!strict
-- MonturaManager: monturas (caballo gratis, Dragón de Fuego con pase).
--
-- * Montar: G o el botón "Montura". Solo fuera de combate (5 s sin pelear),
--   vivo y sin estar en la Guerra.
-- * Montado: el modelo va soldado al personaje, sube la altura de cadera y la
--   velocidad pasa a la de la montura (el anti-cheat la conoce).
-- * Se desmonta al recibir o hacer daño, al morir, o volviendo a tocar G.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local MonetizacionConfig = require(ReplicatedStorage.Configs.MonetizacionConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local AntiCheat = require(script.Parent.Parent.AntiCheat)
local CombatManager = require(script.Parent.Parent.Combate.CombatManager)
local PasesManager = require(script.Parent.PasesManager)

type Respuesta = Types.Respuesta
type Montado = { Id: string, Modelo: Model, Humanoid: Humanoid, Velocidad: number, Cadera: number }

local CFG = MonetizacionConfig
local ALTURA = 1.8

local MonturaManager = {}

local montados: { [Player]: Montado } = {}
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function pieza(
	modelo: Model,
	raiz: BasePart,
	tam: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Size = tam
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = raiz.CFrame * offset
	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = raiz
	soldadura.Part1 = p
	soldadura.Parent = p
	p.Parent = modelo
	return p
end

local function construir(id: string, raiz: BasePart): Model
	local def = CFG.Monturas[id]
	local modelo = Instance.new("Model")
	modelo.Name = `Montura_{id}`
	local y = -2.9 - ALTURA / 2
	local color = def.Color
	local oscuro = color:Lerp(Color3.new(0, 0, 0), 0.35)
	-- Cuerpo, cuello y cabeza.
	pieza(modelo, raiz, Vector3.new(2.2, 2, 5), CFrame.new(0, y, 0.3), color)
	pieza(
		modelo,
		raiz,
		Vector3.new(1.2, 2.2, 1.2),
		CFrame.new(0, y + 1.4, -2.3) * CFrame.Angles(math.rad(30), 0, 0),
		color
	)
	local cabeza = pieza(modelo, raiz, Vector3.new(1.3, 1.1, 2), CFrame.new(0, y + 2.4, -3.2), color)
	-- Patas.
	for _, px in { -0.75, 0.75 } do
		for _, pz in { -1.7, 2.1 } do
			pieza(modelo, raiz, Vector3.new(0.5, 2.6, 0.5), CFrame.new(px, y - 2.1, pz), oscuro)
		end
	end
	if def.Fuego then
		-- Alas y llamas.
		for _, lado in { -1, 1 } do
			pieza(
				modelo,
				raiz,
				Vector3.new(4.5, 0.2, 2.6),
				CFrame.new(lado * 3, y + 0.9, 0) * CFrame.Angles(0, 0, math.rad(lado * 18)),
				oscuro,
				Enum.Material.Fabric
			)
		end
		local cola = pieza(modelo, raiz, Vector3.new(0.7, 0.7, 3), CFrame.new(0, y + 0.2, 3.8), color)
		for _, parte in { cabeza, cola } do
			local fuego = Instance.new("ParticleEmitter")
			fuego.Texture = "rbxasset://textures/particles/fire_main.dds"
			fuego.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 60, 20))
			fuego.LightEmission = 0.8
			fuego.Size = NumberSequence.new(1.1, 0)
			fuego.Lifetime = NumberRange.new(0.3, 0.6)
			fuego.Rate = 30
			fuego.Speed = NumberRange.new(2, 4)
			fuego.Parent = parte
		end
		local luz = Instance.new("PointLight")
		luz.Color = Color3.fromRGB(255, 140, 60)
		luz.Range = 14
		luz.Brightness = 1.5
		luz.Parent = cabeza
	else
		-- Montura de cuero.
		pieza(
			modelo,
			raiz,
			Vector3.new(2.3, 0.3, 1.8),
			CFrame.new(0, y + 1.1, 0.2),
			Color3.fromRGB(70, 40, 25),
			Enum.Material.Fabric
		)
	end
	modelo.Parent = raiz.Parent
	return modelo
end

local function desmontar(player: Player, motivo: string?)
	local m = montados[player]
	if not m then
		return
	end
	montados[player] = nil
	m.Modelo:Destroy()
	if m.Humanoid.Parent then
		m.Humanoid.HipHeight = m.Cadera
		if m.Humanoid.WalkSpeed == m.Velocidad then
			m.Humanoid.WalkSpeed = 16
		end
	end
	AntiCheat.SetVelocidadPermitida(player, nil)
	AntiCheat.Gracia(player, 1)
	player:SetAttribute("Montura", nil)
	if motivo then
		avisar(player, motivo)
	end
end

local function puedeUsar(player: Player, id: string): (boolean, string?)
	local def = CFG.Monturas[id]
	if not def then
		return false, nil
	end
	if def.Pase and not PasesManager.Tiene(player, def.Pase) then
		return false, `{def.Nombre} se consigue con el pase de la tienda.`
	end
	local datos = DataManager.GetData(player)
	if not datos or datos.Nivel < def.NivelMinimo then
		return false, `Necesitás nivel {def.NivelMinimo}.`
	end
	return true, nil
end

local function montar(player: Player, id: string): Respuesta
	if montados[player] then
		desmontar(player, nil)
		return NetworkBridge.Ok(nil)
	end
	local ok, motivo = puedeUsar(player, id)
	if not ok then
		if motivo then
			avisar(player, motivo, "Error")
		end
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local personaje = player.Character
	local h = personaje and personaje:FindFirstChildOfClass("Humanoid")
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not h or h.Health <= 0 or not raiz or not raiz:IsA("BasePart") then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if player:GetAttribute("EnGuerra") == true then
		avisar(player, "En la Guerra no se puede montar.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local c = CombatManager.DeJugador(player)
	if c and Workspace:GetServerTimeNow() - c.UltimoCombate < CFG.SegundosSinCombateParaMontar then
		avisar(player, "No podés montar en combate.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local def = CFG.Monturas[id]
	local cadera = h.HipHeight
	AntiCheat.Gracia(player, 1)
	AntiCheat.SetVelocidadPermitida(player, def.Velocidad + 2)
	h.HipHeight = cadera + ALTURA
	h.WalkSpeed = def.Velocidad
	local modelo = construir(id, raiz)
	montados[player] = { Id = id, Modelo = modelo, Humanoid = h, Velocidad = def.Velocidad, Cadera = cadera }
	player:SetAttribute("Montura", id)
	return NetworkBridge.Ok(nil)
end

function MonturaManager.Montado(player: Player): boolean
	return montados[player] ~= nil
end

function MonturaManager.Init()
	assert(not iniciado, "MonturaManager.Init() se llamó dos veces")
	iniciado = true

	NetworkBridge.Server.OnInvoke("MonturaAlternar", function(player: Player, id: unknown): Respuesta
		local m = NetworkBridge.Guard.OneOf(id, CFG.Monturas)
		if not m then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return montar(player, m)
	end)

	-- Pelear desmonta (recibir o hacer daño).
	CombatManager.DanioAplicado:Connect(function(fuente: any, objetivo: any)
		for _, c in { fuente, objetivo } do
			local p = c and c.Player
			if p and montados[p] then
				desmontar(p, "Te bajaste de la montura por el combate.")
			end
		end
	end)
	PasesManager.Cambio:Connect(function(player: Player, clave: string, activo: boolean)
		local m = montados[player]
		if not activo and m then
			local pase = CFG.Monturas[m.Id].Pase
			if pase == clave then
				desmontar(player, nil)
			end
		end
	end)
	local function alEntrar(player: Player)
		player.CharacterRemoving:Connect(function()
			desmontar(player, nil)
		end)
	end
	for _, player in Players:GetPlayers() do
		alEntrar(player)
	end
	Players.PlayerAdded:Connect(alEntrar)
	Players.PlayerRemoving:Connect(function(player: Player)
		montados[player] = nil
	end)
end

return MonturaManager
