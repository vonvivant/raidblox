--!strict
-- GuerraUI: interfaz de la Guerra de Arquitectos (estilo del HUD de la Fase 7).
--
-- * Panel debajo del minimapa (del mismo lado; a la izquierda con "Zurdo"):
--   fase y reloj (rojo en el último minuto) y una tarjeta por reino con su
--   etapa, barra de progreso, lo que falta de cada recurso y el almacén. Tu
--   reino se marca con borde dorado.
-- * Carga: lo que llevás encima, en una pastilla arriba de la barra de acción.
-- Solo muestra lo que manda el servidor (GuerraEstado, GuerraCarga).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Hud = require(ReplicatedStorage.Modules.Hud)

local jugador = Players.LocalPlayer
local playerGui = jugador:WaitForChild("PlayerGui")

local ANCHO = 300
local RECURSOS = { "Madera", "Piedra", "Hierro" }
local ICONOS: { [string]: string } = { Madera = "🪵", Piedra = "🪨", Hierro = "⛓" }
local COLOR_PANEL = Color3.fromRGB(14, 14, 22)
local DORADO = Color3.fromRGB(255, 213, 74)

local gui: ScreenGui? = nil
local panel: Frame? = nil
local pastillaFase: TextLabel? = nil
local pastillaCarga: Frame? = nil
local textoCarga: TextLabel? = nil

local function texto(padre: Instance, tam: UDim2, pos: UDim2, fuente: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = tam
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = fuente or Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.6
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = padre
	return t
end

local function redondear(g: GuiObject, radio: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radio)
	c.Parent = g
end

local function ubicar()
	local p = panel
	if p then
		-- Debajo del minimapa (o arriba de todo si el minimapa está oculto).
		local y = if Hud.Minimapa then 250 else 8
		p.AnchorPoint = Vector2.new(if Hud.Zurdo then 0 else 1, 0)
		p.Position = if Hud.Zurdo then UDim2.fromOffset(8, y) else UDim2.new(1, -8, 0, y)
	end
end

local function construir()
	if gui then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "GuerraUI"
	g.ResetOnSpawn = false
	g.DisplayOrder = 50

	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.Size = UDim2.fromOffset(ANCHO, 0)
	p.AutomaticSize = Enum.AutomaticSize.Y
	p.BackgroundTransparency = 1
	p.Parent = g
	Hud.Registrar(p)
	local lista = Instance.new("UIListLayout")
	lista.Padding = UDim.new(0, 6)
	lista.SortOrder = Enum.SortOrder.LayoutOrder
	lista.Parent = p

	local fase = Instance.new("TextLabel")
	fase.Name = "Fase"
	fase.Size = UDim2.fromOffset(ANCHO, 30)
	fase.BackgroundColor3 = COLOR_PANEL
	fase.BackgroundTransparency = 0.2
	fase.Font = Enum.Font.GothamBlack
	fase.TextScaled = true
	fase.TextColor3 = DORADO
	fase.LayoutOrder = 0
	redondear(fase, 8)
	local margen = Instance.new("UIPadding")
	margen.PaddingTop = UDim.new(0, 5)
	margen.PaddingBottom = UDim.new(0, 5)
	margen.Parent = fase
	fase.Parent = p

	-- Carga: pastilla arriba de la barra de casteo.
	local c = Instance.new("Frame")
	c.Name = "Carga"
	c.AnchorPoint = Vector2.new(0.5, 1)
	c.Position = UDim2.new(0.5, 0, 1, -130)
	c.Size = UDim2.fromOffset(360, 26)
	c.BackgroundColor3 = COLOR_PANEL
	c.BackgroundTransparency = 0.2
	c.Visible = false
	redondear(c, 13)
	c.Parent = g
	Hud.Registrar(c)
	local tc = texto(c, UDim2.new(1, -20, 1, -6), UDim2.fromOffset(10, 3))
	tc.TextXAlignment = Enum.TextXAlignment.Center

	g.Parent = playerGui
	gui = g
	panel = p
	pastillaFase = fase
	pastillaCarga = c
	textoCarga = tc
	ubicar()
end

Hud.Cambio:Connect(ubicar)

local function formatoTiempo(segundos: number): string
	return string.format("%d:%02d", segundos // 60, segundos % 60)
end

type Tarjeta = {
	Marco: Frame,
	Borde: UIStroke,
	Franja: Frame,
	Titulo: TextLabel,
	Etapa: TextLabel,
	Barra: Frame,
	Requisitos: TextLabel,
	Almacen: TextLabel,
}
local tarjetas: { [string]: Tarjeta } = {}

local function tarjetaDe(id: string, orden: number): Tarjeta
	local existente = tarjetas[id]
	if existente then
		return existente
	end
	local marco = Instance.new("Frame")
	marco.Name = id
	marco.Size = UDim2.fromOffset(ANCHO, 92)
	marco.BackgroundColor3 = COLOR_PANEL
	marco.BackgroundTransparency = 0.2
	marco.LayoutOrder = orden
	redondear(marco, 10)
	local borde = Instance.new("UIStroke")
	borde.Thickness = 1
	borde.Color = Color3.fromRGB(70, 70, 95)
	borde.Parent = marco
	local franja = Instance.new("Frame")
	franja.Size = UDim2.new(0, 6, 1, -12)
	franja.Position = UDim2.fromOffset(6, 6)
	franja.BorderSizePixel = 0
	redondear(franja, 3)
	franja.Parent = marco

	local titulo = texto(marco, UDim2.fromOffset(180, 20), UDim2.fromOffset(20, 6))
	local etapa = texto(marco, UDim2.fromOffset(100, 18), UDim2.fromOffset(ANCHO - 110, 7), Enum.Font.GothamMedium)
	etapa.TextXAlignment = Enum.TextXAlignment.Right
	etapa.TextColor3 = Color3.fromRGB(210, 210, 225)

	local fondo = Instance.new("Frame")
	fondo.Size = UDim2.fromOffset(ANCHO - 32, 10)
	fondo.Position = UDim2.fromOffset(20, 32)
	fondo.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
	fondo.BorderSizePixel = 0
	redondear(fondo, 5)
	fondo.Parent = marco
	local barra = Instance.new("Frame")
	barra.Size = UDim2.fromScale(0, 1)
	barra.BorderSizePixel = 0
	redondear(barra, 5)
	barra.Parent = fondo

	local req = texto(marco, UDim2.fromOffset(ANCHO - 32, 18), UDim2.fromOffset(20, 48), Enum.Font.GothamMedium)
	local alm = texto(marco, UDim2.fromOffset(ANCHO - 32, 15), UDim2.fromOffset(20, 70), Enum.Font.Gotham)
	alm.TextColor3 = Color3.fromRGB(175, 175, 195)

	marco.Parent = panel
	local nueva: Tarjeta = {
		Marco = marco,
		Borde = borde,
		Franja = franja,
		Titulo = titulo,
		Etapa = etapa,
		Barra = barra,
		Requisitos = req,
		Almacen = alm,
	}
	tarjetas[id] = nueva
	return nueva
end

local function textoRequisitos(depositado: any, requisitos: any): string
	if typeof(requisitos) ~= "table" then
		return ""
	end
	local partes = {}
	for _, recurso in RECURSOS do
		local req = requisitos[recurso]
		if typeof(req) == "number" and req > 0 then
			local dep = if typeof(depositado) == "table" and typeof(depositado[recurso]) == "number"
				then depositado[recurso]
				else 0
			table.insert(partes, `{ICONOS[recurso]} {dep}/{req}{if dep >= req then " ✔" else ""}`)
		end
	end
	return table.concat(partes, "   ")
end

local function textoAlmacen(almacen: any): string
	if typeof(almacen) ~= "table" then
		return ""
	end
	local partes = {}
	for _, recurso in RECURSOS do
		local n = almacen[recurso]
		if typeof(n) == "number" and n > 0 then
			table.insert(partes, `{ICONOS[recurso]} {n}`)
		end
	end
	return if #partes > 0 then "Almacén: " .. table.concat(partes, "  ") else "Almacén vacío"
end

local function actualizarEquipos(lista: any, totalEtapas: number)
	if not panel or typeof(lista) ~= "table" then
		return
	end
	local miEquipo = if jugador.Team then jugador.Team.Name else nil
	for i, eq in lista do
		if typeof(eq) ~= "table" or typeof(eq.Id) ~= "string" then
			continue
		end
		local t = tarjetaDe(eq.Id, i)
		local color = if typeof(eq.Color) == "Color3" then eq.Color else Color3.new(1, 1, 1)
		local etapa = if typeof(eq.Etapa) == "number" then eq.Etapa else 1
		local mio = miEquipo ~= nil and (eq.Nombre == miEquipo or eq.Id == miEquipo)
		t.Franja.BackgroundColor3 = color
		t.Titulo.TextColor3 = color
		t.Titulo.Text = `{eq.Nombre} · {eq.Jugadores} 👤`
		t.Etapa.Text = if etapa > totalEtapas
			then "¡Completo!"
			else `{math.min(etapa, totalEtapas)}/{totalEtapas} {eq.EtapaNombre}`
		t.Borde.Color = if mio then DORADO else Color3.fromRGB(70, 70, 95)
		t.Borde.Thickness = if mio then 2 else 1
		t.Barra.BackgroundColor3 = color
		TweenService
			:Create(
				t.Barra,
				TweenInfo.new(0.4),
				{ Size = UDim2.fromScale(math.clamp((etapa - 1) / totalEtapas, 0, 1), 1) }
			)
			:Play()
		t.Requisitos.Text = if etapa > totalEtapas
			then "🏰 Castillo terminado"
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
	local etiqueta = pastillaFase
	if etiqueta then
		etiqueta.TextColor3 = DORADO
		if fase == "Esperando" then
			etiqueta.Text = `⏳ Esperando jugadores (mínimo {estado.JugadoresMinimos})`
		elseif fase == "Cuenta" and typeof(restante) == "number" then
			etiqueta.Text = `⚔ La guerra empieza en {restante}...`
		elseif fase == "EnCurso" and typeof(restante) == "number" then
			etiqueta.Text = `🏗 Guerra de Arquitectos · {formatoTiempo(restante)}`
			if restante <= 60 then
				etiqueta.TextColor3 = Color3.fromRGB(255, 110, 100)
			end
		elseif fase == "Terminada" then
			etiqueta.Text = if estado.Ganador == "Empate"
				then "🤝 ¡Empate!"
				elseif estado.Ganador == "Cancelada" then "Partida cancelada"
				else "🏆 ¡Partida terminada!"
		end
	end
	actualizarEquipos(estado.Equipos, if typeof(estado.TotalEtapas) == "number" then estado.TotalEtapas else 5)
end)

NetworkBridge.Client.OnEvent("GuerraCarga", function(carga: any, capacidad: any)
	if typeof(carga) ~= "table" then
		return
	end
	construir()
	local m, et = pastillaCarga, textoCarga
	if m and et then
		local madera, piedra, hierro = carga.Madera or 0, carga.Piedra or 0, carga.Hierro or 0
		local total = madera + piedra + hierro
		m.Visible = true
		et.Text =
			`Carga {total}/{capacidad}   {ICONOS.Madera} {madera}   {ICONOS.Piedra} {piedra}   {ICONOS.Hierro} {hierro}`
		et.TextColor3 = if typeof(capacidad) == "number" and total >= capacidad
			then Color3.fromRGB(255, 170, 70)
			else Color3.new(1, 1, 1)
	end
end)
