--!strict
-- Hud: ajustes de interfaz compartidos por todo el HUD (Fase 7). Solo cliente.
--
-- * Escala: cada ScreenGui registrada lleva un UIScale. La escala se calcula
--   de la pantalla (base 1280×720) por el ajuste "EscalaUI" del jugador.
-- * Zurdo: espeja el HUD (menú lateral a la derecha, minimapa a la izquierda,
--   y en táctil la barra de acción va a la izquierda).
-- * TextosCombate / Minimapa: mostrar u ocultar.
-- Los ajustes viven en el perfil (Ajustes) y se cambian en el panel Personaje.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EstadoCliente = require(script.Parent.EstadoCliente)
local Signal = require(script.Parent.Signal)

local Hud = {}

Hud.Cambio = Signal.new() :: Signal.Signal<>

Hud.Zurdo = false
Hud.EscalaUsuario = 1
Hud.TextosCombate = true
Hud.Minimapa = true

local escalas: { UIScale } = {}

local function escalaPantalla(): number
	local camara = Workspace.CurrentCamera
	if not camara then
		return 1
	end
	local v = camara.ViewportSize
	return math.clamp(math.min(v.X / 1280, v.Y / 720), 0.55, 1.4)
end

-- Escala final (pantalla × ajuste). Para HUD diseñado en píxeles.
function Hud.Escala(): number
	return escalaPantalla() * Hud.EscalaUsuario
end

-- En táctil no hay teclas: se ocultan los atajos y la barra cambia de lugar.
function Hud.EsTactil(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function aplicar()
	local e = Hud.Escala()
	for i = #escalas, 1, -1 do
		local s = escalas[i]
		if s.Parent then
			s.Scale = e
		else
			table.remove(escalas, i)
		end
	end
end

-- Agrega un UIScale a una ScreenGui (o un marco) diseñada en píxeles.
function Hud.Registrar(gui: Instance)
	local s = Instance.new("UIScale")
	s.Scale = Hud.Escala()
	s.Parent = gui
	table.insert(escalas, s)
end

local function leerAjustes()
	local a = EstadoCliente.Get("Ajustes")
	if typeof(a) ~= "table" then
		return
	end
	local zurdo = a.Zurdo == true
	local escala = if typeof(a.EscalaUI) == "number" then a.EscalaUI else 1
	local textos = a.TextosCombate ~= false
	local mini = a.Minimapa ~= false
	if zurdo ~= Hud.Zurdo or escala ~= Hud.EscalaUsuario or textos ~= Hud.TextosCombate or mini ~= Hud.Minimapa then
		Hud.Zurdo, Hud.EscalaUsuario, Hud.TextosCombate, Hud.Minimapa = zurdo, escala, textos, mini
		aplicar()
		Hud.Cambio:Fire()
	end
end

EstadoCliente.Cambio:Connect(function(campo: string)
	if campo == "Ajustes" or campo == "*" then
		leerAjustes()
	end
end)
leerAjustes()

local function conectarCamara()
	local camara = Workspace.CurrentCamera
	if camara then
		camara:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			aplicar()
			Hud.Cambio:Fire()
		end)
	end
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(conectarCamara)
conectarCamara()

return Hud
