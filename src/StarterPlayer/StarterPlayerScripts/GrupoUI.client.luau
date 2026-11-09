--!strict
-- GrupoUI: grupo (party).
--
-- * Botón "Grupo" (al lado de "Personaje"): tu grupo (expulsar, pasar el
--   liderazgo, salir) y los jugadores del servidor para invitar.
-- * Marcos de los compañeros a la izquierda, con su vida (leída del Humanoid).
-- * Aviso de invitación con Aceptar / Rechazar (vence a los 30 s).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local jugador = Players.LocalPlayer
local CFG = GameConfig.Grupos

type Estado = { Id: string, Lider: number, Miembros: { { UserId: number, Nombre: string } } }

local gui = UIKit.Gui("GrupoUI", 61)
local estado: Estado? = nil

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------

local ventana, contenido = UIKit.Ventana(gui, "Grupo", UDim2.fromScale(0.4, 0.66))
local tituloGrupo = UIKit.Texto(contenido, "Tu grupo", UDim2.new(1, 0, 0, 22))
tituloGrupo.TextXAlignment = Enum.TextXAlignment.Left
tituloGrupo.TextColor3 = Color3.fromRGB(255, 215, 90)
local listaGrupo = UIKit.Lista(contenido, UDim2.new(1, 0, 0.36, -26), UDim2.fromOffset(0, 26))
local salir = UIKit.Boton(
	contenido,
	"Salir del grupo",
	UDim2.new(0.4, 0, 0, 32),
	UDim2.new(0.6, 0, 0.36, 4),
	UIKit.Colores.BotonPeligro
)
salir.Activated:Connect(function()
	NetworkBridge.Client.Invoke("GrupoSalir")
end)
local tituloJugadores =
	UIKit.Texto(contenido, "Jugadores en el servidor", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0.36, 42))
tituloJugadores.TextXAlignment = Enum.TextXAlignment.Left
tituloJugadores.TextColor3 = Color3.fromRGB(255, 215, 90)
local listaJugadores = UIKit.Lista(contenido, UDim2.new(1, 0, 0.64, -68), UDim2.new(0, 0, 0.36, 68))

local abrir = Instance.new("TextButton")
abrir.Name = "BotonGrupo"
abrir.Position = UDim2.fromScale(0.115, 0.455)
abrir.Size = UDim2.fromScale(0.08, 0.038)
abrir.BackgroundColor3 = UIKit.Colores.Boton
abrir.TextColor3 = Color3.new(1, 1, 1)
abrir.Font = Enum.Font.GothamBold
abrir.TextScaled = true
abrir.Text = "Grupo"
UIKit.Esquinas(abrir, 6)
abrir.Parent = gui

local function fila(lista: ScrollingFrame, orden: number, texto: string, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 38)
	f.BackgroundColor3 = UIKit.Colores.Fondo
	f.LayoutOrder = orden
	UIKit.Esquinas(f, 6)
	local t = UIKit.Texto(f, texto, UDim2.new(0.48, 0, 1, -8), UDim2.fromOffset(8, 4))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color
	f.Parent = lista
	return f
end

local function esMiembro(userId: number): boolean
	local e = estado
	if not e then
		return false
	end
	for _, m in e.Miembros do
		if m.UserId == userId then
			return true
		end
	end
	return false
end

local function redibujarPanel()
	UIKit.Limpiar(listaGrupo)
	UIKit.Limpiar(listaJugadores)
	local e = estado
	local soyLider = e == nil or e.Lider == jugador.UserId
	salir.Visible = e ~= nil
	if e then
		for i, m in e.Miembros do
			local esLider = m.UserId == e.Lider
			local f = fila(
				listaGrupo,
				i,
				`{if esLider then "👑 " else ""}{m.Nombre}`,
				if m.UserId == jugador.UserId then Color3.fromRGB(130, 230, 130) else Color3.new(1, 1, 1)
			)
			if soyLider and m.UserId ~= jugador.UserId then
				local lider = UIKit.Boton(f, "Hacer líder", UDim2.new(0.24, 0, 1, -8), UDim2.new(0.5, 0, 0, 4))
				local echar = UIKit.Boton(
					f,
					"Expulsar",
					UDim2.new(0.24, 0, 1, -8),
					UDim2.new(0.75, 0, 0, 4),
					UIKit.Colores.BotonPeligro
				)
				local uid = m.UserId
				lider.Activated:Connect(function()
					NetworkBridge.Client.Invoke("GrupoLider", uid)
				end)
				echar.Activated:Connect(function()
					NetworkBridge.Client.Invoke("GrupoExpulsar", uid)
				end)
			end
		end
	else
		fila(listaGrupo, 1, "No estás en un grupo.", UIKit.Colores.TextoSuave)
	end

	local orden = 0
	local lleno = e ~= nil and #e.Miembros >= CFG.MaxMiembros
	for _, otro in Players:GetPlayers() do
		if otro == jugador or esMiembro(otro.UserId) then
			continue
		end
		orden += 1
		local f = fila(listaJugadores, orden, otro.DisplayName, Color3.new(1, 1, 1))
		if soyLider and not lleno and otro:GetAttribute("GrupoId") == nil then
			local b = UIKit.Boton(
				f,
				"Invitar",
				UDim2.new(0.3, 0, 1, -8),
				UDim2.new(0.69, 0, 0, 4),
				UIKit.Colores.BotonPrimario
			)
			local uid = otro.UserId
			b.Activated:Connect(function()
				NetworkBridge.Client.Invoke("GrupoInvitar", uid)
			end)
		elseif otro:GetAttribute("GrupoId") ~= nil then
			local t = UIKit.Texto(f, "En otro grupo", UDim2.new(0.3, 0, 1, -10), UDim2.new(0.69, 0, 0, 5))
			t.TextColor3 = UIKit.Colores.TextoSuave
		end
	end
	if orden == 0 then
		fila(listaJugadores, 1, "No hay otros jugadores.", UIKit.Colores.TextoSuave)
	end
end

abrir.Activated:Connect(function()
	ventana.Visible = not ventana.Visible
	if ventana.Visible then
		redibujarPanel()
		UIKit.EnfocarPrimero(ventana)
	end
end)
Players.PlayerAdded:Connect(function()
	if ventana.Visible then
		redibujarPanel()
	end
end)
Players.PlayerRemoving:Connect(function()
	if ventana.Visible then
		task.defer(redibujarPanel)
	end
end)

------------------------------------------------------------------------
-- Marcos de los compañeros
------------------------------------------------------------------------

local marcos = Instance.new("Frame")
marcos.Name = "MarcosGrupo"
marcos.Position = UDim2.fromScale(0.01, 0.67)
marcos.Size = UDim2.fromScale(0.16, 0.2)
marcos.BackgroundTransparency = 1
marcos.Parent = gui
local layoutMarcos = Instance.new("UIListLayout")
layoutMarcos.Padding = UDim.new(0, 4)
layoutMarcos.Parent = marcos

type Marco = { UserId: number, Relleno: Frame, Texto: TextLabel }
local marcosActivos: { Marco } = {}

local function redibujarMarcos()
	UIKit.Limpiar(marcos)
	table.clear(marcosActivos)
	local e = estado
	if not e then
		return
	end
	for i, m in e.Miembros do
		if m.UserId == jugador.UserId then
			continue
		end
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 30)
		f.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		f.BackgroundTransparency = 0.3
		f.LayoutOrder = i
		UIKit.Esquinas(f, 4)
		local fondo = Instance.new("Frame")
		fondo.Position = UDim2.new(0, 4, 0.55, 0)
		fondo.Size = UDim2.new(1, -8, 0.35, 0)
		fondo.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
		fondo.BorderSizePixel = 0
		fondo.Parent = f
		local relleno = Instance.new("Frame")
		relleno.Size = UDim2.fromScale(1, 1)
		relleno.BackgroundColor3 = Color3.fromRGB(60, 190, 80)
		relleno.BorderSizePixel = 0
		relleno.Parent = fondo
		local texto = Instance.new("TextLabel")
		texto.Position = UDim2.fromOffset(4, 0)
		texto.Size = UDim2.new(1, -8, 0.55, 0)
		texto.BackgroundTransparency = 1
		texto.Font = Enum.Font.GothamBold
		texto.TextScaled = true
		texto.TextXAlignment = Enum.TextXAlignment.Left
		texto.TextColor3 = Color3.new(1, 1, 1)
		texto.Text = `{if m.UserId == e.Lider then "👑 " else ""}{m.Nombre}`
		texto.Parent = f
		f.Parent = marcos
		table.insert(marcosActivos, { UserId = m.UserId, Relleno = relleno, Texto = texto })
	end
end

local acumulado = 0
RunService.Heartbeat:Connect(function(dt: number)
	acumulado += dt
	if acumulado < 0.2 then
		return
	end
	acumulado = 0
	for _, marco in marcosActivos do
		local otro = Players:GetPlayerByUserId(marco.UserId)
		local personaje = otro and otro.Character
		local h = personaje and personaje:FindFirstChildOfClass("Humanoid")
		local fraccion = if h and h.MaxHealth > 0 then math.clamp(h.Health / h.MaxHealth, 0, 1) else 0
		marco.Relleno.Size = UDim2.fromScale(fraccion, 1)
		marco.Relleno.BackgroundColor3 = if fraccion > 0.5
			then Color3.fromRGB(60, 190, 80)
			elseif fraccion > 0.25 then Color3.fromRGB(230, 180, 50)
			else Color3.fromRGB(210, 60, 50)
	end
end)

------------------------------------------------------------------------
-- Invitación
------------------------------------------------------------------------

local aviso = Instance.new("Frame")
aviso.AnchorPoint = Vector2.new(0.5, 0)
aviso.Position = UDim2.fromScale(0.5, 0.12)
aviso.Size = UDim2.fromScale(0.32, 0.1)
aviso.BackgroundColor3 = UIKit.Colores.Fondo
aviso.Visible = false
UIKit.Esquinas(aviso, 10)
aviso.Parent = gui
local textoAviso = UIKit.Texto(aviso, "", UDim2.new(1, -16, 0.45, 0), UDim2.fromOffset(8, 4))
local aceptar =
	UIKit.Boton(aviso, "Aceptar", UDim2.new(0.45, 0, 0.4, 0), UDim2.fromScale(0.04, 0.54), UIKit.Colores.BotonPrimario)
local rechazar =
	UIKit.Boton(aviso, "Rechazar", UDim2.new(0.45, 0, 0.4, 0), UDim2.fromScale(0.51, 0.54), UIKit.Colores.BotonPeligro)
local invitacionDe: number? = nil
local contadorAviso = 0

local function responder(acepta: boolean)
	local de = invitacionDe
	aviso.Visible = false
	invitacionDe = nil
	if de then
		NetworkBridge.Client.Invoke("GrupoResponder", de, acepta)
	end
end
aceptar.Activated:Connect(function()
	responder(true)
end)
rechazar.Activated:Connect(function()
	responder(false)
end)

NetworkBridge.Client.OnEvent("GrupoInvitacion", function(deUserId: any, nombre: any)
	if typeof(deUserId) ~= "number" or typeof(nombre) ~= "string" then
		return
	end
	invitacionDe = deUserId
	textoAviso.Text = `{nombre} te invita a su grupo`
	aviso.Visible = true
	contadorAviso += 1
	local este = contadorAviso
	task.delay(CFG.ExpiraInvitacion, function()
		if contadorAviso == este then
			aviso.Visible = false
			invitacionDe = nil
		end
	end)
end)

------------------------------------------------------------------------
-- Estado
------------------------------------------------------------------------

NetworkBridge.Client.OnEvent("GrupoEstado", function(nuevo: any)
	estado = if typeof(nuevo) == "table" then nuevo :: Estado else nil
	redibujarMarcos()
	if ventana.Visible then
		redibujarPanel()
	end
end)
