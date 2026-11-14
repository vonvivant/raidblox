--!strict
-- ConfigServidor: configuración que NO llega a los clientes (vive en
-- ServerScriptService). Acá van listas de permisos y secretos.

local ConfigServidor = {
	-- UserIds que pueden usar los NPCs de prueba (Banquero y Mercader) en un
	-- servidor publicado con GameConfig.ModoPruebas. El creador del juego
	-- siempre puede, y en Studio pueden todos. Ejemplo: { 12345678, 87654321 }
	Probadores = {} :: { number },

	-- Fase 7.4: administradores (panel 🛡 Admin). El creador del juego siempre
	-- es admin. En Studio también lo es quien prueba. Ejemplo: { 12345678 }
	Admins = {} :: { number },

	-- Webhook PRIVADO de Discord para el registro de comandos de admin. Discord
	-- rechaza los pedidos que salen de los servidores de Roblox: poné la URL
	-- de un proxy de webhooks (por ejemplo un reemplazo de
	-- "discord.com/api/webhooks/..." por el dominio de tu proxy). Vacío = no
	-- se envía nada (solo se escribe en la consola del servidor).
	-- Requiere activar "Permitir solicitudes HTTP" en la configuración del juego.
	WebhookAdmin = "",
}

return ConfigServidor
