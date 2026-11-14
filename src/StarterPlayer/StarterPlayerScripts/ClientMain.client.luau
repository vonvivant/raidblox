--!strict
-- ClientMain: arranque del cliente. Inicia el espejo local de datos
-- (EstadoCliente) y deja un registro en la consola para depurar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)

EstadoCliente.Cambio:Connect(function(campo: string)
	if campo == "*" then
		print(`[RaidBlox] Datos cargados: nivel {EstadoCliente.Get("Nivel")}, oro {EstadoCliente.Get("Oro")}`)
	end
end)
