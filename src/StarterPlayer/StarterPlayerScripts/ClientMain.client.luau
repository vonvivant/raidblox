--!strict
-- ClientMain: arranque del cliente. En la Fase 1 solo mantiene un espejo local
-- de los datos para comprobar que el guardado funciona. La UI real (HUD,
-- inventario) llega en las fases 4 y 7 y va a leer de este espejo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)

-- Espejo local con la misma forma que el snapshot del servidor
-- (Nivel, Experiencia, Oro, Inventario, MisionesActivas...).
-- El cliente solo lo muestra, nunca decide nada con él.
local datosLocales: { [string]: any } = {}
local cargado = false

local function aplicarSnapshot(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	for clave, valor in snapshot do
		datosLocales[clave] = valor
	end
	if not cargado then
		cargado = true
		print(`[RaidBlox] Datos cargados: nivel {datosLocales.Nivel}, oro {datosLocales.Oro}`)
	end
end

-- Traduce una sección de DataSync a los campos del espejo.
local function aplicarSeccion(seccion: string, valor: any)
	if seccion == "Nivel" and typeof(valor) == "table" then
		datosLocales.Nivel = valor.Nivel
		datosLocales.Experiencia = valor.Experiencia
	elseif seccion == "Misiones" and typeof(valor) == "table" then
		datosLocales.MisionesActivas = valor.Activas
		datosLocales.MisionesCompletadas = valor.Completadas
	elseif seccion == "Honor" then
		datosLocales.PuntosHonor = valor
	elseif seccion == "Cosmeticos" and typeof(valor) == "table" then
		for clave, v in valor do
			datosLocales[clave] = v
		end
	else
		datosLocales[seccion] = valor
	end
	print(`[RaidBlox] Cambió {seccion}:`, valor)
end

-- El servidor manda el snapshot completo apenas carga el perfil. Si eso pasó
-- antes de que este script conectara, el evento queda en cola hasta acá.
NetworkBridge.Client.OnEvent("DatosIniciales", aplicarSnapshot)

NetworkBridge.Client.OnEvent("DataSync", function(seccion: any, valor: any)
	if typeof(seccion) == "string" then
		aplicarSeccion(seccion, valor)
	end
end)

NetworkBridge.Client.OnEvent("Notificacion", function(texto: any, _tipo: any)
	if typeof(texto) == "string" then
		print(`[RaidBlox] {texto}`)
	end
end)

-- Respaldo: pedir los datos por si el snapshot inicial se perdió. La carga
-- puede tardar bastante si el jugador viene de otro servidor (session lock),
-- así que se reintenta sin límite mientras el servidor diga DATA_NOT_LOADED.
task.spawn(function()
	while not cargado do
		local respuesta = NetworkBridge.Client.Invoke("SolicitarDatos")
		if respuesta.Success then
			aplicarSnapshot(respuesta.Data)
		elseif respuesta.ErrorCode ~= "DATA_NOT_LOADED" and respuesta.ErrorCode ~= "RATE_LIMITED" then
			warn(`[RaidBlox] Error pidiendo datos: {respuesta.ErrorCode}`)
		end
		task.wait(2)
	end
end)
