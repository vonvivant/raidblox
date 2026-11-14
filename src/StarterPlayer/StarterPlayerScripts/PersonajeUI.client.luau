--!strict
-- PersonajeUI: panel "Personaje" con clase, bando, género y opciones de chat.
--
-- * Clase: abre el selector (en pruebas se cambia libremente).
-- * Bando: muestra el actual. Violeta es neutral; para volver a Violeta desde
--   Rojo o Azul hay que pagar (lo valida el servidor).
-- * Género: Mi avatar / Masculino / Femenino (lo aplica el servidor).
-- * Chat: mostrar/minimizar (posición y tamaño: arrastrando la ventana).
-- * Interfaz (Fase 7): mano (diestro/zurdo), tamaño del HUD, números de
--   combate y minimapa. Se guardan en el perfil; los aplica el módulo Hud.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local MenuLateral = require(ReplicatedStorage.Modules.MenuLateral)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local EventosCliente = require(ReplicatedStorage.Modules.EventosCliente)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local jugador = Players.LocalPlayer
local CFG = GameConfig.Bandos

local gui = UIKit.Gui("PersonajeUI", 62)
local ventana, marcoContenido = UIKit.Ventana(gui, "Personaje", UDim2.fromScale(0.42, 0.78))
local contenido = UIKit.Lista(marcoContenido, UDim2.fromScale(1, 1))
contenido.BackgroundTransparency = 1

local abrir = Instance.new("TextButton")
abrir.Name = "BotonPersonaje"
abrir.BackgroundColor3 = UIKit.Colores.Boton
abrir.TextColor3 = Color3.new(1, 1, 1)
abrir.Font = Enum.Font.GothamBold
abrir.TextScaled = true
abrir.Text = "Personaje"
UIKit.Esquinas(abrir, 6)
MenuLateral.Agregar(abrir, 1)
abrir.Activated:Connect(function()
	ventana.Visible = not ventana.Visible
	if ventana.Visible then
		UIKit.EnfocarPrimero(ventana)
	end
end)

local layout = contenido:FindFirstChildOfClass("UIListLayout")
if layout then
	layout.Padding = UDim.new(0, 8)
end

local orden = 0
local function seccion(titulo: string): Frame
	orden += 1
	local etiqueta = UIKit.Texto(contenido, titulo, UDim2.new(1, 0, 0, 22))
	etiqueta.TextXAlignment = Enum.TextXAlignment.Left
	etiqueta.TextColor3 = Color3.fromRGB(255, 215, 90)
	etiqueta.LayoutOrder = orden
	orden += 1
	local fila = Instance.new("Frame")
	fila.Size = UDim2.new(1, 0, 0, 38)
	fila.BackgroundTransparency = 1
	fila.LayoutOrder = orden
	fila.Parent = contenido
	return fila
end

-- Fila de opciones excluyentes: marca la elegida.
local function opciones(fila: Frame, lista: { { Texto: string, Valor: any } }, alElegir: (any) -> ()): (any) -> ()
	local botones: { [any]: TextButton } = {}
	local ancho = 1 / #lista
	for i, op in lista do
		local b = UIKit.Boton(fila, op.Texto, UDim2.new(ancho, -6, 1, 0), UDim2.new((i - 1) * ancho, 3, 0, 0))
		botones[op.Valor] = b
		b.Activated:Connect(function()
			alElegir(op.Valor)
		end)
	end
	return function(actual: any)
		for valor, b in botones do
			b.BackgroundColor3 = if valor == actual then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		end
	end
end

local function guardar(clave: string, valor: any)
	local r = NetworkBridge.Client.Invoke("GuardarAjuste", clave, valor)
	if not r.Success then
		Avisos.Mostrar("No se pudo guardar el ajuste.", "Error")
	end
end

-- Clase
local filaClase = seccion("Clase")
local botonClase = UIKit.Boton(filaClase, "Cambiar clase", UDim2.new(0.5, -6, 1, 0), UDim2.fromOffset(3, 0))
botonClase.Activated:Connect(function()
	ventana.Visible = false
	EventosCliente.AbrirSelectorClase:Fire()
end)

-- Bando: se elige acá. El servidor decide si se puede (combate, Guerra, espera).
local marcarBando = opciones(seccion("Bando"), {
	{ Texto = "Violeta", Valor = "Violeta" },
	{ Texto = "Rojo", Valor = "Rojo" },
	{ Texto = "Azul", Valor = "Azul" },
}, function(valor)
	NetworkBridge.Client.Invoke("BandoElegir", valor)
end)
orden += 1
local ayudaBando = UIKit.Texto(
	contenido,
	"Violeta: neutral, nadie te puede atacar (si atacás a un rojo pasás a azul, y al revés). Rojo y Azul pelean solo en zonas PvP y en la Guerra. No se cambia en combate ni durante la Guerra.",
	UDim2.new(1, 0, 0, 44)
)
ayudaBando.Font = Enum.Font.Gotham
ayudaBando.TextColor3 = UIKit.Colores.TextoSuave
ayudaBando.TextWrapped = true
ayudaBando.LayoutOrder = orden

local function actualizarBando()
	local bando = jugador:GetAttribute("Bando")
	local nombre = if typeof(bando) == "string" then bando else "Violeta"
	marcarBando(nombre)
	ayudaBando.TextColor3 = (CFG.Colores :: any)[nombre] or UIKit.Colores.TextoSuave
end
jugador:GetAttributeChangedSignal("Bando"):Connect(actualizarBando)
actualizarBando()

-- Género
local marcarGenero = opciones(seccion("Género del personaje"), {
	{ Texto = "Mi avatar", Valor = "Avatar" },
	{ Texto = "Masculino", Valor = "Masculino" },
	{ Texto = "Femenino", Valor = "Femenino" },
}, function(valor)
	guardar("Genero", valor)
end)

-- Chat (la posición y el tamaño se cambian arrastrando la ventana del chat)
local marcarVisible = opciones(seccion("Chat: ventana"), {
	{ Texto = "Mostrar", Valor = true },
	{ Texto = "Minimizar", Valor = false },
}, function(valor)
	guardar("ChatVisible", valor)
end)

-- Interfaz
local marcarMano = opciones(seccion("Interfaz: mano"), {
	{ Texto = "Diestro", Valor = false },
	{ Texto = "Zurdo", Valor = true },
}, function(valor)
	guardar("Zurdo", valor)
end)
local marcarEscala = opciones(seccion("Interfaz: tamaño"), {
	{ Texto = "Chico", Valor = 0.85 },
	{ Texto = "Normal", Valor = 1 },
	{ Texto = "Grande", Valor = 1.15 },
	{ Texto = "Enorme", Valor = 1.3 },
}, function(valor)
	guardar("EscalaUI", valor)
end)
local marcarTextos = opciones(seccion("Números de daño y cura"), {
	{ Texto = "Mostrar", Valor = true },
	{ Texto = "Ocultar", Valor = false },
}, function(valor)
	guardar("TextosCombate", valor)
end)
local marcarGuerra = opciones(seccion("Guerra de Arquitectos"), {
	{ Texto = "Participar", Valor = false },
	{ Texto = "Ignorar", Valor = true },
}, function(valor)
	guardar("IgnorarGuerra", valor)
end)
local marcarMinimapa = opciones(seccion("Minimapa"), {
	{ Texto = "Mostrar", Valor = true },
	{ Texto = "Ocultar", Valor = false },
}, function(valor)
	guardar("Minimapa", valor)
end)

local function actualizarAjustes()
	local ajustes = EstadoCliente.Get("Ajustes")
	if typeof(ajustes) ~= "table" then
		return
	end
	marcarGenero(ajustes.Genero)
	marcarVisible(ajustes.ChatVisible)
	marcarMano(ajustes.Zurdo == true)
	marcarEscala(if typeof(ajustes.EscalaUI) == "number" then ajustes.EscalaUI else 1)
	marcarTextos(ajustes.TextosCombate ~= false)
	marcarMinimapa(ajustes.Minimapa ~= false)
	marcarGuerra(ajustes.IgnorarGuerra == true)
end

EstadoCliente.Cambio:Connect(function(campo: string)
	if campo == "Ajustes" or campo == "*" then
		actualizarAjustes()
	end
end)
actualizarAjustes()
