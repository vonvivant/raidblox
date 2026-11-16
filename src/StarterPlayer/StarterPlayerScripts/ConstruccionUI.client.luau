--!strict
-- ConstruccionUI: poner y sacar cosas adentro de tu parcela, y la huerta.
--
-- Cómo se usa: el Arquitecto abre el panel; se elige una pieza y aparece una
-- vista fantasma que sigue al mouse por el piso de la parcela. Clic izquierdo
-- la pone, R la gira, Q sube y E baja, clic derecho o Escape cancela. En modo
-- "sacar", el clic sobre una pieza puesta la saca.
--
-- Los canteros se usan con el cartel de acercarse: si está vacío abre la lista
-- de semillas, y si ya tiene algo plantado cosecha.
--
-- Nada de esto decide nada: el servidor revalida permiso, lugar, superposición
-- y oro en cada pedido.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CFG = require(ReplicatedStorage.Configs.ConstruccionConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local ParcelasConfig = require(ReplicatedStorage.Configs.ParcelasConfig)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local jugador = Players.LocalPlayer
local camara = Workspace.CurrentCamera
local gui = UIKit.Gui("ConstruccionUI", 46)
local ventana, contenido = UIKit.Ventana(gui, "Construir", UDim2.fromScale(0.3, 0.6))
ventana.Visible = false

local ayuda = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 36), UDim2.fromOffset(0, 0))
ayuda.TextWrapped = true
ayuda.TextXAlignment = Enum.TextXAlignment.Left
ayuda.TextColor3 = UIKit.Colores.TextoSuave

local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -76), UDim2.fromOffset(0, 40))
local modoSacar =
	UIKit.Boton(contenido, "Modo sacar: no", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 1, -32), UIKit.Colores.Boton)

local parcelaActual: string? = nil
local piezaElegida: CFG.Pieza? = nil
local giro = 0
local alto = 1
local fantasma: Part? = nil
local sacando = false

------------------------------------------------------------------------
-- Dónde está la parcela en la que estoy parado
------------------------------------------------------------------------

local function parcelaDebajo(): (string?, Vector3?)
	local personaje = jugador.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		return nil, nil
	end
	local mejorId: string? = nil
	local mejorCentro: Vector3? = nil
	local mejorDistancia = math.huge
	for _, barrio in ParcelasConfig.Barrios do
		for numero = 1, ParcelasConfig.CantidadDe(barrio) do
			local centro = ParcelasConfig.Centro(barrio, numero)
			local distancia = (Vector3.new(centro.X, raiz.Position.Y, centro.Z) - raiz.Position).Magnitude
			if distancia < mejorDistancia and distancia <= barrio.Lado then
				mejorDistancia = distancia
				mejorId = ParcelasConfig.Id(barrio.Id, numero)
				mejorCentro = centro
			end
		end
	end
	return mejorId, mejorCentro
end

------------------------------------------------------------------------
-- Vista fantasma
------------------------------------------------------------------------

local function borrarFantasma()
	if fantasma then
		fantasma:Destroy()
		fantasma = nil
	end
end

local function posicionDeseada(centro: Vector3): Vector3?
	local mouse = UserInputService:GetMouseLocation()
	local rayo = camara:ViewportPointToRay(mouse.X, mouse.Y)
	-- Se proyecta sobre el plano horizontal de la parcela, a la altura elegida.
	local planoY = centro.Y + 0.5 + alto
	if math.abs(rayo.Direction.Y) < 0.001 then
		return nil
	end
	local t = (planoY - rayo.Origin.Y) / rayo.Direction.Y
	if t <= 0 then
		return nil
	end
	local punto = rayo.Origin + rayo.Direction * t
	return Vector3.new(CFG.Acomodar(punto.X - centro.X), alto, CFG.Acomodar(punto.Z - centro.Z))
end

local function actualizarFantasma()
	local pieza = piezaElegida
	local id = parcelaActual
	if not pieza or not id then
		borrarFantasma()
		return
	end
	local barrio, numero = ParcelasConfig.Partir(id)
	if not barrio or not numero then
		return
	end
	local centro = ParcelasConfig.Centro(barrio, numero)
	local relativa = posicionDeseada(centro)
	if not relativa then
		return
	end
	if not fantasma then
		local parte = Instance.new("Part")
		parte.Anchored = true
		parte.CanCollide = false
		parte.CanQuery = false
		parte.Transparency = 0.45
		parte.Material = pieza.Material
		parte.Parent = Workspace
		fantasma = parte
	end
	local parte = fantasma :: Part
	parte.Size = CFG.TamanoGirado(pieza, giro)
	parte.Position = centro + Vector3.new(relativa.X, relativa.Y + 0.5, relativa.Z)
	local entra = CFG.Entra(barrio.Lado, pieza, giro, relativa.X, relativa.Y, relativa.Z)
	parte.Color = if entra then Color3.fromRGB(120, 230, 140) else Color3.fromRGB(230, 110, 110)
end

local function poner()
	local pieza = piezaElegida
	local id = parcelaActual
	if not pieza or not id or not fantasma then
		return
	end
	local barrio, numero = ParcelasConfig.Partir(id)
	if not barrio or not numero then
		return
	end
	local centro = ParcelasConfig.Centro(barrio, numero)
	local relativa = fantasma.Position - centro - Vector3.new(0, 0.5, 0)
	task.spawn(function()
		NetworkBridge.Client.Invoke("ParcelaConstruir", id, "Poner", {
			Pieza = pieza.Id,
			X = relativa.X,
			Y = relativa.Y,
			Z = relativa.Z,
			Giro = giro,
		})
	end)
end

local function sacar(parte: BasePart)
	local id = parte:GetAttribute("Parcela")
	local indice = parte:GetAttribute("Indice")
	if typeof(id) ~= "string" or typeof(indice) ~= "number" then
		return
	end
	task.spawn(function()
		NetworkBridge.Client.Invoke("ParcelaConstruir", id, "Quitar", { Indice = indice })
	end)
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------

local function dibujarLista()
	UIKit.Limpiar(lista)
	local categorias = { "Estructura", "Mueble", "Huerta", "Mascotas" }
	for _, categoria in categorias do
		local encabezado = UIKit.Texto(lista, categoria, UDim2.new(1, -8, 0, 22))
		encabezado.TextColor3 = UIKit.Colores.Oro
		encabezado.TextXAlignment = Enum.TextXAlignment.Left
		for _, pieza in CFG.Piezas do
			if pieza.Categoria ~= categoria then
				continue
			end
			local boton = UIKit.Boton(
				lista,
				`{pieza.Nombre} · ${pieza.Precio}`,
				UDim2.new(1, -8, 0, 28),
				nil,
				if piezaElegida == pieza then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
			)
			boton.Activated:Connect(function()
				piezaElegida = pieza
				sacando = false
				modoSacar.Text = "Modo sacar: no"
				borrarFantasma()
				dibujarLista()
			end)
		end
	end
end

modoSacar.Activated:Connect(function()
	sacando = not sacando
	modoSacar.Text = if sacando then "Modo sacar: SÍ" else "Modo sacar: no"
	if sacando then
		piezaElegida = nil
		borrarFantasma()
		dibujarLista()
	end
end)

------------------------------------------------------------------------
-- Huerta
------------------------------------------------------------------------

local menuSemillas, contenidoSemillas = UIKit.Ventana(gui, "Plantar", UDim2.fromScale(0.22, 0.32))
menuSemillas.Visible = false

local function abrirSemillas(parcelaId: string, indice: number)
	UIKit.Limpiar(contenidoSemillas)
	local fila = Instance.new("UIListLayout")
	fila.Padding = UDim.new(0, 6)
	fila.Parent = contenidoSemillas
	for _, cultivo in CFG.Cultivos do
		local item = ItemCatalog[cultivo.Semilla]
		local boton = UIKit.Boton(
			contenidoSemillas,
			`{cultivo.Nombre} · {cultivo.Horas} h`,
			UDim2.new(1, 0, 0, 30),
			nil,
			UIKit.Colores.Boton
		)
		boton.Activated:Connect(function()
			menuSemillas.Visible = false
			task.spawn(function()
				NetworkBridge.Client.Invoke("ParcelaConstruir", parcelaId, "Plantar", {
					Indice = indice,
					Semilla = cultivo.Semilla,
				})
			end)
		end)
		if item then
			boton.Text = `{item.Nombre} → {cultivo.Nombre} ({cultivo.Horas} h)`
		end
	end
	menuSemillas.Visible = true
end

ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, quien: Player)
	if quien ~= jugador or prompt.ObjectText ~= "Cantero" then
		return
	end
	local parte = prompt.Parent
	if not parte or not parte:IsA("BasePart") then
		return
	end
	local parcelaId = parte:GetAttribute("Parcela")
	local indice = parte:GetAttribute("Indice")
	if typeof(parcelaId) ~= "string" or typeof(indice) ~= "number" then
		return
	end
	if prompt.ActionText == "Cosechar" then
		task.spawn(function()
			NetworkBridge.Client.Invoke("ParcelaConstruir", parcelaId, "Cosechar", { Indice = indice })
		end)
		return
	end
	abrirSemillas(parcelaId, indice)
end)

------------------------------------------------------------------------
-- Entrada
------------------------------------------------------------------------

local function alClic(_: string, estado: Enum.UserInputState, entrada: InputObject): Enum.ContextActionResult
	if estado ~= Enum.UserInputState.Begin or not ventana.Visible then
		return Enum.ContextActionResult.Pass
	end
	if entrada.UserInputType == Enum.UserInputType.MouseButton2 then
		piezaElegida = nil
		borrarFantasma()
		dibujarLista()
		return Enum.ContextActionResult.Sink
	end
	if entrada.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return Enum.ContextActionResult.Pass
	end
	if piezaElegida then
		poner()
		return Enum.ContextActionResult.Sink
	end
	if sacando then
		local mouse = UserInputService:GetMouseLocation()
		local rayo = camara:ViewportPointToRay(mouse.X, mouse.Y)
		local resultado = Workspace:Raycast(rayo.Origin, rayo.Direction * 400)
		local parte = resultado and resultado.Instance
		if parte and parte:IsA("BasePart") and parte:GetAttribute("Indice") then
			sacar(parte)
			return Enum.ContextActionResult.Sink
		end
	end
	return Enum.ContextActionResult.Pass
end

local function alTeclado(_: string, estado: Enum.UserInputState, entrada: InputObject): Enum.ContextActionResult
	if estado ~= Enum.UserInputState.Begin or not piezaElegida then
		return Enum.ContextActionResult.Pass
	end
	if entrada.KeyCode == Enum.KeyCode.R then
		giro = (giro + 1) % 4
	elseif entrada.KeyCode == Enum.KeyCode.Q then
		alto = math.clamp(alto + CFG.Paso, 0, CFG.AlturaMaxima)
	elseif entrada.KeyCode == Enum.KeyCode.E then
		alto = math.clamp(alto - CFG.Paso, 0, CFG.AlturaMaxima)
	else
		return Enum.ContextActionResult.Pass
	end
	actualizarFantasma()
	return Enum.ContextActionResult.Sink
end

NetworkBridge.Client.OnEvent("ConstruirPanel", function(abrir: any)
	if abrir ~= true then
		ventana.Visible = false
		piezaElegida = nil
		borrarFantasma()
		return
	end
	ayuda.Text = "Elegí una pieza y hacé clic en tu parcela. R gira, Q sube, E baja, clic derecho cancela."
	dibujarLista()
	ventana.Visible = true
end)

ventana:GetPropertyChangedSignal("Visible"):Connect(function()
	if not ventana.Visible then
		piezaElegida = nil
		sacando = false
		modoSacar.Text = "Modo sacar: no"
		borrarFantasma()
		ContextActionService:UnbindAction("ConstruirClic")
		ContextActionService:UnbindAction("ConstruirTeclas")
		return
	end
	ContextActionService:BindAction(
		"ConstruirClic",
		alClic,
		false,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.MouseButton2
	)
	ContextActionService:BindAction("ConstruirTeclas", alTeclado, false, Enum.KeyCode.R, Enum.KeyCode.Q, Enum.KeyCode.E)
end)

-- Mientras el panel está abierto, el fantasma sigue al mouse.
task.spawn(function()
	while true do
		task.wait(0.05)
		if not ventana.Visible then
			continue
		end
		local id = parcelaDebajo()
		parcelaActual = id
		if piezaElegida and id then
			actualizarFantasma()
		elseif fantasma and not id then
			borrarFantasma()
		end
	end
end)
