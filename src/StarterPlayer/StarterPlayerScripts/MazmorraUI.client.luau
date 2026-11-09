--!strict
-- MazmorraUI: panel de la mazmorra en curso (arriba a la derecha).
-- Sala, enemigos que quedan, tiempo, intentos, vida del jefe y botón para salir.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local gui = UIKit.Gui("MazmorraUI", 42)

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.fromScale(0.99, 0.3)
panel.Size = UDim2.fromScale(0.2, 0.21)
panel.BackgroundColor3 = UIKit.Colores.Fondo
panel.BackgroundTransparency = 0.15
panel.Visible = false
UIKit.Esquinas(panel, 10)
panel.Parent = gui
local limite = Instance.new("UISizeConstraint")
limite.MinSize = Vector2.new(220, 150)
limite.Parent = panel

local titulo = UIKit.Texto(panel, "", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 6))
titulo.TextColor3 = Color3.fromRGB(220, 190, 255)
titulo.TextXAlignment = Enum.TextXAlignment.Left
local sala = UIKit.Texto(panel, "", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 32))
sala.TextXAlignment = Enum.TextXAlignment.Left
local detalle = UIKit.Texto(panel, "", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 54))
detalle.TextXAlignment = Enum.TextXAlignment.Left
detalle.TextColor3 = UIKit.Colores.TextoSuave

local fondoJefe = Instance.new("Frame")
fondoJefe.Position = UDim2.fromOffset(8, 78)
fondoJefe.Size = UDim2.new(1, -16, 0, 12)
fondoJefe.BackgroundColor3 = Color3.fromRGB(50, 20, 20)
fondoJefe.BorderSizePixel = 0
fondoJefe.Visible = false
UIKit.Esquinas(fondoJefe, 4)
fondoJefe.Parent = panel
local rellenoJefe = Instance.new("Frame")
rellenoJefe.Size = UDim2.fromScale(1, 1)
rellenoJefe.BackgroundColor3 = Color3.fromRGB(210, 60, 50)
rellenoJefe.BorderSizePixel = 0
UIKit.Esquinas(rellenoJefe, 4)
rellenoJefe.Parent = fondoJefe

local salir = UIKit.Boton(panel, "Salir", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 1, -38), UIKit.Colores.BotonPeligro)
local confirmar = false
salir.Activated:Connect(function()
	if not confirmar then
		confirmar = true
		salir.Text = "¿Salir? Tocá otra vez"
		task.delay(3, function()
			confirmar = false
			salir.Text = "Salir"
		end)
		return
	end
	confirmar = false
	salir.Text = "Salir"
	NetworkBridge.Client.Invoke("MazmorraSalir")
end)

local function reloj(segundos: number): string
	local s = math.max(0, math.floor(segundos))
	return string.format("%d:%02d", s // 60, s % 60)
end

NetworkBridge.Client.OnEvent("MazmorraEstado", function(e: any)
	if typeof(e) ~= "table" then
		panel.Visible = false
		return
	end
	panel.Visible = true
	titulo.Text = tostring(e.Nombre)
	if e.Estado == "Victoria" then
		sala.Text = "¡Victoria!"
		sala.TextColor3 = Color3.fromRGB(255, 215, 90)
		detalle.Text = `Salida automática en {reloj(e.Salida or 0)} (o usá el portal)`
	elseif e.Estado == "Derrota" then
		sala.Text = "Derrota"
		sala.TextColor3 = Color3.fromRGB(240, 90, 80)
		detalle.Text = `Saliendo en {reloj(e.Salida or 0)}`
	elseif e.Estado == "Esperando" then
		sala.Text = "Esperando al grupo…"
		sala.TextColor3 = UIKit.Colores.Texto
		detalle.Text = ""
	else
		sala.TextColor3 = UIKit.Colores.Texto
		sala.Text = `Sala {e.Sala}/{e.TotalSalas}: {e.NombreSala}`
		local enemigos = if e.VidaJefe then "Jefe" else `Enemigos: {e.Restantes}`
		detalle.Text = `{enemigos}  ·  {reloj(e.Tiempo)}  ·  Intentos: {e.Intentos}`
	end
	local vida = e.VidaJefe
	fondoJefe.Visible = typeof(vida) == "number"
	if typeof(vida) == "number" then
		rellenoJefe.Size = UDim2.fromScale(math.clamp(vida, 0, 1), 1)
	end
end)
