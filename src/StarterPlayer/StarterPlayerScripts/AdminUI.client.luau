--!strict
-- AdminUI: panel de administración (Fase 7.4). El botón "🛡 Admin" del menú
-- lateral aparece solo si el servidor te marcó como admin; igual, el servidor
-- vuelve a validar cada acción (la interfaz no decide nada).
--
-- Izquierda: jugadores del servidor. Derecha: acciones sobre el elegido
-- (ir, traer, revivir, inventario, expulsar, banear, dar oro e ítems),
-- desbanear por UserId e invocar RaidBlox de prueba.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local MenuLateral = require(ReplicatedStorage.Modules.MenuLateral)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local jugador = Players.LocalPlayer

local function esperarAdmin()
	if jugador:GetAttribute("Admin") ~= true then
		jugador:GetAttributeChangedSignal("Admin"):Wait()
	end
end
esperarAdmin()

local gui = UIKit.Gui("AdminUI", 70)
local ventana, contenido = UIKit.Ventana(gui, "🛡 Administración", UDim2.fromScale(0.72, 0.82))

local abrir = Instance.new("TextButton")
abrir.Name = "BotonAdmin"
abrir.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
abrir.TextColor3 = Color3.new(1, 1, 1)
abrir.Font = Enum.Font.GothamBold
abrir.TextScaled = true
abrir.Text = "🛡 Admin"
UIKit.Esquinas(abrir, 6)
MenuLateral.Agregar(abrir, 9)

local listaJugadores = UIKit.Lista(contenido, UDim2.new(0.28, -6, 1, 0))
local panel = UIKit.Lista(contenido, UDim2.new(0.72, 0, 1, 0), UDim2.fromScale(0.28, 0))

local elegido: Player? = nil
local recargar: () -> ()
local orden = 0

local function accion(nombre: string, a: any?, b: any?, c: any?): any
	local r = NetworkBridge.Client.Invoke("AdminAccion", nombre, a, b, c)
	if r.Success then
		Avisos.Mostrar(`{nombre}: hecho.`, "Info")
	else
		Avisos.Mostrar(`{nombre}: {r.ErrorCode}`, "Error")
	end
	return r
end

local function fila(alto: number): Frame
	orden += 1
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, alto)
	f.BackgroundColor3 = UIKit.Colores.Fondo
	f.LayoutOrder = orden
	UIKit.Esquinas(f, 8)
	f.Parent = panel
	return f
end

local function titulo(texto: string)
	local f = fila(26)
	f.BackgroundTransparency = 1
	local t = UIKit.Texto(f, texto, UDim2.new(1, -10, 1, 0), UDim2.fromOffset(6, 0))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = UIKit.Colores.Oro
end

-- Fila de botones del mismo ancho.
local function botones(lista: { { Texto: string, Color: Color3?, Accion: () -> () } })
	local f = fila(38)
	local ancho = 1 / #lista
	for i, b in lista do
		local boton = UIKit.Boton(f, b.Texto, UDim2.new(ancho, -8, 1, -8), UDim2.new((i - 1) * ancho, 4, 0, 4), b.Color)
		boton.Activated:Connect(b.Accion)
	end
end

local function dibujarInventario(info: any)
	titulo(`Inventario de {info.Nombre}: Nv. {info.Nivel} · {info.Clase} · {info.Oro} oro`)
	for _, e in info.Equipo do
		local f = fila(22)
		local t = UIKit.Texto(f, `⚔ {e}`, UDim2.new(1, -10, 1, 0), UDim2.fromOffset(6, 0))
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Font = Enum.Font.Gotham
	end
	for _, it in info.Items do
		local f = fila(22)
		local t = UIKit.Texto(
			f,
			`#{it.Ranura}  {it.Nombre} x{it.Cantidad}  ({it.Rareza})  [{it.ItemId}]`,
			UDim2.new(1, -10, 1, 0),
			UDim2.fromOffset(6, 0)
		)
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Font = Enum.Font.Gotham
	end
end

local function dibujarPanel(info: any, inventario: any?)
	UIKit.Limpiar(panel)
	orden = 0
	local p = elegido
	if p and p.Parent == Players then
		local id = p.UserId
		titulo(`Jugador: {p.DisplayName} (@{p.Name}) · {id}`)
		botones({
			{
				Texto = "Ir hacia",
				Accion = function()
					accion("Ir", id)
				end,
			},
			{
				Texto = "Traer",
				Accion = function()
					accion("Traer", id)
				end,
			},
			{
				Texto = "Revivir",
				Accion = function()
					accion("Revivir", id)
				end,
			},
			{
				Texto = "Ver inventario",
				Accion = function()
					local r = accion("Inventario", id)
					if r.Success then
						dibujarPanel(info, r.Data)
					end
				end,
			},
		})

		-- Moderación
		local fm = fila(78)
		local motivo = UIKit.Entrada(fm, "Motivo", UDim2.new(1, -12, 0, 32), UDim2.fromOffset(6, 4))
		local kick =
			UIKit.Boton(fm, "Expulsar", UDim2.new(0.5, -9, 0, 32), UDim2.new(0, 6, 0, 42), Color3.fromRGB(150, 100, 30))
		local ban = UIKit.Boton(
			fm,
			"Banear para siempre",
			UDim2.new(0.5, -9, 0, 32),
			UDim2.new(0.5, 3, 0, 42),
			UIKit.Colores.BotonPeligro
		)
		kick.Activated:Connect(function()
			accion("Kick", id, if motivo.Text ~= "" then motivo.Text else nil)
		end)
		local confirmar = 0
		ban.Activated:Connect(function()
			if motivo.Text == "" then
				Avisos.Mostrar("Escribí el motivo del baneo.", "Error")
				return
			end
			if os.clock() > confirmar then
				confirmar = os.clock() + 4
				ban.Text = "¿Seguro? Tocá otra vez"
				return
			end
			confirmar = 0
			ban.Text = "Banear para siempre"
			accion("Ban", id, motivo.Text)
		end)

		-- Oro e ítems
		local fo = fila(40)
		local oro = UIKit.Entrada(fo, "Oro", UDim2.new(0.6, -9, 1, -8), UDim2.fromOffset(6, 4))
		local darOro = UIKit.Boton(fo, "Dar oro", UDim2.new(0.4, -9, 1, -8), UDim2.new(0.6, 3, 0, 4))
		darOro.Activated:Connect(function()
			local n = tonumber(oro.Text)
			if n then
				accion("DarOro", id, math.floor(n))
			end
		end)
		local fi = fila(78)
		local item = UIKit.Entrada(fi, "ItemId (ej. EspadaHierro)", UDim2.new(0.6, -9, 0, 32), UDim2.fromOffset(6, 4))
		local cantidad = UIKit.Entrada(fi, "Cant.", UDim2.new(0.15, -6, 0, 32), UDim2.new(0.6, 3, 0, 4))
		local dar = UIKit.Boton(fi, "Dar", UDim2.new(0.25, -9, 0, 32), UDim2.new(0.75, 3, 0, 4))
		dar.Activated:Connect(function()
			if not ItemCatalog[item.Text] then
				Avisos.Mostrar("Ese ItemId no existe.", "Error")
				return
			end
			accion("DarItem", id, item.Text, tonumber(cantidad.Text) or 1)
		end)
		-- Con rareza fija (para equipo).
		for i, r in { "Raro", "Epico", "Mistico", "Unico" } do
			local b = UIKit.Boton(fi, r, UDim2.new(0.25, -8, 0, 30), UDim2.new((i - 1) * 0.25, 4, 0, 42))
			b.Activated:Connect(function()
				if ItemCatalog[item.Text] then
					accion("DarItemRareza", id, item.Text, r)
				end
			end)
		end
		if inventario then
			dibujarInventario(inventario)
		end
	else
		titulo("Elegí un jugador de la lista.")
	end

	-- Desbanear
	titulo("Desbanear por UserId")
	local fd = fila(40)
	local uid = UIKit.Entrada(fd, "UserId", UDim2.new(0.6, -9, 1, -8), UDim2.fromOffset(6, 4))
	local desban = UIKit.Boton(fd, "Desbanear", UDim2.new(0.4, -9, 1, -8), UDim2.new(0.6, 3, 0, 4))
	desban.Activated:Connect(function()
		local n = tonumber(uid.Text)
		if n then
			accion("Desban", math.floor(n))
		end
	end)

	-- Jefes
	if info and info.Jefes then
		titulo("Invocar RaidBlox de prueba (aparece adelante tuyo, no reaparece)")
		local lista = {}
		for _, j in info.Jefes do
			table.insert(lista, {
				Texto = j.Nombre,
				Color = Color3.fromRGB(130, 60, 30),
				Accion = function()
					accion("InvocarJefe", j.Id)
				end,
			})
		end
		if #lista > 0 then
			botones(lista)
		end
	end
	if info and not info.Webhook then
		titulo("Registro: solo consola (falta ConfigServidor.WebhookAdmin).")
	end
end

local infoServidor: any = nil

local function dibujarJugadores()
	UIKit.Limpiar(listaJugadores)
	local lista = Players:GetPlayers()
	table.sort(lista, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	for i, p in lista do
		local b = UIKit.Boton(
			listaJugadores,
			p.DisplayName,
			UDim2.new(1, 0, 0, 32),
			nil,
			if p == elegido then UIKit.Colores.BotonPrimario else UIKit.Colores.Boton
		)
		b.LayoutOrder = i
		b.Activated:Connect(function()
			elegido = p
			dibujarJugadores()
			dibujarPanel(infoServidor, nil)
		end)
	end
end

recargar = function()
	local r = NetworkBridge.Client.Invoke("AdminInfo")
	if not r.Success then
		Avisos.Mostrar("Sin permiso de administrador.", "Error")
		ventana.Visible = false
		return
	end
	infoServidor = r.Data
	dibujarJugadores()
	dibujarPanel(infoServidor, nil)
end

abrir.Activated:Connect(function()
	ventana.Visible = not ventana.Visible
	if ventana.Visible then
		task.spawn(recargar)
	end
end)

Players.PlayerAdded:Connect(function()
	if ventana.Visible then
		dibujarJugadores()
	end
end)
Players.PlayerRemoving:Connect(function(p: Player)
	if p == elegido then
		elegido = nil
		if ventana.Visible then
			dibujarPanel(infoServidor, nil)
		end
	end
	if ventana.Visible then
		task.defer(dibujarJugadores)
	end
end)
