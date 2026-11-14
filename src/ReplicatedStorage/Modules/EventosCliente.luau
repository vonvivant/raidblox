--!strict
-- EventosCliente: señales entre scripts del cliente (todos los LocalScripts
-- comparten este módulo). Ej.: el panel Personaje abre el selector de clase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Modules.Signal)

local EventosCliente = {
	AbrirSelectorClase = Signal.new() :: Signal.Signal<>,
	-- El botón "M" del minimapa (y la tecla M) abren o cierran el mapa del mundo.
	AlternarMapa = Signal.new() :: Signal.Signal<>,
}

return EventosCliente
