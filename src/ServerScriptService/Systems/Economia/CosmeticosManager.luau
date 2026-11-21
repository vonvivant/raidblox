--!strict
-- CosmeticosManager: el NPC de Cosméticos, un solo lugar para la estética del
-- equipo que el jugador tiene **puesto**.
--
-- Cuatro pestañas:
--   * Visual  — cambia el aspecto del ítem sin tocar sus estadísticas. Usa el
--               transmog por slot que ya existía (EquipoVisible).
--   * Colores — el color de cada pieza, sobre `Meta.Pers` del ítem equipado.
--   * Decals  — calcomanías de color, agrupadas por tipo.
--   * Marcas  — grabados con normal map.
--
-- Absorbe al Transfigurador (#30) y al Tintorero (#31), y la parte de grabado
-- del Inscriptor (#5), que se queda con pergaminos y libros.
--
-- Qué se cobra: aplicar lo que ya tenés desbloqueado es **gratis**. Lo que
-- cuesta es **deshacer**: el primero gratis y de ahí cada uno el doble del
-- anterior (CosmeticosConfig.CostoDeshacer). Por eso el preview importa: la
-- idea es decidir mirando, no probando.
--
-- Cómo se guarda el "antes": en vez de llevar historial adentro del ítem, cada
-- vez que se aplica algo se anota en el perfil lo que ese slot tenía
-- (`CosmeticosAnterior[slot]`: su Pers y su transmog). Deshacer restaura esa
-- foto. Es un solo paso atrás, que es lo que pidió el diseño, y funciona igual
-- para las cuatro pestañas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AparienciaEquipoConfig = require(ReplicatedStorage.Configs.AparienciaEquipoConfig)
local CFG = require(ReplicatedStorage.Configs.CosmeticosConfig)
local PersonalizadorConfig = require(ReplicatedStorage.Configs.PersonalizadorConfig)
local StencilsConfig = require(ReplicatedStorage.Configs.StencilsConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Personalizador = require(ReplicatedStorage.Modules.Personalizador)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local EquipoVisible = require(script.Parent.Parent.EquipoVisible)
local NpcManager = require(script.Parent.Parent.NpcManager)
local PersonalizadorManager = require(script.Parent.PersonalizadorManager)

local CosmeticosManager = {}

local iniciado = false
local sesiones: { [Player]: BasePart } = {}
local enCurso: { [Player]: boolean } = {}

local function avisar(player: Player, texto: string, tipo: string?)
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
	end
end

local function raizDe(player: Player): BasePart?
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	return if raiz and raiz:IsA("BasePart") then raiz else nil
end

-- ¿Sigue junto al NPC con el que abrió? Se revalida en cada pedido.
local function enElNpc(player: Player): boolean
	local npc = sesiones[player]
	local raiz = raizDe(player)
	if not npc or not npc.Parent or not raiz then
		return false
	end
	return (raiz.Position - npc.Position).Magnitude <= CFG.Distancia
end

local function datosDe(player: Player): Types.DatosJugador?
	return DataManager.GetData(player)
end

local function itemEquipado(player: Player, slot: string): Types.ItemInstancia?
	local datos = datosDe(player)
	if not datos then
		return nil
	end
	local equipamiento: { [string]: Types.ItemInstancia? } = datos.Equipamiento :: any
	return equipamiento[slot]
end

local function deshechos(player: Player): number
	local datos = datosDe(player)
	if not datos then
		return 0
	end
	local n = (datos :: any).CosmeticosDeshechos
	return if typeof(n) == "number" then n else 0
end

local function anteriorDe(player: Player, slot: string): { Pers: string?, Transmog: string? }?
	local datos = datosDe(player)
	if not datos then
		return nil
	end
	local todos: { [string]: any } = (datos :: any).CosmeticosAnterior or {}
	local mio = todos[slot]
	return if typeof(mio) == "table" then mio else nil
end

-- Guarda lo que el slot tiene AHORA, antes de pisarlo.
local function recordarEstado(player: Player, slot: string)
	local item = itemEquipado(player, slot)
	local datos = datosDe(player)
	if not datos then
		return
	end
	local transmog: { [string]: string } = (datos.Transmog or {}) :: any
	local foto = {
		Pers = if item and item.Meta then item.Meta.Pers else nil,
		Transmog = transmog[slot],
	}
	DataManager.Mutar(player, "Cosmeticos", function(d)
		local campos: { [string]: any } = d :: any
		local todos: { [string]: any } = campos.CosmeticosAnterior or {}
		todos[slot] = foto
		campos.CosmeticosAnterior = todos
	end)
end

------------------------------------------------------------------------
-- Lo que ve el cliente
------------------------------------------------------------------------

-- Catálogo del ítem equipado en ese slot (piezas editables, etc.).
local function entradaDe(player: Player, slot: string): (Personalizador.Entrada?, Types.ItemInstancia?)
	local item = itemEquipado(player, slot)
	if not item then
		return nil, nil
	end
	return PersonalizadorManager.Catalogo()[item.ItemId], item
end

local function estado(player: Player): { [string]: any }
	local datos = datosDe(player)
	local slots: { any } = {}
	for _, slot in AparienciaEquipoConfig.SlotsVisibles do
		local entrada, item = entradaDe(player, slot :: any)
		local piezas: { any } = {}
		if entrada then
			for _, pieza in entrada.Piezas do
				table.insert(piezas, {
					Id = pieza.Id,
					Nombre = pieza.Nombre,
					Material = pieza.Material,
					Color = pieza.Color,
					EsMesh = pieza.EsMesh,
				})
			end
		end
		table.insert(slots, {
			Slot = slot,
			ItemId = if item then item.ItemId else nil,
			Nombre = if entrada then entrada.Nombre else nil,
			Pers = if item and item.Meta then item.Meta.Pers else nil,
			Piezas = piezas,
			Editable = entrada ~= nil,
			HayAnterior = anteriorDe(player, slot :: any) ~= nil,
		})
	end
	return {
		Slots = slots,
		Transmog = if datos then datos.Transmog or {} else {},
		Apariencias = if datos then datos.Apariencias or {} else {},
		Libros = if datos then (datos :: any).Stencils or {} else {},
		Deshechos = deshechos(player),
		CostoDeshacer = CFG.CostoDeshacer(deshechos(player)),
		Oro = if datos then datos.Oro else 0,
	}
end

------------------------------------------------------------------------
-- Aplicar
------------------------------------------------------------------------

-- Pestañas Colores, Decals y Marcas: las tres escriben la personalización del
-- ítem equipado, y el servidor valida lo mismo en todos los casos (piezas que
-- existen, materiales válidos, decals y marcas desbloqueados y dentro de los
-- topes). La pestaña solo decide qué se le deja tocar.
local function aplicarPersonalizacion(
	player: Player,
	slot: string,
	pestana: string,
	datosPers: unknown
): Types.Respuesta
	local entrada, item = entradaDe(player, slot)
	if not entrada or not item then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local libros: { string } = estado(player).Libros
	local pers, motivo = Personalizador.Normalizar(entrada, datosPers, libros)
	if not pers then
		avisar(player, `No se pudo aplicar: {motivo or "datos inválidos"}.`)
		return NetworkBridge.Fail("INVALID_ARGS")
	end

	local antes = PersonalizadorConfig.Decodificar(if item.Meta then item.Meta.Pers else nil) or {}
	-- Cada pestaña solo puede tocar lo suyo: así, por ejemplo, un pedido de la
	-- pestaña de colores no puede colar un decal que no se pagó.
	for piezaId, pieza in pers do
		local previa = antes[piezaId]
		local original = entrada.PorId[piezaId]
		local colorAntes = if previa then previa.Color else (if original then original.Color else nil)
		local materialAntes = if previa then previa.Material else (if original then original.Material else nil)
		if pestana ~= "Colores" and colorAntes and pieza.Color ~= colorAntes then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		if materialAntes and pieza.Material ~= materialAntes then
			-- El material se elige al comprar el objeto, no acá.
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		local stencilAntes = if previa then previa.Stencil else nil
		if pestana ~= "Decals" and not PersonalizadorConfig.MismoStencil(stencilAntes, pieza.Stencil) then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		local relieveAntes = if previa then previa.Relieve else nil
		if pestana ~= "Marcas" and relieveAntes ~= pieza.Relieve then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
	end

	if PersonalizadorConfig.Diferencias(antes, pers) == 0 then
		return NetworkBridge.Ok({ Estado = "SinCambios" })
	end

	recordarEstado(player, slot)
	local meta: Types.ItemMeta = if item.Meta then table.clone(item.Meta) else {}
	meta.Pers = PersonalizadorConfig.Codificar(pers)
	if not DataManager.SetMetaEquipo(player, slot, meta) then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	avisar(player, "Listo. Deshacer el próximo cambio cuesta " .. CFG.TextoDeshacer(deshechos(player)) .. ".", "Exito")
	return NetworkBridge.Ok({ Estado = "Aplicado", Pers = meta.Pers })
end

-- Pestaña Visual: el transmog del slot (no toca el ítem ni sus estadísticas).
local function aplicarVisual(player: Player, slot: string, apariencia: string): Types.Respuesta
	recordarEstado(player, slot)
	local respuesta = EquipoVisible.ElegirTransmog(player, slot, apariencia)
	if not respuesta.Success then
		return respuesta
	end
	avisar(player, "Visual cambiada. Las estadísticas del objeto no se tocan.", "Exito")
	return respuesta
end

------------------------------------------------------------------------
-- Deshacer
------------------------------------------------------------------------

local function deshacer(player: Player, slot: string): Types.Respuesta
	local foto = anteriorDe(player, slot)
	if not foto then
		avisar(player, "No hay nada que deshacer en ese slot.", "Aviso")
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local costo = CFG.CostoDeshacer(deshechos(player))
	if costo > 0 and not DataManager.SpendGold(player, costo) then
		avisar(player, `Deshacer cuesta {costo} de oro.`)
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end

	-- Se restaura la foto completa del slot: personalización y transmog.
	local item = itemEquipado(player, slot)
	if item then
		local meta: Types.ItemMeta = if item.Meta then table.clone(item.Meta) else {}
		local anterior = foto.Pers
		if anterior ~= nil then
			meta.Pers = anterior
		else
			-- Volver a "sin personalizar": el campo se saca del Meta.
			(meta :: any).Pers = nil
		end
		DataManager.SetMetaEquipo(player, slot, meta)
	end
	local visualAntes: string = foto.Transmog or ""
	EquipoVisible.ElegirTransmog(player, slot, visualAntes)

	DataManager.Mutar(player, "Cosmeticos", function(d)
		local campos: { [string]: any } = d :: any
		campos.CosmeticosDeshechos = (
			if typeof(campos.CosmeticosDeshechos) == "number" then campos.CosmeticosDeshechos else 0
		) + 1
		local todos: { [string]: any } = campos.CosmeticosAnterior or {}
		todos[slot] = nil -- un solo paso atrás
		campos.CosmeticosAnterior = todos
	end)
	avisar(
		player,
		if costo > 0
			then `Deshecho por {costo} de oro. El próximo: {CFG.TextoDeshacer(deshechos(player))}.`
			else `Deshecho. El próximo cuesta {CFG.TextoDeshacer(deshechos(player))}.`,
		"Exito"
	)
	return NetworkBridge.Ok({ Estado = "Deshecho", Costo = costo })
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

local function abrir(player: Player, raiz: BasePart): boolean
	if not raizDe(player) or not DataManager.GetData(player) then
		return false
	end
	sesiones[player] = raiz
	NetworkBridge.Server.FireClient("CosmeticosAbrir", player, estado(player))
	return true
end

function CosmeticosManager.Init()
	if iniciado then
		return
	end
	iniciado = true

	NpcManager.RegistrarAccion("Cosmeticos", function(player: Player, npc: any): boolean
		local raiz = if typeof(npc) == "table" then npc.Raiz else nil
		if not raiz or not raiz:IsA("BasePart") then
			return false
		end
		return abrir(player, raiz)
	end)

	NetworkBridge.Server.OnInvoke("CosmeticosEstado", function(player: Player): Types.Respuesta
		if not enElNpc(player) then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		return NetworkBridge.Ok(estado(player))
	end)

	NetworkBridge.Server.OnInvoke(
		"CosmeticosAplicar",
		function(player: Player, pestana: unknown, slot: unknown, datos: unknown): Types.Respuesta
			if not CFG.PestanaValida(pestana) then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			local nombreSlot = NetworkBridge.Guard.String(slot, 24)
			if not nombreSlot or not table.find(AparienciaEquipoConfig.SlotsVisibles, nombreSlot :: any) then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if not enElNpc(player) then
				avisar(player, "Acercate al NPC de cosméticos.")
				return NetworkBridge.Fail("NOT_ALLOWED")
			end
			if enCurso[player] then
				return NetworkBridge.Fail("RATE_LIMITED")
			end
			enCurso[player] = true
			local ok, respuesta = pcall(function(): Types.Respuesta
				if pestana == "Visual" then
					local id = if datos == "" then "" else NetworkBridge.Guard.String(datos, 40)
					if not id then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					return aplicarVisual(player, nombreSlot, id)
				end
				return aplicarPersonalizacion(player, nombreSlot, pestana :: string, datos)
			end)
			enCurso[player] = nil
			if not ok then
				warn(`[Cosmeticos] aplicar falló: {respuesta}`)
				return NetworkBridge.Fail("INTERNAL_ERROR")
			end
			return respuesta
		end
	)

	NetworkBridge.Server.OnInvoke("CosmeticosDeshacer", function(player: Player, slot: unknown): Types.Respuesta
		local nombreSlot = NetworkBridge.Guard.String(slot, 24)
		if not nombreSlot or not table.find(AparienciaEquipoConfig.SlotsVisibles, nombreSlot :: any) then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not enElNpc(player) then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		if enCurso[player] then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		enCurso[player] = true
		local ok, respuesta = pcall(deshacer, player, nombreSlot)
		enCurso[player] = nil
		if not ok then
			warn(`[Cosmeticos] deshacer falló: {respuesta}`)
			return NetworkBridge.Fail("INTERNAL_ERROR")
		end
		return respuesta
	end)

	NetworkBridge.Server.OnEvent("CosmeticosCerrar", function(player: Player)
		sesiones[player] = nil
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		sesiones[player] = nil
		enCurso[player] = nil
	end)

	local _ = StencilsConfig -- el cliente arma la lista; acá valida Normalizar
end

return CosmeticosManager
