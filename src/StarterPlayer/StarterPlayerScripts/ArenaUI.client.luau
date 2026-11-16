--!strict
-- ArenaUI: cartel de la arena clasificatoria (NPC-038).
--
-- En cola muestra el modo, el rating y cuánto llevás esperando, con un botón
-- para salir. En partida muestra la ronda, el marcador, cuántos quedan en pie
-- de cada lado y el tiempo. El servidor manda todo; acá solo se dibuja.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local gui = UIKit.Gui("ArenaUI", 43)

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.fromScale(0.5, 0.04)
panel.Size = UDim2.fromScale(0.26, 0.13)
panel.BackgroundColor3 = UIKit.Colores.Fondo
panel.BackgroundTransparency = 0.15
panel.Visible = false
UIKit.Esquinas(panel, 10)
panel.Parent = gui
local limite = Instance.new("UISizeConstraint")
limite.MinSize = Vector2.new(260, 96)
limite.MaxSize = Vector2.new(420, 160)
limite.Parent = panel

local titulo = UIKit.Texto(panel, "", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 6))
titulo.TextColor3 = Color3.fromRGB(255, 170, 120)

local marcador = UIKit.Texto(panel, "", UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 30))

local detalle = UIKit.Texto(panel, "", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 62))
detalle.TextColor3 = UIKit.Colores.TextoSuave

local salir = UIKit.Boton(
	panel,
	"Salir de la cola",
	UDim2.new(1, -16, 0, 26),
	UDim2.new(0, 8, 1, -32),
	UIKit.Colores.BotonPeligro
)
salir.Visible = false
salir.Activated:Connect(function()
	NetworkBridge.Client.Fire("ArenaSalirCola")
end)

local function reloj(segundos: number): string
	local s = math.max(0, math.floor(segundos))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function fase(e: { [string]: any }): string
	if e.Fase == "Preparacion" then
		return `Preparate… {reloj(e.Segundos or 0)}`
	elseif e.Fase == "Jugando" then
		return `En juego · {reloj(e.Segundos or 0)}`
	elseif e.Fase == "Pausa" then
		return `Próxima ronda en {reloj(e.Segundos or 0)}`
	end
	return "Terminada"
end

NetworkBridge.Client.OnEvent("ArenaEstado", function(e: any)
	if typeof(e) ~= "table" then
		panel.Visible = false
		return
	end
	panel.Visible = true
	local estado: { [string]: any } = e
	if estado.Fase == "Cola" then
		titulo.Text = `Arena {tostring(estado.Modo)} · buscando rivales`
		marcador.Text = `{tostring(estado.Rango)} · {tostring(estado.Rating)}`
		detalle.Text = `Esperando {reloj(estado.Espera or 0)}`
		salir.Visible = true
		return
	end
	salir.Visible = false
	titulo.Text = `{tostring(estado.Nombre)} · ronda {tostring(estado.Ronda)}/{tostring(estado.Rondas)}`
	marcador.Text = `{tostring(estado.MisRondas)} — {tostring(estado.RondasRival)}`
	detalle.Text = `En pie: {tostring(estado.Vivos)} vs {tostring(estado.VivosRival)}  ·  {fase(estado)}`
end)
