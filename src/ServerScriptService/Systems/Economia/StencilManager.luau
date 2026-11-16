--!strict
-- StencilManager: los libros de stencils.
--
-- Un libro es un ítem consumible. Al leerlo se desbloquean para siempre los
-- stencils de ese libro y el libro se gasta. Leer uno que ya tenías no hace
-- nada y **no lo consume**: avisa y queda en la mochila (así no se pierde por
-- un clic de más; se puede vender o regalar).
--
-- Lo desbloqueado vive en el perfil (`DatosJugador.Stencils`), así que vale
-- para todos los ítems y para siempre. Quién puede usar cada stencil lo
-- revalida el servidor en cada personalización (ver Personalizador.Normalizar).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage.Configs.StencilsConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local InventarioManager = require(script.Parent.InventarioManager)

local StencilManager = {}

local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
	end
end

function StencilManager.Librosde(player: Player): { string }
	local datos = DataManager.GetData(player)
	if not datos then
		return {}
	end
	local lista: { string } = (datos :: any).Stencils or {}
	return lista
end

function StencilManager.Tiene(player: Player, libroId: string): boolean
	return table.find(StencilManager.Librosde(player), libroId) ~= nil
end

local function leer(player: Player, libroId: string): (boolean, string?)
	local libro = CFG.Libro(libroId)
	if not libro then
		return false, "Ese libro no existe."
	end
	if StencilManager.Tiene(player, libroId) then
		-- Ya lo sabe: no se gasta el libro.
		return false, `Ya conocés el {libro.Nombre}.`
	end
	DataManager.Mutar(player, "Stencils", function(d)
		local campos: { [string]: any } = d :: any
		local lista: { string } = campos.Stencils or {}
		if not table.find(lista, libroId) then
			table.insert(lista, libroId)
		end
		campos.Stencils = lista
	end)
	local cuantos = #CFG.DelLibro(libroId)
	avisar(player, `Aprendiste el {libro.Nombre}: {cuantos} stencils nuevos en el personalizador.`, "Oro")
	return true, nil
end

function StencilManager.Init()
	if iniciado then
		return
	end
	iniciado = true

	for _, libro in CFG.Libros do
		InventarioManager.RegistrarUso(libro.Item, function(player: Player): (boolean, string?)
			return leer(player, libro.Id)
		end)
	end

	-- El cliente pregunta qué libros tiene para armar la lista del probador.
	NetworkBridge.Server.OnInvoke("StencilsMios", function(player: Player): Types.Respuesta
		return NetworkBridge.Ok({ Libros = StencilManager.Librosde(player) })
	end)
end

return StencilManager
