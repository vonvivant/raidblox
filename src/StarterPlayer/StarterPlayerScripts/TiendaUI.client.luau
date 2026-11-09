--!strict
-- TiendaUI: tienda de pases (Fase 6.1). Botón "🛒 Tienda".
-- Cada pase muestra qué da, el precio en Robux y si ya lo tenés. La compra la
-- abre el servidor; en modo pruebas los pases sin Id se pueden simular.
-- Con el Título Personalizado, acá se escribe el título.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local MenuLateral = require(ReplicatedStorage.Modules.MenuLateral)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local DORADO = Color3.fromRGB(255, 213, 74)

local gui = UIKit.Gui("TiendaUI", 63)
local ventana, contenido = UIKit.Ventana(gui, "Tienda", UDim2.fromScale(0.5, 0.74))

local abrir = Instance.new("TextButton")
abrir.Name = "BotonTienda"
abrir.BackgroundColor3 = Color3.fromRGB(110, 80, 20)
abrir.TextColor3 = Color3.new(1, 1, 1)
abrir.Font = Enum.Font.GothamBold
abrir.TextScaled = true
abrir.Text = "🛒 Tienda"
UIKit.Esquinas(abrir, 6)
MenuLateral.Agregar(abrir, 4)

local lista = UIKit.Lista(contenido, UDim2.fromScale(1, 1))
local cargando = false

local function dibujar(datos: any)
	UIKit.Limpiar(lista)
	local pases = datos.Pases
	table.sort(pases, function(a: any, b: any): boolean
		return a.Orden < b.Orden
	end)
	for i, p in pases do
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, if p.Clave == "TituloPersonal" and p.Tengo then 112 else 76)
		f.BackgroundColor3 = UIKit.Colores.Fondo
		f.LayoutOrder = i
		UIKit.Esquinas(f, 8)
		local nombre = UIKit.Texto(f, p.Nombre, UDim2.new(0.66, 0, 0, 24), UDim2.fromOffset(10, 6))
		nombre.TextXAlignment = Enum.TextXAlignment.Left
		nombre.TextColor3 = DORADO
		local desc = UIKit.Texto(f, p.Descripcion, UDim2.new(0.66, 0, 0, 38), UDim2.fromOffset(10, 32))
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextWrapped = true
		desc.TextColor3 = UIKit.Colores.TextoSuave

		local texto: string
		local color: Color3 = UIKit.Colores.BotonPrimario
		if p.Tengo then
			texto = if p.Simulable then "Tenés (quitar)" else "✔ Lo tenés"
			color = UIKit.Colores.Boton
		elseif p.ALaVenta then
			texto = if p.Precio then `R$ {p.Precio}` else "Comprar"
		elseif p.Simulable then
			texto = "Simular (pruebas)"
			color = Color3.fromRGB(90, 70, 140)
		else
			texto = "Próximamente"
			color = UIKit.Colores.Boton
		end
		local b = UIKit.Boton(f, texto, UDim2.new(0.3, 0, 0, 36), UDim2.new(0.68, 0, 0, 20), color)
		local clave = p.Clave
		if (not p.Tengo and (p.ALaVenta or p.Simulable)) or (p.Tengo and p.Simulable) then
			b.Activated:Connect(function()
				local r = NetworkBridge.Client.Invoke("TiendaComprarPase", clave)
				if r.Success then
					task.delay(if p.ALaVenta then 2 else 0.2, function()
						if ventana.Visible then
							local nuevo = NetworkBridge.Client.Invoke("TiendaInfo")
							if nuevo.Success then
								dibujar(nuevo.Data)
							end
						end
					end)
				end
			end)
		end

		if p.Clave == "TituloPersonal" and p.Tengo then
			local caja =
				UIKit.Entrada(f, "Tu título (hasta 24 letras)", UDim2.new(0.62, 0, 0, 30), UDim2.fromOffset(10, 74))
			caja.Text = datos.Titulo or ""
			local guardar = UIKit.Boton(f, "Guardar título", UDim2.new(0.3, 0, 0, 30), UDim2.new(0.68, 0, 0, 74))
			guardar.Activated:Connect(function()
				NetworkBridge.Client.Invoke("TiendaGuardarTitulo", caja.Text)
			end)
		end
		f.Parent = lista
	end
end

local function recargar()
	if cargando then
		return
	end
	cargando = true
	local r = NetworkBridge.Client.Invoke("TiendaInfo")
	cargando = false
	if r.Success then
		dibujar(r.Data)
	else
		Avisos.Mostrar("No se pudo abrir la tienda.", "Error")
	end
end

abrir.Activated:Connect(function()
	ventana.Visible = not ventana.Visible
	if ventana.Visible then
		task.spawn(recargar)
		UIKit.EnfocarPrimero(ventana)
	end
end)
