--!strict
-- LlegadaTeleport: al llegar a un place por teleport, reemplaza la pantalla de
-- carga por defecto de Roblox por la temática que traía el jugador y la
-- desvanece cuando el juego terminó de cargar. Corre en ReplicatedFirst para
-- ejecutarse antes que todo lo demás.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local gui = TeleportService:GetArrivingTeleportGui()
if not gui then
	return -- entrada normal: se usa la pantalla de Roblox
end

ReplicatedFirst:RemoveDefaultLoadingScreen()
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
task.wait(1)

local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
for _, objeto in gui:GetDescendants() do
	if objeto:IsA("TextLabel") then
		TweenService:Create(objeto, info, { TextTransparency = 1 }):Play()
	elseif objeto:IsA("Frame") then
		TweenService:Create(objeto, info, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.9)
gui:Destroy()
