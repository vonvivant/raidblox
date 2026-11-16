--!strict
-- Pruebas: ¿hay que crear el contenido de prueba (zona de práctica, estaciones,
-- nodos, Casa de Subastas, arena de la Guerra)?
--
-- Siempre en Studio. En un servidor publicado, solo si GameConfig.ModoPruebas
-- está activado: sirve para probar con amigos antes de tener los mapas reales.
-- Apagalo cuando armes los mapas definitivos.
--
-- Ojo: los comandos de prueba (ServerStorage.RaidBloxDebug) siguen siendo SOLO
-- de Studio; ModoPruebas no los habilita.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Configs.GameConfig)

local Pruebas = {}

function Pruebas.Activas(): boolean
	return RunService:IsStudio() or GameConfig.ModoPruebas
end

return Pruebas
