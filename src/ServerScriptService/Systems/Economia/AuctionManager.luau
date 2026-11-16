--!strict
-- AuctionManager: Casa de Subastas global, compartida por todos los servidores.
--
-- Almacenamiento híbrido:
--   * DataStore (fuente de verdad):
--       "L_<id>"      -> publicación { Item, Precio, VendedorId, Estado, Expira, pendientes... }
--       "V_<userId>"  -> ids del vendedor (activas o con entregas pendientes); máximo 5 activas
--       "C_<userId>"  -> ids comprados con el ítem todavía sin entregar
--   * MemoryStore SortedMap: índice de búsqueda ordenado por precio. Sus entradas
--     vencen solas; no es la verdad, solo sirve para buscar rápido.
--
-- Reglas:
--   * Publicar cobra un depósito del 5% que se quema. Al vender se retiene un 10%.
--   * Toda transición de estado (vender, cancelar, vencer) es un UpdateAsync que
--     solo escribe si el estado actual lo permite y lleva un token único: así se
--     sabe con certeza si ESTA llamada ganó, aun si el UpdateAsync se reintentó.
--   * Al vender/cancelar/vencer, la publicación queda con "PendienteItem" y/o
--     "PendienteOro". Cada flag se borra recién cuando el buzón confirmó la
--     entrega. Si algo falla (o el servidor se apaga), se reintenta cuando el
--     vendedor o el comprador vuelven a entrar. Los mensajes del buzón usan ids
--     fijos ("<id>:item", "<id>:oro"), así un reintento nunca entrega dos veces.
--   * Antes de escribir en la subasta se guarda el perfil del jugador
--     (SaveNowAsync): si el servidor se cae, el perfil no vuelve a un estado en
--     el que todavía tiene el ítem o el oro que ya entregó.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Pruebas = require(game:GetService("ReplicatedStorage").Modules.Pruebas)
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ItemRarityConfig = require(ReplicatedStorage.Configs.ItemRarityConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local Buzon = require(script.Parent.Parent.Buzon)
local PasesManager = require(script.Parent.Parent.Monetizacion.PasesManager)

type ItemInstancia = Types.ItemInstancia
type Respuesta = Types.Respuesta

type Publicacion = {
	Id: string,
	VendedorId: number,
	VendedorNombre: string,
	Item: ItemInstancia,
	Precio: number,
	Creada: number, -- os.time()
	Expira: number, -- os.time()
	Estado: "Activa" | "Vendida" | "Cancelada" | "Expirada",
	CompradorId: number?,
	Destinatario: number?, -- quién recibe el ítem (comprador o vendedor)
	Neto: number?, -- oro para el vendedor tras el impuesto
	PendienteItem: boolean?,
	PendienteOro: boolean?,
	Token: string?,
}

local CFG = GameConfig.Subastas
local TAG_CASA = "CasaSubastas"
local PAGINAS_BUSQUEDA = 5 -- hasta 1000 publicaciones (200 por página)

local AuctionManager = {}

local store: DataStore? = nil
local indice: MemoryStoreSortedMap? = nil
local opcionesSinCache: DataStoreGetOptions? = nil
local ocupados: { [Player]: boolean } = {}
local operacionesEnCurso = 0
local cache: { hora: number, entradas: { any } } = { hora = 0, entradas = {} }
local iniciado = false

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function conReintentos<T>(intentos: number, fn: () -> T): (boolean, T?)
	local espera = 0.5
	for intento = 1, intentos do
		local ok, resultado = pcall(fn)
		if ok then
			return true, resultado
		end
		warn(`[Subastas] Intento {intento}/{intentos} falló: {resultado}`)
		if intento < intentos then
			task.wait(espera)
			espera *= 2
		end
	end
	return false, nil
end

local function obtenerStore(): DataStore
	assert(store, "AuctionManager.Init() no se llamó")
	return store
end

local function obtenerIndice(): MemoryStoreSortedMap
	assert(indice, "AuctionManager.Init() no se llamó")
	return indice
end

local function duracionSegundos(): number
	return if RunService:IsStudio() then CFG.DuracionEnStudioMinutos * 60 else CFG.DuracionHoras * 3600
end

local function avisar(player: Player, texto: string, tipo: string?)
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
	end
end

local function nombreItem(item: ItemInstancia): string
	local def = ItemCatalog[item.ItemId]
	return if def then def.Nombre else item.ItemId
end

local function resumen(p: Publicacion): { [string]: any }
	return {
		Id = p.Id,
		Item = p.Item,
		Nombre = nombreItem(p.Item),
		Precio = p.Precio,
		Vendedor = p.VendedorNombre,
		Expira = p.Expira,
		Estado = p.Estado,
	}
end

-- Lectura sin caché (GetAsync normal puede devolver datos de hasta 4 s atrás).
local function leer(id: string): (boolean, Publicacion?)
	local ok, valor = conReintentos(3, function()
		return obtenerStore():GetAsync(`L_{id}`, opcionesSinCache)
	end)
	if not ok then
		return false, nil
	end
	return true, if typeof(valor) == "table" then valor :: Publicacion else nil
end

local function leerLista(clave: string): (boolean, { string })
	local ok, valor = conReintentos(3, function()
		return obtenerStore():GetAsync(clave, opcionesSinCache)
	end)
	if not ok then
		return false, {}
	end
	return true, if typeof(valor) == "table" then valor :: { string } else {}
end

local function quitarDeLista(clave: string, id: string)
	conReintentos(3, function()
		obtenerStore():UpdateAsync(clave, function(lista: { string }?): { string }?
			if not lista or not table.find(lista, id) then
				return nil -- nada que cambiar
			end
			local nueva: { string } = {}
			for _, otro in lista do
				if otro ~= id then
					table.insert(nueva, otro)
				end
			end
			return nueva
		end)
		return true
	end)
end

local function agregarALista(clave: string, id: string): boolean
	local ok = conReintentos(3, function()
		obtenerStore():UpdateAsync(clave, function(lista: { string }?): { string }?
			local actual = lista or {}
			if table.find(actual, id) then
				return nil -- ya estaba (reintento): no se duplica
			end
			table.insert(actual, id)
			return actual
		end)
		return true
	end)
	return ok
end

local function quitarDelIndice(id: string)
	conReintentos(3, function()
		obtenerIndice():RemoveAsync(id)
		return true
	end)
	cache.hora = 0
end

-- Resultado de una transición: "Gano" (esta llamada escribió), "Perdio" (no se
-- escribió: otro llegó antes o el estado no lo permitía) o "Desconocido" (el
-- DataStore falló y no se pudo saber). Solo "Perdio" permite devolver algo.
type Resultado = "Gano" | "Perdio" | "Desconocido"

local function transicion(
	id: string,
	condicion: (Publicacion) -> boolean,
	aplicar: (Publicacion) -> ()
): (Resultado, Publicacion?)
	local token = HttpService:GenerateGUID(false)
	local yaEscrito: Publicacion? = nil
	local ok, resultado = conReintentos(3, function()
		return obtenerStore():UpdateAsync(`L_{id}`, function(actual: Publicacion?): Publicacion?
			if actual and actual.Token == token then
				yaEscrito = actual -- un intento anterior nuestro ya se escribió
				return nil
			end
			if not actual or not condicion(actual) then
				return nil
			end
			aplicar(actual)
			actual.Token = token
			return actual
		end)
	end)
	if yaEscrito then
		return "Gano", yaEscrito
	end
	local p = resultado :: Publicacion?
	if ok then
		if p and p.Token == token then
			return "Gano", p
		end
		return "Perdio", nil
	end
	-- Falló: puede que alguno de los intentos se haya escrito igual. El token
	-- queda en la publicación (ninguna otra transición la cambia después), así
	-- que releyendo se sabe.
	local okLeer, actual = leer(id)
	if okLeer and actual and actual.Token == token then
		return "Gano", actual
	elseif okLeer then
		return "Perdio", nil
	end
	return "Desconocido", nil
end

local function quitarFlag(id: string, flag: "PendienteItem" | "PendienteOro")
	conReintentos(3, function()
		obtenerStore():UpdateAsync(`L_{id}`, function(actual: Publicacion?): Publicacion?
			if not actual or not (actual :: any)[flag] then
				return nil
			end
			(actual :: any)[flag] = nil
			return actual
		end)
		return true
	end)
end

-- Entrega lo pendiente de una publicación. Devuelve true si no quedó nada pendiente.
local function entregarPendientes(p: Publicacion): boolean
	local completo = true
	if p.PendienteItem then
		local destino = p.Destinatario or p.VendedorId
		local motivo = if p.Estado == "Vendida"
			then "Compra en subasta"
			elseif p.Estado == "Cancelada" then "Subasta cancelada"
			else "Subasta vencida"
		if Buzon.EnviarItemAsync(destino, p.Item, motivo, `subasta:{p.Id}:item`) then
			quitarFlag(p.Id, "PendienteItem")
			p.PendienteItem = nil
		else
			completo = false
		end
	end
	if p.PendienteOro then
		local neto = p.Neto or (p.Precio - math.floor(p.Precio * CFG.Impuesto))
		if Buzon.EnviarOroAsync(p.VendedorId, neto, `Venta de {nombreItem(p.Item)}`, `subasta:{p.Id}:oro`) then
			quitarFlag(p.Id, "PendienteOro")
			p.PendienteOro = nil
		else
			completo = false
		end
	end
	return completo
end

-- Devoluciones: primero directo al perfil (sin pausas); si no entra, por el
-- buzón con un id fijo (un reintento nunca entrega dos veces). true si quedó
-- entregado o encaminado con éxito.
-- Si el perfil ya no está activo (el jugador se fue), NO se devuelve nada: el
-- diario quedó guardado en el perfil y la reconciliación lo resuelve al volver
-- (solo por buzón, con el mismo id fijo, así nunca se paga dos veces).
local function devolverItem(player: Player, item: ItemInstancia, idFijo: string, motivo: string): boolean
	if not DataManager.PerfilActivo(player) then
		return false
	end
	if DataManager.AgregarInstancia(player, item) then
		return true
	end
	return Buzon.EnviarItemAsync(player.UserId, item, motivo, idFijo)
end

local function devolverOro(player: Player, cantidad: number, idFijo: string, motivo: string): boolean
	if not DataManager.PerfilActivo(player) then
		return false
	end
	if DataManager.AddGold(player, cantidad) then
		return true
	end
	return Buzon.EnviarOroAsync(player.UserId, cantidad, motivo, idFijo)
end

-- Cierra en el diario una publicación que no llegó a crearse y devuelve todo.
local function devolverPublicacion(player: Player, id: string, item: ItemInstancia, deposito: number)
	-- El diario se borra en el mismo bloque sin pausas en que vuelven ítem y
	-- oro al perfil; si alguno va por el buzón, se borra al confirmarse.
	DataManager.QuitarPendiente(player, "Subastas", id)
	local okItem = devolverItem(player, item, `subasta:{id}:rollback`, "Subasta no publicada")
	local okOro = devolverOro(player, deposito, `subasta:{id}:deposito`, "Depósito devuelto")
	if not okItem or not okOro then
		-- No se pudo devolver todo: se vuelve a anotar para reintentar al entrar.
		DataManager.RegistrarPendienteSubasta(
			player,
			id,
			if okItem then { Uid = item.Uid, ItemId = item.ItemId, Cantidad = 0, Rareza = item.Rareza } else item,
			if okOro then 0 else deposito
		)
	end
	quitarDeLista(`V_{player.UserId}`, id)
end

------------------------------------------------------------------------
-- Reconciliación del diario (al entrar y cuando una operación quedó en duda)
------------------------------------------------------------------------

local ESPERA_DIARIO = 90 -- s: antes de esto, una operación podría seguir en vuelo en otro servidor

-- Operaciones de este servidor todavía en curso (la reconciliación no las toca).
local operacionesPorId: { [string]: boolean } = {}
local reconciliando: { [Player]: boolean } = {}

local reconciliar: (Player) -> ()

local function reconciliarDespues(player: Player)
	task.delay(ESPERA_DIARIO + 5, function()
		if player.Parent == Players and DataManager.PerfilActivo(player) then
			reconciliar(player)
		end
	end)
end

reconciliar = function(player: Player)
	if reconciliando[player] then
		return -- ya hay una corriendo para este jugador
	end
	reconciliando[player] = true
	local ok, err = pcall(function(): nil
		local datos = DataManager.GetData(player)
		if not datos then
			return nil
		end
		local pendientes = false

		-- ¿Sigue la misma entrada en el diario? (se revisa después de cada pausa)
		local function sigue(tipo: "Subastas" | "Compras", id: string, creado: number): boolean
			local actual = DataManager.GetData(player)
			local entrada = actual and (actual.Pendientes[tipo] :: any)[id]
			return entrada ~= nil and entrada.Creado == creado
		end

		for id, pend in table.clone(datos.Pendientes.Subastas) do
			if operacionesPorId[id] then
				pendientes = true
				continue
			end
			local okLeer, p = leer(id)
			if not okLeer or not sigue("Subastas", id, pend.Creado) then
				pendientes = pendientes or not okLeer
				continue
			end
			if p and p.VendedorId == player.UserId then
				-- La publicación existe: el ítem está en ella.
				DataManager.QuitarPendiente(player, "Subastas", id)
				agregarALista(`V_{player.UserId}`, id)
			elseif os.time() - pend.Creado < ESPERA_DIARIO then
				pendientes = true -- puede estar creándose todavía
			else
				-- Nunca se creó: se devuelve SOLO por buzón, con ids fijos (si un
				-- envío anterior ya llegó, el buzón lo descarta).
				local item = pend.Item
				local okItem = item.Cantidad <= 0
					or Buzon.EnviarItemAsync(player.UserId, item, "Subasta no publicada", `subasta:{id}:rollback`)
				local okOro = pend.Deposito <= 0
					or Buzon.EnviarOroAsync(player.UserId, pend.Deposito, "Depósito devuelto", `subasta:{id}:deposito`)
				if okItem and okOro and sigue("Subastas", id, pend.Creado) then
					DataManager.QuitarPendiente(player, "Subastas", id)
				else
					pendientes = true
				end
				quitarDeLista(`V_{player.UserId}`, id)
			end
		end

		for id, pend in table.clone(datos.Pendientes.Compras) do
			if operacionesPorId[id] then
				pendientes = true
				continue
			end
			local okLeer, p = leer(id)
			if not okLeer or not sigue("Compras", id, pend.Creado) then
				pendientes = pendientes or not okLeer
				continue
			end
			if p and p.Estado == "Vendida" and p.CompradorId == player.UserId then
				-- La compra se concretó: el ítem llega por la lista C_.
				DataManager.QuitarPendiente(player, "Compras", id)
				agregarALista(`C_{player.UserId}`, id)
			elseif os.time() - pend.Creado < ESPERA_DIARIO and (not p or p.Estado == "Activa") then
				pendientes = true -- la transición podría seguir en vuelo
			else
				local enviado = Buzon.EnviarOroAsync(
					player.UserId,
					pend.Precio,
					"Compra no realizada",
					`subasta:{id}:reembolso:{player.UserId}`
				)
				if enviado and sigue("Compras", id, pend.Creado) then
					DataManager.QuitarPendiente(player, "Compras", id)
				else
					pendientes = true
				end
			end
		end

		if pendientes then
			reconciliarDespues(player)
		end
		return nil
	end)
	reconciliando[player] = nil
	if not ok then
		warn(`[Subastas] Error reconciliando a {player.UserId}: {err}`)
	end
end

------------------------------------------------------------------------
-- Procesamiento por jugador (vencimientos y entregas pendientes)
------------------------------------------------------------------------

local function procesarJugador(player: Player): { { [string]: any } }
	local userId = player.UserId
	local resultado: { { [string]: any } } = {}
	local datos = DataManager.GetData(player)

	local okV, ids = leerLista(`V_{userId}`)
	if okV then
		for _, id in ids do
			local okP, p = leer(id)
			if not okP then
				continue
			end
			if not p then
				-- Reserva sin publicación: se borra solo si el diario no dice que
				-- se está creando (podría estar en vuelo en otro servidor).
				if not (datos and datos.Pendientes.Subastas[id]) then
					quitarDeLista(`V_{userId}`, id)
				end
				continue
			end
			local actual: Publicacion = p
			if actual.Estado == "Activa" and actual.Expira <= os.time() then
				local res, vencida = transicion(id, function(x)
					return x.Estado == "Activa" and x.Expira <= os.time()
				end, function(x)
					x.Estado = "Expirada"
					x.Destinatario = x.VendedorId
					x.PendienteItem = true
				end)
				if res == "Gano" and vencida then
					actual = vencida
					quitarDelIndice(id)
				elseif res == "Perdio" then
					local okR, releida = leer(id) -- otro la vendió o la venció primero
					if okR and releida then
						actual = releida
					end
				end
			end
			local completo = entregarPendientes(actual)
			if actual.Estado ~= "Activa" and completo then
				quitarDeLista(`V_{userId}`, id)
			end
			table.insert(resultado, resumen(actual))
		end
	end

	-- Compras con el ítem todavía sin entregar.
	local okC, compras = leerLista(`C_{userId}`)
	if okC then
		for _, id in compras do
			local okP, p = leer(id)
			if okP and (not p or entregarPendientes(p)) then
				quitarDeLista(`C_{userId}`, id)
			end
		end
	end
	return resultado
end

------------------------------------------------------------------------
-- Operaciones
------------------------------------------------------------------------

local function publicar(player: Player, uid: string, precio: number): Respuesta
	local id = HttpService:GenerateGUID(false)
	local vendedorId = player.UserId

	-- 0. Chequeos sin DataStore primero (evita gastar escrituras con pedidos inválidos).
	do
		local clave0, item0 = DataManager.BuscarPorUid(player, uid)
		local datos0 = DataManager.GetData(player)
		if not clave0 or not item0 or not datos0 then
			return NetworkBridge.Fail("NOT_FOUND")
		end
		if datos0.Oro < math.max(1, math.floor(precio * CFG.Deposito)) then
			avisar(player, `Necesitás {math.max(1, math.floor(precio * CFG.Deposito))} de oro para el depósito.`)
			return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
		end
	end
	operacionesPorId[id] = true
	local maxPublicaciones = PasesManager.LimitePublicaciones(player) -- 15 con el pase
	local resultado = (function(): Respuesta
		-- 1. Reservar un lugar en la lista del vendedor (el límite se verifica de forma atómica).
		local function reservar(): string
			local estado = "error"
			local ok = conReintentos(3, function()
				estado = "error"
				obtenerStore():UpdateAsync(`V_{vendedorId}`, function(lista: { string }?): { string }?
					local actual = lista or {}
					if table.find(actual, id) then
						estado = "ok"
						return nil
					end
					if #actual >= maxPublicaciones then
						estado = "lleno"
						return nil
					end
					table.insert(actual, id)
					estado = "ok"
					return actual
				end)
				return true
			end)
			return if ok then estado else "error"
		end
		local reserva = reservar()
		if reserva == "lleno" then
			procesarJugador(player) -- limpia publicaciones terminadas y reintenta
			reserva = reservar()
		end
		if reserva == "lleno" then
			avisar(player, `Ya tenés {maxPublicaciones} publicaciones activas.`)
			return NetworkBridge.Fail("NOT_ALLOWED")
		elseif reserva ~= "ok" then
			return NetworkBridge.Fail("INTERNAL_ERROR")
		end

		-- 2. Buscar el ítem por Uid y retenerlo junto con el depósito, anotándolo en
		--    el diario del perfil, todo sin pausas.
		local clave, item = DataManager.BuscarPorUid(player, uid)
		local datos = DataManager.GetData(player)
		local deposito = math.max(1, math.floor(precio * CFG.Deposito))
		if not clave or not item or not datos then
			quitarDeLista(`V_{vendedorId}`, id)
			return NetworkBridge.Fail("NOT_FOUND")
		end
		if datos.Oro < deposito then
			quitarDeLista(`V_{vendedorId}`, id)
			avisar(player, `Necesitás {deposito} de oro para el depósito.`)
			return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
		end
		if not DataManager.SpendGold(player, deposito) then
			quitarDeLista(`V_{vendedorId}`, id)
			return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
		end
		local retenido = DataManager.QuitarDeRanura(player, clave, item.Cantidad)
		if not retenido then
			DataManager.AddGold(player, deposito)
			quitarDeLista(`V_{vendedorId}`, id)
			return NetworkBridge.Fail("INTERNAL_ERROR")
		end
		DataManager.RegistrarPendienteSubasta(player, id, retenido, deposito)

		-- 3. Guardar el perfil (con el diario) ANTES de crear la publicación.
		if not DataManager.SaveNowAsync(player, 8) then
			devolverPublicacion(player, id, retenido, deposito)
			avisar(player, "No se pudo guardar tu progreso; intentá de nuevo.")
			return NetworkBridge.Fail("INTERNAL_ERROR")
		end
		if not DataManager.PerfilActivo(player) then
			return NetworkBridge.Fail("DATA_NOT_LOADED") -- se fue: el diario lo resuelve al volver
		end

		-- 4. Crear la publicación (UpdateAsync con token: se sabe si se escribió).
		local ahora = os.time()
		local token = HttpService:GenerateGUID(false)
		local publicacion: Publicacion = {
			Id = id,
			VendedorId = vendedorId,
			VendedorNombre = player.DisplayName,
			Item = retenido,
			Precio = precio,
			Creada = ahora,
			Expira = ahora + duracionSegundos(),
			Estado = "Activa",
			Token = token,
		}
		local okCrear, creada = conReintentos(3, function()
			return obtenerStore():UpdateAsync(`L_{id}`, function(actual: Publicacion?): Publicacion?
				if actual then
					return nil -- ya existe (un intento anterior se escribió)
				end
				return publicacion
			end)
		end)
		local confirmada = okCrear and creada ~= nil
		if not confirmada then
			local okLeer, existente = leer(id)
			if okLeer and existente and existente.Token == token then
				confirmada = true
			elseif okLeer and not existente then
				-- Definitivamente no se creó: se devuelve todo.
				devolverPublicacion(player, id, retenido, deposito)
				return NetworkBridge.Fail("INTERNAL_ERROR")
			else
				-- No se sabe: el diario queda anotado y se revisa más tarde.
				reconciliarDespues(player)
				avisar(
					player,
					"La Casa de Subastas tiene problemas; si la publicación no aparece, tu ítem y el depósito vuelven solos."
				)
				return NetworkBridge.Fail("INTERNAL_ERROR")
			end
		end
		DataManager.QuitarPendiente(player, "Subastas", id)
		agregarALista(`V_{vendedorId}`, id) -- por si otro servidor borró la reserva mientras tanto

		-- 5. Indexar para la búsqueda.
		local okIndice = conReintentos(3, function()
			obtenerIndice():SetAsync(id, resumen(publicacion), duracionSegundos(), precio)
			return true
		end)
		if not okIndice then
			warn(`[Subastas] {id} publicada pero no indexada; se puede cancelar desde "Mis publicaciones"`)
		end
		cache.hora = 0
		avisar(player, `Publicaste {nombreItem(retenido)} por {precio} de oro (depósito: {deposito}).`, "Oro")
		return NetworkBridge.Ok(resumen(publicacion))
	end)()
	operacionesPorId[id] = nil
	return resultado
end

local function comprar(player: Player, id: string): Respuesta
	local okLeer, p = leer(id)
	if not okLeer then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if not p or p.Estado ~= "Activa" or p.Expira <= os.time() then
		avisar(player, "Esa publicación ya no está disponible.")
		quitarDelIndice(id)
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if p.VendedorId == player.UserId then
		avisar(player, "No podés comprar tu propia publicación.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local precio = p.Precio
	local compradorId = player.UserId
	if operacionesPorId[id] then
		return NetworkBridge.Fail("RATE_LIMITED")
	end
	operacionesPorId[id] = true
	local resultado = (function(): Respuesta
		-- El oro sale del perfil y queda anotado en el diario, sin pausas; después
		-- se guarda el perfil antes de la transacción.
		if not DataManager.SpendGold(player, precio) then
			avisar(player, "No tenés oro suficiente.")
			return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
		end
		DataManager.RegistrarPendienteCompra(player, id, precio)
		if not DataManager.SaveNowAsync(player, 8) then
			DataManager.QuitarPendiente(player, "Compras", id)
			DataManager.AddGold(player, precio)
			avisar(player, "No se pudo guardar tu progreso; intentá de nuevo.")
			return NetworkBridge.Fail("INTERNAL_ERROR")
		end
		if not DataManager.PerfilActivo(player) then
			return NetworkBridge.Fail("DATA_NOT_LOADED") -- se fue: el diario lo resuelve al volver
		end

		local res, ganada = transicion(id, function(x)
			return x.Estado == "Activa" and x.Expira > os.time() and x.Precio == precio
		end, function(x)
			x.Estado = "Vendida"
			x.CompradorId = compradorId
			x.Destinatario = compradorId
			x.Neto = precio - math.floor(precio * CFG.Impuesto)
			x.PendienteItem = true
			x.PendienteOro = true
		end)
		if res == "Desconocido" then
			-- No se sabe si se compró: NO se devuelve nada todavía. El diario lo
			-- resuelve en cuanto el DataStore responda.
			reconciliarDespues(player)
			avisar(player, "La Casa de Subastas no responde. Si la compra no se concretó, te devolvemos el oro solo.")
			return NetworkBridge.Fail("INTERNAL_ERROR")
		elseif res == "Perdio" or not ganada then
			DataManager.QuitarPendiente(player, "Compras", id)
			devolverOro(player, precio, `subasta:{id}:reembolso:{compradorId}`, "Compra no realizada")
			task.spawn(DataManager.SaveNowAsync, player, 8)
			avisar(player, "Otro jugador la compró primero. Te devolvimos el oro.")
			quitarDelIndice(id)
			return NetworkBridge.Fail("NOT_FOUND")
		end

		-- Compra hecha: el diario se cierra y la lista C_ asegura la entrega.
		DataManager.QuitarPendiente(player, "Compras", id)
		agregarALista(`C_{compradorId}`, id)
		quitarDelIndice(id)
		local completo = entregarPendientes(ganada)
		if completo then
			quitarDeLista(`C_{compradorId}`, id)
			quitarDeLista(`V_{ganada.VendedorId}`, id)
		end
		avisar(player, `Compraste {nombreItem(ganada.Item)}: llega a tu inventario por el buzón.`, "Oro")
		return NetworkBridge.Ok(nil)
	end)()
	operacionesPorId[id] = nil
	return resultado
end

local function cancelar(player: Player, id: string): Respuesta
	local vendedorId = player.UserId
	local res, cancelada = transicion(id, function(x)
		return x.Estado == "Activa" and x.VendedorId == vendedorId
	end, function(x)
		x.Estado = "Cancelada"
		x.Destinatario = vendedorId
		x.PendienteItem = true
	end)
	if res == "Desconocido" then
		avisar(player, "La Casa de Subastas no responde; probá de nuevo en un rato.")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	elseif res ~= "Gano" or not cancelada then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	quitarDelIndice(id)
	if entregarPendientes(cancelada) then
		quitarDeLista(`V_{vendedorId}`, id)
	end
	avisar(player, "Publicación cancelada: el ítem vuelve por el buzón (el depósito no se devuelve).", "Info")
	return NetworkBridge.Ok(nil)
end

local function buscar(texto: string?, rareza: string?, categoria: string?, precioMaximo: number?): Respuesta
	local ahora = os.clock()
	if ahora - cache.hora > CFG.CacheBusquedaSegundos then
		local todas: { any } = {}
		local limite: any = nil
		for _ = 1, PAGINAS_BUSQUEDA do
			local ok, pagina = conReintentos(2, function()
				return obtenerIndice():GetRangeAsync(Enum.SortDirection.Ascending, 200, limite)
			end)
			if not ok or not pagina then
				if #todas == 0 then
					return NetworkBridge.Fail("INTERNAL_ERROR")
				end
				break
			end
			local entradas = pagina :: { any }
			for _, e in entradas do
				table.insert(todas, e)
			end
			if #entradas < 200 then
				break
			end
			local ultima = entradas[#entradas]
			limite = { key = ultima.key, sortKey = ultima.sortKey }
		end
		cache.hora = ahora
		cache.entradas = todas
	end
	local filtro = if texto then string.lower(texto) else nil
	local resultado: { any } = {}
	local t = os.time()
	for _, entrada in cache.entradas do
		local r = entrada.value
		if typeof(r) ~= "table" or typeof(r.Expira) ~= "number" or r.Expira <= t then
			continue
		end
		if filtro and filtro ~= "" and not string.find(string.lower(tostring(r.Nombre)), filtro, 1, true) then
			continue
		end
		if rareza and typeof(r.Item) == "table" and r.Item.Rareza ~= rareza then
			continue
		end
		if categoria then
			local def = if typeof(r.Item) == "table" then ItemCatalog[r.Item.ItemId] else nil
			if not def or def.Tipo ~= categoria then
				continue
			end
		end
		if precioMaximo and (typeof(r.Precio) ~= "number" or r.Precio > precioMaximo) then
			continue
		end
		table.insert(resultado, r)
		if #resultado >= 50 then
			break
		end
	end
	return NetworkBridge.Ok(resultado)
end

-- Enfriamiento por jugador y por operación: cada pedido cuesta lecturas y
-- escrituras de DataStore (presupuesto compartido con los perfiles).
local ultimoPedido: { [Player]: { [string]: number } } = {}
local ESPERAS: { [string]: number } = { Buscar = 1, Publicar = 2, Comprar = 2, Cancelar = 2, Mias = 10 }

local function enfriado(player: Player, operacion: string): boolean
	local porJugador = ultimoPedido[player]
	if not porJugador then
		porJugador = {}
		ultimoPedido[player] = porJugador
	end
	local ahora = os.clock()
	if ahora - (porJugador[operacion] or -math.huge) < (ESPERAS[operacion] or 1) then
		return false
	end
	porJugador[operacion] = ahora
	return true
end

-- Los ids de publicación son GUID: cualquier otra cosa se rechaza sin tocar el DataStore.
local function esGuid(texto: string): boolean
	return string.match(texto, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

-- Una operación de subasta por jugador a la vez.
local function conCandado(player: Player, fn: () -> Respuesta): Respuesta
	if ocupados[player] then
		return NetworkBridge.Fail("RATE_LIMITED")
	end
	ocupados[player] = true
	operacionesEnCurso += 1
	local ok, resultado = pcall(fn)
	operacionesEnCurso -= 1
	ocupados[player] = nil
	if not ok then
		warn(`[Subastas] Error: {resultado}`)
		avisar(player, "La Casa de Subastas no está disponible en este momento.")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	return resultado
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

local function prepararTablon(objeto: Instance)
	if not objeto:IsA("BasePart") then
		return
	end
	local tablon = objeto
	local prompt = tablon:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir"
	prompt.ObjectText = "Casa de Subastas"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = tablon
	prompt.Triggered:Connect(function(player: Player)
		NetworkBridge.Server.FireClient("SubastaAbrir", player)
	end)
end

local function crearTablonPrueba()
	local tablon = Instance.new("Part")
	tablon.Name = "CasaDeSubastas"
	tablon.Anchored = true
	tablon.Size = Vector3.new(8, 6, 1)
	tablon.Color = Color3.fromRGB(120, 85, 50)
	tablon.Material = Enum.Material.WoodPlanks
	tablon.Position = Vector3.new(40, 3, -30)
	local cartel = Instance.new("BillboardGui")
	cartel.Size = UDim2.fromScale(10, 1.6)
	cartel.StudsOffset = Vector3.new(0, 4.5, 0)
	cartel.MaxDistance = 80
	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.TextColor3 = Color3.fromRGB(255, 215, 90)
	texto.TextStrokeTransparency = 0.3
	texto.Text = "Casa de Subastas"
	texto.Parent = cartel
	cartel.Parent = tablon
	tablon.Parent = Workspace
	CollectionService:AddTag(tablon, TAG_CASA)
end

function AuctionManager.Init()
	assert(not iniciado, "AuctionManager.Init() se llamó dos veces")
	iniciado = true

	local okStore, s = pcall(function()
		return DataStoreService:GetDataStore(CFG.NombreStore .. (if RunService:IsStudio() then "_Studio" else ""))
	end)
	local okIndice, m = pcall(function()
		return MemoryStoreService:GetSortedMap(CFG.NombreIndice .. (if RunService:IsStudio() then "_Studio" else ""))
	end)
	if not okStore or not okIndice then
		warn("[Subastas] DataStore o MemoryStore no disponibles; la Casa de Subastas queda desactivada.")
		return
	end
	store = s
	indice = m
	local opciones = Instance.new("DataStoreGetOptions")
	opciones.UseCache = false
	opcionesSinCache = opciones

	if Pruebas.Activas() and #CollectionService:GetTagged(TAG_CASA) == 0 then
		crearTablonPrueba()
	end
	for _, objeto in CollectionService:GetTagged(TAG_CASA) do
		prepararTablon(objeto)
	end
	CollectionService:GetInstanceAddedSignal(TAG_CASA):Connect(prepararTablon)

	local CATEGORIAS = { Material = true, Consumible = true, Equipo = true, Herramienta = true, Cosmetico = true }
	NetworkBridge.Server.OnInvoke(
		"SubastaBuscar",
		function(player: Player, texto: unknown, rareza: unknown, categoria: unknown, precioMaximo: unknown): Respuesta
			local filtro = if texto == nil or texto == "" then nil else NetworkBridge.Guard.String(texto, 40)
			local r = if rareza == nil or rareza == ""
				then nil
				else NetworkBridge.Guard.OneOf(rareza, ItemRarityConfig.Rarezas)
			local c = if categoria == nil or categoria == ""
				then nil
				else NetworkBridge.Guard.OneOf(categoria, CATEGORIAS)
			local tope = if precioMaximo == nil
				then nil
				else NetworkBridge.Guard.Integer(precioMaximo, 1, CFG.PrecioMaximo)
			if (categoria ~= nil and categoria ~= "" and not c) or (precioMaximo ~= nil and not tope) then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if not enfriado(player, "Buscar") then
				return NetworkBridge.Fail("RATE_LIMITED")
			end
			return conCandado(player, function()
				return buscar(filtro, r, c, tope)
			end)
		end
	)

	NetworkBridge.Server.OnInvoke("SubastaPublicar", function(player: Player, uid: unknown, precio: unknown): Respuesta
		local u = NetworkBridge.Guard.String(uid, 64)
		local p = NetworkBridge.Guard.Integer(precio, CFG.PrecioMinimo, CFG.PrecioMaximo)
		if not u or not p then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not enfriado(player, "Publicar") then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return conCandado(player, function()
			return publicar(player, u, p)
		end)
	end)

	NetworkBridge.Server.OnInvoke("SubastaComprar", function(player: Player, id: unknown): Respuesta
		local s2 = NetworkBridge.Guard.String(id, 64)
		if not s2 or not esGuid(s2) then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not enfriado(player, "Comprar") then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return conCandado(player, function()
			return comprar(player, s2)
		end)
	end)

	NetworkBridge.Server.OnInvoke("SubastaCancelar", function(player: Player, id: unknown): Respuesta
		local s2 = NetworkBridge.Guard.String(id, 64)
		if not s2 or not esGuid(s2) then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not enfriado(player, "Cancelar") then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return conCandado(player, function()
			return cancelar(player, s2)
		end)
	end)

	NetworkBridge.Server.OnInvoke("SubastaMias", function(player: Player): Respuesta
		if not enfriado(player, "Mias") then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return conCandado(player, function()
			return NetworkBridge.Ok(procesarJugador(player))
		end)
	end)

	-- Al entrar: vencimientos y entregas pendientes (como vendedor y como comprador).
	DataManager.PerfilCargado:Connect(function(player: Player)
		task.spawn(function()
			conCandado(player, function()
				reconciliar(player) -- primero el diario: operaciones que quedaron a medias
				procesarJugador(player)
				return NetworkBridge.Ok(nil)
			end)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		ocupados[player] = nil
		ultimoPedido[player] = nil
	end)
	-- El cierre del servidor espera a las operaciones de subasta en curso.
	game:BindToClose(function()
		local limite = os.clock() + 25
		while operacionesEnCurso > 0 and os.clock() < limite do
			task.wait(0.2)
		end
	end)
end

return AuctionManager
