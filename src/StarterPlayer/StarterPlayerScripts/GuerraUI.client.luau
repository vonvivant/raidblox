--!strict
-- GuerraUI: interfaz mínima de la Guerra de Arquitectos para poder jugar y
-- probar la partida: progreso de cada equipo, tiempo y recursos que llevás.
-- La interfaz definitiva llega con la Fase 7 (HUD).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui: ScreenGui? = nil
local panelEquipos: Frame? = nil
local etiquetaFase: TextLabel? = nil
local etiquetaCarga: TextLabel? = nil

local function texto(padre: Instance, nombre: string, tam: UDim2, pos: UDim2): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = nombre
	t.Size = tam
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.5
	t.Parent = padre
	return t
end

local function construir()
	if gui then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "GuerraUI"
	g.ResetOnSpawn = false
	g.DisplayOrder = 50

	local fases = texto(g, "Fase", UDim2.fromScale(0.4, 0.04), UDim2.fromScale(0.3, 0.01))
	local equiposFrame = Instance.new("Frame")
	equiposFrame.Name = "Equipos"
	equiposFrame.Size = UDim2.fromScale(0.5, 0.11)
	equiposFrame.Position = UDim2.fromScale(0.25, 0.055)
	equiposFrame.BackgroundTransparency = 1
	equiposFrame.Parent = g
	local lista = Instance.new("UIListLayout")
	lista.FillDirection = Enum.FillDirection.Horizontal
	lista.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lista.Padding = UDim.new(0.02, 0)
	lista.Parent = equiposFrame

	local carga = texto(g, "Carga", UDim2.fromScale(0.28, 0.04), UDim2.fromScale(0.01, 0.9))
	carga.TextXAlignment = Enum.TextXAlignment.Left

	g.Parent = playerGui
	gui = g
	panelEquipos = equiposFrame
	etiquetaFase = fases
	etiquetaCarga = carga
end

local function formatoTiempo(segundos: number): string
	return string.format("%d:%02d", segundos // 60, segundos % 60)
end

local function textoRequisitos(depositado: any, requisitos: any): string
	local partes = {}
	if typeof(requisitos) ~= "table" then
		return ""
	end
	for _, recurso in { "Madera", "Piedra", "Hierro" } do
		local req = requisitos[recurso]
		if typeof(req) == "number" then
			local dep = if typeof(depositado) == "table" and typeof(depositado[recurso]) == "number"
				then depositado[recurso]
				else 0
			table.insert(partes, `{recurso} {dep}/{req}`)
		end
	end
	return table.concat(partes, "  ")
end

type Tarjeta = { Marco: Frame, Titulo: TextLabel, Barra: Frame, Requisitos: TextLabel, Almacen: TextLabel }
local tarjetas: { [string]: Tarjeta } = {}

-- Crea la tarjeta de un equipo una sola vez; después solo se actualizan textos y barra.
local function tarjetaDe(id: string, panel: Frame): Tarjeta
	local existente = tarjetas[id]
	if existente then
		return existente
	end
	local marco = Instance.new("Frame")
	marco.Name = id
	marco.Size = UDim2.fromScale(0.48, 1)
	marco.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
	marco.BackgroundTransparency = 0.3
	local esquinas = Instance.new("UICorner")
	esquinas.CornerRadius = UDim.new(0.15, 0)
	esquinas.Parent = marco

	local titulo = texto(marco, "Titulo", UDim2.fromScale(0.94, 0.3), UDim2.fromScale(0.03, 0.03))
	local barraFondo = Instance.new("Frame")
	barraFondo.Size = UDim2.fromScale(0.94, 0.12)
	barraFondo.Position = UDim2.fromScale(0.03, 0.36)
	barraFondo.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	barraFondo.BorderSizePixel = 0
	barraFondo.Parent = marco
	local barra = Instance.new("Frame")
	barra.Size = UDim2.fromScale(0, 1)
	barra.BorderSizePixel = 0
	barra.Parent = barraFondo

	local req = texto(marco, "Requisitos", UDim2.fromScale(0.94, 0.24), UDim2.fromScale(0.03, 0.52))
	req.Font = Enum.Font.Gotham
	local alm = texto(marco, "Almacen", UDim2.fromScale(0.94, 0.2), UDim2.fromScale(0.03, 0.77))
	alm.Font = Enum.Font.Gotham
	alm.TextColor3 = Color3.fromRGB(190, 190, 205)

	marco.Parent = panel
	local nueva: Tarjeta = { Marco = marco, Titulo = titulo, Barra = barra, Requisitos = req, Almacen = alm }
	tarjetas[id] = nueva
	return nueva
end

local function textoAlmacen(almacen: any): string
	if typeof(almacen) ~= "table" then
		return ""
	end
	local partes = {}
	for _, recurso in { "Madera", "Piedra", "Hierro" } do
		local n = almacen[recurso]
		if typeof(n) == "number" and n > 0 then
			table.insert(partes, `{recurso} {n}`)
		end
	end
	return if #partes > 0 then "Almacén: " .. table.concat(partes, " · ") else ""
end

local function actualizarEquipos(lista: any, totalEtapas: number)
	local panel = panelEquipos
	if not panel or typeof(lista) ~= "table" then
		return
	end
	for _, eq in lista do
		if typeof(eq) ~= "table" or typeof(eq.Id) ~= "string" then
			continue
		end
		local t = tarjetaDe(eq.Id, panel)
		local color = if typeof(eq.Color) == "Color3" then eq.Color else Color3.new(1, 1, 1)
		local etapa = if typeof(eq.Etapa) == "number" then eq.Etapa else 1
		t.Titulo.TextColor3 = color
		t.Titulo.Text = `{eq.Nombre} ({eq.Jugadores}) - {math.min(etapa, totalEtapas)}/{totalEtapas} {eq.EtapaNombre}`
		t.Barra.BackgroundColor3 = color
		t.Barra.Size = UDim2.fromScale(math.clamp((etapa - 1) / totalEtapas, 0, 1), 1)
		t.Requisitos.Text = if etapa > totalEtapas
			then "Castillo terminado"
			else textoRequisitos(eq.Depositado, eq.Requisitos)
		t.Almacen.Text = textoAlmacen(eq.Almacen)
	end
end

NetworkBridge.Client.OnEvent("GuerraEstado", function(estado: any)
	if typeof(estado) ~= "table" then
		return
	end
	construir()
	local fase = estado.Fase
	local restante = estado.TiempoRestante
	local etiqueta = etiquetaFase
	if etiqueta then
		if fase == "Esperando" then
			etiqueta.Text = `Esperando jugadores (mínimo {estado.JugadoresMinimos})`
		elseif fase == "Cuenta" and typeof(restante) == "number" then
			etiqueta.Text = `La guerra empieza en {restante}...`
		elseif fase == "EnCurso" and typeof(restante) == "number" then
			etiqueta.Text = `Guerra de Arquitectos - {formatoTiempo(restante)}`
		elseif fase == "Terminada" then
			etiqueta.Text = if estado.Ganador == "Empate"
				then "¡Empate!"
				elseif estado.Ganador == "Cancelada" then "Partida cancelada"
				else "¡Partida terminada!"
		end
	end
	actualizarEquipos(estado.Equipos, if typeof(estado.TotalEtapas) == "number" then estado.TotalEtapas else 5)
end)

NetworkBridge.Client.OnEvent("GuerraCarga", function(carga: any, capacidad: any)
	if typeof(carga) ~= "table" then
		return
	end
	construir()
	local etiqueta = etiquetaCarga
	if etiqueta then
		local total = (carga.Madera or 0) + (carga.Piedra or 0) + (carga.Hierro or 0)
		etiqueta.Text =
			`Carga {total}/{capacidad}: Madera {carga.Madera or 0} · Piedra {carga.Piedra or 0} · Hierro {carga.Hierro or 0}`
	end
end)
