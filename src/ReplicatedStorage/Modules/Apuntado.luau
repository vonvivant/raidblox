--!strict
-- Apuntado: estado compartido del modo apuntado (mira) en el cliente.
--
--   Activo  el jugador eligió el modo apuntado (Q / clic en el stick derecho).
--   Libre   el mouse está suelto (ventana abierta, escribiendo o Alt apretado):
--           se ve el cursor y el clic izquierdo no ataca.
--
-- Lo maneja MiraUI; CombatClient lo lee para mandar el punto de la mira al
-- servidor, que es quien decide a quién le pega. Solo para el cliente.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Signal = require(script.Parent.Signal)

local Apuntado = {}

Apuntado.Activo = false
Apuntado.Libre = false
Apuntado.Cambio = Signal.new() :: Signal.Signal<boolean>

local ALCANCE = 400
local parametros = RaycastParams.new()
parametros.FilterType = Enum.RaycastFilterType.Exclude
parametros.RespectCanCollide = true -- ignora zonas invisibles y adornos sin colisión

local function rayo(): RaycastResult?
	local camara = Workspace.CurrentCamera
	if not camara then
		return nil
	end
	local personaje = Players.LocalPlayer.Character
	parametros.FilterDescendantsInstances = if personaje then { personaje } else {}
	local vista = camara.ViewportSize
	local r = camara:ViewportPointToRay(vista.X / 2, vista.Y / 2)
	return Workspace:Raycast(r.Origin, r.Direction * ALCANCE, parametros)
end

-- Punto del mundo bajo la mira (o lejos, en la dirección de la mira).
function Apuntado.Punto(): Vector3?
	local camara = Workspace.CurrentCamera
	if not camara then
		return nil
	end
	local impacto = rayo()
	if impacto then
		return impacto.Position
	end
	local vista = camara.ViewportSize
	local r = camara:ViewportPointToRay(vista.X / 2, vista.Y / 2)
	return r.Origin + r.Direction * ALCANCE
end

-- Personaje o enemigo (Model con Humanoid) bajo la mira, si hay.
function Apuntado.ModeloEnMira(): Model?
	local impacto = rayo()
	local parte: Instance? = impacto and impacto.Instance
	while parte and parte ~= Workspace do
		if parte:IsA("Model") and parte:FindFirstChildOfClass("Humanoid") then
			return parte
		end
		parte = parte.Parent
	end
	return nil
end

function Apuntado.SetActivo(activo: boolean)
	if Apuntado.Activo == activo then
		return
	end
	Apuntado.Activo = activo
	Apuntado.Cambio:Fire(activo)
end

return Apuntado
