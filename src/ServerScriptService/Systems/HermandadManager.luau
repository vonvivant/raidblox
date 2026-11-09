--!strict
-- HermandadManager: hermandades (guilds) persistentes entre servidores.
--
-- Claves del DataStore (todas se escriben con UpdateAsync):
--   G_<id>   la hermandad: nombre, líder, miembros con su rango, permisos por
--            rango e historial (altas, bajas, rangos).
--   B_<id>   el banco: oro, 4 pestañas de ítems, registro de movimientos y
--            las últimas operaciones aplicadas (Ops) para no aplicar dos veces.
--   N_<nombre en minúsculas>  reserva del nombre ("" = libre).
--   J_<userId>  en qué hermandad está el jugador ("" = ninguna). Se escribe
--            ANTES de sumarlo a G_ y se borra DESPUÉS de sacarlo: si algo se
--            corta en el medio, al entrar se ve que G_ no lo lista y se limpia.
--
-- Quién está conectado (y en qué zona) va en un SortedMap de MemoryStore por
-- hermandad, que vence solo si el servidor se cae. Los cambios se avisan a los
-- otros servidores por MessagingService.
--
-- Banco, sin duplicados:
--   * Depositar: sale del inventario, se escribe B_ con un id de operación.
--     Si la escritura falla se lee B_: solo si la operación NO está, se devuelve
--     (y si no se puede saber, se vuelve a mirar más tarde antes de devolver).
--   * Retirar: B_ quita el ítem y guarda la operación con el ítem; recién
--     entonces se entrega. Retirar siempre relee los permisos sin caché.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local DataManager = require(script.Parent.DataManager)
local Buzon = require(script.Parent.Buzon)
local ZoneManager = require(script.Parent.ZoneManager)

type Respuesta = Types.Respuesta
type ItemInstancia = Types.ItemInstancia

type Miembro = {
	Rango: string,
	Nombre: string,
	Nivel: number,
	Clase: string,
	Zona: string,
	UltimaVez: number,
	Ingreso: number,
}
type Hermandad = {
	Id: string,
	Nombre: string,
	Creada: number,
	Lider: number,
	Miembros: { [string]: Miembro },
	Permisos: { [string]: { [string]: boolean } },
	Historial: { { T: number, A: string } },
	Disuelta: boolean?,
}
type Op = { Id: string, T: number, Item: ItemInstancia?, Oro: number? }
type Movimiento = { T: number, U: number, N: string, A: string, D: string }
type Banco = {
	Oro: number,
	Pestanas: { [string]: { [string]: ItemInstancia } },
	Registro: { Movimiento },
	Ops: { Op },
}

local CFG = GameConfig.Hermandades
local SUFIJO = if RunService:IsStudio() then "_Studio" else ""
local TOPICO = "Hermandades" .. SUFIJO
local CACHE_SEGUNDOS = 20
local VENCE_EN_LINEA = 150
local LATIDO = 60
local MAX_OPS = 100
local NIVEL_RANGO: { [string]: number } = { Lider = 4, Oficial = 3, Miembro = 2, Recluta = 1 }

local HermandadManager = {}

local hermandadDe: { [Player]: string } = {}
local ultimoEstado: { [Player]: { Nivel: number, Clase: string } } = {}
local invitaciones: { [Player]: { [string]: { Vence: number, Nombre: string } } } = {}
local ocupado: { [Player]: boolean } = {}
local ultimaLlamada: { [Player]: { [string]: number } } = {}
local cache: { [string]: { Datos: Hermandad?, Hora: number } } = {}
local reconciliando: { [string]: boolean } = {}
local enCurso = 0
local iniciado = false

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local store: DataStore? = nil
local function obtenerStore(): DataStore
	local s = store
	if not s then
		s = DataStoreService:GetDataStore(CFG.NombreStore .. SUFIJO)
		store = s
	end
	return s :: DataStore
end

local function enLineaDe(gid: string): MemoryStoreSortedMap
	return MemoryStoreService:GetSortedMap(`{CFG.NombreEnLinea}{SUFIJO}_{gid}`)
end

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function enfriado(player: Player, accion: string, segundos: number): boolean
	local mias = ultimaLlamada[player]
	if not mias then
		mias = {}
		ultimaLlamada[player] = mias
	end
	local ahora = os.clock()
	if ahora - (mias[accion] or -math.huge) < segundos then
		return true
	end
	mias[accion] = ahora
	return false
end

-- Lee una clave con reintentos. (llamadaOk, valor)
local function leer(clave: string): (boolean, any)
	for intento = 1, 3 do
		local ok, valor = pcall(function(): any
			return obtenerStore():GetAsync(clave)
		end)
		if ok then
			return true, valor
		end
		task.wait(intento)
	end
	return false, nil
end

-- UpdateAsync con reintentos. La transformación devuelve nil para no escribir.
-- (llamadaOk, valor escrito o nil si se abortó). llamadaOk = false: no se sabe
-- si se escribió.
local function actualizar(clave: string, transformar: (any) -> any): (boolean, any)
	for intento = 1, 3 do
		local ok, valor = pcall(function(): any
			return obtenerStore():UpdateAsync(clave, transformar)
		end)
		if ok then
			return true, valor
		end
		task.wait(intento)
	end
	return false, nil
end

local function trabajo(fn: () -> ())
	enCurso += 1
	local ok, err = pcall(function(): nil
		fn()
		return nil
	end)
	enCurso -= 1
	if not ok then
		warn(`[Hermandad] {err}`)
	end
end

local function nivelRango(rango: string?): number
	return if rango then NIVEL_RANGO[rango] or 0 else 0
end

local function rangoDe(g: Hermandad, userId: number): string?
	local m = g.Miembros[tostring(userId)]
	return m and m.Rango
end

local function puede(g: Hermandad, userId: number, permiso: string): boolean
	local rango = rangoDe(g, userId)
	if rango == "Lider" then
		return true
	end
	local permisos = rango and g.Permisos[rango]
	return permisos ~= nil and permisos[permiso] == true
end

local function contar(t: { [string]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function historial(g: Hermandad, texto: string)
	table.insert(g.Historial, { T = os.time(), A = texto })
	while #g.Historial > CFG.MaxHistorial do
		table.remove(g.Historial, 1)
	end
end

local function zonaActual(): string
	return ZoneManager.ZonaActual() or "Desconocida"
end

local function estadoJugador(player: Player): { Nivel: number, Clase: string }
	local datos = DataManager.GetData(player)
	if datos then
		local e = { Nivel = datos.Nivel, Clase = datos.Clase :: string }
		ultimoEstado[player] = e
		return e
	end
	return ultimoEstado[player] or { Nivel = 1, Clase = "Guerrero" }
end

local function nuevoMiembro(player: Player, rango: string): Miembro
	local e = estadoJugador(player)
	return {
		Rango = rango,
		Nombre = player.DisplayName,
		Nivel = e.Nivel,
		Clase = e.Clase,
		Zona = zonaActual(),
		UltimaVez = os.time(),
		Ingreso = os.time(),
	}
end

local function nombreItem(item: ItemInstancia): string
	local def = ItemCatalog[item.ItemId]
	return `{if def then def.Nombre else item.ItemId} x{item.Cantidad} ({item.Rareza})`
end

local function bancoVacio(): Banco
	local pestanas: { [string]: { [string]: ItemInstancia } } = {}
	for i = 1, CFG.Pestanas do
		pestanas[tostring(i)] = {}
	end
	return { Oro = 0, Pestanas = pestanas, Registro = {}, Ops = {} }
end

local function buscarOp(b: Banco, id: string): Op?
	for i = #b.Ops, 1, -1 do
		if b.Ops[i].Id == id then
			return b.Ops[i]
		end
	end
	return nil
end

local function anotar(b: Banco, op: Op, player: Player, accion: string, detalle: string)
	table.insert(b.Ops, op)
	while #b.Ops > MAX_OPS do
		table.remove(b.Ops, 1)
	end
	table.insert(b.Registro, { T = os.time(), U = player.UserId, N = player.DisplayName, A = accion, D = detalle })
	while #b.Registro > CFG.MaxRegistro do
		table.remove(b.Registro, 1)
	end
end

------------------------------------------------------------------------
-- Lectura con caché
------------------------------------------------------------------------

local function leerHermandad(gid: string, fresco: boolean): (boolean, Hermandad?)
	local c = cache[gid]
	if not fresco and c and os.clock() - c.Hora < CACHE_SEGUNDOS then
		return true, c.Datos
	end
	local ok, valor = leer(`G_{gid}`)
	if not ok then
		return false, nil
	end
	local g: Hermandad? = if typeof(valor) == "table" and not valor.Disuelta then valor else nil
	cache[gid] = { Datos = g, Hora = os.clock() }
	return true, g
end

local function guardarCache(gid: string, g: Hermandad?)
	cache[gid] = { Datos = if g and not g.Disuelta then g else nil, Hora = os.clock() }
end

-- Escribe G_ y actualiza la caché. motivo: por qué se abortó (si se abortó).
local function actualizarHermandad(gid: string, cambiar: (Hermandad) -> string?): (boolean, Hermandad?, string?)
	local motivo: string? = nil
	local ok, valor = actualizar(`G_{gid}`, function(actual: any): any
		motivo = nil
		if typeof(actual) ~= "table" or actual.Disuelta then
			motivo = "NO_EXISTE"
			return nil
		end
		motivo = cambiar(actual :: Hermandad)
		return if motivo then nil else actual
	end)
	if ok and valor then
		guardarCache(gid, valor)
	end
	return ok, valor, motivo
end

-- J_ y N_: "" = libre.
local function reservar(clave: string, valor: string): (boolean, boolean)
	local ok, escrito = actualizar(clave, function(actual: any): any
		if actual == nil or actual == "" or actual == valor then
			return valor
		end
		return nil
	end)
	return ok, ok and escrito == valor
end

local function liberar(clave: string, valor: string)
	actualizar(clave, function(actual: any): any
		return if actual == valor then "" else nil
	end)
end

------------------------------------------------------------------------
-- Estado local y avisos entre servidores
------------------------------------------------------------------------

local function marcarEnLinea(player: Player)
	local gid = hermandadDe[player]
	if not gid then
		return
	end
	local e = estadoJugador(player)
	pcall(function()
		enLineaDe(gid):SetAsync(
			tostring(player.UserId),
			{ N = player.DisplayName, Nv = e.Nivel, C = e.Clase, Z = zonaActual() },
			VENCE_EN_LINEA
		)
	end)
end

local function establecer(player: Player, g: Hermandad?, que: string?)
	if g then
		hermandadDe[player] = g.Id
		player:SetAttribute("HermandadId", g.Id)
		player:SetAttribute("Hermandad", g.Nombre)
		NetworkBridge.Server.FireClient("HermandadCambio", player, { Id = g.Id, Nombre = g.Nombre }, que or "miembros")
	else
		local anterior = hermandadDe[player]
		hermandadDe[player] = nil
		player:SetAttribute("HermandadId", nil)
		player:SetAttribute("Hermandad", nil)
		NetworkBridge.Server.FireClient("HermandadCambio", player, nil, que or "miembros")
		if anterior then
			task.spawn(pcall, function()
				enLineaDe(anterior):RemoveAsync(tostring(player.UserId))
			end)
		end
	end
end

local function publicar(gid: string, tipo: string)
	task.spawn(pcall, function()
		MessagingService:PublishAsync(TOPICO, { G = gid, T = tipo, J = game.JobId })
	end)
end

-- Ajusta a los jugadores de ESTE servidor según el estado de la hermandad.
local function aplicarLocal(gid: string, g: Hermandad?, tipo: string)
	for player, suGid in hermandadDe do
		if suGid ~= gid then
			continue
		end
		if not g or not g.Miembros[tostring(player.UserId)] then
			establecer(player, nil)
			avisar(player, "Ya no formás parte de la hermandad.", "Error")
		else
			establecer(player, g, tipo)
		end
	end
end

local function notificar(gid: string, g: Hermandad?, tipo: string)
	aplicarLocal(gid, g, tipo)
	publicar(gid, tipo)
end

-- El banco cambió: las ventanas abiertas se refrescan.
local function bancoLocal(gid: string)
	for player, suGid in hermandadDe do
		if suGid == gid then
			NetworkBridge.Server.FireClient(
				"HermandadCambio",
				player,
				{ Id = gid, Nombre = player:GetAttribute("Hermandad") },
				"banco"
			)
		end
	end
end

local function avisarBanco(gid: string)
	bancoLocal(gid)
	publicar(gid, "banco")
end

local function alMensaje(mensaje: any)
	local datos = typeof(mensaje) == "table" and mensaje.Data
	if typeof(datos) ~= "table" or typeof(datos.G) ~= "string" or datos.J == game.JobId then
		return
	end
	local gid: string = datos.G
	local tipo = if datos.T == "banco" then "banco" else "miembros"
	local hay = false
	for _, suGid in hermandadDe do
		if suGid == gid then
			hay = true
			break
		end
	end
	if not hay then
		cache[gid] = nil
		return
	end
	if tipo == "banco" then
		bancoLocal(gid)
		return
	end
	if reconciliando[gid] then
		return
	end
	reconciliando[gid] = true
	task.delay(0.5, function()
		local ok, g = leerHermandad(gid, true)
		reconciliando[gid] = nil
		if ok then
			aplicarLocal(gid, g, tipo)
		end
	end)
end

------------------------------------------------------------------------
-- Entrar y salir del juego
------------------------------------------------------------------------

local function alCargar(player: Player)
	estadoJugador(player)
	local ok, gid = leer(`J_{player.UserId}`)
	if not ok or typeof(gid) ~= "string" or gid == "" or player.Parent ~= Players then
		return
	end
	local okG, g = leerHermandad(gid, true)
	if not okG or player.Parent ~= Players then
		return
	end
	if g and g.Miembros[tostring(player.UserId)] then
		establecer(player, g)
		marcarEnLinea(player)
	else
		-- Quedó anotado en J_ pero la hermandad ya no lo lista.
		liberar(`J_{player.UserId}`, gid)
	end
end

local function alSalir(player: Player)
	local gid = hermandadDe[player]
	local e = ultimoEstado[player]
	hermandadDe[player] = nil
	ultimoEstado[player] = nil
	invitaciones[player] = nil
	ocupado[player] = nil
	ultimaLlamada[player] = nil
	if not gid then
		return
	end
	local uid = tostring(player.UserId)
	local nombre = player.DisplayName
	task.spawn(trabajo, function()
		pcall(function()
			enLineaDe(gid):RemoveAsync(uid)
		end)
		actualizarHermandad(gid, function(h: Hermandad): string?
			local m = h.Miembros[uid]
			if not m then
				return "NO_MIEMBRO"
			end
			m.Nombre = nombre
			m.UltimaVez = os.time()
			m.Zona = zonaActual()
			if e then
				m.Nivel = e.Nivel
				m.Clase = e.Clase
			end
			return nil
		end)
	end)
end

------------------------------------------------------------------------
-- Crear, invitar, salir
------------------------------------------------------------------------

local function limpiarNombre(texto: string): string?
	local limpio = string.gsub(string.gsub(texto, "%c", ""), "%s+", " ")
	limpio = string.match(limpio, "^%s*(.-)%s*$") or ""
	local largo = utf8.len(limpio)
	-- Tope en bytes: la clave N_<nombre> del DataStore admite hasta 50.
	if not largo or largo < CFG.LargoNombre.Min or largo > CFG.LargoNombre.Max or #limpio > 40 then
		return nil
	end
	return limpio
end

local function crear(player: Player, texto: string): Respuesta
	if hermandadDe[player] then
		avisar(player, "Ya estás en una hermandad.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local datos = DataManager.GetData(player)
	if not datos then
		return NetworkBridge.Fail("DATA_NOT_LOADED")
	end
	if not Pruebas.Activas() and datos.Nivel < CFG.NivelMinimo then
		avisar(player, `Necesitás nivel {CFG.NivelMinimo} para fundar una hermandad.`, "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if datos.Oro < CFG.CostoCreacion then
		avisar(player, `Fundar una hermandad cuesta {CFG.CostoCreacion} de oro.`, "Error")
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	local nombre = limpiarNombre(texto)
	if not nombre then
		avisar(player, `El nombre debe tener entre {CFG.LargoNombre.Min} y {CFG.LargoNombre.Max} letras.`, "Error")
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	local okFiltro, filtrado = pcall(function(): string
		local resultado = TextService:FilterStringAsync(nombre, player.UserId, Enum.TextFilterContext.PublicChat)
		return resultado:GetNonChatStringForBroadcastAsync()
	end)
	if not okFiltro then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if filtrado ~= nombre then
		avisar(player, "Ese nombre no está permitido.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not DataManager.SpendGold(player, CFG.CostoCreacion) then
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end

	local gid = HttpService:GenerateGUID(false)
	local claveNombre = `N_{string.lower(nombre)}`
	local claveJugador = `J_{player.UserId}`
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	local creada: Hermandad? = nil
	trabajo(function()
		local okN, nombreLibre = reservar(claveNombre, gid)
		if not okN or not nombreLibre then
			-- Si no se supo si se escribió, se libera por las dudas (solo si es nuestro).
			liberar(claveNombre, gid)
			if okN then
				avisar(player, "Ya existe una hermandad con ese nombre.", "Error")
				resultado = NetworkBridge.Fail("NOT_ALLOWED")
			end
			return
		end
		local okJ, jugadorLibre = reservar(claveJugador, gid)
		if not okJ or not jugadorLibre then
			liberar(claveJugador, gid)
			liberar(claveNombre, gid)
			if okJ then
				avisar(player, "Ya estás en una hermandad.", "Error")
				resultado = NetworkBridge.Fail("NOT_ALLOWED")
			end
			return
		end
		local g: Hermandad = {
			Id = gid,
			Nombre = nombre,
			Creada = os.time(),
			Lider = player.UserId,
			Miembros = { [tostring(player.UserId)] = nuevoMiembro(player, "Lider") },
			Permisos = {},
			Historial = {},
		}
		for rango: string, permisos: any in CFG.PermisosIniciales :: any do
			g.Permisos[rango] = table.clone(permisos)
		end
		historial(g, `{player.DisplayName} fundó la hermandad.`)
		local okG, escrito = actualizar(`G_{gid}`, function(actual: any): any
			return if actual == nil then g else nil
		end)
		if not okG or not escrito then
			liberar(claveJugador, gid)
			liberar(claveNombre, gid)
			return
		end
		creada = escrito
		resultado = NetworkBridge.Ok(nil)
	end)

	local g = creada
	if g then
		guardarCache(gid, g)
		establecer(player, g)
		marcarEnLinea(player)
		avisar(player, `¡Fundaste la hermandad {nombre}!`, "Oro")
	else
		Buzon.DarOro(player, CFG.CostoCreacion, "Fundar hermandad (devolución)")
		if resultado.ErrorCode == "INTERNAL_ERROR" then
			avisar(player, "No se pudo crear la hermandad. Te devolvimos el oro.", "Error")
		end
	end
	return resultado
end

local function invitar(player: Player, userId: number): Respuesta
	local gid = hermandadDe[player]
	local invitado = Players:GetPlayerByUserId(userId)
	if not gid then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not invitado or invitado == player then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if hermandadDe[invitado] then
		avisar(player, `{invitado.DisplayName} ya está en una hermandad.`, "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local ok, g = leerHermandad(gid, false)
	if not ok then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if not g or not puede(g, player.UserId, "Invitar") then
		avisar(player, "Tu rango no puede invitar.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if contar(g.Miembros) >= CFG.MaxMiembros then
		avisar(player, "La hermandad está llena.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local suyas = invitaciones[invitado]
	if not suyas then
		suyas = {}
		invitaciones[invitado] = suyas
	end
	suyas[gid] = { Vence = os.clock() + CFG.ExpiraInvitacion, Nombre = g.Nombre }
	NetworkBridge.Server.FireClient("HermandadInvitacion", invitado, gid, g.Nombre, player.DisplayName)
	avisar(player, `Invitaste a {invitado.DisplayName} a {g.Nombre}.`)
	return NetworkBridge.Ok(nil)
end

local function responder(player: Player, gid: string, acepta: boolean): Respuesta
	local suyas = invitaciones[player]
	local inv = suyas and suyas[gid]
	if suyas then
		suyas[gid] = nil
	end
	if not inv or os.clock() > inv.Vence then
		avisar(player, "La invitación ya no es válida.", "Error")
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if not acepta then
		return NetworkBridge.Ok(nil)
	end
	if hermandadDe[player] then
		avisar(player, "Ya estás en una hermandad.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local claveJugador = `J_{player.UserId}`
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	local unida: Hermandad? = nil
	trabajo(function()
		local okJ, libre = reservar(claveJugador, gid)
		if not okJ or not libre then
			if okJ then
				avisar(player, "Ya estás en una hermandad.", "Error")
				resultado = NetworkBridge.Fail("NOT_ALLOWED")
			end
			return
		end
		local uid = tostring(player.UserId)
		local ok, g, motivo = actualizarHermandad(gid, function(h: Hermandad): string?
			if h.Miembros[uid] then
				return nil
			end
			if contar(h.Miembros) >= CFG.MaxMiembros then
				return "LLENA"
			end
			h.Miembros[uid] = nuevoMiembro(player, "Recluta")
			historial(h, `{player.DisplayName} se unió.`)
			return nil
		end)
		if ok and g then
			unida = g
			resultado = NetworkBridge.Ok(nil)
			return
		end
		if ok then
			-- Se abortó: no quedó en la hermandad, se libera J_.
			liberar(claveJugador, gid)
			avisar(
				player,
				if motivo == "LLENA" then "La hermandad está llena." else "La hermandad ya no existe.",
				"Error"
			)
			resultado = NetworkBridge.Fail("NOT_ALLOWED")
		end
		-- Si no se sabe si se escribió, J_ queda: al reconectarse se verifica.
	end)
	local g = unida
	if g then
		establecer(player, g)
		marcarEnLinea(player)
		avisar(player, `Te uniste a {g.Nombre}.`, "Oro")
		for otro, suGid in hermandadDe do
			if suGid == gid and otro ~= player then
				avisar(otro, `{player.DisplayName} se unió a la hermandad.`)
			end
		end
		notificar(gid, g, "miembros")
	end
	return resultado
end

-- Saca a un jugador (por salir o por expulsión) de G_ y luego libera su J_.
local function sacar(gid: string, userId: number, texto: string): (boolean, Hermandad?, string?)
	local uid = tostring(userId)
	local ok, g, motivo = actualizarHermandad(gid, function(h: Hermandad): string?
		local m = h.Miembros[uid]
		if not m then
			return "NO_MIEMBRO"
		end
		if m.Rango == "Lider" then
			return "ES_LIDER"
		end
		h.Miembros[uid] = nil
		historial(h, texto)
		return nil
	end)
	if ok and (g or motivo == "NO_MIEMBRO") then
		liberar(`J_{userId}`, gid)
		local local_ = Players:GetPlayerByUserId(userId)
		if local_ and hermandadDe[local_] == gid then
			establecer(local_, nil)
		end
	end
	return ok, g, motivo
end

local function salir(player: Player): Respuesta
	local gid = hermandadDe[player]
	if not gid then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	trabajo(function()
		local ok, g, motivo = sacar(gid, player.UserId, `{player.DisplayName} se fue.`)
		if not ok then
			return
		end
		if motivo == "ES_LIDER" then
			avisar(player, "Pasá el liderazgo antes de irte (o disolvé la hermandad si estás solo).", "Error")
			resultado = NetworkBridge.Fail("NOT_ALLOWED")
			return
		end
		avisar(player, "Saliste de la hermandad.")
		notificar(gid, g, "miembros")
		resultado = NetworkBridge.Ok(nil)
	end)
	return resultado
end

local function disolver(player: Player): Respuesta
	local gid = hermandadDe[player]
	if not gid then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	trabajo(function()
		local okB, b = leer(`B_{gid}`)
		if not okB then
			return
		end
		if typeof(b) == "table" then
			local banco = b :: Banco
			local vacio = banco.Oro <= 0
			for _, pestana in banco.Pestanas do
				if next(pestana) ~= nil then
					vacio = false
				end
			end
			if not vacio then
				avisar(player, "Vaciá el banco antes de disolver la hermandad.", "Error")
				resultado = NetworkBridge.Fail("NOT_ALLOWED")
				return
			end
		end
		local nombre = ""
		local motivo: string? = nil
		local ok, escrito = actualizar(`G_{gid}`, function(actual: any): any
			motivo = nil
			if typeof(actual) ~= "table" or actual.Disuelta then
				motivo = "NO_EXISTE"
				return nil
			end
			local g = actual :: Hermandad
			if rangoDe(g, player.UserId) ~= "Lider" then
				motivo = "NO_LIDER"
				return nil
			end
			if contar(g.Miembros) > 1 then
				motivo = "MIEMBROS"
				return nil
			end
			nombre = g.Nombre
			return { Id = gid, Disuelta = true }
		end)
		if not ok then
			return
		end
		if not escrito then
			avisar(
				player,
				if motivo == "MIEMBROS"
					then "Solo se puede disolver cuando quedás solo en la hermandad."
					else "No podés disolver esta hermandad.",
				"Error"
			)
			resultado = NetworkBridge.Fail("NOT_ALLOWED")
			return
		end
		guardarCache(gid, nil)
		liberar(`N_{string.lower(nombre)}`, gid)
		liberar(`J_{player.UserId}`, gid)
		establecer(player, nil)
		avisar(player, `Disolviste {nombre}.`)
		publicar(gid, "miembros")
		resultado = NetworkBridge.Ok(nil)
	end)
	return resultado
end

------------------------------------------------------------------------
-- Rangos y permisos
------------------------------------------------------------------------

local function expulsar(player: Player, userId: number): Respuesta
	local gid = hermandadDe[player]
	if not gid or userId == player.UserId then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local ok, g = leerHermandad(gid, true)
	if not ok then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	local objetivo = g and g.Miembros[tostring(userId)]
	if not g or not objetivo then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if
		not puede(g, player.UserId, "Expulsar")
		or nivelRango(rangoDe(g, player.UserId)) <= nivelRango(objetivo.Rango)
	then
		avisar(player, "No podés expulsar a ese miembro.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	trabajo(function()
		local okS, nuevo, motivo = sacar(gid, userId, `{player.DisplayName} expulsó a {objetivo.Nombre}.`)
		if not okS then
			return
		end
		if motivo == "ES_LIDER" then
			resultado = NetworkBridge.Fail("NOT_ALLOWED")
			return
		end
		local local_ = Players:GetPlayerByUserId(userId)
		if local_ then
			avisar(local_, "Te expulsaron de la hermandad.", "Error")
		end
		avisar(player, `Expulsaste a {objetivo.Nombre}.`)
		notificar(gid, nuevo, "miembros")
		resultado = NetworkBridge.Ok(nil)
	end)
	return resultado
end

local function cambiarRango(player: Player, userId: number, rango: string): Respuesta
	local gid = hermandadDe[player]
	if not gid or userId == player.UserId or rango == "Lider" or not NIVEL_RANGO[rango] then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	trabajo(function()
		local nombre = ""
		local ok, g, motivo = actualizarHermandad(gid, function(h: Hermandad): string?
			local mio = nivelRango(rangoDe(h, player.UserId))
			local objetivo = h.Miembros[tostring(userId)]
			if not objetivo then
				return "NO_MIEMBRO"
			end
			if
				not puede(h, player.UserId, "Rangos")
				or mio <= nivelRango(objetivo.Rango)
				or mio <= nivelRango(rango)
			then
				return "SIN_PERMISO"
			end
			if objetivo.Rango == rango then
				return "IGUAL"
			end
			objetivo.Rango = rango
			nombre = objetivo.Nombre
			historial(h, `{player.DisplayName} pasó a {objetivo.Nombre} a {rango}.`)
			return nil
		end)
		if not ok then
			return
		end
		if not g then
			if motivo == "SIN_PERMISO" then
				avisar(player, "No podés darle ese rango.", "Error")
			end
			resultado = NetworkBridge.Fail(if motivo == "NO_MIEMBRO" then "NOT_FOUND" else "NOT_ALLOWED")
			return
		end
		avisar(player, `{nombre} ahora es {rango}.`)
		notificar(gid, g, "miembros")
		resultado = NetworkBridge.Ok(nil)
	end)
	return resultado
end

local function transferir(player: Player, userId: number): Respuesta
	local gid = hermandadDe[player]
	if not gid or userId == player.UserId then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	trabajo(function()
		local nombre = ""
		local ok, g = actualizarHermandad(gid, function(h: Hermandad): string?
			local yo = h.Miembros[tostring(player.UserId)]
			local objetivo = h.Miembros[tostring(userId)]
			if not yo or yo.Rango ~= "Lider" or not objetivo then
				return "SIN_PERMISO"
			end
			yo.Rango = "Oficial"
			objetivo.Rango = "Lider"
			h.Lider = userId
			nombre = objetivo.Nombre
			historial(h, `{player.DisplayName} pasó el liderazgo a {objetivo.Nombre}.`)
			return nil
		end)
		if not ok then
			return
		end
		if not g then
			resultado = NetworkBridge.Fail("NOT_ALLOWED")
			return
		end
		avisar(player, `{nombre} es el nuevo líder.`)
		notificar(gid, g, "miembros")
		resultado = NetworkBridge.Ok(nil)
	end)
	return resultado
end

local function cambiarPermiso(player: Player, rango: string, permiso: string, valor: boolean): Respuesta
	local gid = hermandadDe[player]
	if not gid or rango == "Lider" or not NIVEL_RANGO[rango] or not table.find(CFG.Permisos, permiso) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	trabajo(function()
		local ok, g = actualizarHermandad(gid, function(h: Hermandad): string?
			if rangoDe(h, player.UserId) ~= "Lider" then
				return "SIN_PERMISO"
			end
			local permisos = h.Permisos[rango]
			if not permisos then
				permisos = {}
				h.Permisos[rango] = permisos
			end
			permisos[permiso] = valor
			return nil
		end)
		if not ok then
			return
		end
		resultado = if g then NetworkBridge.Ok(nil) else NetworkBridge.Fail("NOT_ALLOWED")
		if g then
			notificar(gid, g, "miembros")
		end
	end)
	return resultado
end

------------------------------------------------------------------------
-- Información para la interfaz
------------------------------------------------------------------------

local function info(player: Player): Respuesta
	local gid = hermandadDe[player]
	if not gid then
		return NetworkBridge.Ok(nil)
	end
	local ok, g = leerHermandad(gid, false)
	if not ok then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if not g then
		establecer(player, nil)
		return NetworkBridge.Ok(nil)
	end
	local enLinea: { [string]: any } = {}
	pcall(function()
		local items = enLineaDe(gid):GetRangeAsync(Enum.SortDirection.Ascending, 200)
		for _, item in items do
			enLinea[item.key] = item.value
		end
	end)
	local miembros = {}
	for uid, m in g.Miembros do
		local vivo = enLinea[uid]
		table.insert(miembros, {
			UserId = tonumber(uid),
			Nombre = if vivo then vivo.N else m.Nombre,
			Rango = m.Rango,
			Nivel = if vivo then vivo.Nv else m.Nivel,
			Clase = if vivo then vivo.C else m.Clase,
			Zona = if vivo then vivo.Z else m.Zona,
			EnLinea = vivo ~= nil,
			UltimaVez = m.UltimaVez,
		})
	end
	local mios = {}
	for _, permiso in CFG.Permisos do
		mios[permiso] = puede(g, player.UserId, permiso)
	end
	local ultimos = {}
	for i = #g.Historial, math.max(1, #g.Historial - 19), -1 do
		table.insert(ultimos, g.Historial[i])
	end
	return NetworkBridge.Ok({
		Id = g.Id,
		Nombre = g.Nombre,
		Lider = g.Lider,
		MiRango = rangoDe(g, player.UserId),
		MisPermisos = mios,
		Permisos = g.Permisos,
		Miembros = miembros,
		Historial = ultimos,
		Max = CFG.MaxMiembros,
	})
end

local function verBanco(player: Player): Respuesta
	local gid = hermandadDe[player]
	if not gid then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local okG, g = leerHermandad(gid, false)
	local okB, b = leer(`B_{gid}`)
	if not okG or not okB then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if not g or not g.Miembros[tostring(player.UserId)] then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local banco: Banco = if typeof(b) == "table" then b else bancoVacio()
	local registro = {}
	for i = #banco.Registro, math.max(1, #banco.Registro - 49), -1 do
		table.insert(registro, banco.Registro[i])
	end
	return NetworkBridge.Ok({
		Oro = banco.Oro,
		Pestanas = banco.Pestanas,
		Registro = registro,
		Ranuras = CFG.RanurasPorPestana,
		PuedoItems = puede(g, player.UserId, "RetirarItems"),
		PuedoOro = puede(g, player.UserId, "RetirarOro"),
	})
end

------------------------------------------------------------------------
-- Banco
------------------------------------------------------------------------

-- ¿Quedó aplicada la operación? "si", "no" o "desconocido".
local function verificarOp(gid: string, opId: string): ("si" | "no" | "desconocido", Op?)
	local ok, b = leer(`B_{gid}`)
	if not ok then
		return "desconocido", nil
	end
	local op = if typeof(b) == "table" then buscarOp(b :: Banco, opId) else nil
	return if op then "si" else "no", op
end

-- Cuando no se pudo saber, se vuelve a mirar más tarde (hasta 5 veces).
local function resolverDespues(gid: string, opId: string, siAplicada: (Op) -> (), siNo: () -> ())
	task.spawn(function()
		for _ = 1, 5 do
			task.wait(60)
			local estado, op = verificarOp(gid, opId)
			if estado == "si" and op then
				siAplicada(op)
				return
			elseif estado == "no" then
				siNo()
				return
			end
		end
		warn(`[Hermandad] Operación {opId} del banco {gid} sin resolver`)
	end)
end

local function miembroConPermiso(player: Player, permiso: string?): (string?, Respuesta?)
	local gid = hermandadDe[player]
	if not gid then
		return nil, NetworkBridge.Fail("NOT_ALLOWED")
	end
	-- Sin caché: los permisos pueden haber cambiado en otro servidor.
	local ok, g = leerHermandad(gid, permiso ~= nil)
	if not ok then
		return nil, NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if not g or not g.Miembros[tostring(player.UserId)] then
		return nil, NetworkBridge.Fail("NOT_ALLOWED")
	end
	if permiso and not puede(g, player.UserId, permiso) then
		avisar(player, "Tu rango no puede retirar eso del banco.", "Error")
		return nil, NetworkBridge.Fail("NOT_ALLOWED")
	end
	return gid, nil
end

local function depositarItem(player: Player, clave: string, cantidad: number, pestana: number): Respuesta
	local gid, error_ = miembroConPermiso(player, nil)
	if not gid then
		return error_ :: Respuesta
	end
	local item = DataManager.QuitarDeRanura(player, clave, cantidad)
	if not item then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local opId = HttpService:GenerateGUID(false)
	local detalle = nombreItem(item)
	local userId = player.UserId
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	trabajo(function()
		local motivo: string? = nil
		local aplicado = false
		local ok = actualizar(`B_{gid}`, function(actual: any): any
			motivo = nil
			aplicado = false
			local b: Banco = if typeof(actual) == "table" then actual else bancoVacio()
			if buscarOp(b, opId) then
				aplicado = true
				return nil
			end
			local ranuras = b.Pestanas[tostring(pestana)]
			if not ranuras then
				ranuras = {}
				b.Pestanas[tostring(pestana)] = ranuras
			end
			for i = 1, CFG.RanurasPorPestana do
				if ranuras[tostring(i)] == nil then
					ranuras[tostring(i)] = item
					anotar(b, { Id = opId, T = os.time() }, player, "Depositó", `{detalle} (pestaña {pestana})`)
					aplicado = true
					return b
				end
			end
			motivo = "LLENA"
			return nil
		end)
		if ok and aplicado then
			resultado = NetworkBridge.Ok(nil)
			return
		end
		if ok then
			Buzon.DarItem(player, item, "Banco de hermandad (devolución)")
			avisar(
				player,
				if motivo == "LLENA" then "Esa pestaña del banco está llena." else "No se pudo depositar.",
				"Error"
			)
			resultado = NetworkBridge.Fail("NOT_ALLOWED")
			return
		end
		local estado = verificarOp(gid, opId)
		if estado == "si" then
			resultado = NetworkBridge.Ok(nil)
		elseif estado == "no" then
			Buzon.DarItem(player, item, "Banco de hermandad (devolución)")
			avisar(player, "No se pudo depositar. Te devolvimos el ítem.", "Error")
		else
			avisar(player, "El banco no responde. Si el depósito no entró, el ítem vuelve a tu buzón.", "Error")
			resolverDespues(gid, opId, function() end, function()
				Buzon.EnviarItem(userId, item, "Banco de hermandad (devolución)", `banco:{opId}`)
			end)
		end
	end)
	if resultado.Success then
		avisar(player, `Depositaste {detalle}.`)
		avisarBanco(gid)
	end
	return resultado
end

local function retirarItem(player: Player, pestana: number, ranura: number, uid: string): Respuesta
	if DataManager.RanurasLibres(player) < 1 then
		avisar(player, "No tenés lugar en la mochila.", "Error")
		return NetworkBridge.Fail("INVENTORY_FULL")
	end
	local gid, error_ = miembroConPermiso(player, "RetirarItems")
	if not gid then
		return error_ :: Respuesta
	end
	local opId = HttpService:GenerateGUID(false)
	local userId = player.UserId
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	local entregado: ItemInstancia? = nil
	trabajo(function()
		local sacado: ItemInstancia? = nil
		local ok = actualizar(`B_{gid}`, function(actual: any): any
			sacado = nil
			if typeof(actual) ~= "table" then
				return nil
			end
			local b = actual :: Banco
			local previa = buscarOp(b, opId)
			if previa then
				sacado = previa.Item
				return nil
			end
			local ranuras = b.Pestanas[tostring(pestana)]
			local it = ranuras and ranuras[tostring(ranura)]
			if not ranuras or not it or it.Uid ~= uid then
				return nil
			end
			ranuras[tostring(ranura)] = nil
			sacado = it
			anotar(
				b,
				{ Id = opId, T = os.time(), Item = it },
				player,
				"Retiró",
				`{nombreItem(it)} (pestaña {pestana})`
			)
			return b
		end)
		if ok then
			if sacado then
				entregado = sacado
				resultado = NetworkBridge.Ok(nil)
			else
				avisar(player, "Ese ítem ya no está en el banco.", "Error")
				resultado = NetworkBridge.Fail("NOT_FOUND")
			end
			return
		end
		local estado, op = verificarOp(gid, opId)
		if estado == "si" and op and op.Item then
			entregado = op.Item
			resultado = NetworkBridge.Ok(nil)
		elseif estado == "desconocido" then
			avisar(player, "El banco no responde. Si el retiro entró, el ítem llega a tu buzón.", "Error")
			resolverDespues(gid, opId, function(o: Op)
				if o.Item then
					Buzon.EnviarItem(userId, o.Item, "Banco de hermandad", `banco:{opId}`)
				end
			end, function() end)
		end
	end)
	local item = entregado
	if item then
		Buzon.DarItem(player, item, "Banco de hermandad")
		avisar(player, `Retiraste {nombreItem(item)}.`)
		avisarBanco(gid)
	end
	return resultado
end

local function moverOro(player: Player, cantidad: number, deposito: boolean): Respuesta
	local gid, error_ = miembroConPermiso(player, if deposito then nil else "RetirarOro")
	if not gid then
		return error_ :: Respuesta
	end
	if deposito and not DataManager.SpendGold(player, cantidad) then
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	local opId = HttpService:GenerateGUID(false)
	local userId = player.UserId
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	local aplicadoFinal = false
	trabajo(function()
		local motivo: string? = nil
		local aplicado = false
		local ok = actualizar(`B_{gid}`, function(actual: any): any
			motivo = nil
			aplicado = false
			local b: Banco = if typeof(actual) == "table" then actual else bancoVacio()
			if buscarOp(b, opId) then
				aplicado = true
				return nil
			end
			if deposito then
				if b.Oro + cantidad > CFG.MaxOroBanco then
					motivo = "TOPE"
					return nil
				end
				b.Oro += cantidad
			else
				if b.Oro < cantidad then
					motivo = "FONDOS"
					return nil
				end
				b.Oro -= cantidad
			end
			anotar(
				b,
				{ Id = opId, T = os.time(), Oro = cantidad },
				player,
				if deposito then "Depositó" else "Retiró",
				`{cantidad} de oro`
			)
			aplicado = true
			return b
		end)
		local estado: "si" | "no" | "desconocido" = if ok
			then (if aplicado then "si" else "no")
			else verificarOp(gid, opId)
		if estado == "si" then
			aplicadoFinal = true
			resultado = NetworkBridge.Ok(nil)
		elseif estado == "no" then
			if deposito then
				Buzon.DarOro(player, cantidad, "Banco de hermandad (devolución)")
			end
			avisar(
				player,
				if motivo == "FONDOS"
					then "El banco no tiene tanto oro."
					elseif motivo == "TOPE" then "El banco llegó al tope de oro."
					else "No se pudo completar la operación.",
				"Error"
			)
			resultado = NetworkBridge.Fail(if motivo == "FONDOS" then "INSUFFICIENT_FUNDS" else "NOT_ALLOWED")
		else
			avisar(player, "El banco no responde. Se revisa en unos minutos y se corrige por buzón.", "Error")
			resolverDespues(gid, opId, function()
				if not deposito then
					Buzon.EnviarOro(userId, cantidad, "Banco de hermandad", `banco:{opId}`)
				end
			end, function()
				if deposito then
					Buzon.EnviarOro(userId, cantidad, "Banco de hermandad (devolución)", `banco:{opId}`)
				end
			end)
		end
	end)
	if aplicadoFinal then
		if not deposito then
			Buzon.DarOro(player, cantidad, "Banco de hermandad")
		end
		avisar(player, `{if deposito then "Depositaste" else "Retiraste"} {cantidad} de oro.`, "Oro")
		avisarBanco(gid)
	end
	return resultado
end

------------------------------------------------------------------------
-- API
------------------------------------------------------------------------

-- Id de la hermandad del jugador (voz de hermandad, etiquetas).
function HermandadManager.HermandadDe(player: Player): string?
	return hermandadDe[player]
end

function HermandadManager.MismaHermandad(a: Player, b: Player): boolean
	local g = hermandadDe[a]
	return g ~= nil and g == hermandadDe[b]
end

function HermandadManager.Init()
	assert(not iniciado, "HermandadManager.Init() se llamó dos veces")
	iniciado = true

	local Guard = NetworkBridge.Guard
	local function usuario(v: unknown): number?
		return Guard.Integer(v, 1, 2 ^ 53)
	end
	-- Envuelve una operación: datos cargados, una por vez por jugador y espera mínima.
	local function operacion(nombre: string, espera: number, fn: (Player, ...any) -> Respuesta)
		NetworkBridge.Server.OnInvoke(nombre, function(player: Player, ...: any): Respuesta
			if not DataManager.IsLoaded(player) then
				return NetworkBridge.Fail("DATA_NOT_LOADED")
			end
			if ocupado[player] or enfriado(player, nombre, espera) then
				return NetworkBridge.Fail("RATE_LIMITED")
			end
			ocupado[player] = true
			local ok, resultado = pcall(fn, player, ...)
			ocupado[player] = nil
			if not ok then
				warn(`[Hermandad] {nombre}: {resultado}`)
				return NetworkBridge.Fail("INTERNAL_ERROR")
			end
			return resultado
		end)
	end

	operacion("HermandadCrear", 5, function(player: Player, nombre: any): Respuesta
		local n = Guard.String(nombre, 60)
		return if n then crear(player, n) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	operacion("HermandadInfo", 1, function(player: Player): Respuesta
		return info(player)
	end)
	operacion("HermandadInvitar", 2, function(player: Player, userId: any): Respuesta
		local u = usuario(userId)
		return if u then invitar(player, u) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	operacion("HermandadResponder", 1, function(player: Player, gid: any, acepta: any): Respuesta
		local g = Guard.String(gid, 40)
		local a = Guard.Boolean(acepta)
		if not g or a == nil then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return responder(player, g, a)
	end)
	operacion("HermandadSalir", 3, function(player: Player): Respuesta
		return salir(player)
	end)
	operacion("HermandadDisolver", 5, function(player: Player): Respuesta
		return disolver(player)
	end)
	operacion("HermandadExpulsar", 2, function(player: Player, userId: any): Respuesta
		local u = usuario(userId)
		return if u then expulsar(player, u) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	operacion("HermandadRango", 1, function(player: Player, userId: any, rango: any): Respuesta
		local u = usuario(userId)
		local r = Guard.String(rango, 20)
		if not u or not r then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return cambiarRango(player, u, r)
	end)
	operacion("HermandadTransferir", 3, function(player: Player, userId: any): Respuesta
		local u = usuario(userId)
		return if u then transferir(player, u) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	operacion("HermandadPermiso", 0.5, function(player: Player, rango: any, permiso: any, valor: any): Respuesta
		local r = Guard.String(rango, 20)
		local p = Guard.String(permiso, 20)
		local v = Guard.Boolean(valor)
		if not r or not p or v == nil then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return cambiarPermiso(player, r, p, v)
	end)
	operacion("HermandadBanco", 1, function(player: Player): Respuesta
		return verBanco(player)
	end)
	operacion("HermandadDepositarItem", 1, function(player: Player, ranura: any, cantidad: any, pestana: any): Respuesta
		local r = Guard.String(ranura, 6)
		local c = Guard.Integer(cantidad, 1, 1e6)
		local p = Guard.Integer(pestana, 1, CFG.Pestanas)
		if not r or not c or not p then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return depositarItem(player, r, c, p)
	end)
	operacion("HermandadRetirarItem", 1, function(player: Player, pestana: any, ranura: any, uid: any): Respuesta
		local p = Guard.Integer(pestana, 1, CFG.Pestanas)
		local r = Guard.Integer(ranura, 1, CFG.RanurasPorPestana)
		local u = Guard.String(uid, 40)
		if not p or not r or not u then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		return retirarItem(player, p, r, u)
	end)
	operacion("HermandadDepositarOro", 1, function(player: Player, cantidad: any): Respuesta
		local c = Guard.Integer(cantidad, 1, CFG.MaxOroBanco)
		return if c then moverOro(player, c, true) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	operacion("HermandadRetirarOro", 1, function(player: Player, cantidad: any): Respuesta
		local c = Guard.Integer(cantidad, 1, CFG.MaxOroBanco)
		return if c then moverOro(player, c, false) else NetworkBridge.Fail("INVALID_ARGS")
	end)

	DataManager.PerfilCargado:Connect(function(player: Player)
		task.spawn(alCargar, player)
	end)
	for _, player in Players:GetPlayers() do
		if DataManager.IsLoaded(player) then
			task.spawn(alCargar, player)
		end
	end
	Players.PlayerRemoving:Connect(alSalir)

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPICO, alMensaje)
		end)
		if not ok then
			warn(`[Hermandad] Sin avisos entre servidores: {err}`)
		end
	end)

	-- Latido: mantiene "en línea" (vence solo si el servidor se cae).
	task.spawn(function()
		while true do
			task.wait(LATIDO)
			for player in hermandadDe do
				task.spawn(marcarEnLinea, player)
			end
		end
	end)

	game:BindToClose(function()
		local limite = os.clock() + 20
		task.wait(0.5) -- deja arrancar los guardados de PlayerRemoving
		while enCurso > 0 and os.clock() < limite do
			task.wait(0.1)
		end
	end)
end

return HermandadManager
