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
--   game.ServerStorage.RaidBloxDebug:Invoke("Npcs")             -- lista los NPC y dónde están
--   game.ServerStorage.RaidBloxDebug:Invoke("Ir", "Banquero")   -- te lleva a ese NPC
--   game.ServerStorage.RaidBloxDebug:Invoke("Ir", -30, 0, 32)   -- te lleva a esa posición
-- Cualquier función de DataManager que reciba (player, ...) sirve. Se aplica al
-- primer jugador; para otro: Invoke("@NombreDeUsuario", "AddGold", 500).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DataManager = require(script.Parent.DataManager)

local DebugStudio = {}

-- NPC de servicio que hay en el mundo (los que dibuja el minimapa).
local function npcs(): { { Nombre: string, Posicion: Vector3 } }
	local lista: { { Nombre: string, Posicion: Vector3 } } = {}
	for _, parte in CollectionService:GetTagged("NpcServicio") do
		local modelo = parte:FindFirstAncestorOfClass("Model")
		if parte:IsA("BasePart") then
			local numero = parte:GetAttribute("Numero")
			local nombre = if modelo then modelo.Name else parte.Name
			table.insert(lista, {
				Nombre = if typeof(numero) == "number" then `#{numero} {nombre}` else nombre,
				Posicion = parte.Position,
			})
		end
	end
	table.sort(lista, function(a, b): boolean
		return a.Nombre < b.Nombre
	end)
	return lista
end

local function listarNpcs()
	local lista = npcs()
	print(`[Debug] {#lista} NPC de servicio:`)
	for _, npc in lista do
		print(
			`  {npc.Nombre}  ->  Invoke("Ir", {math.round(npc.Posicion.X)}, {math.round(npc.Posicion.Y)}, {math.round(
				npc.Posicion.Z
			)})`
		)
	end
end

-- Te lleva a una posición o al NPC cuyo nombre contenga ese texto.
local function ir(player: Player, a: unknown, b: unknown, c: unknown): boolean
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not raiz or not raiz:IsA("BasePart") then
		warn("[Debug] No tenés personaje")
		return false
	end
	local destino: Vector3? = nil
	if typeof(a) == "number" and typeof(b) == "number" and typeof(c) == "number" then
		destino = Vector3.new(a, b, c)
	elseif typeof(a) == "string" then
		local buscado = string.lower(a)
		for _, npc in npcs() do
			if string.find(string.lower(npc.Nombre), buscado, 1, true) then
				-- Un paso adelante del NPC, no encima.
				destino = npc.Posicion + Vector3.new(0, 0, 4)
				print(`[Debug] Vas a {npc.Nombre}`)
				break
			end
		end
		if not destino then
			warn(`[Debug] No encontré un NPC que diga "{a}". Probá Invoke("Npcs")`)
			return false
		end
	else
		warn('[Debug] Usá Invoke("Ir", "nombre") o Invoke("Ir", x, y, z)')
		return false
	end
	raiz.CFrame = CFrame.new((destino :: Vector3) + Vector3.new(0, 3, 0))
	return true
end

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
	if metodo == "Npcs" then
		listarNpcs()
		return nil
	end
	if metodo == "Ir" then
		return ir(player, args[1], args[2], args[3])
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
