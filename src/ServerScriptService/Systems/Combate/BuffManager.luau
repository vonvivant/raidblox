--!strict
-- BuffManager: efectos de los consumibles con efecto propio (elixires,
-- tónicos, infusiones, antídotos) y de las mejoras temporales que dan los NPC
-- (por ejemplo, el Afilador). Las definiciones están en ConsumiblesConfig.
--
-- * Instantáneos: se aplican en el momento (los cobra InventarioManager con la
--   recarga compartida de las pociones).
-- * Temporales: uno por categoría; se guardan en el perfil (`Buffs`) con su
--   vencimiento en os.time(), así que siguen corriendo si el jugador muere,
--   cambia de zona o se desconecta. Al reaparecer se vuelven a aplicar con el
--   tiempo que les queda.
--
-- Todo se decide en el servidor: el cliente solo pide usar una ranura.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConsumiblesConfig = require(ReplicatedStorage.Configs.ConsumiblesConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local CombatManager = require(script.Parent.CombatManager)

type Definicion = ConsumiblesConfig.Definicion
type EfectoTemporal = ConsumiblesConfig.EfectoTemporal
type Activo = { Id: string, Hasta: number, Malo: boolean? }

local PREFIJO = "Buff_" -- fuente de las auras que pone este módulo

local BuffManager = {}

local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

-- Efectos que corresponden a un buff activo (los malos si el sorteo salió mal).
local function efectosDe(activo: Activo): { EfectoTemporal }
	local def = ConsumiblesConfig.Definiciones[activo.Id]
	if not def then
		return {}
	end
	if activo.Malo and def.Riesgo then
		return def.Riesgo.Malos
	end
	return def.Efectos or {}
end

-- Buffs vigentes del jugador (poda los vencidos).
local function activos(player: Player): { [string]: Activo }
	local datos = DataManager.GetData(player)
	local mapa = datos and datos.Buffs
	if not mapa then
		return {}
	end
	local ahora = os.time()
	for categoria, activo in mapa do
		if activo.Hasta <= ahora or not ConsumiblesConfig.Definiciones[activo.Id] then
			mapa[categoria] = nil
		end
	end
	return mapa
end

-- Suma de un tipo de efecto entre todos los buffs activos.
local function total(player: Player, tipo: string): number
	local suma = 0
	for _, activo in activos(player) do
		for _, efecto in efectosDe(activo) do
			if efecto.Tipo == tipo then
				suma += efecto.Porcentaje
			end
		end
	end
	return suma
end

-- Pone en el combatiente las auras de una categoría, con el tiempo que le queda.
local function aplicarAuras(c: CombatManager.Combatiente, categoria: string, activo: Activo)
	local fuente = PREFIJO .. categoria
	CombatManager.QuitarAuras(c, fuente)
	local restante = activo.Hasta - os.time()
	if restante <= 0 then
		return
	end
	for _, efecto in efectosDe(activo) do
		local stat = efecto.Stat
		if efecto.Tipo == "Aura" and (stat == "Ataque" or stat == "Poder" or stat == "Defensa") then
			CombatManager.AplicarEfecto(
				c,
				c,
				{ Tipo = "Aura", Stat = stat, Porcentaje = efecto.Porcentaje, Duracion = restante },
				fuente
			)
		end
	end
end

local function reaplicar(player: Player, c: CombatManager.Combatiente)
	for categoria, activo in activos(player) do
		aplicarAuras(c, categoria, activo)
	end
	CombatManager.PublicarEfectos(c)
end

-- Activa un buff temporal (reemplaza al de su misma categoría). Devuelve false
-- si la definición no existe, no es temporal o el jugador no está en condiciones.
function BuffManager.Dar(player: Player, id: string): boolean
	local def = ConsumiblesConfig.Definiciones[id]
	local categoria = def and def.Categoria
	local duracion = def and def.Duracion
	local datos = DataManager.GetData(player)
	local c = CombatManager.DeJugador(player)
	if not def or not categoria or not duracion or not datos or not c or not CombatManager.EstaVivo(c) then
		return false
	end
	local riesgo = def.Riesgo
	local malo = riesgo ~= nil and math.random() < riesgo.Probabilidad
	local activo: Activo = { Id = id, Hasta = os.time() + duracion, Malo = if malo then true else nil }
	local anterior: { [string]: Activo } = datos.Buffs or {}
	local reemplazado = anterior[categoria]
	anterior[categoria] = activo
	datos.Buffs = anterior
	aplicarAuras(c, categoria, activo)
	CombatManager.PublicarEfectos(c)

	local nombreCategoria = ConsumiblesConfig.NombresCategoria[categoria] or categoria
	if malo and riesgo then
		avisar(player, riesgo.Texto, "Error")
	elseif reemplazado and reemplazado.Id ~= id then
		local previo = ConsumiblesConfig.Definiciones[reemplazado.Id]
		avisar(player, `{def.Nombre} reemplazó a {if previo then previo.Nombre else "tu " .. nombreCategoria}.`)
	else
		avisar(player, `{def.Nombre}: activo por {math.ceil(duracion / 60)} min.`)
	end
	return true
end

-- Usa un consumible de ConsumiblesConfig. Devuelve si se aplicó (recién ahí se
-- gasta el ítem) y, si no, el motivo para mostrarle al jugador.
function BuffManager.Usar(player: Player, itemId: string): (boolean, string?)
	local def = ConsumiblesConfig.Definiciones[itemId]
	local c = CombatManager.DeJugador(player)
	if not def then
		return false, "Ese objeto no se puede usar."
	end
	if not c or not CombatManager.EstaVivo(c) then
		return false, "No podés usarlo ahora."
	end
	if not def.Instantaneo then
		return BuffManager.Dar(player, itemId), "No podés usarlo ahora."
	end
	local hizoAlgo = false
	local instantaneos: { ConsumiblesConfig.EfectoInstantaneo } = def.EfectosInstantaneos or {}
	for _, efecto in instantaneos do
		local porcentaje = efecto.Porcentaje or 0
		local duracion = efecto.Duracion or 0
		if efecto.Tipo == "Purificar" then
			hizoAlgo = CombatManager.Purificar(c, PREFIJO) > 0 or hizoAlgo
		elseif efecto.Tipo == "Escudo" then
			CombatManager.DarEscudo(c, c.Stats.VidaMax * porcentaje / 100, duracion)
			hizoAlgo = true
		elseif efecto.Tipo == "CuraTiempo" then
			CombatManager.AplicarEfecto(c, c, {
				Tipo = "CuraTiempo",
				Base = c.Stats.VidaMax * porcentaje / 100,
				Factor = 0,
				Duracion = duracion,
				Intervalo = efecto.Intervalo or 2,
			}, PREFIJO .. itemId)
			hizoAlgo = true
		end
	end
	if not hizoAlgo then
		return false, "No tenés nada que curar."
	end
	return true, nil
end

-- ¿Ese ítem lo maneja este módulo? Y si es instantáneo (comparte la recarga
-- de las pociones).
function BuffManager.Maneja(itemId: string): (boolean, boolean)
	local def = ConsumiblesConfig.Definiciones[itemId]
	return def ~= nil, def ~= nil and def.Instantaneo == true
end

function BuffManager.Init()
	assert(not iniciado, "BuffManager.Init() se llamó dos veces")
	iniciado = true

	CombatManager.SetPrisa(function(player: Player): number
		return math.min(total(player, "Prisa"), ConsumiblesConfig.PrisaMaxima) / 100
	end)

	-- Lo que no es un aura de stat también se muestra junto a los buffs.
	CombatManager.SetEfectosExtra(function(player: Player)
		local lista: { { Nombre: string, Hasta: number } } = {}
		local resto = CombatManager.Ahora() - os.time() -- pasa de os.time() a hora del servidor
		for _, activo in activos(player) do
			for _, efecto in efectosDe(activo) do
				if efecto.Tipo == "Prisa" then
					table.insert(lista, { Nombre = `-{efecto.Porcentaje}% recargas`, Hasta = activo.Hasta + resto })
				elseif efecto.Tipo == "RegenMana" then
					table.insert(lista, { Nombre = "Energía", Hasta = activo.Hasta + resto })
				elseif efecto.Tipo == "RegenVida" then
					table.insert(lista, { Nombre = "Vitalidad", Hasta = activo.Hasta + resto })
				end
			end
		end
		return lista
	end)

	CombatManager.JugadorListo:Connect(reaplicar)
	for _, player in Players:GetPlayers() do
		local c = CombatManager.DeJugador(player)
		if c then
			reaplicar(player, c)
		end
	end

	-- Pulsos de regeneración. Solo trabaja para quien tiene un buff de ese tipo.
	task.spawn(function()
		while true do
			task.wait(ConsumiblesConfig.IntervaloRegen)
			for _, player in Players:GetPlayers() do
				local datos = DataManager.GetData(player)
				if not datos or not datos.Buffs or next(datos.Buffs) == nil then
					continue
				end
				local mana = total(player, "RegenMana")
				if mana > 0 then
					CombatManager.RecuperarJugador(player, "Mana", mana)
				end
				local vida = total(player, "RegenVida")
				if vida > 0 then
					CombatManager.RecuperarJugador(player, "Vida", vida)
				end
			end
		end
	end)
end

return BuffManager
