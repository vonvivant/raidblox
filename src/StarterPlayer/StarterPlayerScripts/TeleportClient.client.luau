--!strict
-- TeleportClient: muestra la pantalla de carga temática cuando el servidor
-- inicia un teleport y avisa en pantalla si algo falla.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local PantallaCarga = require(ReplicatedStorage.Modules.PantallaCarga)
local Avisos = require(ReplicatedStorage.Modules.Avisos)

local jugador = Players.LocalPlayer
local playerGui = jugador:WaitForChild("PlayerGui")

local actual: PantallaCarga.Pantalla? = nil

local function cerrar()
	if actual then
		actual.Ocultar()
		actual = nil
	end
end

NetworkBridge.Client.OnEvent("TeleportEstado", function(estado: any, zonaId: any, mensaje: any)
	if typeof(estado) ~= "string" or typeof(zonaId) ~= "string" then
		return
	end
	if estado == "Iniciando" then
		cerrar()
		local pantalla = PantallaCarga.Crear(zonaId)
		pantalla.Gui.Parent = playerGui
		-- Esta GUI se mantiene visible durante el viaje y al llegar al otro place.
		pcall(function()
			TeleportService:SetTeleportGui(pantalla.Gui)
		end)
		actual = pantalla
	elseif estado == "Reintentando" then
		if actual and typeof(mensaje) == "string" then
			actual.SetEstado(mensaje)
		end
	elseif estado == "Simulado" then
		task.wait(1)
		cerrar()
	elseif estado == "Fallo" then
		cerrar()
		Avisos.Mostrar(if typeof(mensaje) == "string" then mensaje else "No se pudo viajar.", "Error")
	end
end)

-- Avisos generales del servidor (nivel insuficiente, zona no disponible...).
NetworkBridge.Client.OnEvent("Notificacion", function(texto: any, tipo: any)
	if typeof(texto) == "string" then
		Avisos.Mostrar(texto, if typeof(tipo) == "string" then tipo else "Info")
	end
end)
