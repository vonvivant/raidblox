--!strict
-- ConstruccionManager: lo que se construye adentro de una parcela.
--
-- Muebles, paredes, canteros de huerta y patio de mascotas. Lo construido se
-- guarda en el mismo registro de la parcela (DataStore global), con las
-- posiciones **relativas al centro**, así vale igual en todos los servidores.
--
-- Qué valida el servidor en cada pieza que se pone:
--   1. Que la parcela exista, esté al día y que el jugador sea dueño o socio.
--   2. Que la pieza exista y que no se haya pasado del tope (40 por parcela,
--      más los límites propios: un patio de mascotas, seis canteros).
--   3. Que entre adentro del terreno, con su margen, y que no se pase de alto.
--   4. Que no se pise con otra ya puesta.
--   5. Que tenga el oro. Se cobra y después se escribe; si la escritura no
--      entra, se devuelve (mismo criterio que la compra de la parcela).
--
-- La huerta: un cantero se planta con una semilla del inventario, tarda sus
-- horas y después se cosecha. El tiempo se mide con `os.time()` guardado en la
-- pieza, así que sigue corriendo con el servidor apagado y no se puede acelerar
-- desde el cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CFG = require(ReplicatedStorage.Configs.ConstruccionConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local ParcelasConfig = require(ReplicatedStorage.Configs.ParcelasConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local DataManager = require(script.Parent.Parent.DataManager)
local NpcManager = require(script.Parent.Parent.NpcManager)
local ParcelaManager = require(script.Parent.ParcelaManager)

type Puesta = ParcelaManager.Puesta
type Pieza = CFG.Pieza

local ConstruccionManager = {}

local iniciado = false
local azar = Random.new()
local enCurso: { [Player]: boolean } = {}
local dibujadas: { [string]: Folder } = {}

local function avisar(player: Player, texto: string, tipo: string?)
	if player.Parent == Players then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Error")
	end
end

local function piezasDe(registro: ParcelaManager.Registro?): { Puesta }
	if not registro then
		return {}
	end
	return registro.Piezas or {}
end

------------------------------------------------------------------------
-- Dibujar
------------------------------------------------------------------------

local function carpetaDe(parcelaId: string): Folder?
	local padre = Workspace:FindFirstChild("Parcelas")
	if not padre then
		return nil
	end
	local parcela = padre:FindFirstChild(parcelaId)
	if not parcela or not parcela:IsA("Folder") then
		return nil
	end
	local construido = parcela:FindFirstChild("Construido")
	if construido and construido:IsA("Folder") then
		return construido
	end
	local nueva = Instance.new("Folder")
	nueva.Name = "Construido"
	nueva.Parent = parcela
	return nueva
end

-- Un cantero muestra en qué anda: vacío, creciendo o listo.
local function textoCantero(puesta: Puesta): (string, Color3)
	if not puesta.Cultivo then
		return "Cantero vacío", Color3.fromRGB(180, 170, 150)
	end
	local cultivo = CFG.Cultivo(puesta.Cultivo)
	if not cultivo then
		return "Cantero vacío", Color3.fromRGB(180, 170, 150)
	end
	local falta = CFG.Falta(cultivo, puesta.Desde or 0, os.time())
	if falta <= 0 then
		return `{cultivo.Nombre}: listo`, Color3.fromRGB(150, 230, 140)
	end
	local horas = math.floor(falta / 3600)
	local minutos = math.ceil((falta % 3600) / 60)
	local cuanto = if horas > 0 then `{horas} h {minutos} min` else `{minutos} min`
	return `{cultivo.Nombre}: {cuanto}`, Color3.fromRGB(230, 215, 150)
end

local function dibujarPieza(parcelaId: string, indice: number, puesta: Puesta, centro: Vector3, padre: Folder)
	local pieza = CFG.Pieza(puesta.Pieza)
	if not pieza then
		return
	end
	local parte = Instance.new("Part")
	parte.Name = `{indice}_{pieza.Id}`
	parte.Anchored = true
	parte.Size = CFG.TamanoGirado(pieza, puesta.Giro)
	parte.CFrame = CFrame.new(centro + Vector3.new(puesta.X, puesta.Y, puesta.Z))
	parte.Color = pieza.Color
	parte.Material = pieza.Material
	parte:SetAttribute("Parcela", parcelaId)
	parte:SetAttribute("Indice", indice)
	parte:SetAttribute("Pieza", pieza.Id)
	parte.Parent = padre

	if pieza.Id == "Fogata" then
		local luz = Instance.new("PointLight")
		luz.Range = 22
		luz.Brightness = 2
		luz.Color = Color3.fromRGB(255, 170, 90)
		luz.Parent = parte
	end

	if pieza.Categoria == "Huerta" then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(170, 40)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.MaxDistance = 90
		billboard.Parent = parte
		local etiqueta = Instance.new("TextLabel")
		etiqueta.Size = UDim2.fromScale(1, 1)
		etiqueta.BackgroundTransparency = 0.4
		etiqueta.BackgroundColor3 = Color3.fromRGB(22, 20, 16)
		etiqueta.TextScaled = true
		etiqueta.Font = Enum.Font.GothamMedium
		local texto, color = textoCantero(puesta)
		etiqueta.Text = texto
		etiqueta.TextColor3 = color
		etiqueta.Parent = billboard

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = if puesta.Cultivo then "Cosechar" else "Plantar"
		prompt.ObjectText = "Cantero"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 12
		prompt.Parent = parte
	end
end

function ConstruccionManager.Dibujar(parcelaId: string)
	local padre = carpetaDe(parcelaId)
	if not padre then
		return
	end
	padre:ClearAllChildren()
	dibujadas[parcelaId] = padre
	local barrio, numero = ParcelasConfig.Partir(parcelaId)
	if not barrio or not numero then
		return
	end
	local registro = ParcelaManager.Leer(parcelaId)
	local centro = ParcelasConfig.Centro(barrio, numero) + Vector3.new(0, 0.5, 0)
	for indice, puesta in piezasDe(registro) do
		dibujarPieza(parcelaId, indice, puesta, centro, padre)
	end
end

local function dibujarTodo()
	local padre = Workspace:FindFirstChild("Parcelas")
	if not padre then
		return
	end
	for _, hijo in padre:GetChildren() do
		if hijo:IsA("Folder") then
			ConstruccionManager.Dibujar(hijo.Name)
		end
	end
end

------------------------------------------------------------------------
-- Construir
------------------------------------------------------------------------

-- Lado útil de la parcela (si está fusionada, igual se construye dentro de
-- cada una: la fusión comparte cofre y nombre, no el espacio aéreo).
local function ladoDe(parcelaId: string): number?
	local barrio = ParcelasConfig.Partir(parcelaId)
	return if barrio then barrio.Lado else nil
end

local function puedeTocar(player: Player, parcelaId: string): boolean
	if not ParcelaManager.PuedeConstruir(player, parcelaId) then
		avisar(player, "No tenés permiso para construir acá.")
		return false
	end
	local barrio, numero = ParcelasConfig.Partir(parcelaId)
	local personaje = player.Character
	local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
	if not barrio or not numero or not raiz or not raiz:IsA("BasePart") then
		return false
	end
	local centro = ParcelasConfig.Centro(barrio, numero)
	if (raiz.Position - centro).Magnitude > CFG.DistanciaConstruir then
		avisar(player, "Acercate a la parcela para construir.")
		return false
	end
	return true
end

local function construir(
	player: Player,
	parcelaId: string,
	piezaId: string,
	x: number,
	y: number,
	z: number,
	giro: number
): Types.Respuesta
	local pieza = CFG.Pieza(piezaId)
	local lado = ladoDe(parcelaId)
	if not pieza or not lado or not CFG.GiroValido(giro) then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if not puedeTocar(player, parcelaId) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end

	-- Acomodar a la grilla antes de validar: lo que se valida es lo que se guarda.
	local px, py, pz = CFG.Acomodar(x), CFG.Acomodar(y), CFG.Acomodar(z)
	if not CFG.Entra(lado, pieza, giro, px, py, pz) then
		avisar(player, "Ahí no entra: se sale del terreno o es demasiado alto.")
		return NetworkBridge.Fail("INVALID_ARGS")
	end

	local registro = ParcelaManager.Leer(parcelaId, 0)
	local puestas = piezasDe(registro)
	if not CFG.PuedeAgregar(puestas, pieza) then
		avisar(player, `No entran más: tope de {CFG.MaxPiezas} por parcela y {pieza.Limite or CFG.MaxPiezas} de esta.`)
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local nueva: Puesta = { Pieza = pieza.Id, X = px, Y = py, Z = pz, Giro = giro }
	for _, otra in puestas do
		local piezaOtra = CFG.Pieza(otra.Pieza)
		if
			piezaOtra
			and CFG.SePisan(
				pieza,
				giro,
				Vector3.new(px, py, pz),
				piezaOtra,
				otra.Giro,
				Vector3.new(otra.X, otra.Y, otra.Z)
			)
		then
			avisar(player, "Ahí ya hay algo puesto.")
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
	end

	if not DataManager.SpendGold(player, pieza.Precio) then
		return NetworkBridge.Fail("INSUFFICIENT_FUNDS")
	end
	local gano = ParcelaManager.Editar(parcelaId, function(actual)
		if not actual then
			return nil
		end
		local lista: { Puesta } = actual.Piezas or {}
		if #lista >= CFG.MaxPiezas then
			return nil
		end
		table.insert(lista, nueva)
		actual.Piezas = lista
		return actual
	end)
	if not gano then
		DataManager.AddGold(player, pieza.Precio)
		avisar(player, "No se pudo guardar la construcción. No se te cobró nada.")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	ConstruccionManager.Dibujar(parcelaId)
	avisar(player, `{pieza.Nombre} puesta por {pieza.Precio} de oro.`, "Exito")
	return NetworkBridge.Ok({ Piezas = #piezasDe(ParcelaManager.Leer(parcelaId, 0)) })
end

-- Sacar devuelve la mitad de lo que costó: así se puede rehacer sin perder todo.
local function quitar(player: Player, parcelaId: string, indice: number): Types.Respuesta
	if not puedeTocar(player, parcelaId) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local devolver = 0
	local gano = ParcelaManager.Editar(parcelaId, function(actual)
		if not actual then
			return nil
		end
		local lista: { Puesta } = actual.Piezas or {}
		local puesta = lista[indice]
		if not puesta then
			return nil
		end
		local pieza = CFG.Pieza(puesta.Pieza)
		devolver = if pieza then math.floor(pieza.Precio / 2) else 0
		table.remove(lista, indice)
		actual.Piezas = lista
		return actual
	end)
	if not gano then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if devolver > 0 then
		DataManager.AddGold(player, devolver)
	end
	ConstruccionManager.Dibujar(parcelaId)
	avisar(player, `Sacaste la pieza. Te devolvieron {devolver} de oro.`, "Info")
	return NetworkBridge.Ok({})
end

------------------------------------------------------------------------
-- Huerta
------------------------------------------------------------------------

local function plantar(player: Player, parcelaId: string, indice: number, semilla: string): Types.Respuesta
	local cultivo = CFG.Cultivo(semilla)
	if not cultivo then
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if not puedeTocar(player, parcelaId) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local registro = ParcelaManager.Leer(parcelaId, 0)
	local puesta = piezasDe(registro)[indice]
	local pieza = if puesta then CFG.Pieza(puesta.Pieza) else nil
	if not puesta or not pieza or pieza.Categoria ~= "Huerta" then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if puesta.Cultivo then
		avisar(player, "Ese cantero ya tiene algo plantado.")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	-- Primero la semilla: si no la tiene, no se toca nada.
	if not DataManager.RemoveItem(player, semilla, 1) then
		avisar(player, `Te falta {ItemCatalog[semilla].Nombre}.`)
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local gano = ParcelaManager.Editar(parcelaId, function(actual)
		if not actual then
			return nil
		end
		local lista: { Puesta } = actual.Piezas or {}
		local mia = lista[indice]
		if not mia or mia.Cultivo then
			return nil
		end
		mia.Cultivo = semilla
		mia.Desde = os.time()
		actual.Piezas = lista
		return actual
	end)
	if not gano then
		DataManager.AddItem(player, semilla, 1, "Comun", nil)
		avisar(player, "No se pudo plantar. La semilla sigue siendo tuya.")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	ConstruccionManager.Dibujar(parcelaId)
	avisar(player, `Plantaste {cultivo.Nombre}. Vuelve en {cultivo.Horas} h.`, "Exito")
	return NetworkBridge.Ok({})
end

local function cosechar(player: Player, parcelaId: string, indice: number): Types.Respuesta
	if not puedeTocar(player, parcelaId) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local registro = ParcelaManager.Leer(parcelaId, 0)
	local puesta = piezasDe(registro)[indice]
	if not puesta or not puesta.Cultivo then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	local cultivo = CFG.Cultivo(puesta.Cultivo)
	if not cultivo then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if not CFG.Lista(cultivo, puesta.Desde or 0, os.time()) then
		local falta = CFG.Falta(cultivo, puesta.Desde or 0, os.time())
		avisar(player, `Todavía no está: faltan {math.ceil(falta / 60)} min.`, "Aviso")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local cantidad = azar:NextInteger(cultivo.Min, cultivo.Max)
	-- Se vacía el cantero primero: si el inventario está lleno, no se pierde
	-- la cosecha (el cantero queda plantado y se puede volver).
	if not DataManager.AddItem(player, cultivo.Cosecha, cantidad, "Comun", nil) then
		avisar(player, "No te entra la cosecha: hacé lugar en la mochila.")
		return NetworkBridge.Fail("INVENTORY_FULL")
	end
	local gano = ParcelaManager.Editar(parcelaId, function(actual)
		if not actual then
			return nil
		end
		local lista: { Puesta } = actual.Piezas or {}
		local mia = lista[indice]
		if not mia then
			return nil
		end
		mia.Cultivo = nil
		mia.Desde = nil
		actual.Piezas = lista
		return actual
	end)
	if not gano then
		-- Ya se entregó la cosecha: si el registro no se pudo limpiar, se saca
		-- lo entregado para no dejar un cantero que coseche dos veces.
		DataManager.RemoveItem(player, cultivo.Cosecha, cantidad)
		avisar(player, "No se pudo cosechar. Probá de nuevo en un momento.")
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	ConstruccionManager.Dibujar(parcelaId)
	avisar(player, `+{ItemCatalog[cultivo.Cosecha].Nombre} x{cantidad}`, "Exito")
	return NetworkBridge.Ok({ Cantidad = cantidad })
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function ConstruccionManager.Init()
	if iniciado then
		return
	end
	iniciado = true
	task.defer(dibujarTodo)

	NpcManager.RegistrarAccion("ParcelasConstruir", function(player: Player): boolean
		NetworkBridge.Server.FireClient("ConstruirPanel", player, true)
		return true
	end)

	NetworkBridge.Server.OnInvoke(
		"ParcelaConstruir",
		function(player: Player, parcelaId: unknown, accion: unknown, datos: unknown): Types.Respuesta
			local id = NetworkBridge.Guard.String(parcelaId, 48)
			local que = NetworkBridge.Guard.OneOf(accion, {
				Poner = true,
				Quitar = true,
				Plantar = true,
				Cosechar = true,
				Listar = true,
			})
			if not id or not que or not ParcelasConfig.Valido(id) then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if not DataManager.GetData(player) then
				return NetworkBridge.Fail("DATA_NOT_LOADED")
			end
			if typeof(datos) ~= "table" and que ~= "Listar" then
				return NetworkBridge.Fail("INVALID_ARGS")
			end
			if enCurso[player] then
				return NetworkBridge.Fail("RATE_LIMITED")
			end
			enCurso[player] = true

			local tabla: { [string]: unknown } = if typeof(datos) == "table" then datos :: any else {}
			local ok, resultado = pcall(function(): Types.Respuesta
				if que == "Listar" then
					return NetworkBridge.Ok({
						Piezas = piezasDe(ParcelaManager.Leer(id)),
						Puedo = ParcelaManager.PuedeConstruir(player, id),
					})
				elseif que == "Poner" then
					local piezaId = NetworkBridge.Guard.String(tabla.Pieza, 32)
					local x = NetworkBridge.Guard.Number(tabla.X, -500, 500)
					local y = NetworkBridge.Guard.Number(tabla.Y, -10, CFG.AlturaMaxima)
					local z = NetworkBridge.Guard.Number(tabla.Z, -500, 500)
					local giro = NetworkBridge.Guard.Integer(tabla.Giro, 0, 3)
					if not piezaId or not x or not y or not z or giro == nil then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					return construir(player, id, piezaId, x, y, z, giro)
				end
				local indice = NetworkBridge.Guard.Integer(tabla.Indice, 1, CFG.MaxPiezas)
				if not indice then
					return NetworkBridge.Fail("INVALID_ARGS")
				end
				if que == "Quitar" then
					return quitar(player, id, indice)
				elseif que == "Plantar" then
					local semilla = NetworkBridge.Guard.String(tabla.Semilla, 32)
					if not semilla then
						return NetworkBridge.Fail("INVALID_ARGS")
					end
					return plantar(player, id, indice, semilla)
				end
				return cosechar(player, id, indice)
			end)
			enCurso[player] = nil
			if not ok then
				warn(`[Construccion] {que} falló: {resultado}`)
				return NetworkBridge.Fail("INTERNAL_ERROR")
			end
			return resultado
		end
	)

	Players.PlayerRemoving:Connect(function(player: Player)
		enCurso[player] = nil
	end)

	-- Los canteros avisan solos cuando la cosecha está lista.
	task.spawn(function()
		while true do
			task.wait(60)
			for parcelaId in dibujadas do
				pcall(ConstruccionManager.Dibujar, parcelaId)
			end
		end
	end)
end

return ConstruccionManager
