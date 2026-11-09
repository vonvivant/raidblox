--!strict
-- HermandadUI: hermandad (guild).
--
-- Botón "Hermandad" al lado de "Grupo". Sin hermandad: fundar una (o esperar
-- una invitación). Con hermandad, cuatro pestañas:
--   Miembros  conectados y desconectados (zona, nivel, clase), rangos,
--             expulsar, pasar el liderazgo e invitar a jugadores del servidor.
--   Banco     oro y 4 pestañas de ítems; depositar desde la mochila.
--   Registro  movimientos del banco e historial de la hermandad.
--   Rangos    permisos de cada rango (los edita el líder).
-- Todo lo decide el servidor; esta pantalla solo pide y muestra.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
local UIKit = require(ReplicatedStorage.Modules.UIKit)
local ItemInfo = require(ReplicatedStorage.Modules.ItemInfo)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local jugador = Players.LocalPlayer
local CFG = GameConfig.Hermandades
local DORADO = Color3.fromRGB(255, 215, 90)
local VERDE = Color3.fromRGB(130, 230, 130)
local NOMBRES_RANGO: { [string]: string } =
	{ Lider = "Líder", Oficial = "Oficial", Miembro = "Miembro", Recluta = "Recluta" }
local NOMBRES_PERMISO: { [string]: string } = {
	Invitar = "Invitar",
	Expulsar = "Expulsar",
	Rangos = "Cambiar rangos",
	RetirarItems = "Retirar ítems",
	RetirarOro = "Retirar oro",
}
local ESCALERA = { "Recluta", "Miembro", "Oficial" }

local gui = UIKit.Gui("HermandadUI", 62)
local ventana, contenido = UIKit.Ventana(gui, "Hermandad", UDim2.fromScale(0.64, 0.74))

local abrir = Instance.new("TextButton")
abrir.Name = "BotonHermandad"
abrir.Position = UDim2.fromScale(0.2, 0.455)
abrir.Size = UDim2.fromScale(0.09, 0.038)
abrir.BackgroundColor3 = UIKit.Colores.Boton
abrir.TextColor3 = Color3.new(1, 1, 1)
abrir.Font = Enum.Font.GothamBold
abrir.TextScaled = true
abrir.Text = "Hermandad"
UIKit.Esquinas(abrir, 6)
abrir.Parent = gui

local info: any = nil -- última respuesta de HermandadInfo
local banco: any = nil
local pestanaBanco = 1
local vistaActual = "Miembros"
local ocupado = false

local function invocar(remote: string, ...: any): any
	if ocupado then
		return nil
	end
	ocupado = true
	local r = NetworkBridge.Client.Invoke(remote, ...)
	ocupado = false
	if not r.Success and r.ErrorCode == "TIMEOUT" then
		Avisos.Mostrar("El servidor tarda en responder; probá de nuevo en un momento.", "Error")
	end
	return r
end

local function haceCuanto(t: number): string
	local s = math.max(0, os.time() - t)
	if s < 3600 then
		return `hace {math.max(1, s // 60)} min`
	elseif s < 86400 then
		return `hace {s // 3600} h`
	end
	return `hace {s // 86400} d`
end

------------------------------------------------------------------------
-- Estructura: fundar / pestañas
------------------------------------------------------------------------

local fundar = Instance.new("Frame")
fundar.Size = UDim2.fromScale(1, 1)
fundar.BackgroundTransparency = 1
fundar.Visible = false
fundar.Parent = contenido
UIKit.Texto(fundar, "No estás en una hermandad.", UDim2.new(1, 0, 0, 28), UDim2.fromScale(0, 0.1))
local explicacion = UIKit.Texto(
	fundar,
	`Fundá una por {CFG.CostoCreacion} de oro (nivel {CFG.NivelMinimo}+), o pedile a alguien que te invite.`,
	UDim2.new(1, 0, 0, 44),
	UDim2.fromScale(0, 0.2)
)
explicacion.TextColor3 = UIKit.Colores.TextoSuave
local nombreNueva = UIKit.Entrada(
	fundar,
	`Nombre ({CFG.LargoNombre.Min} a {CFG.LargoNombre.Max} letras)`,
	UDim2.new(0.6, 0, 0, 40),
	UDim2.fromScale(0.2, 0.38)
)
local botonFundar = UIKit.Boton(
	fundar,
	`Fundar ({CFG.CostoCreacion} oro)`,
	UDim2.new(0.4, 0, 0, 40),
	UDim2.fromScale(0.3, 0.52),
	UIKit.Colores.BotonPrimario
)

local principal = Instance.new("Frame")
principal.Size = UDim2.fromScale(1, 1)
principal.BackgroundTransparency = 1
principal.Visible = false
principal.Parent = contenido

local barra = Instance.new("Frame")
barra.Size = UDim2.new(1, 0, 0, 34)
barra.BackgroundTransparency = 1
barra.Parent = principal
local layoutBarra = Instance.new("UIListLayout")
layoutBarra.FillDirection = Enum.FillDirection.Horizontal
layoutBarra.Padding = UDim.new(0, 6)
layoutBarra.SortOrder = Enum.SortOrder.LayoutOrder
layoutBarra.Parent = barra

local cuerpo = Instance.new("Frame")
cuerpo.Position = UDim2.fromOffset(0, 42)
cuerpo.Size = UDim2.new(1, 0, 1, -42)
cuerpo.BackgroundTransparency = 1
cuerpo.Parent = principal

local vistas: { [string]: Frame } = {}
local botonesVista: { [string]: TextButton } = {}
local redibujar: () -> ()

for i, nombre in { "Miembros", "Banco", "Registro", "Rangos" } do
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.Parent = cuerpo
	vistas[nombre] = f
	local b = UIKit.Boton(barra, nombre, UDim2.new(0.22, 0, 1, 0))
	b.LayoutOrder = i
	botonesVista[nombre] = b
	b.Activated:Connect(function()
		vistaActual = nombre
		redibujar()
	end)
end

local function fila(lista: ScrollingFrame, orden: number, texto: string, color: Color3?, alto: number?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, alto or 38)
	f.BackgroundColor3 = UIKit.Colores.Fondo
	f.LayoutOrder = orden
	UIKit.Esquinas(f, 6)
	local t = UIKit.Texto(f, texto, UDim2.new(0.5, 0, 1, -8), UDim2.fromOffset(8, 4))
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color or UIKit.Colores.Texto
	f.Parent = lista
	return f
end

local function botonFila(f: Frame, texto: string, x: number, ancho: number, color: Color3?): TextButton
	return UIKit.Boton(f, texto, UDim2.new(ancho, -4, 1, -8), UDim2.new(x, 2, 0, 4), color)
end

------------------------------------------------------------------------
-- Miembros
------------------------------------------------------------------------

local vMiembros = vistas.Miembros
local cabecera = UIKit.Texto(vMiembros, "", UDim2.new(0.7, 0, 0, 26))
cabecera.TextXAlignment = Enum.TextXAlignment.Left
cabecera.TextColor3 = DORADO
local botonSalir =
	UIKit.Boton(vMiembros, "Salir", UDim2.new(0.28, 0, 0, 28), UDim2.new(0.72, 0, 0, 0), UIKit.Colores.BotonPeligro)
local listaMiembros = UIKit.Lista(vMiembros, UDim2.new(1, 0, 0.62, -34), UDim2.fromOffset(0, 34))
local tituloInvitar =
	UIKit.Texto(vMiembros, "Invitar jugadores del servidor", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0.62, 4))
tituloInvitar.TextXAlignment = Enum.TextXAlignment.Left
tituloInvitar.TextColor3 = DORADO
local listaInvitar = UIKit.Lista(vMiembros, UDim2.new(1, 0, 0.38, -30), UDim2.new(0, 0, 0.62, 30))

local confirmarSalir = false
botonSalir.Activated:Connect(function()
	if not info then
		return
	end
	local solo = #info.Miembros <= 1
	if not confirmarSalir then
		confirmarSalir = true
		botonSalir.Text = if solo then "¿Disolver? (otra vez)" else "¿Salir? (otra vez)"
		task.delay(3, function()
			confirmarSalir = false
			if info then
				botonSalir.Text = if #info.Miembros <= 1 and info.MiRango == "Lider" then "Disolver" else "Salir"
			end
		end)
		return
	end
	confirmarSalir = false
	invocar(if solo and info.MiRango == "Lider" then "HermandadDisolver" else "HermandadSalir")
end)

local function rangoVecino(rango: string, paso: number): string?
	local i = table.find(ESCALERA, rango)
	return if i then ESCALERA[i + paso] else nil
end

local function nivelRango(r: string?): number
	return if r == "Lider"
		then 4
		elseif r == "Oficial" then 3
		elseif r == "Miembro" then 2
		elseif r == "Recluta" then 1
		else 0
end

local function dibujarMiembros()
	UIKit.Limpiar(listaMiembros)
	UIKit.Limpiar(listaInvitar)
	local i = info
	if not i then
		return
	end
	local conectados = 0
	for _, m in i.Miembros do
		if m.EnLinea then
			conectados += 1
		end
	end
	cabecera.Text =
		`{i.Nombre}  ·  {#i.Miembros}/{i.Max} miembros  ·  {conectados} conectados  ·  sos {NOMBRES_RANGO[i.MiRango] or "?"}`
	botonSalir.Text = if #i.Miembros <= 1 and i.MiRango == "Lider" then "Disolver" else "Salir"

	local miembros = table.clone(i.Miembros)
	table.sort(miembros, function(a: any, b: any): boolean
		if a.EnLinea ~= b.EnLinea then
			return a.EnLinea
		end
		if a.Rango ~= b.Rango then
			return nivelRango(a.Rango) > nivelRango(b.Rango)
		end
		return a.Nombre < b.Nombre
	end)
	local mio = nivelRango(i.MiRango)
	for orden, m in miembros do
		local estado = if m.EnLinea then `{m.Zona}` else `desconectado {haceCuanto(m.UltimaVez)}`
		local texto =
			`{if m.Rango == "Lider" then "👑 " else ""}{m.Nombre} · {NOMBRES_RANGO[m.Rango] or m.Rango}\nNv {m.Nivel} {m.Clase} · {estado}`
		local color = if m.UserId == jugador.UserId
			then VERDE
			elseif m.EnLinea then UIKit.Colores.Texto
			else UIKit.Colores.TextoSuave
		local f = fila(listaMiembros, orden, texto, color, 46)
		if m.UserId == jugador.UserId or mio <= nivelRango(m.Rango) then
			continue
		end
		local uid = m.UserId
		if i.MisPermisos.Rangos then
			local arriba = rangoVecino(m.Rango, 1)
			local abajo = rangoVecino(m.Rango, -1)
			if arriba and nivelRango(arriba) < mio then
				botonFila(f, "▲", 0.5, 0.08).Activated:Connect(function()
					invocar("HermandadRango", uid, arriba)
				end)
			end
			if abajo then
				botonFila(f, "▼", 0.58, 0.08).Activated:Connect(function()
					invocar("HermandadRango", uid, abajo)
				end)
			end
		end
		if i.MiRango == "Lider" then
			local liderar = botonFila(f, "Hacer líder", 0.66, 0.17)
			local confirmar = false
			liderar.Activated:Connect(function()
				if not confirmar then
					confirmar = true
					liderar.Text = "¿Seguro?"
					return
				end
				invocar("HermandadTransferir", uid)
			end)
		end
		if i.MisPermisos.Expulsar then
			botonFila(f, "Expulsar", 0.83, 0.17, UIKit.Colores.BotonPeligro).Activated:Connect(function()
				invocar("HermandadExpulsar", uid)
			end)
		end
	end

	local orden = 0
	if i.MisPermisos.Invitar then
		for _, otro in Players:GetPlayers() do
			if otro == jugador or otro:GetAttribute("HermandadId") ~= nil then
				continue
			end
			orden += 1
			local f = fila(listaInvitar, orden, otro.DisplayName)
			local uid = otro.UserId
			botonFila(f, "Invitar", 0.7, 0.3, UIKit.Colores.BotonPrimario).Activated:Connect(function()
				invocar("HermandadInvitar", uid)
			end)
		end
	end
	if orden == 0 then
		fila(
			listaInvitar,
			1,
			if i.MisPermisos.Invitar
				then "No hay jugadores sin hermandad en el servidor."
				else "Tu rango no puede invitar.",
			UIKit.Colores.TextoSuave
		)
	end
end

------------------------------------------------------------------------
-- Banco
------------------------------------------------------------------------

local vBanco = vistas.Banco
local textoOro = UIKit.Texto(vBanco, "Oro: …", UDim2.new(0.3, 0, 0, 30))
textoOro.TextXAlignment = Enum.TextXAlignment.Left
textoOro.TextColor3 = UIKit.Colores.Oro
local cantidadOro = UIKit.Entrada(vBanco, "Cantidad", UDim2.new(0.2, 0, 0, 30), UDim2.fromScale(0.31, 0))
local depositarOro =
	UIKit.Boton(vBanco, "Depositar", UDim2.new(0.18, 0, 0, 30), UDim2.fromScale(0.52, 0), UIKit.Colores.BotonPrimario)
local retirarOro = UIKit.Boton(vBanco, "Retirar", UDim2.new(0.18, 0, 0, 30), UDim2.fromScale(0.71, 0))

local barraPestanas = Instance.new("Frame")
barraPestanas.Position = UDim2.fromOffset(0, 38)
barraPestanas.Size = UDim2.new(0.6, 0, 0, 28)
barraPestanas.BackgroundTransparency = 1
barraPestanas.Parent = vBanco
local layoutPestanas = Instance.new("UIListLayout")
layoutPestanas.FillDirection = Enum.FillDirection.Horizontal
layoutPestanas.Padding = UDim.new(0, 4)
layoutPestanas.Parent = barraPestanas

local rejilla = Instance.new("ScrollingFrame")
rejilla.Position = UDim2.fromOffset(0, 72)
rejilla.Size = UDim2.new(0.6, -6, 1, -72)
rejilla.BackgroundColor3 = UIKit.Colores.Panel
rejilla.BackgroundTransparency = 0.3
rejilla.BorderSizePixel = 0
rejilla.ScrollBarThickness = 6
rejilla.AutomaticCanvasSize = Enum.AutomaticSize.Y
rejilla.CanvasSize = UDim2.new()
UIKit.Esquinas(rejilla, 8)
rejilla.Parent = vBanco
local layoutRejilla = Instance.new("UIGridLayout")
layoutRejilla.CellSize = UDim2.new(1 / 4, -6, 0, 52)
layoutRejilla.CellPadding = UDim2.fromOffset(4, 4)
layoutRejilla.SortOrder = Enum.SortOrder.LayoutOrder
layoutRejilla.Parent = rejilla

local tituloMochila =
	UIKit.Texto(vBanco, "Tu mochila → depositar", UDim2.new(0.4, 0, 0, 24), UDim2.new(0.6, 0, 0, 40))
tituloMochila.TextColor3 = DORADO
local listaMochila = UIKit.Lista(vBanco, UDim2.new(0.4, 0, 1, -72), UDim2.new(0.6, 0, 0, 72))

local function cargarBanco()
	local r = invocar("HermandadBanco")
	if r and r.Success then
		banco = r.Data
	end
end

local function dibujarBanco()
	for _, hijo in barraPestanas:GetChildren() do
		if hijo:IsA("GuiObject") then
			hijo:Destroy()
		end
	end
	UIKit.Limpiar(rejilla)
	UIKit.Limpiar(listaMochila)
	local b = banco
	textoOro.Text = if b then `Oro: {b.Oro}` else "Oro: …"
	retirarOro.Visible = b ~= nil and b.PuedoOro
	for p = 1, CFG.Pestanas do
		local boton = UIKit.Boton(
			barraPestanas,
			`Pestaña {p}`,
			UDim2.new(0.25, -4, 1, 0),
			nil,
			if p == pestanaBanco then UIKit.Colores.BotonPrimario else nil
		)
		boton.Activated:Connect(function()
			pestanaBanco = p
			dibujarBanco()
		end)
	end
	if b then
		local ranuras = b.Pestanas[tostring(pestanaBanco)] or {}
		for r = 1, b.Ranuras do
			local item = ranuras[tostring(r)]
			local celda = UIKit.Boton(rejilla, if item then ItemInfo.Corto(item) else "", UDim2.new())
			celda.LayoutOrder = r
			celda.BackgroundColor3 = if item then UIKit.Colores.Boton else UIKit.Colores.Fondo
			if item then
				celda.TextColor3 = ItemInfo.Color(item)
				if b.PuedoItems then
					celda.Activated:Connect(function()
						local resp = invocar("HermandadRetirarItem", pestanaBanco, r, item.Uid)
						if resp and resp.Success then
							cargarBanco()
							dibujarBanco()
						end
					end)
				end
			end
		end
	end
	local inv = EstadoCliente.Get("Inventario")
	local orden = 0
	if inv then
		for clave, item in inv.Slots do
			orden += 1
			local f = fila(listaMochila, tonumber(clave) or orden, ItemInfo.Corto(item), ItemInfo.Color(item))
			f.Size = UDim2.new(1, 0, 0, 36)
			local c = clave
			botonFila(f, "Depositar", 0.6, 0.4, UIKit.Colores.BotonPrimario).Activated:Connect(function()
				local resp = invocar("HermandadDepositarItem", c, item.Cantidad, pestanaBanco)
				if resp and resp.Success then
					cargarBanco()
					dibujarBanco()
				end
			end)
		end
	end
	if orden == 0 then
		fila(listaMochila, 1, "La mochila está vacía.", UIKit.Colores.TextoSuave)
	end
end

local function moverOro(remote: string)
	local cantidad = tonumber(cantidadOro.Text)
	if not cantidad or cantidad < 1 or cantidad ~= math.floor(cantidad) then
		Avisos.Mostrar("Escribí una cantidad de oro válida.", "Error")
		return
	end
	local r = invocar(remote, cantidad)
	if r and r.Success then
		cantidadOro.Text = ""
		cargarBanco()
		dibujarBanco()
	end
end
depositarOro.Activated:Connect(function()
	moverOro("HermandadDepositarOro")
end)
retirarOro.Activated:Connect(function()
	moverOro("HermandadRetirarOro")
end)

------------------------------------------------------------------------
-- Registro y rangos
------------------------------------------------------------------------

local vRegistro = vistas.Registro
local tituloBanco = UIKit.Texto(vRegistro, "Banco", UDim2.new(0.5, -4, 0, 24))
tituloBanco.TextColor3 = DORADO
local listaRegistro = UIKit.Lista(vRegistro, UDim2.new(0.5, -4, 1, -28), UDim2.fromOffset(0, 28))
local tituloHistorial = UIKit.Texto(vRegistro, "Hermandad", UDim2.new(0.5, -4, 0, 24), UDim2.new(0.5, 4, 0, 0))
tituloHistorial.TextColor3 = DORADO
local listaHistorial = UIKit.Lista(vRegistro, UDim2.new(0.5, -4, 1, -28), UDim2.new(0.5, 4, 0, 28))

local function dibujarRegistro()
	UIKit.Limpiar(listaRegistro)
	UIKit.Limpiar(listaHistorial)
	local b = banco
	if b then
		for i, mov in b.Registro do
			local f = fila(listaRegistro, i, `{mov.N} {string.lower(mov.A)} {mov.D}\n{haceCuanto(mov.T)}`, nil, 44)
			local t = f:FindFirstChildOfClass("TextLabel")
			if t then
				t.Size = UDim2.new(1, -16, 1, -8)
				t.TextColor3 = if mov.A == "Retiró" then Color3.fromRGB(240, 170, 120) else VERDE
			end
		end
		if #b.Registro == 0 then
			fila(listaRegistro, 1, "Todavía no hay movimientos.", UIKit.Colores.TextoSuave)
		end
	end
	local i = info
	if i then
		for orden, h in i.Historial do
			local f = fila(listaHistorial, orden, `{h.A}\n{haceCuanto(h.T)}`, nil, 44)
			local t = f:FindFirstChildOfClass("TextLabel")
			if t then
				t.Size = UDim2.new(1, -16, 1, -8)
			end
		end
	end
end

local vRangos = vistas.Rangos
local listaRangos = UIKit.Lista(vRangos, UDim2.fromScale(1, 1))

local function dibujarRangos()
	UIKit.Limpiar(listaRangos)
	local i = info
	if not i then
		return
	end
	local esLider = i.MiRango == "Lider"
	local nota = fila(
		listaRangos,
		0,
		if esLider then "Tocá un permiso para activarlo o desactivarlo." else "Solo el líder cambia los permisos.",
		UIKit.Colores.TextoSuave,
		30
	)
	nota.BackgroundTransparency = 1
	local orden = 0
	for _, rango in { "Oficial", "Miembro", "Recluta" } do
		orden += 1
		local f = fila(listaRangos, orden, NOMBRES_RANGO[rango], DORADO, 30)
		f.BackgroundTransparency = 1
		for _, permiso in CFG.Permisos do
			orden += 1
			local activo = i.Permisos[rango] and i.Permisos[rango][permiso] == true
			local p = fila(listaRangos, orden, `   {NOMBRES_PERMISO[permiso] or permiso}`, nil, 34)
			local b = botonFila(
				p,
				if activo then "Sí" else "No",
				0.7,
				0.3,
				if activo then UIKit.Colores.BotonPrimario else UIKit.Colores.BotonPeligro
			)
			b.Active = esLider
			b.AutoButtonColor = esLider
			if esLider then
				b.Activated:Connect(function()
					local r = invocar("HermandadPermiso", rango, permiso, not activo)
					if r and r.Success then
						i.Permisos[rango][permiso] = not activo
						dibujarRangos()
					end
				end)
			end
		end
	end
end

------------------------------------------------------------------------
-- Redibujar
------------------------------------------------------------------------

redibujar = function()
	fundar.Visible = info == nil
	principal.Visible = info ~= nil
	if not info then
		return
	end
	for nombre, f in vistas do
		f.Visible = nombre == vistaActual
		botonesVista[nombre].BackgroundColor3 = if nombre == vistaActual
			then UIKit.Colores.BotonPrimario
			else UIKit.Colores.Boton
	end
	if vistaActual == "Miembros" then
		dibujarMiembros()
	elseif vistaActual == "Banco" then
		dibujarBanco()
	elseif vistaActual == "Registro" then
		dibujarRegistro()
	else
		dibujarRangos()
	end
end

local function recargar(conBanco: boolean)
	local r = invocar("HermandadInfo")
	if not r then
		return
	end
	if r.Success then
		info = r.Data
	end
	if info and (conBanco or vistaActual == "Banco" or vistaActual == "Registro") then
		cargarBanco()
	end
	redibujar()
end

botonFundar.Activated:Connect(function()
	local r = invocar("HermandadCrear", nombreNueva.Text)
	if r and r.Success then
		nombreNueva.Text = ""
		vistaActual = "Miembros"
		recargar(false)
	end
end)

abrir.Activated:Connect(function()
	ventana.Visible = not ventana.Visible
	if ventana.Visible then
		redibujar()
		task.spawn(recargar, false)
		UIKit.EnfocarPrimero(ventana)
	end
end)

for _, nombre in { "Banco", "Registro" } do
	botonesVista[nombre].Activated:Connect(function()
		task.spawn(function()
			cargarBanco()
			redibujar()
		end)
	end)
end

EstadoCliente.Cambio:Connect(function(campo: string)
	if ventana.Visible and vistaActual == "Banco" and (campo == "Inventario" or campo == "*") then
		dibujarBanco()
	end
end)

------------------------------------------------------------------------
-- Avisos del servidor
------------------------------------------------------------------------

local pendiente = false
NetworkBridge.Client.OnEvent("HermandadCambio", function(estado: any, que: any)
	if typeof(estado) ~= "table" then
		info = nil
		banco = nil
		if ventana.Visible then
			redibujar()
		end
		return
	end
	if not ventana.Visible or pendiente then
		return
	end
	-- Varios avisos seguidos se juntan en una sola recarga.
	pendiente = true
	task.delay(0.4, function()
		pendiente = false
		if ventana.Visible then
			recargar(que == "banco")
		end
	end)
end)

local aviso = Instance.new("Frame")
aviso.AnchorPoint = Vector2.new(0.5, 0)
aviso.Position = UDim2.fromScale(0.5, 0.23)
aviso.Size = UDim2.fromScale(0.36, 0.11)
aviso.BackgroundColor3 = UIKit.Colores.Fondo
aviso.Visible = false
UIKit.Esquinas(aviso, 10)
aviso.Parent = gui
local textoAviso = UIKit.Texto(aviso, "", UDim2.new(1, -16, 0.45, 0), UDim2.fromOffset(8, 4))
local aceptar =
	UIKit.Boton(aviso, "Unirme", UDim2.fromScale(0.44, 0.4), UDim2.fromScale(0.04, 0.54), UIKit.Colores.BotonPrimario)
local rechazar =
	UIKit.Boton(aviso, "Rechazar", UDim2.fromScale(0.44, 0.4), UDim2.fromScale(0.52, 0.54), UIKit.Colores.BotonPeligro)
local invitacion: string? = nil
local contador = 0

local function responder(acepta: boolean)
	local gid = invitacion
	aviso.Visible = false
	invitacion = nil
	if gid then
		local r = invocar("HermandadResponder", gid, acepta)
		if r and r.Success and acepta and ventana.Visible then
			recargar(false)
		end
	end
end
aceptar.Activated:Connect(function()
	responder(true)
end)
rechazar.Activated:Connect(function()
	responder(false)
end)

NetworkBridge.Client.OnEvent("HermandadInvitacion", function(gid: any, nombre: any, de: any)
	if typeof(gid) ~= "string" or typeof(nombre) ~= "string" or typeof(de) ~= "string" then
		return
	end
	invitacion = gid
	textoAviso.Text = `{de} te invita a la hermandad «{nombre}»`
	aviso.Visible = true
	contador += 1
	local este = contador
	task.delay(CFG.ExpiraInvitacion, function()
		if contador == este then
			aviso.Visible = false
			invitacion = nil
		end
	end)
end)
