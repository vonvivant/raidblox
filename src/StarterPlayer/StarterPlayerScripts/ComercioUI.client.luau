--!strict
-- ComercioUI: comercio directo 1v1.
--
-- * Acercate a otro jugador y activá "Comerciar" (aparece sobre él).
-- * El otro recibe una invitación para aceptar o rechazar.
-- * Cada uno arma su oferta (ítems de la mochila y oro). Cualquier cambio quita
--   los bloqueos.
-- * "Bloquear oferta" → cuando ambos bloquean hay 3 s de espera → "Confirmar".
-- * Si se alejan más de 15 studs, se cancela.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local ItemInfo = require(ReplicatedStorage.Modules.ItemInfo)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local CFG = GameConfig.Comercio
local jugador = Players.LocalPlayer

local gui = UIKit.Gui("ComercioUI", 66)

------------------------------------------------------------------------
-- "Comerciar" sobre los demás jugadores (prompts locales: solo los ve este cliente)
------------------------------------------------------------------------

local function agregarPrompt(otro: Player, personaje: Model)
	local raiz = personaje:WaitForChild("HumanoidRootPart", 10)
	if not raiz or not raiz:IsA("BasePart") then
		return
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "ComerciarRaidBlox"
	pp.ActionText = "Comerciar"
	pp.ObjectText = otro.DisplayName
	pp.KeyboardKeyCode = Enum.KeyCode.T
	pp.GamepadKeyCode = Enum.KeyCode.ButtonY
	pp.HoldDuration = 0.3
	pp.MaxActivationDistance = CFG.DistanciaMaxima - 2
	pp.RequiresLineOfSight = false
	pp.Triggered:Connect(function()
		NetworkBridge.Client.Fire("ComercioSolicitar", otro)
	end)
	pp.Parent = raiz
end

local function seguirJugador(otro: Player)
	if otro == jugador then
		return
	end
	otro.CharacterAdded:Connect(function(personaje: Model)
		agregarPrompt(otro, personaje)
	end)
	if otro.Character then
		task.spawn(agregarPrompt, otro, otro.Character)
	end
end
for _, otro in Players:GetPlayers() do
	seguirJugador(otro)
end
Players.PlayerAdded:Connect(seguirJugador)

------------------------------------------------------------------------
-- Invitación
------------------------------------------------------------------------

local invitacion = Instance.new("Frame")
invitacion.AnchorPoint = Vector2.new(0.5, 0)
invitacion.Position = UDim2.fromScale(0.5, 0.3)
invitacion.Size = UDim2.fromScale(0.3, 0.13)
invitacion.BackgroundColor3 = UIKit.Colores.Fondo
invitacion.Visible = false
invitacion.Parent = gui
UIKit.Esquinas(invitacion, 10)
local textoInvitacion = UIKit.Texto(invitacion, "", UDim2.new(1, -16, 0.45, 0), UDim2.fromOffset(8, 6))
local aceptar = UIKit.Boton(
	invitacion,
	"Aceptar",
	UDim2.new(0.45, 0, 0.35, 0),
	UDim2.fromScale(0.03, 0.55),
	UIKit.Colores.BotonPrimario
)
local rechazar = UIKit.Boton(
	invitacion,
	"Rechazar",
	UDim2.new(0.45, 0, 0.35, 0),
	UDim2.fromScale(0.52, 0.55),
	UIKit.Colores.BotonPeligro
)
local invitador: Player? = nil

local function responder(acepta: boolean)
	local de = invitador
	invitacion.Visible = false
	invitador = nil
	if de then
		NetworkBridge.Client.Fire("ComercioResponder", de, acepta)
	end
end
aceptar.Activated:Connect(function()
	responder(true)
end)
rechazar.Activated:Connect(function()
	responder(false)
end)

NetworkBridge.Client.OnEvent("ComercioInvitacion", function(de: any)
	if typeof(de) ~= "Instance" or not de:IsA("Player") then
		return
	end
	invitador = de
	textoInvitacion.Text = `{de.DisplayName} quiere comerciar con vos.`
	invitacion.Visible = true
	task.delay(CFG.ExpiraInvitacion, function()
		if invitador == de then
			invitacion.Visible = false
			invitador = nil
		end
	end)
end)

------------------------------------------------------------------------
-- Ventana de comercio
------------------------------------------------------------------------

local ventana, contenido = UIKit.Ventana(gui, "Comercio", UDim2.fromScale(0.62, 0.68))
local cerrarVentana = ventana:FindFirstChildOfClass("TextButton")
if cerrarVentana then
	-- Cerrar la ventana es cancelar el comercio.
	cerrarVentana.Activated:Connect(function()
		NetworkBridge.Client.Fire("ComercioCancelar")
	end)
end

local function columna(titulo: string, x: number): (TextLabel, ScrollingFrame, TextLabel, TextLabel)
	local t = UIKit.Texto(contenido, titulo, UDim2.new(0.32, 0, 0, 28), UDim2.fromScale(x, 0))
	local lista = UIKit.Lista(contenido, UDim2.new(0.32, 0, 0.6, 0), UDim2.new(x, 0, 0, 32))
	local oro = UIKit.Texto(contenido, "Oro: 0", UDim2.new(0.32, 0, 0, 26), UDim2.new(x, 0, 0.6, 38))
	oro.TextColor3 = UIKit.Colores.Oro
	local estado = UIKit.Texto(contenido, "", UDim2.new(0.32, 0, 0, 24), UDim2.new(x, 0, 0.6, 66))
	estado.Font = Enum.Font.Gotham
	return t, lista, oro, estado
end

local _, listaMochila, _, _ = columna("Tu mochila (tocá para ofrecer)", 0)
local _, listaMia, oroMia, estadoMio = columna("Tu oferta", 0.34)
local tituloSuya, listaSuya, oroSuya, estadoSuyo = columna("Su oferta", 0.68)

local entradaOro = UIKit.Entrada(contenido, "Oro a ofrecer", UDim2.new(0.2, 0, 0, 34), UDim2.new(0.34, 0, 1, -40))
local bloquear = UIKit.Boton(contenido, "Bloquear oferta", UDim2.new(0.2, 0, 0, 34), UDim2.new(0.56, 0, 1, -40))
local confirmar = UIKit.Boton(
	contenido,
	"Confirmar",
	UDim2.new(0.2, 0, 0, 34),
	UDim2.new(0.78, 0, 1, -40),
	UIKit.Colores.BotonPrimario
)

local miOferta: { Uids: { string }, Oro: number } = { Uids = {}, Oro = 0 }
local confirmarDesde: number? = nil
local abierta = false

local function enviarOferta()
	NetworkBridge.Client.Fire("ComercioOfertar", miOferta.Uids, miOferta.Oro)
end

local function filaItem(lista: ScrollingFrame, item: any, orden: number, alTocar: (() -> ())?)
	local b = UIKit.Boton(lista, ItemInfo.Corto(item), UDim2.new(1, 0, 0, 36))
	b.LayoutOrder = orden
	b.TextColor3 = ItemInfo.Color(item)
	if alTocar then
		b.Activated:Connect(alTocar)
	else
		b.AutoButtonColor = false
		b.Selectable = false
	end
end

local function redibujarMochila()
	UIKit.Limpiar(listaMochila)
	local inv = EstadoCliente.Get("Inventario")
	if typeof(inv) ~= "table" then
		return
	end
	local orden = 0
	for i = 1, inv.MaxSlots do
		local item = inv.Slots[tostring(i)]
		if item and not table.find(miOferta.Uids, item.Uid) then
			orden += 1
			filaItem(listaMochila, item, orden, function()
				if #miOferta.Uids >= CFG.MaxItemsPorLado then
					Avisos.Mostrar(`Máximo {CFG.MaxItemsPorLado} objetos por oferta.`, "Error")
					return
				end
				table.insert(miOferta.Uids, item.Uid)
				enviarOferta()
			end)
		end
	end
end

entradaOro.FocusLost:Connect(function()
	local n = tonumber(entradaOro.Text)
	miOferta.Oro = if n then math.max(0, math.floor(n)) else 0
	entradaOro.Text = if miOferta.Oro > 0 then tostring(miOferta.Oro) else ""
	enviarOferta()
end)
bloquear.Activated:Connect(function()
	NetworkBridge.Client.Fire("ComercioBloquear")
end)
confirmar.Activated:Connect(function()
	NetworkBridge.Client.Fire("ComercioConfirmar")
end)

NetworkBridge.Client.OnEvent("ComercioEstado", function(estado: any)
	if typeof(estado) ~= "table" then
		return
	end
	if estado.Terminado then
		abierta = false
		ventana.Visible = false
		miOferta = { Uids = {}, Oro = 0 }
		entradaOro.Text = ""
		Avisos.Mostrar(tostring(estado.Motivo or "Comercio terminado."), if estado.Exito then "Oro" else "Error")
		return
	end
	if not abierta then
		abierta = true
		ventana.Visible = true
		UIKit.EnfocarPrimero(ventana)
	end
	tituloSuya.Text = `Oferta de {estado.Otro}`

	-- Mi oferta según el servidor (fuente de verdad), oro incluido.
	miOferta.Oro = tonumber(estado.Mia.Oro) or 0
	if not entradaOro:IsFocused() then
		entradaOro.Text = if miOferta.Oro > 0 then tostring(miOferta.Oro) else ""
	end
	miOferta.Uids = {}
	UIKit.Limpiar(listaMia)
	for i, item in estado.Mia.Items do
		table.insert(miOferta.Uids, item.Uid)
		local uid = item.Uid
		filaItem(listaMia, item, i, function()
			local pos = table.find(miOferta.Uids, uid)
			if pos then
				table.remove(miOferta.Uids, pos)
				enviarOferta()
			end
		end)
	end
	miOferta.Oro = estado.Mia.Oro
	oroMia.Text = `Oro: {estado.Mia.Oro}`
	UIKit.Limpiar(listaSuya)
	for i, item in estado.Suya.Items do
		filaItem(listaSuya, item, i, nil)
	end
	oroSuya.Text = `Oro: {estado.Suya.Oro}`

	estadoMio.Text = if estado.ConfirmadoYo
		then "✔ Confirmado"
		elseif estado.BloqueadoYo then "🔒 Bloqueado"
		else "Editando"
	estadoSuyo.Text = if estado.ConfirmadoOtro
		then "✔ Confirmado"
		elseif estado.BloqueadoOtro then "🔒 Bloqueado"
		else "Editando"
	confirmarDesde = if typeof(estado.ConfirmarDesde) == "number" then estado.ConfirmarDesde else nil
	redibujarMochila()
end)

EstadoCliente.Cambio:Connect(function(campo: string)
	if abierta and (campo == "Inventario" or campo == "*") then
		redibujarMochila()
	end
end)

RunService.RenderStepped:Connect(function()
	if not abierta then
		return
	end
	local desde = confirmarDesde
	if not desde then
		confirmar.Text = "Confirmar"
		confirmar.AutoButtonColor = false
		confirmar.BackgroundColor3 = UIKit.Colores.Boton
		return
	end
	local restante = desde - Workspace:GetServerTimeNow()
	if restante > 0 then
		confirmar.Text = `Confirmar ({math.ceil(restante)})`
		confirmar.BackgroundColor3 = UIKit.Colores.Boton
	else
		confirmar.Text = "Confirmar"
		confirmar.AutoButtonColor = true
		confirmar.BackgroundColor3 = UIKit.Colores.BotonPrimario
	end
end)
