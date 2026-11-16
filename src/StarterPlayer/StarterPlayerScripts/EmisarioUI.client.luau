--!strict
-- EmisarioUI: recompensas de facción del Emisario (NPC-027). Muestra tu
-- reputación con tu bando y lo que podés canjear por puntos de honor.
-- El servidor valida reputación, honor y cercanía al NPC en cada compra.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ProgresionSocialConfig = require(ReplicatedStorage.Configs.ProgresionSocialConfig)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local CFG = ProgresionSocialConfig

local gui = UIKit.Gui("EmisarioUI", 65)
local ventana, contenido = UIKit.Ventana(gui, "Recompensas de facción", UDim2.fromScale(0.46, 0.66))

local cabecera = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 26))
cabecera.TextXAlignment = Enum.TextXAlignment.Left
cabecera.TextColor3 = UIKit.Colores.Oro
local detalle = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 28))
detalle.TextXAlignment = Enum.TextXAlignment.Left
detalle.TextColor3 = UIKit.Colores.TextoSuave
local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -56), UDim2.fromOffset(0, 54))

local npcId: string? = nil
local ocupado = false

local function numero(campo: string): number
	local v = EstadoCliente.Get(campo)
	return if typeof(v) == "number" then v else 0
end

local function bando(): string
	local v = EstadoCliente.Get("Faccion")
	return if typeof(v) == "string" then v else "Violeta"
end

local function reputacion(): number
	local social = EstadoCliente.Get("Social")
	local mapa = if typeof(social) == "table" then social.Reputacion else nil
	local valor = if typeof(mapa) == "table" then mapa[bando()] else nil
	return if typeof(valor) == "number" then valor else 0
end

local function redibujar()
	UIKit.Limpiar(lista)
	local mia = reputacion()
	local nivel, falta = CFG.NivelDe(mia)
	local miBando = bando()
	if miBando ~= "Rojo" and miBando ~= "Azul" then
		cabecera.Text = "No perteneces a ningún bando"
		detalle.Text = "Elegí Rojo o Azul en el panel Personaje para ganar reputación."
		return
	end
	cabecera.Text = `Bando {miBando} · {nivel} ({mia} de reputación)`
	detalle.Text = if falta > 0
		then `Faltan {falta} para el próximo rango  ·  honor: {numero("PuntosHonor")}`
		else `Rango máximo  ·  honor: {numero("PuntosHonor")}`

	for indice, oferta in CFG.Ofertas do
		local nivelPedido = CFG.NivelDe(oferta.Reputacion)
		local alcanza = mia >= oferta.Reputacion
		local tieneHonor = numero("PuntosHonor") >= oferta.Costo
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 56)
		f.BackgroundColor3 = UIKit.Colores.Fondo
		f.LayoutOrder = indice
		UIKit.Esquinas(f, 6)
		local nombre = oferta.Nombre
		if oferta.ItemId then
			local def = ItemCatalog[oferta.ItemId]
			nombre = `{if def then def.Nombre else oferta.ItemId} x{oferta.Cantidad or 1}`
		end
		local t = UIKit.Texto(f, nombre, UDim2.new(0.68, 0, 0, 24), UDim2.fromOffset(8, 4))
		t.TextXAlignment = Enum.TextXAlignment.Left
		if not alcanza then
			t.TextColor3 = UIKit.Colores.TextoSuave
		end
		local d = UIKit.Texto(
			f,
			if alcanza then oferta.Descripcion else `Pide ser {nivelPedido}`,
			UDim2.new(0.68, 0, 0, 20),
			UDim2.fromOffset(8, 30)
		)
		d.Font = Enum.Font.Gotham
		d.TextColor3 = UIKit.Colores.TextoSuave
		d.TextXAlignment = Enum.TextXAlignment.Left
		local b = UIKit.Boton(
			f,
			`{oferta.Costo} honor`,
			UDim2.new(0.28, 0, 0, 36),
			UDim2.new(0.7, 0, 0, 10),
			if alcanza and tieneHonor then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		b.Activated:Connect(function()
			local id = npcId
			if ocupado or not id or not alcanza or not tieneHonor then
				return
			end
			ocupado = true
			NetworkBridge.Client.Invoke("EmisarioComprar", id, indice)
			ocupado = false
			redibujar()
		end)
		f.Parent = lista
	end
end

-- El servidor manda abrir esta ventana desde el servicio del Emisario.
NetworkBridge.Client.OnEvent("NpcAbrir", function(id: any, arquetipo: any)
	if typeof(id) == "string" and arquetipo == "EmisarioFaccion" then
		npcId = id -- se guarda para la compra; la ventana la abre el servicio
	end
end)

NetworkBridge.Client.OnEvent("NpcVentana", function(nombre: any)
	if nombre ~= "Emisario" then
		return
	end
	redibujar()
	ventana.Visible = true
	UIKit.EnfocarPrimero(ventana)
end)

EstadoCliente.Cambio:Connect(function(campo: string)
	if ventana.Visible and (campo == "Honor" or campo == "Social" or campo == "Faccion" or campo == "*") then
		redibujar()
	end
end)
