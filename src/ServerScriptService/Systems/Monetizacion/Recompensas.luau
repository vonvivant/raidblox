--!strict
-- Recompensas: entrega una recompensa del pase de batalla o de un código.
-- No pausa (sin yields): se puede usar en el mismo bloque que marca la
-- recompensa como reclamada. Lo que no entra en la mochila va por buzón con
-- el id fijo que se le pase (así nunca se entrega dos veces).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaseBatallaConfig = require(ReplicatedStorage.Configs.PaseBatallaConfig)
local DataManager = require(script.Parent.Parent.DataManager)
local Buzon = require(script.Parent.Parent.Buzon)
local LootManager = require(script.Parent.Parent.Combate.LootManager)
local Bonos = require(script.Parent.Bonos)

type Recompensa = PaseBatallaConfig.Recompensa

local Recompensas = {}

local function agregarUnico(lista: { string }?, valor: string): { string }
	local l = lista or {}
	if not table.find(l, valor) then
		table.insert(l, valor)
	end
	return l
end

function Recompensas.Dar(player: Player, r: Recompensa, id: string): boolean
	if not DataManager.PerfilActivo(player) then
		return false
	end
	if r.Tipo == "Oro" then
		local n = r.Cantidad or 0
		if not DataManager.AddGold(player, n) then
			Buzon.EnviarOro(player.UserId, n, "Recompensa", id)
		end
	elseif r.Tipo == "Item" and r.ItemId then
		local g = LootManager.GenerarItem(r.ItemId, r.Cantidad or 1, r.Rareza)
		if g then
			local item = {
				Uid = HttpService:GenerateGUID(false),
				ItemId = g.ItemId,
				Cantidad = g.Cantidad,
				Rareza = g.Rareza,
				Meta = g.Meta,
			}
			if not DataManager.AgregarInstancia(player, item) then
				Buzon.EnviarItem(player.UserId, item, "Recompensa", id)
			end
		end
	elseif r.Tipo == "Titulo" and r.Titulo then
		DataManager.AddTitulo(player, r.Titulo)
	elseif r.Tipo == "Skin" and r.Skin then
		DataManager.UnlockSkinEstructura(player, r.Skin)
	elseif r.Tipo == "Ficha" and r.Ficha then
		DataManager.AgregarFicha(player, r.Ficha, r.Cantidad or 1)
	elseif r.Tipo == "Booster" then
		local hasta = DataManager.ExtenderBoosterXp(player, r.Cantidad or 3600)
		if hasta then
			Bonos.SetBoosterXp(player, hasta, 2)
		end
	elseif r.Tipo == "Mascota" and r.Id then
		local mascota = r.Id
		DataManager.Mutar(player, "Cosmeticos", function(d)
			d.Mascotas = agregarUnico(d.Mascotas, mascota)
		end)
	elseif r.Tipo == "Apariencia" and r.Id then
		local apariencia = r.Id
		DataManager.Mutar(player, "Cosmeticos", function(d)
			d.Apariencias = agregarUnico(d.Apariencias, apariencia)
		end)
	else
		return false
	end
	return true
end

return Recompensas
