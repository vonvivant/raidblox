--!strict
-- NpcFactory: NPCs quietos (no combatientes) con nombre y ProximityPrompt.
-- Los usan los NPCs de misiones y los de prueba.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local NpcFactory = {}

-- Crea el NPC mirando hacia `mirarA` (por defecto, el centro del mapa).
-- Devuelve la raíz, el ProximityPrompt y el modelo.
function NpcFactory.Crear(
	nombre: string,
	titulo: string,
	posicion: Vector3,
	color: Color3,
	accion: string,
	mirarA: Vector3?
): (BasePart, ProximityPrompt, Model)
	local modelo: Model
	local ok, resultado = pcall(function()
		local descripcion = Instance.new("HumanoidDescription")
		descripcion.HeadColor = Color3.fromRGB(234, 184, 146)
		descripcion.TorsoColor = color
		descripcion.LeftArmColor = color
		descripcion.RightArmColor = color
		descripcion.LeftLegColor = Color3.fromRGB(40, 40, 50)
		descripcion.RightLegColor = Color3.fromRGB(40, 40, 50)
		return Players:CreateHumanoidModelFromDescription(descripcion, Enum.HumanoidRigType.R15)
	end)
	if ok and typeof(resultado) == "Instance" and resultado:IsA("Model") then
		modelo = resultado
	else
		modelo = Instance.new("Model")
		local cuerpo = Instance.new("Part")
		cuerpo.Name = "HumanoidRootPart"
		cuerpo.Size = Vector3.new(2, 5, 1)
		cuerpo.Color = color
		cuerpo.Parent = modelo
		modelo.PrimaryPart = cuerpo
	end
	modelo.Name = nombre
	local raiz = modelo:FindFirstChild("HumanoidRootPart") :: BasePart
	for _, d in modelo:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = titulo
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.NameDisplayDistance = 60
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local alto = if humanoid then humanoid.HipHeight + raiz.Size.Y / 2 else 2.5
	local pos = posicion + Vector3.new(0, alto, 0)
	local objetivo = mirarA or Vector3.zero
	modelo:PivotTo(CFrame.lookAt(pos, Vector3.new(objetivo.X, pos.Y, objetivo.Z)))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = accion
	prompt.ObjectText = titulo
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = raiz
	modelo.Parent = Workspace
	return raiz, prompt, modelo
end

return NpcFactory
