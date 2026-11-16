--!strict
-- JuegosUI: ventana de los minijuegos del Crupier (NPC-036).
--
-- Dibuja dos tableros según lo que manda el servidor:
--   * Runas: cuatro runas de color. Primero se enciende la secuencia sola y
--     después el jugador la repite.
--   * Pares: 16 cartas tapadas; se dan vuelta las que el servidor revela.
--
-- El cliente no decide nada: cada toque va al servidor y el estado vuelve de
-- ahí. Si el servidor dice "Mostrando", los botones no responden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CFG = require(ReplicatedStorage.Configs.JuegosConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local gui = UIKit.Gui("JuegosUI", 44)

local ventana, contenido = UIKit.Ventana(gui, "Juegos del Crupier", UDim2.fromScale(0.42, 0.52))
ventana.Visible = false

local titulo = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 0))
titulo.TextColor3 = Color3.fromRGB(150, 225, 165)
titulo.TextXAlignment = Enum.TextXAlignment.Left
local estadoTexto = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 26))
estadoTexto.TextColor3 = UIKit.Colores.TextoSuave
estadoTexto.TextXAlignment = Enum.TextXAlignment.Left

local tablero = Instance.new("Frame")
tablero.BackgroundTransparency = 1
tablero.Position = UDim2.fromOffset(0, 52)
tablero.Size = UDim2.new(1, 0, 1, -94)
tablero.Parent = contenido

local salir =
	UIKit.Boton(contenido, "Salir", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 1, -32), UIKit.Colores.BotonPeligro)

-- Cerrar la ventana (botón Salir o la X) termina la partida en el servidor.
local cerrando = false
local enPartida = false
local function abandonar()
	if cerrando or not enPartida then
		ventana.Visible = false
		return
	end
	cerrando = true
	enPartida = false
	NetworkBridge.Client.Fire("JuegoSalir")
	ventana.Visible = false
	task.delay(0.2, function()
		cerrando = false
	end)
end

salir.Activated:Connect(abandonar)
ventana:GetPropertyChangedSignal("Visible"):Connect(function()
	if not ventana.Visible then
		abandonar()
	end
end)

local runas: { TextButton } = {}
local cartas: { TextButton } = {}
local modo: string? = nil
local bloqueado = false

local function limpiarTablero()
	UIKit.Limpiar(tablero)
	table.clear(runas)
	table.clear(cartas)
end

local function destellar(boton: TextButton, color: Color3)
	local original = boton.BackgroundColor3
	boton.BackgroundColor3 = color
	TweenService:Create(boton, TweenInfo.new(0.45), { BackgroundColor3 = original }):Play()
end

local function armarRunas(colores: number)
	limpiarTablero()
	modo = "Runas"
	local grilla = Instance.new("UIGridLayout")
	grilla.CellSize = UDim2.fromScale(0.48, 0.48)
	grilla.CellPadding = UDim2.fromScale(0.02, 0.02)
	grilla.Parent = tablero
	for i = 1, colores do
		local boton = UIKit.Boton(tablero, "", UDim2.fromScale(0.48, 0.48), nil, CFG.ColoresRuna[i])
		boton.LayoutOrder = i
		boton.Activated:Connect(function()
			if bloqueado then
				return
			end
			destellar(boton, Color3.new(1, 1, 1))
			NetworkBridge.Client.Invoke("JuegoJugar", i)
		end)
		runas[i] = boton
	end
end

local function mostrarSecuencia(secuencia: { number })
	bloqueado = true
	task.spawn(function()
		for _, runa in secuencia do
			local boton = runas[runa]
			if boton then
				destellar(boton, Color3.new(1, 1, 1))
			end
			task.wait(CFG.Runas.MostrarPorRuna)
		end
	end)
end

local function armarCartas()
	limpiarTablero()
	modo = "Pares"
	local grilla = Instance.new("UIGridLayout")
	grilla.CellSize = UDim2.fromScale(0.235, 0.235)
	grilla.CellPadding = UDim2.fromScale(0.015, 0.015)
	grilla.Parent = tablero
	for i = 1, CFG.Cartas() do
		local boton = UIKit.Boton(tablero, "?", UDim2.fromScale(0.235, 0.235), nil, UIKit.Colores.Boton)
		boton.LayoutOrder = i
		boton.Activated:Connect(function()
			if bloqueado then
				return
			end
			NetworkBridge.Client.Invoke("JuegoJugar", i)
		end)
		cartas[i] = boton
	end
end

local function dibujarCartas(vista: { any })
	for i, boton in cartas do
		local valor = vista[i]
		if typeof(valor) == "number" then
			boton.Text = CFG.SimbolosCarta[valor] or tostring(valor)
			boton.BackgroundColor3 = Color3.fromRGB(70, 95, 80)
		else
			boton.Text = "?"
			boton.BackgroundColor3 = UIKit.Colores.Boton
		end
	end
end

NetworkBridge.Client.OnEvent("JuegoEstado", function(e: any)
	if typeof(e) ~= "table" then
		enPartida = false
		ventana.Visible = false
		return
	end
	local estado: { [string]: any } = e
	enPartida = estado.Fase ~= "Fin"
	ventana.Visible = true
	titulo.Text = tostring(estado.Nombre)

	if estado.Fase == "Fin" then
		bloqueado = true
		local record = if estado.EsRecord == true then " ¡Récord!" else ""
		estadoTexto.Text = `{tostring(estado.Motivo)} {tostring(estado.Resultado)} {tostring(estado.Unidad)}.{record}`
		salir.Text = "Cerrar"
		return
	end

	salir.Text = "Salir"
	local record = if typeof(estado.Record) == "number" and estado.Record > 0
		then ` · tu récord: {estado.Record} {tostring(estado.Unidad)}`
		else ""

	if estado.Juego == "Runas" then
		if modo ~= "Runas" or #runas == 0 then
			armarRunas(if typeof(estado.Colores) == "number" then estado.Colores else 4)
		end
		if estado.Mostrando == true then
			estadoTexto.Text = `Ronda {tostring(estado.Ronda)}: mirá la secuencia{record}`
			local secuencia = estado.Secuencia
			if typeof(secuencia) == "table" then
				mostrarSecuencia(secuencia)
			end
		else
			bloqueado = false
			estadoTexto.Text = `Ronda {tostring(estado.Ronda)}: repetila ({tostring(estado.Segundos)} s){record}`
		end
		return
	end

	if modo ~= "Pares" or #cartas == 0 then
		armarCartas()
	end
	bloqueado = false
	estadoTexto.Text = `Intentos {tostring(estado.Intentos)}/{tostring(estado.IntentosMaximos)} · pares {math.floor(
		(if typeof(estado.Resueltos) == "number" then estado.Resueltos else 0) / 2
	)}/{CFG.Pares.Pares} · {tostring(estado.Segundos)} s{record}`
	local vista = estado.Cartas
	if typeof(vista) == "table" then
		dibujarCartas(vista)
		-- Si el par no coincidió, el servidor manda las dos reveladas en `Cartas`
		-- y la verdad en `Tapadas`: se ven un instante y se vuelven a tapar.
		local tapadas = estado.Tapadas
		if estado.Par == false and typeof(tapadas) == "table" then
			bloqueado = true
			task.delay(0.9, function()
				bloqueado = false
				dibujarCartas(tapadas)
			end)
		end
	end
end)
