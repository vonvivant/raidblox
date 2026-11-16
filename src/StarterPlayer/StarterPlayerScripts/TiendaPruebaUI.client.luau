--!strict
-- TiendaPruebaUI: ventana del Mercader de materiales (solo en modo de pruebas).
-- Lista todos los materiales del catálogo a 1 de oro la unidad, con botones
-- para comprar 1, 10 o 99. El servidor valida todo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)

local gui = UIKit.Gui("TiendaPruebaUI", 66)
local ventana, contenido = UIKit.Ventana(gui, "Mercader de materiales (pruebas)", UDim2.fromScale(0.5, 0.65))

local saldo = UIKit.Texto(contenido, "", UDim2.new(1, 0, 0, 28))
saldo.TextColor3 = Color3.fromRGB(255, 215, 90)
saldo.TextXAlignment = Enum.TextXAlignment.Left
local lista = UIKit.Lista(contenido, UDim2.new(1, 0, 1, -36), UDim2.fromOffset(0, 36))

local comprando = false

local function actualizarSaldo()
	local oro = EstadoCliente.Get("Oro")
	saldo.Text = `Oro: {if typeof(oro) == "number" then oro else 0}  ·  Cada material cuesta 1 de oro`
end

-- Materiales ordenados por nombre.
local materiales: { { Id: string, Nombre: string } } = {}
for id, def in ItemCatalog do
	if def.Tipo == "Material" then
		table.insert(materiales, { Id = id, Nombre = def.Nombre })
	end
end
table.sort(materiales, function(a, b)
	return a.Nombre < b.Nombre
end)

for orden, material in materiales do
	local fila = Instance.new("Frame")
	fila.Size = UDim2.new(1, 0, 0, 44)
	fila.BackgroundColor3 = UIKit.Colores.Fondo
	fila.LayoutOrder = orden
	UIKit.Esquinas(fila, 6)
	local nombre = UIKit.Texto(fila, material.Nombre, UDim2.new(0.46, 0, 1, -10), UDim2.fromOffset(8, 5))
	nombre.TextXAlignment = Enum.TextXAlignment.Left
	for i, cantidad in { 1, 10, 99 } do
		local b = UIKit.Boton(
			fila,
			`×{cantidad}`,
			UDim2.new(0.16, 0, 1, -10),
			UDim2.new(0.48 + (i - 1) * 0.17, 0, 0, 5),
			UIKit.Colores.BotonPrimario
		)
		b.Activated:Connect(function()
			if comprando then
				return
			end
			comprando = true
			NetworkBridge.Client.Invoke("TiendaPruebaComprar", material.Id, cantidad)
			comprando = false
		end)
	end
	fila.Parent = lista
end

EstadoCliente.Cambio:Connect(function(campo: string)
	if campo == "Oro" or campo == "*" then
		actualizarSaldo()
	end
end)

NetworkBridge.Client.OnEvent("TiendaPruebaAbrir", function()
	actualizarSaldo()
	ventana.Visible = true
	UIKit.EnfocarPrimero(ventana)
end)
