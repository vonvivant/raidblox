--!strict
-- ForjaManager: servicios de herrería sobre el equipo (ForjaConfig).
--
-- * Durabilidad: el equipo puesto se desgasta al morir y, cada tanto, al
--   recibir golpes. Con durabilidad 0 no da estadísticas hasta repararlo.
-- * Reparar (Reparador de Armaduras), Desencantar, Reforjar y Engarzar gemas:
--   acciones que se registran en NpcManager y se usan hablando con el NPC.
--
-- Cada operación verifica todo antes de tocar nada (oro, materiales, lugar en
-- la mochila) y después cobra y aplica sin ceder el hilo, así que no se puede
-- quedar a medias ni duplicar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ForjaConfig = require(ReplicatedStorage.Configs.ForjaConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ItemRarityConfig = require(ReplicatedStorage.Configs.ItemRarityConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local NpcManager = require(script.Parent.Parent.NpcManager)
local Buzon = require(script.Parent.Parent.Buzon)
local CombatManager = require(script.Parent.Parent.Combate.CombatManager)

type ItemInstancia = Types.ItemInstancia

local DUR = ForjaConfig.Durabilidad

local ForjaManager = {}

local iniciado = false
local azar = Random.new()

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
end

local function nombreDe(item: ItemInstancia): string
	local def = ItemCatalog[item.ItemId]
	return if def then def.Nombre else item.ItemId
end

-- Cuántas unidades de un ítem (sin metadatos) hay en la mochila.
local function contar(player: Player, itemId: string): number
	local datos = DataManager.GetData(player)
	local total = 0
	if datos then
		for _, item in datos.Inventario.Slots do
			if item.ItemId == itemId and item.Meta == nil then
				total += item.Cantidad
			end
		end
	end
	return total
end

------------------------------------------------------------------------
-- Durabilidad
------------------------------------------------------------------------

local function equipados(datos: Types.DatosJugador): { ItemInstancia }
	local lista: { ItemInstancia } = {}
	for _, item in datos.Equipamiento :: { [string]: ItemInstancia } do
		if ForjaConfig.TieneDurabilidad(item) then
			table.insert(lista, item)
		end
	end
	return lista
end

local function fijarDurabilidad(item: ItemInstancia, valor: number)
	local meta: Types.ItemMeta = item.Meta or {}
	if valor >= DUR.Maxima then
		(meta :: any).Dur = nil
		-- Un equipo Común entero vuelve a no tener metadatos.
		item.Meta = if next(meta) == nil then nil else meta
	else
		meta.Dur = math.max(0, math.floor(valor))
		item.Meta = meta
	end
end

-- Le quita `puntos` a las piezas dadas y avisa si alguna quedó baja o rota.
local function desgastar(player: Player, piezas: { ItemInstancia }, puntos: number)
	local rotas: { string } = {}
	local bajas: { string } = {}
	local cambio = false
	DataManager.Mutar(player, "Equipamiento", function()
		for _, item in piezas do
			local antes = ForjaConfig.DurabilidadDe(item)
			if antes <= 0 then
				continue
			end
			local ahora = math.max(0, antes - puntos)
			fijarDurabilidad(item, ahora)
			cambio = true
			if ahora == 0 then
				table.insert(rotas, nombreDe(item))
			elseif ahora <= DUR.AvisoBajo and antes > DUR.AvisoBajo then
				table.insert(bajas, nombreDe(item))
			end
		end
	end)
	if not cambio then
		return
	end
	if #rotas > 0 then
		avisar(player, `Se rompió: {table.concat(rotas, ", ")}. No da estadísticas hasta repararlo.`)
	elseif #bajas > 0 then
		avisar(player, `Durabilidad baja: {table.concat(bajas, ", ")}. Buscá un Reparador.`, "Info")
	end
end

local function alMorir(player: Player)
	local datos = DataManager.GetData(player)
	if datos then
		desgastar(player, equipados(datos), DUR.PorMuerte)
	end
end

local function alRecibirGolpe(player: Player)
	if azar:NextNumber() >= DUR.ProbabilidadPorGolpe then
		return
	end
	local datos = DataManager.GetData(player)
	local piezas = if datos then equipados(datos) else {}
	if #piezas > 0 then
		desgastar(player, { piezas[azar:NextInteger(1, #piezas)] }, 1)
	end
end

-- Piezas a reparar: las equipadas y, si `conMochila`, también las guardadas.
local function aReparar(player: Player, conMochila: boolean): ({ ItemInstancia }, number)
	local datos = DataManager.GetData(player)
	local lista: { ItemInstancia } = {}
	local costo = 0
	if not datos then
		return lista, 0
	end
	local function sumar(item: ItemInstancia)
		local c = ForjaConfig.CostoReparar(item)
		if c > 0 then
			table.insert(lista, item)
			costo += c
		end
	end
	for _, item in datos.Equipamiento :: { [string]: ItemInstancia } do
		sumar(item)
	end
	if conMochila then
		for _, item in datos.Inventario.Slots do
			sumar(item)
		end
	end
	return lista, costo
end

-- Gancho de RazaManager: descuento en el costo de reparar.
local descuentoReparacion: ((Player, number) -> number)? = nil

function ForjaManager.RegistrarDescuentoReparacion(fn: (Player, number) -> number)
	descuentoReparacion = fn
end

local function reparar(player: Player, conMochila: boolean): boolean
	if CombatManager.EnCombate(player) then
		avisar(player, "No se puede reparar en combate.")
		return false
	end
	local piezas, costo = aReparar(player, conMochila)
	if descuentoReparacion then
		costo = descuentoReparacion(player, costo)
	end
	if #piezas == 0 then
		avisar(player, "No tenés nada que reparar.", "Info")
		return false
	end
	if not DataManager.SpendGold(player, costo) then
		avisar(player, `Reparar cuesta {costo} de oro.`)
		return false
	end
	DataManager.Mutar(player, "Equipamiento", function()
		for _, item in piezas do
			fijarDurabilidad(item, DUR.Maxima)
		end
	end)
	if conMochila then
		DataManager.Mutar(player, "Inventario", function() end)
	end
	avisar(player, `Reparaste {#piezas} pieza(s) por {costo} de oro.`, "Oro")
	return true
end

-- Cuántos puntos de durabilidad le faltan a lo que lleva puesto.
local function puntosEquipados(player: Player): number
	local datos = DataManager.GetData(player)
	if not datos then
		return 0
	end
	local faltan = 0
	for _, item in equipados(datos) do
		faltan += DUR.Maxima - ForjaConfig.DurabilidadDe(item)
	end
	return faltan
end

-- Cotización de la reparación de campo: cuánto sale, cuántas piezas entran y
-- cuántos segundos faltan para poder usarla.
local ultimaEmergencia: { [Player]: number } = {}

local function esperaEmergencia(player: Player): number
	local ultima = ultimaEmergencia[player]
	if not ultima then
		return 0
	end
	return math.max(0, ForjaConfig.Emergencia.EsperaSegundos - (os.clock() - ultima))
end

local function cotizarCampo(player: Player): (number, number, number)
	local piezas, costo = aReparar(player, false)
	if descuentoReparacion then
		costo = descuentoReparacion(player, costo)
	end
	return ForjaConfig.CostoEmergencia(costo), #piezas, esperaEmergencia(player)
end

-- Reparación de campo: lo mismo que "Reparar lo equipado", sin NPC, al triple
-- y con espera. Sigue sin funcionar en combate: lo que se paga es no tener que
-- volver a la ciudad, no arreglarse en medio de una pelea.
local function repararCampo(player: Player): Types.Respuesta
	if CombatManager.EnCombate(player) then
		avisar(player, "No se puede reparar en combate.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local espera = esperaEmergencia(player)
	if espera > 0 then
		avisar(player, `La reparación de campo se puede usar de nuevo en {math.ceil(espera / 60)} min.`)
		return NetworkBridge.Fail("RATE_LIMITED")
	end
	if puntosEquipados(player) < ForjaConfig.Emergencia.MinimoPuntos then
		avisar(player, "Tu equipo está casi entero: no vale la pena pagar la tarifa.", "Info")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local piezas, base = aReparar(player, false)
	if descuentoReparacion then
		base = descuentoReparacion(player, base)
	end
	local costo = ForjaConfig.CostoEmergencia(base)
	if #piezas == 0 or costo <= 0 then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not DataManager.SpendGold(player, costo) then
		avisar(player, `La reparación de campo cuesta {costo} de oro.`)
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	-- Recién acá se marca el uso: si no se pudo cobrar, no se gastó la espera.
	ultimaEmergencia[player] = os.clock()
	DataManager.Mutar(player, "Equipamiento", function()
		for _, item in piezas do
			fijarDurabilidad(item, DUR.Maxima)
		end
	end)
	avisar(player, `Reparación de campo: {#piezas} pieza(s) por {costo} de oro.`, "Oro")
	return NetworkBridge.Ok({ Costo = costo, Piezas = #piezas })
end

------------------------------------------------------------------------
-- Operaciones sobre un ítem de la mochila
------------------------------------------------------------------------

-- Validación común: el ítem existe, la operación aplica y alcanza el oro y el
-- material. Devuelve el ítem y el costo, o nil (ya avisó al jugador).
local function preparar(player: Player, operacion: string, ranura: string): (ItemInstancia?, number)
	local item = DataManager.ItemEnRanura(player, ranura)
	local datos = DataManager.GetData(player)
	if not item or not datos or not ForjaConfig.Aplica(operacion, item) then
		avisar(player, "Ese objeto no sirve para esto.")
		return nil, 0
	end
	local costo = ForjaConfig.Costo(operacion, item)
	if datos.Oro < costo then
		avisar(player, `Cuesta {costo} de oro.`)
		return nil, 0
	end
	local material, cantidad = ForjaConfig.Material(operacion)
	if material and contar(player, material) < cantidad then
		local def = ItemCatalog[material]
		avisar(player, `Necesitás {cantidad} {if def then def.Nombre else material}.`)
		return nil, 0
	end
	return item, costo
end

-- Cobra el oro y el material de la operación (preparar() ya verificó que alcanzan).
local function cobrar(player: Player, operacion: string, costo: number): boolean
	local material, cantidad = ForjaConfig.Material(operacion)
	if material and not DataManager.RemoveItem(player, material, cantidad) then
		return false
	end
	if not DataManager.SpendGold(player, costo) then
		if material then
			DataManager.AddItem(player, material, cantidad, "Comun")
		end
		return false
	end
	return true
end

local function desencantar(player: Player, _npc: any, ranura: string): boolean
	local item, costo = preparar(player, "Desencantar", ranura)
	if not item then
		return false
	end
	local resultado = ForjaConfig.Desencantar.Resultado[item.Rareza]
	local tipos = 0
	for _ in resultado do
		tipos += 1
	end
	-- El ítem destruido libera una ranura; cada esencia ocupa, como mucho, una.
	if DataManager.RanurasLibres(player) + 1 < tipos then
		avisar(player, "No tenés lugar en la mochila para las esencias.")
		return false
	end
	if not cobrar(player, "Desencantar", costo) then
		return false
	end
	local nombre = nombreDe(item)
	DataManager.QuitarDeRanura(player, ranura, item.Cantidad)
	local partes: { string } = {}
	for itemId, cantidad in resultado do
		if not DataManager.AddItem(player, itemId, cantidad, "Comun") then
			warn(`[Forja] No entró {itemId} x{cantidad} para {player.UserId} al desencantar`)
		end
		local def = ItemCatalog[itemId]
		table.insert(partes, `{if def then def.Nombre else itemId} x{cantidad}`)
	end
	table.sort(partes)
	avisar(player, `Desencantaste {nombre}: {table.concat(partes, ", ")}.`, "Oro")
	return true
end

-- Sortea `cantidad` efectos secundarios, prefiriendo los que el ítem no tenía.
local function nuevosEfectos(previos: { [string]: boolean }, cantidad: number): { string }
	local nuevos: { string } = {}
	local repetidos: { string } = {}
	for clave in ItemRarityConfig.Efectos do
		table.insert(if previos[clave] then repetidos else nuevos, clave)
	end
	table.sort(nuevos)
	table.sort(repetidos)
	local function mezclar(lista: { string })
		for i = #lista, 2, -1 do
			local j = azar:NextInteger(1, i)
			lista[i], lista[j] = lista[j], lista[i]
		end
	end
	mezclar(nuevos)
	mezclar(repetidos)
	local elegidos: { string } = {}
	for _, lista in { nuevos, repetidos } do
		for _, clave in lista do
			if #elegidos < cantidad then
				table.insert(elegidos, clave)
			end
		end
	end
	return elegidos
end

local function reforjar(player: Player, _npc: any, ranura: string): boolean
	local item, costo = preparar(player, "Reforjar", ranura)
	if not item then
		return false
	end
	if not cobrar(player, "Reforjar", costo) then
		return false
	end
	local rareza = ItemRarityConfig.Rarezas[item.Rareza]
	local meta: Types.ItemMeta = if item.Meta then table.clone(item.Meta) else {}
	local previos: { [string]: boolean } = {}
	for clave in meta do
		if string.sub(clave, 1, 7) == "Efecto_" then
			previos[string.sub(clave, 8)] = true
			meta[clave] = nil
		end
	end
	local textos: { string } = {}
	for _, clave in nuevosEfectos(previos, rareza.EfectosSecundarios) do
		local efecto = ItemRarityConfig.Efectos[clave]
		local valor = azar:NextInteger(efecto.Min, efecto.Max)
		meta["Efecto_" .. clave] = valor
		table.insert(textos, string.format(efecto.Formato, valor))
	end
	local previas = if typeof(meta.Reforjas) == "number" then meta.Reforjas else 0
	meta.Reforjas = previas + 1
	DataManager.SetMetaRanura(player, ranura, meta)
	-- Registro de la operación (queda en el log del servidor).
	print(
		`[Forja] {player.UserId} reforjó {item.ItemId} ({item.Uid}) por {costo} de oro: {table.concat(textos, "; ")}`
	)
	avisar(player, `{nombreDe(item)} reforjado: {table.concat(textos, ", ")}.`, "Oro")
	return true
end

local function engarzar(player: Player, _npc: any, ranura: string, gemaId: string?): boolean
	local gema = if gemaId then ForjaConfig.Engarzar.Gemas[gemaId] else nil
	if not gemaId or not gema then
		avisar(player, "Elegí una gema.")
		return false
	end
	local item, costo = preparar(player, "Engarzar", ranura)
	if not item then
		return false
	end
	if contar(player, gemaId) < 1 then
		avisar(player, "No tenés esa gema.")
		return false
	end
	if not cobrar(player, "Engarzar", costo) then
		return false
	end
	if not DataManager.RemoveItem(player, gemaId, 1) then
		return false
	end
	local meta: Types.ItemMeta = if item.Meta then table.clone(item.Meta) else {}
	meta["Gema" .. (#ForjaConfig.GemasDe(item) + 1)] = gemaId
	DataManager.SetMetaRanura(player, ranura, meta)
	avisar(player, `{nombreDe(item)}: {gema.Texto}.`, "Oro")
	return true
end

-- Saca una gema engarzada y la devuelve entera a la mochila. `extra` es el
-- número de ranura (1 a 3) tal como lo muestra la ventana.
local function extraer(player: Player, _npc: any, ranura: string, extra: string?): boolean
	local indice = tonumber(extra)
	if not indice or indice ~= math.floor(indice) or indice < 1 or indice > 3 then
		avisar(player, "Elegí qué gema sacar.")
		return false
	end
	local item, costo = preparar(player, "Extraer", ranura)
	if not item then
		return false
	end
	local gemas = ForjaConfig.GemasDe(item)
	local gemaId = gemas[indice]
	if not gemaId then
		avisar(player, "Esa ranura está vacía.")
		return false
	end
	if DataManager.RanurasLibres(player) < 1 and contar(player, gemaId) <= 0 then
		avisar(player, "No tenés lugar en la mochila para la gema.")
		return false
	end
	if not cobrar(player, "Extraer", costo) then
		return false
	end
	-- Las gemas se corren para no dejar huecos: las ranuras se cuentan por
	-- cuántas gemas hay, un hueco haría desaparecer las de atrás.
	local meta: Types.ItemMeta = if item.Meta then table.clone(item.Meta) else {}
	local quedan = ForjaConfig.SinGema(gemas, indice)
	for i = 1, 3 do
		local libre: { [string]: any } = meta
		libre["Gema" .. i] = quedan[i]
	end
	DataManager.SetMetaRanura(player, ranura, meta)
	if not DataManager.AddItem(player, gemaId, 1, "Comun") then
		-- No debería pasar (ya se revisó el lugar); si pasa, al buzón, que la
		-- gema no se pierda.
		warn(`[Forja] No entró la gema {gemaId} de {player.UserId}: va al buzón`)
		Buzon.EnviarItem(player.UserId, { ItemId = gemaId, Cantidad = 1, Rareza = "Comun" }, "Gema extraída")
	end
	local def = ItemCatalog[gemaId]
	avisar(player, `Sacaste {if def then def.Nombre else gemaId} de {nombreDe(item)}.`, "Oro")
	return true
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function ForjaManager.Init()
	assert(not iniciado, "ForjaManager.Init() se llamó dos veces")
	iniciado = true

	CombatManager.Murio:Connect(function(c: CombatManager.Combatiente)
		if c.Player then
			alMorir(c.Player)
		end
	end)
	CombatManager.DanioAplicado:Connect(function(_fuente, objetivo: CombatManager.Combatiente, cantidad: number)
		if objetivo.Player and cantidad > 0 then
			alRecibirGolpe(objetivo.Player)
		end
	end)

	NpcManager.RegistrarAccion("RepararEquipado", function(player: Player): boolean
		return reparar(player, false)
	end)
	NpcManager.RegistrarCotizacion("RepararEquipado", function(player: Player): number
		local _, costo = aReparar(player, false)
		return costo
	end)
	NpcManager.RegistrarAccion("RepararTodo", function(player: Player): boolean
		return reparar(player, true)
	end)
	NpcManager.RegistrarCotizacion("RepararTodo", function(player: Player): number
		local _, costo = aReparar(player, true)
		return costo
	end)

	NpcManager.RegistrarAccionItem("Desencantar", desencantar)
	NpcManager.RegistrarAccionItem("Reforjar", reforjar)
	NpcManager.RegistrarAccionItem("Engarzar", engarzar)
	NpcManager.RegistrarAccionItem("Extraer", extraer)

	Players.PlayerRemoving:Connect(function(player: Player)
		ultimaEmergencia[player] = nil
	end)

	NetworkBridge.Server.OnInvoke("ForjaCampoCotizar", function(player: Player): Types.Respuesta
		local costo, piezas, espera = cotizarCampo(player)
		return NetworkBridge.Ok({ Costo = costo, Piezas = piezas, Espera = math.ceil(espera) })
	end)

	NetworkBridge.Server.OnInvoke("ForjaCampoReparar", function(player: Player): Types.Respuesta
		return repararCampo(player)
	end)
end

return ForjaManager
