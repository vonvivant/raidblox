--!strict
-- EstadoCliente: espejo local (solo lectura) de los datos del jugador, para
-- todas las interfaces del cliente. Es el ÚNICO que escucha DatosIniciales y
-- DataSync: así ningún script se pierde eventos por haber cargado tarde.
--
-- Uso (solo en el cliente):
--   local EstadoCliente = require(ReplicatedStorage.Modules.EstadoCliente)
--   local inv = EstadoCliente.Get("Inventario")
--   EstadoCliente.Cambio:Connect(function(campo) ... end)

local RunService = game:GetService("RunService")

local NetworkBridge = require(script.Parent.NetworkBridge)
local Signal = require(script.Parent.Signal)

local EstadoCliente = {}

-- Se dispara con el nombre del campo que cambió (o "*" al cargar todo).
EstadoCliente.Cambio = Signal.new() :: Signal.Signal<string>

local datos: { [string]: any } = {}
local cargado = false
local iniciado = false

function EstadoCliente.Get(campo: string): any
	return datos[campo]
end

function EstadoCliente.Cargado(): boolean
	return cargado
end

local function aplicarSnapshot(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	for clave, valor in snapshot do
		datos[clave] = valor
	end
	cargado = true
	EstadoCliente.Cambio:Fire("*")
end

-- Traduce una sección de DataSync a los campos del espejo.
local function aplicarSeccion(seccion: string, valor: any)
	if seccion == "Nivel" and typeof(valor) == "table" then
		datos.Nivel = valor.Nivel
		datos.Experiencia = valor.Experiencia
		EstadoCliente.Cambio:Fire("Nivel")
	elseif seccion == "Misiones" and typeof(valor) == "table" then
		datos.MisionesActivas = valor.Activas
		datos.MisionesCompletadas = valor.Completadas
		EstadoCliente.Cambio:Fire("Misiones")
	elseif seccion == "Honor" then
		datos.PuntosHonor = valor
		EstadoCliente.Cambio:Fire("Honor")
	elseif seccion == "Cosmeticos" and typeof(valor) == "table" then
		for clave, v in valor do
			datos[clave] = v
		end
		EstadoCliente.Cambio:Fire("Cosmeticos")
	else
		datos[seccion] = valor
		EstadoCliente.Cambio:Fire(seccion)
	end
end

local function iniciar()
	if iniciado or not RunService:IsClient() then
		return
	end
	iniciado = true
	NetworkBridge.Client.OnEvent("DatosIniciales", aplicarSnapshot)
	NetworkBridge.Client.OnEvent("DataSync", function(seccion: any, valor: any)
		if typeof(seccion) == "string" then
			aplicarSeccion(seccion, valor)
		end
	end)
	-- Respaldo: pedir el snapshot por si el inicial llegó antes de conectar.
	task.spawn(function()
		while not cargado do
			local respuesta = NetworkBridge.Client.Invoke("SolicitarDatos")
			if respuesta.Success then
				aplicarSnapshot(respuesta.Data)
			end
			task.wait(2)
		end
	end)
end

iniciar()

return EstadoCliente
