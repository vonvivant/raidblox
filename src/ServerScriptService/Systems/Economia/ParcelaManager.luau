--!strict
-- ParcelaManager: dueños, alquiler, permisos y fusión de las parcelas.
--
-- Por qué un DataStore y no el perfil: una parcela es de un jugador **en todos
-- los servidores a la vez**. Si viviera en el perfil, dos jugadores en dos
-- servidores podrían comprar la misma. Así que la verdad está en un DataStore
-- global, una clave por parcela, y toda transición pasa por `UpdateAsync`, que
-- es lo único que garantiza "o la gano yo, o la ganó otro".
--
-- El perfil guarda igual la lista de parcelas del jugador (`Parcelas`), pero
-- solo como copia para el límite y la interfaz: ante una diferencia, manda el
-- DataStore.
--
-- Orden de las operaciones que cobran: se **cobra primero** y después se
-- escribe. Si la escritura no entra (otro servidor ganó, o el DataStore falla),
-- se devuelve el oro. Al revés sería peor: una parcela marcada como vendida y
-- sin cobrar quedaría trabada para todos, mientras que un cobro con devolución
-- es un problema de un solo jugador y de un segundo. Si la devolución también
-- falla (el jugador se fue en el medio), queda en el log del servidor.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CFG = require(ReplicatedStorage.Configs.ParcelasConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local NpcManager = require(script.Parent.Parent.NpcManager)
local VaultManager = require(script.Parent.VaultManager)
local ZoneManager = require(script.Parent.Parent.ZoneManager)

type Barrio = CFG.Barrio
type Permiso = CFG.Permiso

-- Una pieza construida, con la posición relativa al centro de la parcela.
export type Puesta = {
	Pieza: string,
	X: number,
	Y: number,
	Z: number,
	Giro: number,
	Cultivo: string?, -- semilla plantada, si es un cantero
	Desde: number?, -- cuándo se plantó
}

export type Registro = {
	Id: string,
	Dueno: number,
	DuenoNombre: string,
	Desde: number,
	Hasta: number, -- hasta cuándo está paga (os.time())
	Nombre: string?,
	Permisos: { [string]: Permiso }, -- UserId en texto -> nivel
	Fusion: { string }?, -- ids fusionados con esta
	Piezas: { Puesta }?, -- lo construido (ver ConstruccionManager)
	-- Foto de las mascotas del dueño, para que el patio las muestre aunque él
	-- no esté en este servidor.
	Mascotas: { string }?,
	Bando: string?, -- bando del dueño, para el estandarte
}

local ParcelaManager = {}

local NOMBRE_STORE = "Parcelas_v1"
-- Lo que acepta el remote (Guard.OneOf pide un mapa, no una lista).
local ACCIONES = {
	Comprar = true,
	Alquiler = true,
	Permiso = true,
	Renombrar = true,
	Fusionar = true,
	Abandonar = true,
}
local NIVELES = { Visita = true, Invitado = true, Socio = true }
local REFRESCO = 45 -- segundos que vale una lectura en caché

local store: DataStore? = nil
local sinCache: DataStoreGetOptions? = nil
local iniciado = false
local enCurso: { [Player]: boolean } = {}
local cache: { [string]: { hora: number, registro: Registro? } } = {}
local carteles: { [string]: TextLabel } = {}

local function avisar(player: Player, texto: string, tipo: string?)
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
	end
end

local function clave(id: string): string
	return `P_{(string.gsub(id, ":", "_"))}`
end

local function conReintentos<T>(intentos: number, fn: () -> T): (boolean, T?)
	local espera = 0.5
	for intento = 1, intentos do
		local ok, resultado = pcall(fn)
		if ok then
			return true, resultado
		end
		warn(`[Parcelas] intento {intento}/{intentos}: {resultado}`)
		if intento < intentos then
			task.wait(espera)
			espera *= 2
		end
	end
	return false, nil
end

local function obtenerStore(): DataStore
	assert(store, "ParcelaManager.Init() no se llamó")
	return store
end

------------------------------------------------------------------------
-- Lectura
------------------------------------------------------------------------

local function leer(id: string, frescura: number?): Registro?
	local guardado = cache[id]
	local tope = frescura or REFRESCO
	if guardado and os.clock() - guardado.hora < tope then
		return guardado.registro
	end
	local ok, valor = conReintentos(3, function()
		return obtenerStore():GetAsync(clave(id), sinCache)
	end)
	if not ok then
		return if guardado then guardado.registro else nil
	end
	local registro: Registro? = if typeof(valor) == "table" then valor :: any else nil
	cache[id] = { hora = os.clock(), registro = registro }
	return registro
end

-- Estado de una parcela tal como lo ve un jugador.
local function resumen(id: string, registro: Registro?, player: Player?): { [string]: any }
	local barrio, numero = CFG.Partir(id)
	local ahora = os.time()
	local datos: { [string]: any } = {
		Id = id,
		Barrio = if barrio then barrio.Id else "",
		Numero = numero,
		Precio = if barrio then barrio.Precio else 0,
	}
	if not registro or CFG.Libre(registro.Hasta, ahora) then
		datos.Estado = "Libre"
		return datos
	end
	datos.Estado = if CFG.Vencida(registro.Hasta, ahora) then "Vencida" else "Ocupada"
	datos.Dueno = registro.DuenoNombre
	datos.Nombre = registro.Nombre
	datos.Hasta = registro.Hasta
	datos.Fusion = registro.Fusion
	if player then
		datos.EsMia = registro.Dueno == player.UserId
		datos.MiPermiso = registro.Permisos[tostring(player.UserId)]
		if datos.EsMia then
			datos.Permisos = registro.Permisos
			datos.DiasQuePuedePagar = CFG.DiasQuePuedePagar(registro.Hasta, ahora)
		end
	end
	return datos
end

-- Nivel de alguien sobre una parcela: "Dueno", un permiso, o nil.
function ParcelaManager.Nivel(player: Player, id: string): string?
	local registro = leer(id)
	if not registro or CFG.Libre(registro.Hasta, os.time()) then
		return nil
	end
	if registro.Dueno == player.UserId then
		return "Dueno"
	end
	-- Con el alquiler vencido, los permisos de los demás no valen.
	if CFG.Vencida(registro.Hasta, os.time()) then
		return nil
	end
	return registro.Permisos[tostring(player.UserId)]
end

-- ¿Puede construir o abrir el cofre de bóveda de esa parcela?
function ParcelaManager.PuedeConstruir(player: Player, id: string): boolean
	local nivel = ParcelaManager.Nivel(player, id)
	return nivel == "Dueno" or CFG.PuedeConstruir(nivel)
end

------------------------------------------------------------------------
-- Escritura
------------------------------------------------------------------------

-- Aplica `cambiar` a la parcela. `cambiar` devuelve el registro nuevo, o nil
-- para no escribir nada (y entonces esta función devuelve false).
-- No cede el hilo adentro de `cambiar`.
local function escribir(id: string, cambiar: (Registro?) -> Registro?): (boolean, Registro?)
	local escrito: Registro? = nil
	local gano = false
	local ok = conReintentos(3, function()
		escrito = nil
		gano = false
		obtenerStore():UpdateAsync(clave(id), function(actual: Registro?): Registro?
			local nuevo = cambiar(actual)
			if nuevo == nil then
				return nil -- abortar: no escribe
			end
			escrito = nuevo
			gano = true
			return nuevo
		end)
		return true
	end)
	if ok and gano then
		cache[id] = { hora = os.clock(), registro = escrito }
		return true, escrito
	end
	if ok then
		-- La función abortó a propósito: la caché quedó al día igual.
		cache[id] = { hora = os.clock(), registro = cache[id] and cache[id].registro }
	end
	return false, nil
end

local function misParcelas(player: Player): { string }
	local datos = DataManager.GetData(player)
	if not datos then
		return {}
	end
	local lista: { string } = (datos :: any).Parcelas or {}
	return lista
end

local function anotarEnPerfil(player: Player, id: string, tenerla: boolean)
	DataManager.Mutar(player, "Parcelas", function(d)
		local libre: { [string]: any } = d :: any
		local lista: { string } = libre.Parcelas or {}
		local donde = table.find(lista, id)
		if tenerla and not donde then
			table.insert(lista, id)
		elseif not tenerla and donde then
			table.remove(lista, donde)
		end
		libre.Parcelas = lista
	end)
end

-- Para ConstruccionManager: leer y editar el registro sin duplicar la lógica
-- del DataStore. `Editar` no cede el hilo adentro de `cambiar`.
function ParcelaManager.Leer(id: string, frescura: number?): Registro?
	return leer(id, frescura)
end

function ParcelaManager.Editar(id: string, cambiar: (Registro?) -> Registro?): (boolean, Registro?)
	return escribir(id, cambiar)
end

------------------------------------------------------------------------
-- Operaciones
------------------------------------------------------------------------

local function unaPorVez(player: Player): boolean
	if enCurso[player] then
		return false
	end
	enCurso[player] = true
	return true
end

local function comprar(player: Player, id: string): Types.Respuesta
	local barrio = CFG.Partir(id)
	if not barrio then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if #misParcelas(player) >= CFG.MaxPorJugador then
		avisar(player, `Ya tenés {CFG.MaxPorJugador} parcelas. Soltá una para comprar otra.`)
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local registro = leer(id, 0)
	local ahora = os.time()
	if registro and not CFG.Libre(registro.Hasta, ahora) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end

	-- Se cobra y después se escribe; si no se gana la parcela, se devuelve.
	if not DataManager.SpendGold(player, barrio.Precio) then
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	local nuevo: Registro = {
		Id = id,
		Dueno = player.UserId,
		DuenoNombre = player.DisplayName,
		Desde = ahora,
		Hasta = ahora + CFG.DiasAlCompar * 86400,
		Permisos = {},
	}
	local gano = escribir(id, function(actual: Registro?): Registro?
		if actual and not CFG.Libre(actual.Hasta, ahora) then
			return nil -- otro servidor la tiene
		end
		return nuevo
	end)
	if not gano then
		DataManager.AddGold(player, barrio.Precio)
		avisar(player, "Esa parcela ya no está libre. No se te cobró nada.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	anotarEnPerfil(player, id, true)
	avisar(
		player,
		`Compraste {barrio.Nombre} #{select(2, CFG.Partir(id))}. Está paga por {CFG.DiasAlCompar} días.`,
		"Exito"
	)
	return NetworkBridge.Ok({ Parcela = resumen(id, nuevo, player) })
end

local function pagarAlquiler(player: Player, id: string, dias: number): Types.Respuesta
	local registro = leer(id, 0)
	if not registro or registro.Dueno ~= player.UserId then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local ahora = os.time()
	if CFG.Libre(registro.Hasta, ahora) then
		avisar(player, "Perdiste esa parcela: pasó el plazo de gracia.")
		anotarEnPerfil(player, id, false)
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local tope = CFG.DiasQuePuedePagar(registro.Hasta, ahora)
	if dias < 1 or dias > tope then
		avisar(player, `Podés pagar hasta {tope} días más.`)
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local costo = CFG.Alquiler(dias)
	if not DataManager.SpendGold(player, costo) then
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	local gano, escrito = escribir(id, function(actual: Registro?): Registro?
		if not actual or actual.Dueno ~= player.UserId then
			return nil
		end
		-- Si estaba vencida pero en gracia, el alquiler corre desde hoy.
		local base = math.max(actual.Hasta, ahora)
		actual.Hasta = base + dias * 86400
		return actual
	end)
	if not gano then
		DataManager.AddGold(player, costo)
		avisar(player, "No se pudo registrar el pago. No se te cobró nada.")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	avisar(player, `Alquiler pagado: {dias} día(s) por {costo} de oro.`, "Exito")
	return NetworkBridge.Ok({ Parcela = resumen(id, escrito, player) })
end

local function permiso(player: Player, id: string, usuarioId: number, nivel: string?): Types.Respuesta
	local registro = leer(id, 0)
	if not registro or registro.Dueno ~= player.UserId then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if usuarioId == player.UserId then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if nivel ~= nil and not CFG.PermisoValido(nivel) then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local gano, escrito = escribir(id, function(actual: Registro?): Registro?
		if not actual or actual.Dueno ~= player.UserId then
			return nil
		end
		local clave2 = tostring(usuarioId)
		if nivel == nil then
			actual.Permisos[clave2] = nil
			return actual
		end
		local cuantos = 0
		for _ in actual.Permisos do
			cuantos += 1
		end
		if actual.Permisos[clave2] == nil and cuantos >= CFG.MaxInvitados then
			return nil
		end
		actual.Permisos[clave2] = nivel :: Permiso
		return actual
	end)
	if not gano then
		avisar(player, `No se pudo cambiar el permiso (¿más de {CFG.MaxInvitados} invitados?).`)
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	avisar(player, if nivel then `Permiso puesto: {nivel}.` else "Permiso quitado.", "Exito")
	return NetworkBridge.Ok({ Parcela = resumen(id, escrito, player) })
end

local function renombrar(player: Player, id: string, nombre: string): Types.Respuesta
	if not CFG.NombreValido(nombre) then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local gano, escrito = escribir(id, function(actual: Registro?): Registro?
		if not actual or actual.Dueno ~= player.UserId then
			return nil
		end
		actual.Nombre = nombre
		return actual
	end)
	if not gano then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	ParcelaManager.RefrescarCarteles()
	return NetworkBridge.Ok({ Parcela = resumen(id, escrito, player) })
end

-- Fusionar dos parcelas vecinas y propias: comparten nombre y cofre, y el área
-- de construcción pasa a ser la suma de las dos.
local function fusionar(player: Player, idA: string, idB: string): Types.Respuesta
	if not CFG.Fusionables(idA, idB) then
		avisar(player, "Solo se fusionan parcelas vecinas del mismo barrio.")
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local a, b = leer(idA, 0), leer(idB, 0)
	local ahora = os.time()
	if not a or not b or a.Dueno ~= player.UserId or b.Dueno ~= player.UserId then
		avisar(player, "Las dos parcelas tienen que ser tuyas.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if CFG.Vencida(a.Hasta, ahora) or CFG.Vencida(b.Hasta, ahora) then
		avisar(player, "Primero poné al día el alquiler de las dos.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end

	local okA = escribir(idA, function(actual: Registro?): Registro?
		if not actual or actual.Dueno ~= player.UserId then
			return nil
		end
		local lista: { string } = actual.Fusion or {}
		if not table.find(lista, idB) then
			table.insert(lista, idB)
		end
		actual.Fusion = lista
		return actual
	end)
	if not okA then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	local okB = escribir(idB, function(actual: Registro?): Registro?
		if not actual or actual.Dueno ~= player.UserId then
			return nil
		end
		local lista: { string } = actual.Fusion or {}
		if not table.find(lista, idA) then
			table.insert(lista, idA)
		end
		actual.Fusion = lista
		return actual
	end)
	if not okB then
		-- Deshacer el lado que sí entró, para que no quede una fusión a medias.
		escribir(idA, function(actual: Registro?): Registro?
			if not actual then
				return nil
			end
			local lista: { string } = actual.Fusion or {}
			local donde = table.find(lista, idB)
			if donde then
				table.remove(lista, donde)
			end
			actual.Fusion = lista
			return actual
		end)
		avisar(player, "No se pudo fusionar. Quedó todo como estaba.")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	avisar(player, "Parcelas fusionadas.", "Exito")
	ParcelaManager.RefrescarCarteles()
	return NetworkBridge.Ok({ Fusion = { idA, idB } })
end

local function abandonar(player: Player, id: string): Types.Respuesta
	local gano = escribir(id, function(actual: Registro?): Registro?
		if not actual or actual.Dueno ~= player.UserId then
			return nil
		end
		-- Soltar también las fusiones que la tenían de compañera.
		return {
			Id = id,
			Dueno = 0,
			DuenoNombre = "",
			Desde = 0,
			Hasta = 0,
			Permisos = {},
		}
	end)
	if not gano then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	anotarEnPerfil(player, id, false)
	avisar(player, "Dejaste la parcela. No hay devolución del oro.", "Aviso")
	ParcelaManager.RefrescarCarteles()
	return NetworkBridge.Ok({ Parcela = resumen(id, nil, player) })
end

------------------------------------------------------------------------
-- Mundo: límites, cartel y cofre de bóveda
------------------------------------------------------------------------

local function barriosDeEsteServidor(): { Barrio }
	local zona = ZoneManager.ZonaActual()
	local lista: { Barrio } = {}
	for _, barrio in CFG.Barrios do
		-- En el servidor de pruebas se arman todos, así se pueden ver.
		if zona == "Pruebas" or barrio.Zona == zona then
			table.insert(lista, barrio)
		end
	end
	return lista
end

local function textoCartel(id: string): string
	local registro = leer(id)
	local barrio, numero = CFG.Partir(id)
	local titulo = if barrio then `{barrio.Nombre} #{numero}` else id
	if not registro or CFG.Libre(registro.Hasta, os.time()) then
		local precio = if barrio then barrio.Precio else 0
		return `{titulo}\nEN VENTA · {precio} de oro`
	end
	local nombre = registro.Nombre or `Casa de {registro.DuenoNombre}`
	if CFG.Vencida(registro.Hasta, os.time()) then
		return `{titulo}\n{nombre}\nALQUILER VENCIDO`
	end
	return `{titulo}\n{nombre}\nde {registro.DuenoNombre}`
end

function ParcelaManager.RefrescarCarteles()
	for id, etiqueta in carteles do
		if etiqueta.Parent then
			etiqueta.Text = textoCartel(id)
		else
			carteles[id] = nil
		end
	end
end

local function construirParcela(barrio: Barrio, numero: number, padre: Folder)
	local id = CFG.Id(barrio.Id, numero)
	local centro = CFG.Centro(barrio, numero)
	local carpeta = Instance.new("Folder")
	carpeta.Name = id
	carpeta:SetAttribute("Parcela", id)
	carpeta.Parent = padre

	local piso = Instance.new("Part")
	piso.Name = "Piso"
	piso.Anchored = true
	piso.Size = Vector3.new(barrio.Lado, 1, barrio.Lado)
	piso.Position = centro
	piso.Color = Color3.fromRGB(135, 125, 110)
	piso.Material = Enum.Material.Ground
	piso.TopSurface = Enum.SurfaceType.Smooth
	piso:SetAttribute("Parcela", id)
	piso.Parent = carpeta

	-- Cuatro postes para que se vea el límite sin tapar la vista.
	local mitad = barrio.Lado / 2
	for i, esquina in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		local poste = Instance.new("Part")
		poste.Name = `Poste{i}`
		poste.Anchored = true
		poste.Size = Vector3.new(1.4, 7, 1.4)
		poste.Position = centro + Vector3.new(esquina.X * mitad, 4, esquina.Y * mitad)
		poste.Color = Color3.fromRGB(95, 70, 45)
		poste.Material = Enum.Material.Wood
		poste.Parent = carpeta
	end

	-- Cartel con el estado, visible de lejos.
	local mastil = Instance.new("Part")
	mastil.Name = "Cartel"
	mastil.Anchored = true
	mastil.Size = Vector3.new(1, 9, 1)
	mastil.Position = centro + Vector3.new(0, 5, -mitad - 2)
	mastil.Color = Color3.fromRGB(110, 85, 55)
	mastil.Material = Enum.Material.Wood
	mastil.Parent = carpeta

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(240, 90)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	billboard.MaxDistance = 220
	billboard.AlwaysOnTop = false
	billboard.Parent = mastil

	local etiqueta = Instance.new("TextLabel")
	etiqueta.Size = UDim2.fromScale(1, 1)
	etiqueta.BackgroundTransparency = 0.3
	etiqueta.BackgroundColor3 = Color3.fromRGB(25, 22, 18)
	etiqueta.TextColor3 = Color3.fromRGB(245, 235, 210)
	etiqueta.TextScaled = true
	etiqueta.Font = Enum.Font.GothamMedium
	etiqueta.Text = textoCartel(id)
	etiqueta.Parent = billboard
	carteles[id] = etiqueta

	-- Cofre de bóveda de la parcela: el tag lo usa VaultManager y el atributo
	-- Parcela es lo que le deja preguntar si este jugador tiene permiso.
	local cofre = Instance.new("Part")
	cofre.Name = "CofreVault"
	cofre.Anchored = true
	cofre.Size = Vector3.new(4, 3, 2.5)
	cofre.Position = centro + Vector3.new(mitad - 4, 2, -mitad + 4)
	cofre.Color = Color3.fromRGB(120, 85, 45)
	cofre.Material = Enum.Material.WoodPlanks
	cofre:SetAttribute("Parcela", id)
	cofre.Parent = carpeta
	CollectionService:AddTag(cofre, "CofreVault")
end

local function construirMundo()
	local barrios = barriosDeEsteServidor()
	if #barrios == 0 then
		return
	end
	local padre = Instance.new("Folder")
	padre.Name = "Parcelas"
	padre.Parent = Workspace
	for _, barrio in barrios do
		for numero = 1, CFG.CantidadDe(barrio) do
			construirParcela(barrio, numero, padre)
		end
	end
	if RunService:IsStudio() then
		print(`[Parcelas] {#barrios} barrio(s) armados; la primera está en {CFG.Centro(barrios[1], 1)}`)
	end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

local function listar(player: Player, barrioId: string?): Types.Respuesta
	local lista: { any } = {}
	for _, barrio in CFG.Barrios do
		if barrioId and barrio.Id ~= barrioId then
			continue
		end
		for numero = 1, CFG.CantidadDe(barrio) do
			local id = CFG.Id(barrio.Id, numero)
			table.insert(lista, resumen(id, leer(id), player))
		end
	end
	return NetworkBridge.Ok({ Parcelas = lista, Mias = misParcelas(player), Alquiler = CFG.AlquilerDiario })
end

function ParcelaManager.Init()
	if iniciado then
		return
	end
	iniciado = true
	store = DataStoreService:GetDataStore(NOMBRE_STORE)
	local opciones = Instance.new("DataStoreGetOptions")
	opciones.UseCache = false
	sinCache = opciones

	construirMundo()

	-- VaultManager pregunta esto cuando el cofre tiene atributo Parcela.
	VaultManager.SetPermisoParcela(function(player: Player, id: string): boolean
		return ParcelaManager.PuedeConstruir(player, id)
	end)

	-- Arquitecto de Viviendas (NPC-033).
	NpcManager.RegistrarAccion("ParcelasAbrir", function(player: Player): boolean
		NetworkBridge.Server.FireClient("ParcelaPanel", player, true)
		return true
	end)

	NetworkBridge.Server.OnInvoke("ParcelaListar", function(player: Player, barrioId: unknown): Types.Respuesta
		local id = if barrioId == nil then nil else NetworkBridge.Guard.String(barrioId, 32)
		if barrioId ~= nil and not id then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return listar(player, id)
	end)

	NetworkBridge.Server.OnInvoke(
		"ParcelaAccion",
		function(player: Player, accion: unknown, id: unknown, extra: unknown): Types.Respuesta
			local nombreAccion = NetworkBridge.Guard.OneOf(accion, ACCIONES)
			local parcelaId = NetworkBridge.Guard.String(id, 48)
			if not nombreAccion or not parcelaId or not CFG.Valido(parcelaId) then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if not DataManager.GetData(player) then
				return NetworkBridge.Fail("DATA_NOT_LOADED")
			end
			if not unaPorVez(player) then
				return NetworkBridge.Fail("RATE_LIMITED")
			end

			local ok, resultado = pcall(function(): Types.Respuesta
				if nombreAccion == "Comprar" then
					return comprar(player, parcelaId)
				elseif nombreAccion == "Alquiler" then
					local dias = NetworkBridge.Guard.Integer(extra, 1, CFG.DiasMaximos)
					if not dias then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					return pagarAlquiler(player, parcelaId, dias)
				elseif nombreAccion == "Permiso" then
					-- extra = { Usuario = <UserId>, Nivel = <"Socio"|...|nil> }
					if typeof(extra) ~= "table" then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					local tabla: { [string]: unknown } = extra :: any
					local usuario = NetworkBridge.Guard.Integer(tabla.Usuario, 1, 2 ^ 53)
					if not usuario then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					local nivel = if tabla.Nivel == nil then nil else NetworkBridge.Guard.OneOf(tabla.Nivel, NIVELES)
					if tabla.Nivel ~= nil and not nivel then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					return permiso(player, parcelaId, usuario, nivel)
				elseif nombreAccion == "Renombrar" then
					local nombre = NetworkBridge.Guard.String(extra, CFG.LargoNombre)
					if not nombre then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					return renombrar(player, parcelaId, nombre)
				elseif nombreAccion == "Fusionar" then
					local otra = NetworkBridge.Guard.String(extra, 48)
					if not otra or not CFG.Valido(otra) then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					return fusionar(player, parcelaId, otra)
				end
				return abandonar(player, parcelaId)
			end)
			enCurso[player] = nil
			if not ok then
				warn(`[Parcelas] {nombreAccion} falló: {resultado}`)
				return NetworkBridge.Fail("INTERNAL_ERROR")
			end
			return resultado
		end
	)

	Players.PlayerRemoving:Connect(function(player: Player)
		enCurso[player] = nil
	end)

	-- Los carteles se refrescan solos: otro servidor pudo vender o perder una.
	task.spawn(function()
		while true do
			task.wait(REFRESCO)
			pcall(ParcelaManager.RefrescarCarteles)
		end
	end)
end

return ParcelaManager
