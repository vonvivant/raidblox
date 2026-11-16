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
local Signal = require(ReplicatedStorage.Modules.Signal)
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
local MAX_OPS = 300
local NIVEL_RANGO: { [string]: number } = { Lider = 4, Oficial = 3, Miembro = 2, Recluta = 1 }

local HermandadManager = {}

-- (jugador, id de hermandad o nil): entró, salió o lo expulsaron (voz de hermandad).
HermandadManager.Cambio = Signal.new() :: Signal.Signal<Player, string?>

local hermandadDe: { [Player]: string } = {}
local ultimoEstado: { [Player]: { Nivel: number, Clase: string } } = {}
local invitaciones: { [Player]: { [string]: { Vence: number, Nombre: string } } } = {}
local ocupado: { [Player]: boolean } = {}
local ultimaLlamada: { [Player]: { [string]: number } } = {}
local cache: { [string]: { Datos: Hermandad?, Hora: number } } = {}
local reconciliando: { [string]: boolean } = {}
local opsEnCurso: { [string]: boolean } = {} -- operaciones del banco en curso en este servidor
local reconciliarBanco: (Player) -> ()
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
	if player.Parent ~= Players then
		hermandadDe[player] = nil
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
		HermandadManager.Cambio:Fire(player, g.Id)
	else
		local anterior = hermandadDe[player]
		hermandadDe[player] = nil
		player:SetAttribute("HermandadId", nil)
		player:SetAttribute("Hermandad", nil)
		NetworkBridge.Server.FireClient("HermandadCambio", player, nil, que or "miembros")
		if anterior then
			HermandadManager.Cambio:Fire(player, nil)
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
		if player.Parent ~= Players then
			hermandadDe[player] = nil
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
	task.spawn(reconciliarBanco, player)
	local ok, gid = false, nil
	for intento = 1, 4 do
		ok, gid = leer(`J_{player.UserId}`)
		if ok or player.Parent ~= Players then
			break
		end
		task.wait(15 * intento) -- DataStore caído: se reintenta un rato
	end
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
	if g and player.Parent ~= Players then
		guardarCache(gid, g) -- se fue mientras se creaba: al volver la encuentra
	elseif g then
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
	if g and player.Parent ~= Players then
		notificar(gid, g, "miembros")
	elseif g then
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
-- `por`: quien expulsa (permiso y rango se revisan dentro de la transacción).
local function sacar(gid: string, userId: number, texto: string, por: number?): (boolean, Hermandad?, string?)
	local uid = tostring(userId)
	local ok, g, motivo = actualizarHermandad(gid, function(h: Hermandad): string?
		local m = h.Miembros[uid]
		if not m then
			return "NO_MIEMBRO"
		end
		if m.Rango == "Lider" then
			return "ES_LIDER"
		end
		if por and (not puede(h, por, "Expulsar") or nivelRango(rangoDe(h, por)) <= nivelRango(m.Rango)) then
			return "SIN_PERMISO"
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
		-- Se cierra el banco en la misma escritura que verifica que esté vacío:
		-- después de esto ningún depósito puede entrar.
		local conItems = false
		local okB, cerrado = actualizar(`B_{gid}`, function(actual: any): any
			conItems = false
			local banco: Banco = if typeof(actual) == "table" then actual else bancoVacio()
			if banco.Oro > 0 then
				conItems = true
			end
			for _, pestana in banco.Pestanas do
				if next(pestana) ~= nil then
					conItems = true
				end
			end
			if conItems then
				return nil
			end
			(banco :: any).Cerrado = true
			return banco
		end)
		if not okB then
			return
		end
		if not cerrado then
			avisar(player, "Vaciá el banco antes de disolver la hermandad.", "Error")
			resultado = NetworkBridge.Fail("NOT_ALLOWED")
			return
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
			-- No se disolvió: se vuelve a abrir el banco.
			actualizar(`B_{gid}`, function(actual: any): any
				if typeof(actual) == "table" and actual.Cerrado then
					actual.Cerrado = nil
					return actual
				end
				return nil
			end)
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
		local okS, nuevo, motivo =
			sacar(gid, userId, `{player.DisplayName} expulsó a {objetivo.Nombre}.`, player.UserId)
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

-- Lectura SIN caché (GetAsync guarda cada clave unos segundos): para verificar
-- si una operación quedó escrita hay que ver el valor real.
local function leerFresco(clave: string): (boolean, any)
	for intento = 1, 3 do
		local ok, valor = pcall(function(): any
			local opciones = Instance.new("DataStoreGetOptions")
			opciones.UseCache = false
			return obtenerStore():GetAsync(clave, opciones)
		end)
		if ok then
			return true, valor
		end
		task.wait(intento)
	end
	return false, nil
end

-- ¿Quedó aplicada la operación? "si", "no" o "desconocido".
-- `inicio`: os.time() de cuando se anotó. Solo se responde "no" si la lista de
-- operaciones del banco cubre todo ese tiempo (si se recortó, no se sabe).
local function verificarOp(gid: string, opId: string, inicio: number): (string, Op?)
	local ok, b = leerFresco(`B_{gid}`)
	if not ok then
		return "desconocido", nil
	end
	if typeof(b) ~= "table" then
		return "no", nil
	end
	local banco = b :: Banco
	local op = buscarOp(banco, opId)
	if op then
		return "si", op
	end
	local masVieja = banco.Ops[1]
	if #banco.Ops < MAX_OPS or (masVieja and masVieja.T < inicio - 5) then
		return "no", nil
	end
	return "desconocido", nil
end

-- Entrega en la mochila o, si no entra o no se puede, por buzón con id fijo
-- (así una reconciliación repetida nunca entrega dos veces).
local function darItem(player: Player, item: ItemInstancia, opId: string)
	if not DataManager.AgregarInstancia(player, item) then
		Buzon.EnviarItem(player.UserId, item, "Banco de hermandad", `banco:{opId}`)
	end
end

local function darOro(player: Player, cantidad: number, opId: string)
	if not DataManager.AddGold(player, cantidad) then
		Buzon.EnviarOro(player.UserId, cantidad, "Banco de hermandad", `banco:{opId}`)
	end
end

-- Cierra una entrada del diario según el resultado. Todo en el mismo bloque
-- sin pausas: lo que se entrega y el borrado del diario se guardan juntos.
local function cerrarPendiente(
	player: Player,
	opId: string,
	p: Types.PendienteBanco,
	estado: string, -- "si", "no" o "desconocido"
	op: Op?
)
	if estado == "desconocido" or not DataManager.PerfilActivo(player) then
		return
	end
	if p.Tipo == "DepositoItem" and estado == "no" and p.Item then
		darItem(player, p.Item, opId)
	elseif p.Tipo == "DepositoOro" and estado == "no" and p.Oro then
		darOro(player, p.Oro, opId)
	elseif p.Tipo == "RetiroItem" and estado == "si" and op and op.Item then
		darItem(player, op.Item, opId)
	elseif p.Tipo == "RetiroOro" and estado == "si" and op and op.Oro then
		darOro(player, op.Oro, opId)
	end
	DataManager.QuitarPendienteBanco(player, opId)
end

-- Revisa el diario del jugador (al entrar y cada minuto): operaciones que
-- quedaron a medias por un error o porque se cayó un servidor.
reconciliarBanco = function(player: Player)
	for opId, p in DataManager.PendientesBanco(player) do
		if opsEnCurso[opId] or os.time() - p.Creado < 20 then
			continue
		end
		opsEnCurso[opId] = true
		local estado, op = verificarOp(p.Gid, opId, p.Creado)
		opsEnCurso[opId] = nil
		if player.Parent ~= Players then
			return
		end
		cerrarPendiente(player, opId, p, estado, op)
	end
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

local MOTIVOS: { [string]: string } = {
	LLENA = "Esa pestaña del banco está llena.",
	CERRADO = "El banco de esta hermandad está cerrado.",
	VACIO = "Ese ítem ya no está en el banco.",
	FONDOS = "El banco no tiene tanto oro.",
	TOPE = "El banco llegó al tope de oro.",
}

-- Corre una operación del banco con diario:
--   1. `preparar` saca lo que haga falta del perfil (sin pausas) y se anota en
--      el diario; se guarda el perfil (SaveNowAsync) ANTES de tocar el banco.
--   2. UpdateAsync del banco con el id de la operación.
--   3. Se cierra el diario: confirmado, devuelto o entregado, según el caso.
-- Si no se puede saber el resultado, el diario queda y se reconcilia después.
local function operar(
	player: Player,
	gid: string,
	pendiente: Types.PendienteBanco,
	preparar: () -> boolean,
	deshacer: (string) -> (), -- recibe el id de la operación (para el buzón)
	transformar: (Banco, Op) -> string?
): (Respuesta, Op?)
	local opId = HttpService:GenerateGUID(false)
	if not preparar() then
		return NetworkBridge.Fail("NOT_FOUND"), nil
	end
	DataManager.RegistrarPendienteBanco(player, opId, pendiente)
	opsEnCurso[opId] = true
	local resultado: Respuesta = NetworkBridge.Fail("INTERNAL_ERROR")
	local opFinal: Op? = nil
	trabajo(function()
		if not DataManager.SaveNowAsync(player, 10) then
			-- No se confirmó el guardado: se deshace en memoria (si el guardado
			-- igual entra, el diario lo arregla al volver a entrar).
			if DataManager.PerfilActivo(player) then
				deshacer(opId)
				DataManager.QuitarPendienteBanco(player, opId)
			end
			avisar(player, "No se pudo guardar tu perfil. Probá de nuevo.", "Error")
			return
		end
		local motivo: string? = nil
		local aplicada: Op? = nil
		local ok = actualizar(`B_{gid}`, function(actual: any): any
			motivo = nil
			aplicada = nil
			local b: Banco = if typeof(actual) == "table" then actual else bancoVacio()
			local previa = buscarOp(b, opId)
			if previa then
				aplicada = previa
				return nil
			end
			if (b :: any).Cerrado then
				motivo = "CERRADO"
				return nil
			end
			local op: Op = { Id = opId, T = os.time() }
			motivo = transformar(b, op)
			if motivo then
				return nil
			end
			aplicada = op
			return b
		end)
		if not DataManager.PerfilActivo(player) then
			return -- se fue: el diario guardado se resuelve cuando vuelva
		end
		if ok then
			if aplicada then
				opFinal = aplicada
				cerrarPendiente(player, opId, pendiente, "si", aplicada)
				resultado = NetworkBridge.Ok(nil)
			else
				cerrarPendiente(player, opId, pendiente, "no", nil)
				avisar(player, MOTIVOS[motivo or ""] or "No se pudo completar la operación.", "Error")
				resultado = NetworkBridge.Fail(if motivo == "FONDOS" then "INSUFFICIENT_FUNDS" else "NOT_ALLOWED")
			end
			return
		end
		local estado, op = verificarOp(gid, opId, pendiente.Creado)
		cerrarPendiente(player, opId, pendiente, estado, op)
		if estado == "si" then
			opFinal = op
			resultado = NetworkBridge.Ok(nil)
		elseif estado == "no" then
			avisar(player, "No se pudo completar la operación (no se movió nada).", "Error")
		else
			avisar(player, "El banco no responde. Se revisa en un minuto y se corrige solo.", "Error")
		end
	end)
	opsEnCurso[opId] = nil
	return resultado, opFinal
end

local function depositarItem(player: Player, clave: string, cantidad: number, pestana: number): Respuesta
	local gid, error_ = miembroConPermiso(player, nil)
	if not gid then
		return error_ :: Respuesta
	end
	local item: ItemInstancia? = nil
	local pendiente: Types.PendienteBanco = { Gid = gid, Tipo = "DepositoItem", Creado = os.time() }
	local resultado = operar(player, gid, pendiente, function(): boolean
		item = DataManager.QuitarDeRanura(player, clave, cantidad)
		pendiente.Item = item
		return item ~= nil
	end, function(opId: string)
		local i = item
		if i then
			darItem(player, i, opId)
		end
	end, function(b: Banco, op: Op): string?
		local i = item :: ItemInstancia
		local ranuras = b.Pestanas[tostring(pestana)]
		if not ranuras then
			ranuras = {}
			b.Pestanas[tostring(pestana)] = ranuras
		end
		for r = 1, CFG.RanurasPorPestana do
			if ranuras[tostring(r)] == nil then
				ranuras[tostring(r)] = i
				anotar(b, op, player, "Depositó", `{nombreItem(i)} (pestaña {pestana})`)
				return nil
			end
		end
		return "LLENA"
	end)
	local i = item
	if resultado.Success and i then
		avisar(player, `Depositaste {nombreItem(i)}.`)
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
	local pendiente: Types.PendienteBanco = { Gid = gid, Tipo = "RetiroItem", Creado = os.time() }
	local resultado, op = operar(player, gid, pendiente, function(): boolean
		return true
	end, function(_: string) end, function(b: Banco, o: Op): string?
		local ranuras = b.Pestanas[tostring(pestana)]
		local it = ranuras and ranuras[tostring(ranura)]
		if not ranuras or not it or it.Uid ~= uid then
			return "VACIO"
		end
		ranuras[tostring(ranura)] = nil
		o.Item = it
		anotar(b, o, player, "Retiró", `{nombreItem(it)} (pestaña {pestana})`)
		return nil
	end)
	local item = op and op.Item
	if resultado.Success and item then
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
	local pendiente: Types.PendienteBanco = {
		Gid = gid,
		Tipo = if deposito then "DepositoOro" else "RetiroOro",
		Oro = cantidad,
		Creado = os.time(),
	}
	local resultado = operar(player, gid, pendiente, function(): boolean
		return not deposito or DataManager.SpendGold(player, cantidad)
	end, function(opId: string)
		if deposito then
			darOro(player, cantidad, opId)
		end
	end, function(b: Banco, op: Op): string?
		if deposito then
			if b.Oro + cantidad > CFG.MaxOroBanco then
				return "TOPE"
			end
			b.Oro += cantidad
		else
			if b.Oro < cantidad then
				return "FONDOS"
			end
			b.Oro -= cantidad
		end
		op.Oro = cantidad
		anotar(b, op, player, if deposito then "Depositó" else "Retiró", `{cantidad} de oro`)
		return nil
	end)
	if resultado.Success then
		avisar(player, `{if deposito then "Depositaste" else "Retiraste"} {cantidad} de oro.`, "Oro")
		avisarBanco(gid)
	elseif deposito and resultado.ErrorCode == "NOT_FOUND" then
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
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
			-- Operaciones del banco que quedaron sin resolver (error o caída).
			for _, player in Players:GetPlayers() do
				if next(DataManager.PendientesBanco(player)) ~= nil then
					task.spawn(reconciliarBanco, player)
				end
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
