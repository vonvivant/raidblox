--!strict
-- VozUI: escucha, canales de voz e indicador de quién habla.
--
-- * Escucha: AudioListener en la cámara -> AudioDeviceOutput (lo local; el
--   servidor ya trae la salida de los canales sin distancia).
-- * No te escuchás a vos mismo: se cortan, solo en este cliente, los cables
--   que salen de tu propio micrófono.
-- * Silenciar a alguien: baja a 0 su micrófono, solo para vos.
-- * Parlante 🔊 sobre la cabeza de quien habla (AudioAnalyzer local).
-- * Botón "Voz": elegir canal (Proximidad / Grupo / Hermandad / Zona),
--   apagar tu micrófono y silenciar jugadores.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VoiceChatService = game:GetService("VoiceChatService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local MenuLateral = require(ReplicatedStorage.Modules.MenuLateral)

local jugador = Players.LocalPlayer
local CFG = GameConfig.Voz
local NOMBRES: { [string]: string } = {
	Proximidad = "Proximidad (cerca)",
	Grupo = "Grupo",
	Hermandad = "Hermandad (este servidor)",
	Zona = "Zona (todo el servidor)",
}

type Estado = { Canal: string, Grupo: boolean, Hermandad: boolean, Oyentes: number }
local estado: Estado = { Canal = "Proximidad", Grupo = false, Hermandad = false, Oyentes = -1 }
local silenciados: { [number]: boolean } = {}
local microApagado = false
local sinVoz = false -- la cuenta no tiene chat de voz

------------------------------------------------------------------------
-- Escucha
------------------------------------------------------------------------

local escucha: AudioListener? = nil
local function armarEscucha()
	local camara = Workspace.CurrentCamera
	if not camara then
		return
	end
	if escucha and escucha.Parent == camara then
		return
	end
	if escucha then
		escucha:Destroy()
	end
	local l = Instance.new("AudioListener")
	l.Name = "VozEscucha"
	local salida = Instance.new("AudioDeviceOutput")
	salida.Name = "VozEscuchaSalida"
	salida.Parent = l
	local cable = Instance.new("Wire")
	cable.SourceInstance = l
	cable.TargetInstance = salida
	cable.Parent = l
	l.Parent = camara
	escucha = l
end
armarEscucha()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(armarEscucha)

------------------------------------------------------------------------
-- Micrófonos: eco propio, silenciar e indicador
------------------------------------------------------------------------

type Seguido = { Microfono: AudioDeviceInput, Analizador: AudioAnalyzer, Jugador: Player }
local seguidos: { [Player]: Seguido } = {}
local carpetaLocal = Instance.new("Folder")
carpetaLocal.Name = "VozLocal"
carpetaLocal.Parent = jugador:WaitForChild("PlayerScripts")

local function cortarEco(microfono: AudioDeviceInput)
	local function revisar(hijo: Instance)
		-- Cables del servidor que salen de MI micrófono: los corto solo acá.
		if hijo:IsA("Wire") and hijo.SourceInstance == microfono and hijo.Parent == microfono then
			hijo:Destroy()
		end
	end
	for _, hijo in microfono:GetChildren() do
		revisar(hijo)
	end
	microfono.ChildAdded:Connect(revisar)
end

local function aplicarVolumen(s: Seguido)
	if s.Jugador ~= jugador then
		s.Microfono.Volume = if silenciados[s.Jugador.UserId] then 0 else 1
	end
end

local function seguir(otro: Player, microfono: AudioDeviceInput)
	local previo = seguidos[otro]
	if previo then
		previo.Analizador:Destroy()
	end
	local analizador = Instance.new("AudioAnalyzer")
	analizador.Name = `Analizador_{otro.UserId}`
	analizador.Parent = carpetaLocal
	local cable = Instance.new("Wire")
	cable.SourceInstance = microfono
	cable.TargetInstance = analizador
	cable.Parent = analizador
	local s = { Microfono = microfono, Analizador = analizador, Jugador = otro }
	seguidos[otro] = s
	if otro == jugador then
		cortarEco(microfono)
		microfono.Muted = microApagado
	else
		aplicarVolumen(s)
	end
end

local function vigilar(otro: Player)
	local function probar(hijo: Instance)
		if hijo:IsA("AudioDeviceInput") then
			seguir(otro, hijo)
		end
	end
	for _, hijo in otro:GetChildren() do
		probar(hijo)
	end
	otro.ChildAdded:Connect(probar)
end
for _, otro in Players:GetPlayers() do
	vigilar(otro)
end
Players.PlayerAdded:Connect(vigilar)
Players.PlayerRemoving:Connect(function(otro: Player)
	local s = seguidos[otro]
	if s then
		s.Analizador:Destroy()
		seguidos[otro] = nil
	end
end)

-- Parlante sobre la cabeza.
local parlantes: { [Player]: BillboardGui } = {}
local function parlanteDe(otro: Player): BillboardGui?
	local cabeza = otro.Character and otro.Character:FindFirstChild("Head")
	if not cabeza or not cabeza:IsA("BasePart") then
		return nil
	end
	local b = parlantes[otro]
	if b and b.Adornee == cabeza and b.Parent then
		return b
	end
	if b then
		b:Destroy()
	end
	local nuevo = Instance.new("BillboardGui")
	nuevo.Name = "VozParlante"
	nuevo.Adornee = cabeza
	nuevo.Size = UDim2.fromOffset(34, 34)
	nuevo.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	nuevo.AlwaysOnTop = true
	nuevo.MaxDistance = 120
	nuevo.Enabled = false
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Text = "🔊"
	t.Parent = nuevo
	nuevo.Parent = carpetaLocal
	parlantes[otro] = nuevo
	return nuevo
end

local acumulado = 0
local fase = 0
RunService.Heartbeat:Connect(function(dt: number)
	acumulado += dt
	fase += dt
	if acumulado < 0.1 then
		return
	end
	acumulado = 0
	for otro, s in seguidos do
		local habla = s.Analizador.RmsLevel > CFG.UmbralHablando
			and not (otro ~= jugador and silenciados[otro.UserId])
			and not (otro == jugador and microApagado)
		local b = parlanteDe(otro)
		if b then
			b.Enabled = habla
			if habla then
				-- Late un poco mientras habla.
				local escala = 1 + 0.12 * math.sin(fase * 12)
				b.Size = UDim2.fromOffset(34 * escala, 34 * escala)
			end
		end
	end
end)

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------

local gui = UIKit.Gui("VozUI", 60)
local abrir = Instance.new("TextButton")
abrir.Name = "BotonVoz"
abrir.BackgroundColor3 = UIKit.Colores.Boton
abrir.TextColor3 = Color3.new(1, 1, 1)
abrir.Font = Enum.Font.GothamBold
abrir.TextScaled = true
abrir.Text = "🎙 Voz"
UIKit.Esquinas(abrir, 6)
MenuLateral.Agregar(abrir, 5)

local ventana, contenido = UIKit.Ventana(gui, "Chat de voz", UDim2.fromScale(0.36, 0.62))
local aviso = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 34))
aviso.TextColor3 = UIKit.Colores.TextoSuave
local canales = Instance.new("Frame")
canales.Position = UDim2.fromOffset(0, 38)
canales.Size = UDim2.new(1, 0, 0, 4 * 36)
canales.BackgroundTransparency = 1
canales.Parent = contenido
local layoutCanales = Instance.new("UIListLayout")
layoutCanales.Padding = UDim.new(0, 4)
layoutCanales.SortOrder = Enum.SortOrder.LayoutOrder
layoutCanales.Parent = canales
local botonesCanal: { [string]: TextButton } = {}
for i, c in CFG.Canales do
	local b = UIKit.Boton(canales, NOMBRES[c] or c, UDim2.new(1, 0, 0, 32))
	b.LayoutOrder = i
	botonesCanal[c] = b
	b.Activated:Connect(function()
		NetworkBridge.Client.Invoke("VozCanal", c)
	end)
end
local botonMicro = UIKit.Boton(contenido, "", UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 38 + 4 * 36 + 6))
local tituloLista = UIKit.Texto(
	contenido,
	"Silenciar jugadores (solo para vos)",
	UDim2.new(1, 0, 0, 22),
	UDim2.fromOffset(0, 38 + 4 * 36 + 46)
)
tituloLista.TextColor3 = Color3.fromRGB(255, 215, 90)
local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -(38 + 4 * 36 + 72)), UDim2.fromOffset(0, 38 + 4 * 36 + 72))

local function dibujar()
	local oyentes = if estado.Oyentes < 0
		then "te oye quien esté cerca"
		elseif estado.Oyentes == 0 then "ahora no te oye nadie"
		else `te oyen {estado.Oyentes}`
	aviso.Text = if sinVoz
		then "Tu cuenta no tiene chat de voz activo (13+ verificado). Igual podés silenciar a otros."
		else `Hablás por {NOMBRES[estado.Canal] or estado.Canal}: {oyentes}.`
	abrir.Text = if sinVoz then "🔇 Sin voz" else `{if microApagado then "🔇" else "🎙"} {estado.Canal}`
	botonMicro.Visible = not sinVoz
	for c, b in botonesCanal do
		local habilitado = (c ~= "Grupo" or estado.Grupo) and (c ~= "Hermandad" or estado.Hermandad)
		b.BackgroundColor3 = if c == estado.Canal
			then UIKit.Colores.BotonPrimario
			elseif habilitado then UIKit.Colores.Boton
			else UIKit.Colores.Fondo
		b.TextColor3 = if habilitado then UIKit.Colores.Texto else UIKit.Colores.TextoSuave
	end
	botonMicro.Text = if microApagado
		then "🔇 Micrófono apagado (tocá para prender)"
		else "🎙 Micrófono prendido"
	botonMicro.BackgroundColor3 = if microApagado then UIKit.Colores.BotonPeligro else UIKit.Colores.Boton

	UIKit.Limpiar(lista)
	local orden = 0
	for _, otro in Players:GetPlayers() do
		if otro == jugador then
			continue
		end
		orden += 1
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 34)
		f.BackgroundColor3 = UIKit.Colores.Fondo
		f.LayoutOrder = orden
		UIKit.Esquinas(f, 6)
		local t = UIKit.Texto(f, otro.DisplayName, UDim2.new(0.6, 0, 1, -8), UDim2.fromOffset(8, 4))
		t.TextXAlignment = Enum.TextXAlignment.Left
		local mudo = silenciados[otro.UserId] == true
		local b = UIKit.Boton(
			f,
			if mudo then "Silenciado" else "Silenciar",
			UDim2.new(0.36, 0, 1, -8),
			UDim2.new(0.62, 0, 0, 4),
			if mudo then UIKit.Colores.BotonPeligro else nil
		)
		local uid = otro.UserId
		b.Activated:Connect(function()
			if silenciados[uid] then
				silenciados[uid] = nil
			else
				silenciados[uid] = true
			end
			local s = seguidos[otro]
			if s then
				aplicarVolumen(s)
			end
			dibujar()
		end)
		f.Parent = lista
	end
	if orden == 0 then
		UIKit.Texto(lista, "No hay otros jugadores.", UDim2.new(1, 0, 0, 30)).TextColor3 = UIKit.Colores.TextoSuave
	end
end

botonMicro.Activated:Connect(function()
	microApagado = not microApagado
	local s = seguidos[jugador]
	if s then
		s.Microfono.Muted = microApagado
	end
	dibujar()
end)

abrir.Activated:Connect(function()
	ventana.Visible = not ventana.Visible
	if ventana.Visible then
		dibujar()
		UIKit.EnfocarPrimero(ventana)
	end
end)
Players.PlayerAdded:Connect(function()
	if ventana.Visible then
		dibujar()
	end
end)
Players.PlayerRemoving:Connect(function()
	if ventana.Visible then
		task.defer(dibujar)
	end
end)

NetworkBridge.Client.OnEvent("VozEstado", function(nuevo: any)
	if typeof(nuevo) ~= "table" or typeof(nuevo.Canal) ~= "string" then
		return
	end
	estado = {
		Canal = nuevo.Canal,
		Grupo = nuevo.Grupo == true,
		Hermandad = nuevo.Hermandad == true,
		Oyentes = if typeof(nuevo.Oyentes) == "number" then nuevo.Oyentes else -1,
	}
	dibujar()
end)

-- Si la cuenta no tiene voz, el panel lo explica (el resto igual funciona:
-- podés escuchar a otros si tu cuenta lo permite).
task.spawn(function()
	local ok, habilitada = pcall(function(): boolean
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(jugador.UserId)
	end)
	if ok and not habilitada then
		sinVoz = true
		dibujar()
	end
end)
dibujar()
