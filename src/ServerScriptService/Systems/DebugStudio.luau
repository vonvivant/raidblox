--!strict
-- DebugStudio: comandos de prueba para la barra de comandos de Studio.
--
-- La barra de comandos tiene su propia copia de los módulos (un require desde
-- ahí crea OTRO DataManager, sin tu perfil). Por eso el juego expone un
-- BindableFunction en ServerStorage que ejecuta los comandos con los módulos
-- reales. Solo existe en Studio: en un servidor público no se crea.
--
-- Uso (barra de comandos, vista de Servidor):
--   game.ServerStorage.RaidBloxDebug:Invoke("AddGold", 500)
--   game.ServerStorage.RaidBloxDebug:Invoke("AddItem", "Madera", 150)
--   game.ServerStorage.RaidBloxDebug:Invoke("AddExperience", 1000)
--   game.ServerStorage.RaidBloxDebug:Invoke("Ver")              -- imprime tus datos
-- Cualquier función de DataManager que reciba (player, ...) sirve. Se aplica al
-- primer jugador; para otro: Invoke("@NombreDeUsuario", "AddGold", 500).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DataManager = require(script.Parent.DataManager)

local DebugStudio = {}

local function ejecutar(primero: unknown, ...: any): any
	local args = table.pack(...)
	local player = Players:GetPlayers()[1]
	local metodo = primero
	if typeof(primero) == "string" and string.sub(primero, 1, 1) == "@" then
		player = Players:FindFirstChild(string.sub(primero, 2)) :: Player?
		metodo = args[1]
		args = table.pack(select(2, ...))
	end
	if not player then
		warn("[Debug] No hay jugador")
		return nil
	end
	if metodo == "Ver" then
		local datos = DataManager.GetData(player)
		print(`[Debug] Datos de {player.Name}:`, HttpService:JSONEncode(datos))
		return nil
	end
	local fn = if typeof(metodo) == "string" then (DataManager :: any)[metodo] else nil
	if typeof(fn) ~= "function" then
		warn(`[Debug] DataManager no tiene la función {tostring(metodo)}`)
		return nil
	end
	local resultado = fn(player, table.unpack(args, 1, args.n))
	print(`[Debug] {metodo} ->`, resultado)
	return resultado
end

function DebugStudio.Init()
	if not RunService:IsStudio() then
		return
	end
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "RaidBloxDebug"
	bindable.OnInvoke = ejecutar
	bindable.Parent = ServerStorage
	print('[Debug] Comandos de Studio listos: game.ServerStorage.RaidBloxDebug:Invoke("AddGold", 500)')
end

return DebugStudio
