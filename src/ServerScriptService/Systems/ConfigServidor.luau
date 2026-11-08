--!strict
-- ConfigServidor: configuración que NO llega a los clientes (vive en
-- ServerScriptService). Acá van listas de permisos.

local ConfigServidor = {
	-- UserIds que pueden usar los NPCs de prueba (Banquero y Mercader) en un
	-- servidor publicado con GameConfig.ModoPruebas. El creador del juego
	-- siempre puede, y en Studio pueden todos. Ejemplo: { 12345678, 87654321 }
	Probadores = {} :: { number },
}

return ConfigServidor
