--!strict
-- PasesManager: pases permanentes (Game Passes).
--
-- * Al entrar se consulta UserOwnsGamePassAsync por cada pase con Id; las
--   compras en vivo llegan por PromptGamePassPurchaseFinished. La compra la
--   abre el servidor (PromptGamePassPurchase) a pedido del cliente.
-- * Efectos: VIP (+15% XP y oro vía Bonos, etiqueta dorada), Mochila Extra
--   (50 lugares), Puesto en la Subasta (15 publicaciones), Dragón de Fuego
--   (montura) y Título Personalizado (texto filtrado sobre la cabeza).
-- * Modo pruebas: los pases con Id = 0 los puede "simular" el creador o un
--   probador (solo en memoria, se pierde al salir).
-- * Cartel sobre la cabeza: [VIP] y el título (personalizado o equipado).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Configs.GameConfig)
local MonetizacionConfig = require(ReplicatedStorage.Configs.MonetizacionConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local Pruebas = require(ReplicatedStorage.Modules.Pruebas)
local Signal = require(ReplicatedStorage.Modules.Signal)
local DataManager = require(script.Parent.Parent.DataManager)
local NpcsPrueba = require(script.Parent.Parent.Pruebas.NpcsPrueba)
local Bonos = require(script.Parent.Bonos)

type Respuesta = Types.Respuesta

local CFG = MonetizacionConfig

local PasesManager = {}

-- (jugador, clave del pase, lo tiene)
PasesManager.Cambio = Signal.new() :: Signal.Signal<Player, string, boolean>

local tiene: { [Player]: { [string]: boolean } } = {}
local precios: { [number]: number? } = {}
local reintentarPrecio: { [number]: number } = {}
local ultimoTitulo: { [Player]: number } = {}
local iniciado = false

local function avisar(player: Player, texto: string, tipo: string?)
	NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
end

local function claveDeId(id: number): string?
	for clave, pase in CFG.Pases do
		if pase.Id == id and id ~= 0 then
			return clave
		end
	end
	return nil
end

function PasesManager.Tiene(player: Player, clave: string): boolean
	local t = tiene[player]
	return t ~= nil and t[clave] == true
end

function PasesManager.LimitePublicaciones(player: Player): number
	return if PasesManager.Tiene(player, "SubastaExtra")
		then CFG.PublicacionesConPase
		else GameConfig.Subastas.MaxPublicaciones
end

------------------------------------------------------------------------
-- Cartel sobre la cabeza ([VIP] y título)
------------------------------------------------------------------------

local function actualizarCartel(player: Player)
	local personaje = player.Character
	local cabeza = personaje and personaje:FindFirstChild("Head")
	if not cabeza or not cabeza:IsA("BasePart") then
		return
	end
	local datos = DataManager.GetData(player)
	local titulo: string? = nil
	if datos then
		titulo = if PasesManager.Tiene(player, "TituloPersonal") and datos.TituloPersonalizado
			then datos.TituloPersonalizado
			else datos.TituloEquipado
	end
	local vip = PasesManager.Tiene(player, "VIP")
	local cartel = cabeza:FindFirstChild("CartelJugador")
	if not vip and (titulo == nil or titulo == "") then
		if cartel then
			cartel:Destroy()
		end
		return
	end
	local gui: BillboardGui
	local texto: TextLabel
	if cartel and cartel:IsA("BillboardGui") then
		gui = cartel
		texto = cartel:FindFirstChildOfClass("TextLabel") :: TextLabel
	else
		gui = Instance.new("BillboardGui")
		gui.Name = "CartelJugador"
		gui.Size = UDim2.fromOffset(220, 22)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		texto = Instance.new("TextLabel")
		texto.Size = UDim2.fromScale(1, 1)
		texto.BackgroundTransparency = 1
		texto.Font = Enum.Font.GothamBold
		texto.TextScaled = true
		texto.RichText = true
		texto.TextStrokeTransparency = 0.4
		texto.TextColor3 = Color3.fromRGB(230, 220, 255)
		texto.Parent = gui
		gui.Parent = cabeza
	end
	local partes: { string } = {}
	if vip then
		table.insert(partes, `<font color="#{CFG.Vip.Color:ToHex()}">[VIP]</font>`)
	end
	if titulo and titulo ~= "" then
		-- El título ya viene filtrado; se escapan los signos de RichText.
		local limpio = string.gsub(string.gsub(string.gsub(titulo, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
		table.insert(partes, `«{limpio}»`)
	end
	texto.Text = table.concat(partes, " ")
end

------------------------------------------------------------------------
-- Efectos
------------------------------------------------------------------------

local function aplicar(player: Player, clave: string, activo: boolean)
	if clave == "VIP" then
		player:SetAttribute("VIP", if activo then true else nil)
		Bonos.SetVip(player, if activo then CFG.Vip.MultXp else nil)
	elseif clave == "MochilaExtra" then
		local datos = DataManager.GetData(player)
		local objetivo = if activo then GameConfig.Inventario.SlotsConPase else GameConfig.Inventario.SlotsBase
		if datos and datos.Inventario.MaxSlots ~= objetivo then
			-- Al achicar falla si hay ítems en los lugares extra: no se pierde nada.
			DataManager.SetMaxSlots(player, objetivo)
		end
	end
	player:SetAttribute(`Pase_{clave}`, if activo then true else nil)
	actualizarCartel(player)
	PasesManager.Cambio:Fire(player, clave, activo)
end

local function marcar(player: Player, clave: string, activo: boolean)
	local t = tiene[player]
	if not t then
		t = {}
		tiene[player] = t
	end
	if (t[clave] == true) == activo then
		return
	end
	if activo then
		t[clave] = true
	else
		t[clave] = nil
	end
	aplicar(player, clave, activo)
end

local function consultar(player: Player)
	for clave, pase in CFG.Pases do
		if pase.Id == 0 then
			continue
		end
		task.spawn(function()
			for intento = 1, 3 do
				local ok, lo = pcall(function(): boolean
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pase.Id)
				end)
				if ok then
					if lo and player.Parent == Players then
						marcar(player, clave, true)
					end
					return
				end
				task.wait(2 * intento)
			end
			warn(`[Pases] No se pudo consultar el pase {clave} de {player.Name}`)
		end)
	end
end

------------------------------------------------------------------------
-- Tienda
------------------------------------------------------------------------

local function precio(id: number): number?
	if id == 0 then
		return nil
	end
	-- Si la consulta falla, no se reintenta hasta dentro de un minuto: así abrir
	-- la tienda no dispara un pedido por producto cada vez.
	if precios[id] == nil and os.clock() >= (reintentarPrecio[id] or 0) then
		local ok, info = pcall(function(): any
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.GamePass)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			precios[id] = info.PriceInRobux
		else
			reintentarPrecio[id] = os.clock() + 60
		end
	end
	return precios[id]
end

local function info(player: Player): Respuesta
	local lista = {}
	local simular = Pruebas.Activas() and NpcsPrueba.Permitido(player)
	for clave, pase in CFG.Pases do
		table.insert(lista, {
			Clave = clave,
			Nombre = pase.Nombre,
			Descripcion = pase.Descripcion,
			Orden = pase.Orden,
			ALaVenta = pase.Id ~= 0,
			Precio = precio(pase.Id),
			Tengo = PasesManager.Tiene(player, clave),
			Simulable = simular and pase.Id == 0,
		})
	end
	local datos = DataManager.GetData(player)
	return NetworkBridge.Ok({
		Pases = lista,
		Titulo = if datos then datos.TituloPersonalizado else nil,
	})
end

local function comprar(player: Player, clave: string): Respuesta
	local pase = CFG.Pases[clave]
	if not pase then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if pase.Id ~= 0 then
		if PasesManager.Tiene(player, clave) then
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		MarketplaceService:PromptGamePassPurchase(player, pase.Id)
		return NetworkBridge.Ok(nil)
	end
	if Pruebas.Activas() and NpcsPrueba.Permitido(player) then
		local nuevo = not PasesManager.Tiene(player, clave)
		marcar(player, clave, nuevo)
		avisar(player, `{pase.Nombre}: {if nuevo then "simulado (pruebas)" else "quitado"}.`, "Oro")
		return NetworkBridge.Ok(nil)
	end
	avisar(player, "Este pase todavía no está a la venta.", "Error")
	return NetworkBridge.Fail("NOT_ALLOWED")
end

local function guardarTitulo(player: Player, texto: string): Respuesta
	if not PasesManager.Tiene(player, "TituloPersonal") then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local ahora = os.clock()
	if ahora - (ultimoTitulo[player] or -math.huge) < 5 then
		return NetworkBridge.Fail("RATE_LIMITED")
	end
	ultimoTitulo[player] = ahora
	local limpio = string.gsub(string.gsub(texto, "%c", ""), "%s+", " ")
	limpio = string.match(limpio, "^%s*(.-)%s*$") or ""
	local largo = utf8.len(limpio)
	if not largo or largo > CFG.LargoTitulo then
		avisar(player, `El título puede tener hasta {CFG.LargoTitulo} letras.`, "Error")
		return NetworkBridge.Fail("INVALID_ARGS")
	end
	if limpio == "" then
		DataManager.SetTituloPersonalizado(player, nil)
		actualizarCartel(player)
		return NetworkBridge.Ok(nil)
	end
	local ok, filtrado = pcall(function(): string
		local r = TextService:FilterStringAsync(limpio, player.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	if filtrado ~= limpio then
		avisar(player, "Ese título no está permitido.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	DataManager.SetTituloPersonalizado(player, limpio)
	actualizarCartel(player)
	avisar(player, "Título guardado.", "Oro")
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function PasesManager.Init()
	assert(not iniciado, "PasesManager.Init() se llamó dos veces")
	iniciado = true

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, comprado: boolean)
		local clave = claveDeId(id)
		if comprado and clave then
			marcar(player, clave, true)
			avisar(player, `¡Gracias! Ya tenés {CFG.Pases[clave].Nombre}.`, "Oro")
		end
	end)

	local function alEntrar(player: Player)
		player.CharacterAdded:Connect(function(personaje: Model)
			personaje:WaitForChild("Head", 10)
			actualizarCartel(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		alEntrar(player)
	end
	Players.PlayerAdded:Connect(alEntrar)
	DataManager.PerfilCargado:Connect(function(player: Player)
		consultar(player)
		actualizarCartel(player)
	end)
	DataManager.DatosCambiados:Connect(function(player: Player, seccion: Types.SeccionDatos)
		if seccion == "Honor" or seccion == "Cosmeticos" then
			actualizarCartel(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		tiene[player] = nil
		ultimoTitulo[player] = nil
		Bonos.Limpiar(player)
	end)

	NetworkBridge.Server.OnInvoke("TiendaInfo", function(player: Player): Respuesta
		return info(player)
	end)
	NetworkBridge.Server.OnInvoke("TiendaComprarPase", function(player: Player, clave: unknown): Respuesta
		local c = NetworkBridge.Guard.OneOf(clave, CFG.Pases)
		return if c then comprar(player, c) else NetworkBridge.Fail("INVALID_ARGS")
	end)
	NetworkBridge.Server.OnInvoke("TiendaGuardarTitulo", function(player: Player, texto: unknown): Respuesta
		local t = NetworkBridge.Guard.String(texto, 80)
		return if t then guardarTitulo(player, t) else NetworkBridge.Fail("INVALID_ARGS")
	end)
end

return PasesManager
