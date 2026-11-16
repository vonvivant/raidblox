--!strict
-- PiedrasUI: ventana de viaje rápido que abre una piedra de teletransporte.
-- Muestra las piedras que el jugador ya activó y lo que cuesta ir a cada una.
-- El servidor decide: acá solo se pide el viaje por su id.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExploracionConfig = require(ReplicatedStorage.Configs.ExploracionConfig)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

type Destino = { Id: string, Nombre: string, Zona: string, Costo: number }

local jugador = Players.LocalPlayer
local gui = UIKit.Gui("PiedrasUI", 64)
local ventana, contenido = UIKit.Ventana(gui, "Viaje rápido", UDim2.fromScale(0.4, 0.6))

local subtitulo = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 24))
subtitulo.TextXAlignment = Enum.TextXAlignment.Left
subtitulo.TextColor3 = UIKit.Colores.Oro
local saldo = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 26))
saldo.TextXAlignment = Enum.TextXAlignment.Left
saldo.TextColor3 = UIKit.Colores.TextoSuave
local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -54), UDim2.fromOffset(0, 52))

local destinos: { Destino } = {}
local ocupado = false

local function oro(): number
	local v = EstadoCliente.Get("Oro")
	return if typeof(v) == "number" then v else 0
end

local function redibujar()
	UIKit.Limpiar(lista)
	saldo.Text = `Tu oro: {oro()}`
	if #destinos == 0 then
		local vacio = UIKit.Texto(
			lista,
			"Todavía no activaste otra piedra. Buscá las demás en el mapa (M) y tocalas una vez.",
			UDim2.new(1, 0, 0, 60)
		)
		vacio.TextColor3 = UIKit.Colores.TextoSuave
		vacio.TextWrapped = true
		return
	end
	for i, destino in destinos do
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 50)
		f.BackgroundColor3 = UIKit.Colores.Fondo
		f.LayoutOrder = i
		UIKit.Esquinas(f, 6)
		local t = UIKit.Texto(f, `◈ {destino.Nombre}`, UDim2.new(0.65, 0, 0, 24), UDim2.fromOffset(8, 3))
		t.TextXAlignment = Enum.TextXAlignment.Left
		local d = UIKit.Texto(f, destino.Zona, UDim2.new(0.65, 0, 0, 18), UDim2.fromOffset(8, 27))
		d.Font = Enum.Font.Gotham
		d.TextColor3 = UIKit.Colores.TextoSuave
		d.TextXAlignment = Enum.TextXAlignment.Left
		local alcanza = oro() >= destino.Costo
		local b = UIKit.Boton(
			f,
			`{destino.Costo} oro`,
			UDim2.new(0.3, 0, 0, 34),
			UDim2.new(0.68, 0, 0, 8),
			if alcanza then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		b.Activated:Connect(function()
			if ocupado or not alcanza then
				return
			end
			ocupado = true
			local r = NetworkBridge.Client.Invoke("PiedraViajar", destino.Id)
			ocupado = false
			if r.Success then
				ventana.Visible = false
			end
		end)
		f.Parent = lista
	end
end

NetworkBridge.Client.OnEvent("PiedraAbrir", function(_piedraId: any, nombre: any, lista_: any)
	destinos = {}
	if typeof(lista_) == "table" then
		for _, destino in lista_ do
			if typeof(destino) == "table" and ExploracionConfig.Piedras[destino.Id] then
				table.insert(destinos, destino)
			end
		end
	end
	subtitulo.Text = if typeof(nombre) == "string" then `Estás en: {nombre}` else "Piedra de teletransporte"
	redibujar()
	ventana.Visible = true
	UIKit.EnfocarPrimero(ventana)
end)

EstadoCliente.Cambio:Connect(function(campo: string)
	if ventana.Visible and (campo == "Oro" or campo == "*") then
		redibujar()
	end
end)

-- Si el jugador se aleja o muere, la ventana se cierra.
task.spawn(function()
	while true do
		task.wait(0.5)
		if not ventana.Visible then
			continue
		end
		local personaje = jugador.Character
		local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")
		if not humanoide or humanoide.Health <= 0 then
			ventana.Visible = false
		end
	end
end)
