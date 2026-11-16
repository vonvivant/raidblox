--!strict
-- BarberoUI: ventana del Barbero (NPC-029). Elegís color de piel, peinado y
-- marca, lo ves en tu personaje al instante (solo para vos) y recién al
-- confirmar el servidor cobra y lo guarda.
--
-- Las opciones de peinado y marca que todavía no tienen un accesorio subido al
-- Catálogo aparecen como "próximamente" y no se pueden elegir.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AparienciaConfig = require(ReplicatedStorage.Configs.AparienciaConfig)
local Avisos = require(ReplicatedStorage.Modules.Avisos)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)

local CFG = AparienciaConfig.Barbero
local PARTES = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local jugador = Players.LocalPlayer
local gui = UIKit.Gui("BarberoUI", 66)
local ventana, contenido = UIKit.Ventana(gui, "Barbero", UDim2.fromScale(0.42, 0.62))

local aviso = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 22))
aviso.TextXAlignment = Enum.TextXAlignment.Left
aviso.TextColor3 = UIKit.Colores.TextoSuave
local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -76), UDim2.fromOffset(0, 26))
local confirmar =
	UIKit.Boton(contenido, "Confirmar", UDim2.new(0.5, -4, 0, 40), UDim2.new(0, 0, 1, -44), UIKit.Colores.BotonPrimario)
local cancelar = UIKit.Boton(contenido, "Cancelar", UDim2.new(0.5, -4, 0, 40), UDim2.new(0.5, 4, 1, -44))

local npcId: string? = nil
local elegidos: { Piel: string?, Peinado: string?, Marca: string? } = {}
local ocupado = false

local function estiloActual(): { Piel: string?, Peinado: string?, Marca: string? }
	local valor = EstadoCliente.Get("Apariencia")
	if typeof(valor) ~= "table" then
		return {}
	end
	return { Piel = valor.Piel, Peinado = valor.Peinado, Marca = valor.Marca }
end

-- Vista previa local del color de piel (el resto necesita el servidor).
local function previsualizar()
	local personaje = jugador.Character
	local piel = if elegidos.Piel then CFG.Pieles[elegidos.Piel] else nil
	if not personaje then
		return
	end
	for _, nombre in PARTES do
		local parte = personaje:FindFirstChild(nombre)
		if parte and parte:IsA("BasePart") then
			-- Sin color elegido, LocalTransparencyModifier no sirve: se deja como está.
			if piel then
				parte.Color = piel.Color
			end
		end
	end
end

local redibujar: () -> ()

local function seccion(titulo: string, opciones: { [string]: any }, campo: string, pideAsset: boolean)
	local t = UIKit.Texto(lista, titulo, UDim2.new(1, 0, 0, 24))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = UIKit.Colores.Oro
	local claves: { string } = {}
	for clave in opciones do
		table.insert(claves, clave)
	end
	table.sort(claves, function(a: string, b: string): boolean
		return opciones[a].Nombre < opciones[b].Nombre
	end)
	for _, clave in claves do
		local opcion = opciones[clave]
		local disponible = not pideAsset or opcion.AssetId ~= 0
		local elegida = (elegidos :: any)[campo] == clave
		local b = UIKit.Boton(
			lista,
			if disponible then opcion.Nombre else `{opcion.Nombre} (próximamente)`,
			UDim2.new(1, 0, 0, 30),
			nil,
			if elegida then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		b.TextXAlignment = Enum.TextXAlignment.Left
		if not disponible then
			b.TextColor3 = UIKit.Colores.TextoSuave
		end
		if opcion.Color then
			local muestra = Instance.new("Frame")
			muestra.AnchorPoint = Vector2.new(1, 0.5)
			muestra.Position = UDim2.new(1, -8, 0.5, 0)
			muestra.Size = UDim2.fromOffset(28, 18)
			muestra.BackgroundColor3 = opcion.Color
			UIKit.Esquinas(muestra, 4)
			muestra.Parent = b
		end
		b.Activated:Connect(function()
			if not disponible then
				Avisos.Mostrar("Ese estilo todavía no está disponible.", "Info")
				return
			end
			(elegidos :: any)[campo] = clave
			previsualizar()
			redibujar()
		end)
	end
end

redibujar = function()
	UIKit.Limpiar(lista)
	local oro = EstadoCliente.Get("Oro")
	aviso.Text = `Cada cambio cuesta {CFG.Costo} de oro. Tenés {if typeof(oro) == "number" then oro else 0}.`
	seccion("Color de piel", CFG.Pieles, "Piel", false)
	seccion("Peinado", CFG.Peinados, "Peinado", true)
	seccion("Marcas faciales", CFG.Marcas, "Marca", true)
end

local function cerrar()
	ventana.Visible = false
	npcId = nil
	-- Se vuelve al aspecto real (el servidor reaplica lo guardado al reaparecer).
	local personaje = jugador.Character
	local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")
	if humanoide then
		local ok, descripcion = pcall(function()
			return humanoide:GetAppliedDescription()
		end)
		if ok and descripcion and personaje then
			for _, nombre in PARTES do
				local parte = personaje:FindFirstChild(nombre)
				local propiedad = `{string.gsub(nombre, " ", "")}Color`
				if parte and parte:IsA("BasePart") then
					parte.Color = (descripcion :: any)[propiedad] or parte.Color
				end
			end
		end
	end
end

confirmar.Activated:Connect(function()
	local id = npcId
	local actual = estiloActual()
	if ocupado or not id then
		return
	end
	-- Solo se manda lo que cambió.
	local piel = if elegidos.Piel ~= actual.Piel then elegidos.Piel else nil
	local peinado = if elegidos.Peinado ~= actual.Peinado then elegidos.Peinado else nil
	local marca = if elegidos.Marca ~= actual.Marca then elegidos.Marca else nil
	if not piel and not peinado and not marca then
		Avisos.Mostrar("No cambiaste nada.", "Info")
		return
	end
	ocupado = true
	local r = NetworkBridge.Client.Invoke("BarberoAplicar", id, piel, peinado, marca)
	ocupado = false
	if r.Success then
		ventana.Visible = false
		npcId = nil
	end
end)
cancelar.Activated:Connect(cerrar)

NetworkBridge.Client.OnEvent("NpcAbrir", function(id: any, arquetipo: any)
	if typeof(id) == "string" and arquetipo == "Barbero" then
		npcId = id
	end
end)

NetworkBridge.Client.OnEvent("NpcVentana", function(nombre: any)
	if nombre ~= "Barbero" then
		return
	end
	elegidos = estiloActual()
	redibujar()
	ventana.Visible = true
	UIKit.EnfocarPrimero(ventana)
end)

jugador.CharacterAdded:Connect(cerrar)
