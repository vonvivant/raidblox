--!strict
-- ChatarreroManager: mecánicas propias de la clase Chatarrero (servidor).
-- Los números y las 30 habilidades están en ChatarreroConfig; el combate
-- normal (recargas, Stamina, daño, objetivos) lo resuelve CombatManager, y acá
-- se registran las habilidades "especiales".
--
-- Spoil (estilo Scavenger):
--   1. "Extracción Rápida" sobre un monstruo vivo lo marca (atributo Spoiled).
--      "Marca de Saqueador" duplica la probabilidad de éxito.
--   2. Al morir, si el Spoil tiene éxito (jefes y élites: siempre), el cuerpo
--      queda 20 s resaltado en verde-dorado (tag "RestosSpoil").
--   3. El Chatarrero que lo marcó le saca materiales con Extracción Rápida
--      (uno), Barrido Profundo (todos a 15 studs), Ojo del Tasador (raro
--      garantizado en jefes) o Extracción Quirúrgica (Núcleo de Titán).
--   Cada resto se extrae una vez por Chatarrero. Todo se valida acá.
--
-- Construcciones: Yunque Portátil, Trampa de Oso, pared de chatarra y torreta.
-- También: barras de habilidades (equipar 4 por categoría) y desmantelar.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local ClassConfig = require(ReplicatedStorage.Configs.ClassConfig)
local CFG = require(ReplicatedStorage.Configs.ChatarreroConfig)
local ItemCatalog = require(ReplicatedStorage.Configs.ItemCatalog)
local ProfesionesConfig = require(ReplicatedStorage.Configs.ProfesionesConfig)
local NetworkBridge = require(ReplicatedStorage.Modules.NetworkBridge)
local DataManager = require(script.Parent.Parent.DataManager)
local AntiCheat = require(script.Parent.Parent.AntiCheat)
local Buzon = require(script.Parent.Parent.Buzon)
local GrupoManager = require(script.Parent.Parent.GrupoManager)
local BandoManager = require(script.Parent.Parent.BandoManager)
local EquipoVisible = require(script.Parent.Parent.EquipoVisible)
local CraftingManager = require(script.Parent.Parent.Economia.CraftingManager)
local CombatManager = require(script.Parent.CombatManager)
local EnemyManager = require(script.Parent.EnemyManager)
local LootManager = require(script.Parent.LootManager)

type Respuesta = Types.Respuesta
type Combatiente = CombatManager.Combatiente
type Npc = EnemyManager.Npc
type EntradaSpoil = CFG.EntradaSpoil

type Marcado = { Duenos: { [Player]: boolean }, Marca: boolean }
type Restos = {
	Modelo: Model,
	Posicion: Vector3,
	Duenos: { [Player]: boolean },
	Elite: boolean,
	Jefe: boolean, -- jefe de mazmorra o RaidBlox
	Vence: number,
}
type Caida = { Posicion: Vector3, Hora: number }

local ChatarreroManager = {}

local COLOR_SPOIL = Color3.fromRGB(190, 230, 60)
local COLOR_CHATARRA = Color3.fromRGB(110, 100, 90)

local marcados: { [Combatiente]: Marcado } = {}
local restos: { Restos } = {}
local sobreaceleracion: { [Player]: number } = {}
local granBotin: { [Player]: number } = {}
local caidas: { [Player]: Caida } = {}
local ultimoPedido: { [Player]: number } = {}
local azar = Random.new()
local iniciado = false

local function ahora(): number
	return CombatManager.Ahora()
end

local function avisar(player: Player?, texto: string, tipo: string?)
	if player then
		NetworkBridge.Server.FireClient("Notificacion", player, texto, tipo or "Info")
	end
end

local function esChatarrero(player: Player): boolean
	local datos = DataManager.GetData(player)
	return datos ~= nil and datos.Clase == "Chatarrero"
end

local function carpeta(): Folder
	local f = Workspace:FindFirstChild("Chatarrero")
	if f and f:IsA("Folder") then
		return f
	end
	local nueva = Instance.new("Folder")
	nueva.Name = "Chatarrero"
	nueva.Parent = Workspace
	return nueva
end

local function pieza(tam: Vector3, cf: CFrame, color: Color3, material: Enum.Material, solida: boolean): Part
	local p = Instance.new("Part")
	p.Size = tam
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = solida
	p.CanQuery = solida
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function cartel(parte: BasePart, texto: string, color: Color3)
	local b = Instance.new("BillboardGui")
	b.Size = UDim2.fromScale(8, 1.4)
	b.StudsOffset = Vector3.new(0, parte.Size.Y / 2 + 1.5, 0)
	b.MaxDistance = 70
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = texto
	t.Parent = b
	b.Parent = parte
end

-- Punto sobre el suelo delante del combatiente.
local function alFrente(c: Combatiente, distancia: number): CFrame
	local base = c.Raiz.CFrame
	local frente = Vector3.new(base.LookVector.X, 0, base.LookVector.Z)
	frente = if frente.Magnitude > 0.01 then frente.Unit else Vector3.new(0, 0, -1)
	local origen = c.Raiz.Position + frente * distancia
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c.Modelo, carpeta() }
	local choque = Workspace:Raycast(origen + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	local suelo = if choque then choque.Position else origen - Vector3.new(0, 3, 0)
	return CFrame.lookAt(suelo, suelo + frente)
end

------------------------------------------------------------------------
-- Spoil
------------------------------------------------------------------------

local function duplica(player: Player): boolean
	return (sobreaceleracion[player] or 0) > ahora() and azar:NextNumber() < CFG.Sobreaceleracion.Probabilidad
end

local function dar(player: Player, itemId: string, cantidad: number, origen: string)
	if not DataManager.AddItem(player, itemId, cantidad, "Comun", nil) then
		Buzon.EnviarItem(player.UserId, { ItemId = itemId, Cantidad = cantidad, Rareza = "Comun" }, origen)
	end
end

local function tirar(tabla: { EntradaSpoil }, salida: { [string]: number })
	for _, e in tabla do
		if azar:NextNumber() <= e.Probabilidad then
			salida[e.ItemId] = (salida[e.ItemId] or 0) + azar:NextInteger(e.Min, e.Max)
		end
	end
end

local function quitarRestos(r: Restos)
	local i = table.find(restos, r)
	if i then
		table.remove(restos, i)
	end
	if r.Modelo.Parent then
		CollectionService:RemoveTag(r.Modelo, "RestosSpoil")
		local brillo = r.Modelo:FindFirstChild("BrilloSpoil")
		if brillo then
			brillo:Destroy()
		end
	end
end

-- Saca los materiales de un resto para un jugador. `extra`: "Raro" (Ojo del
-- Tasador) o "Legendario" (Extracción Quirúrgica).
local function extraer(player: Player, r: Restos, extra: string?)
	r.Duenos[player] = nil
	local salida: { [string]: number } = {}
	tirar(if r.Elite then CFG.Spoil.Jefe else CFG.Spoil.Comun, salida)
	if extra == "Raro" then
		tirar({ CFG.Spoil.Raro }, salida)
	elseif extra == "Legendario" then
		tirar({ CFG.Spoil.Legendario }, salida)
	end
	local doble = duplica(player)
	local partes: { string } = {}
	for itemId, cantidad in salida do
		local n = if doble then cantidad * 2 else cantidad
		dar(player, itemId, n, "Spoil")
		local def = ItemCatalog[itemId]
		table.insert(partes, `{if def then def.Nombre else itemId} x{n}`)
	end
	table.sort(partes)
	avisar(player, `Spoil{if doble then " (¡duplicado!)" else ""}: {table.concat(partes, ", ")}`, "Oro")
	if next(r.Duenos) == nil then
		quitarRestos(r)
	end
end

-- Restos del jugador cerca de un punto, del más cercano al más lejano.
local function restosCerca(player: Player, centro: Vector3, radio: number, filtro: ((Restos) -> boolean)?): { Restos }
	local t = ahora()
	local lista: { Restos } = {}
	for _, r in restos do
		if
			r.Duenos[player]
			and r.Vence > t
			and (r.Posicion - centro).Magnitude <= radio
			and (not filtro or filtro(r))
		then
			table.insert(lista, r)
		end
	end
	table.sort(lista, function(a: Restos, b: Restos): boolean
		return (a.Posicion - centro).Magnitude < (b.Posicion - centro).Magnitude
	end)
	return lista
end

local function marcar(c: Combatiente, objetivo: Combatiente, conMarca: boolean)
	local player = c.Player
	if not player then
		return
	end
	local m = marcados[objetivo]
	if not m then
		m = { Duenos = {}, Marca = false }
		marcados[objetivo] = m
	end
	if conMarca then
		m.Marca = true
		objetivo.Modelo:SetAttribute("MarcaSaqueador", true)
		CombatManager.Anunciar(objetivo, "Marcado")
	else
		m.Duenos[player] = true
		objetivo.Modelo:SetAttribute("Spoiled", true)
		CombatManager.Anunciar(objetivo, "Spoil")
	end
end

local function alMorirNpc(npc: Npc)
	local c = npc.Combatiente
	local posicion = c.Raiz.Position
	local elite = npc.Modelo:GetAttribute("Elite") == true

	-- El Gran Botín: cofre para quienes pelearon, si hay un Chatarrero con el
	-- buff activo cerca.
	local t = ahora()
	for chatarrero, hasta in granBotin do
		local cc = CombatManager.DeJugador(chatarrero)
		if hasta > t and cc and (cc.Raiz.Position - posicion).Magnitude <= CFG.GranBotin.Radio then
			for userId, aporte in npc.Aportes do
				local p = Players:GetPlayerByUserId(userId)
				if p and aporte > 0 then
					local salida: { [string]: number } = {}
					tirar(CFG.Spoil.Cofre, salida)
					local items: { LootManager.ItemGenerado } = {}
					for itemId, n in salida do
						table.insert(items, { ItemId = itemId, Cantidad = n, Rareza = "Comun", Meta = nil })
					end
					LootManager.Soltar(p, posicion, items, "El Gran Botín")
				end
			end
			break -- un cofre por monstruo aunque haya varios Chatarreros
		end
	end

	local m = marcados[c]
	marcados[c] = nil
	if not m or next(m.Duenos) == nil then
		return
	end
	local probabilidad = if elite then 1 else math.min(1, CFG.Spoil.Probabilidad * (if m.Marca then 2 else 1))
	local duenos: { [Player]: boolean } = {}
	for player in m.Duenos do
		if player.Parent ~= Players then
			continue
		end
		if azar:NextNumber() <= probabilidad then
			duenos[player] = true
			avisar(
				player,
				`Spoil con éxito: {c.Nombre} dejó restos. Extraelos antes de {CFG.Spoil.DuracionRestos} s.`,
				"Oro"
			)
		else
			avisar(player, `El Spoil de {c.Nombre} falló.`, "Error")
		end
	end
	if next(duenos) == nil then
		return
	end
	npc.DemoraCadaver = CFG.Spoil.DuracionRestos
	local brillo = Instance.new("Highlight")
	brillo.Name = "BrilloSpoil"
	brillo.FillColor = COLOR_SPOIL
	brillo.OutlineColor = Color3.fromRGB(255, 215, 60)
	brillo.FillTransparency = 0.45
	brillo.DepthMode = Enum.HighlightDepthMode.Occluded
	brillo.Parent = npc.Modelo
	CollectionService:AddTag(npc.Modelo, "RestosSpoil")
	local r: Restos = {
		Modelo = npc.Modelo,
		Posicion = posicion,
		Duenos = duenos,
		Elite = elite,
		Jefe = npc.Modelo:GetAttribute("RaidBlox") == true or npc.Modelo:GetAttribute("JefeMazmorra") == true,
		Vence = t + CFG.Spoil.DuracionRestos,
	}
	table.insert(restos, r)
	task.delay(CFG.Spoil.DuracionRestos, quitarRestos, r)
end

------------------------------------------------------------------------
-- Habilidades especiales
------------------------------------------------------------------------

local function soloMonstruos(_c: Combatiente, _hab: ClassConfig.Habilidad, objetivo: Combatiente?): string?
	if not objetivo or objetivo.Player ~= nil then
		return "Solo funciona sobre monstruos."
	end
	return nil
end

local function registrar()
	local R = CombatManager.RegistrarEspecial

	R("Marca", {
		Puede = soloMonstruos,
		Hacer = function(c, _hab, objetivo)
			if objetivo then
				marcar(c, objetivo, true)
			end
		end,
	})

	R("Spoil", {
		Puede = function(c, _hab, objetivo): string?
			local player = c.Player
			if player and #restosCerca(player, c.Raiz.Position, CFG.Spoil.RadioExtraccion) > 0 then
				return nil
			end
			if objetivo and objetivo.Player == nil then
				return nil
			end
			return "Necesitás un monstruo vivo como objetivo o restos tuyos a menos de 10 studs."
		end,
		Hacer = function(c, _hab, objetivo)
			local player = c.Player
			if not player then
				return
			end
			local cerca = restosCerca(player, c.Raiz.Position, CFG.Spoil.RadioExtraccion)
			if cerca[1] then
				extraer(player, cerca[1], nil)
			elseif objetivo and objetivo.Player == nil then
				marcar(c, objetivo, false)
			end
		end,
	})

	R("Barrido", {
		Puede = function(c, hab): string?
			local player = c.Player
			if player and #restosCerca(player, c.Raiz.Position, hab.Radio or 15) > 0 then
				return nil
			end
			return "No hay restos tuyos cerca."
		end,
		Hacer = function(c, hab)
			local player = c.Player
			if player then
				for _, r in restosCerca(player, c.Raiz.Position, hab.Radio or 15) do
					extraer(player, r, nil)
				end
			end
		end,
	})

	R("Tasador", {
		Puede = function(c, hab): string?
			local player = c.Player
			local lista = if player
				then restosCerca(player, c.Raiz.Position, hab.Radio or 12, function(r: Restos): boolean
					return r.Elite
				end)
				else {}
			return if #lista > 0 then nil else "Necesitás restos tuyos de un jefe o élite a menos de 12 studs."
		end,
		Hacer = function(c, hab)
			local player = c.Player
			if not player then
				return
			end
			local lista = restosCerca(player, c.Raiz.Position, hab.Radio or 12, function(r: Restos): boolean
				return r.Elite
			end)
			if lista[1] then
				extraer(player, lista[1], "Raro")
			end
		end,
	})

	R("Quirurgica", {
		Puede = function(c, hab): string?
			local player = c.Player
			local lista = if player
				then restosCerca(player, c.Raiz.Position, hab.Radio or 12, function(r: Restos): boolean
					return r.Jefe
				end)
				else {}
			return if #lista > 0
				then nil
				else "Necesitás restos tuyos de un jefe de mazmorra o RaidBlox a menos de 12 studs."
		end,
		Hacer = function(c, hab)
			local player = c.Player
			if not player then
				return
			end
			local lista = restosCerca(player, c.Raiz.Position, hab.Radio or 12, function(r: Restos): boolean
				return r.Jefe
			end)
			if lista[1] then
				extraer(player, lista[1], "Legendario")
			end
		end,
	})

	R("Olfato", {
		Hacer = function(c)
			local player = c.Player
			if player then
				NetworkBridge.Server.FireClient("ChatarreroOlfato", player, CFG.Olfato.Duracion, CFG.Olfato.Radio)
			end
		end,
	})

	R("Humo", {
		Hacer = function(c, hab)
			local radio = hab.Radio or 12
			local nube = pieza(
				Vector3.one * radio * 2,
				CFrame.new(c.Raiz.Position),
				Color3.fromRGB(120, 120, 125),
				Enum.Material.SmoothPlastic,
				false
			)
			nube.Shape = Enum.PartType.Ball
			nube.Transparency = 0.55
			nube.CastShadow = false
			local humo = Instance.new("Smoke")
			humo.Size = radio
			humo.Opacity = 0.4
			humo.RiseVelocity = 2
			humo.Parent = nube
			nube.Parent = carpeta()
			Debris:AddItem(nube, 6)
			-- Ciega (aturde un momento) a los monstruos comunes dentro de la nube.
			for _, o in CombatManager.EnemigosEnRadio(c, c.Raiz.Position, radio) do
				if o.Player == nil and o.Modelo:GetAttribute("Elite") ~= true then
					CombatManager.AplicarEfecto(c, o, { Tipo = "Aturdir", Duracion = CFG.Humo.Ceguera }, hab.Id)
				end
			end
		end,
	})

	R("Yunque", {
		Hacer = function(c)
			local player = c.Player
			if not player then
				return
			end
			-- Uno por Chatarrero: el anterior se va.
			for _, viejo in CollectionService:GetTagged("YunquePortatil") do
				if viejo:GetAttribute("Dueno") == player.UserId then
					viejo:Destroy()
				end
			end
			local yunque = pieza(
				Vector3.new(4, 2.5, 2.5),
				alFrente(c, 5) * CFrame.new(0, 1.25, 0),
				Color3.fromRGB(70, 70, 78),
				Enum.Material.Metal,
				true
			)
			yunque.Name = "YunquePortatil"
			yunque:SetAttribute("Estacion", "Yunque")
			yunque:SetAttribute("Dueno", player.UserId)
			cartel(yunque, `Yunque de {player.DisplayName}`, Color3.fromRGB(255, 200, 90))
			yunque.Parent = carpeta()
			CollectionService:AddTag(yunque, "YunquePortatil")
			CollectionService:AddTag(yunque, "EstacionCrafteo")
			Debris:AddItem(yunque, CFG.Yunque.Duracion)
		end,
	})

	R("Trampa", {
		Hacer = function(c, hab)
			local trampa = pieza(
				Vector3.new(0.4, 4, 4),
				alFrente(c, 3) * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(95, 90, 85),
				Enum.Material.DiamondPlate,
				false
			)
			trampa.Shape = Enum.PartType.Cylinder
			trampa.Name = "TrampaOso"
			trampa.Parent = carpeta()
			Debris:AddItem(trampa, CFG.Trampa.Duracion)
			local centro = trampa.Position
			local vence = ahora() + CFG.Trampa.Duracion
			task.spawn(function()
				while trampa.Parent and ahora() < vence and CombatManager.EstaVivo(c) do
					local presa = CombatManager.EnemigosEnRadio(c, centro, CFG.Trampa.Radio)[1]
					if presa then
						local s = CFG.Trampa.Sangrado
						CombatManager.AplicarEfecto(
							c,
							presa,
							{ Tipo = "Inmovilizar", Duracion = CFG.Trampa.Inmovil },
							hab.Id
						)
						CombatManager.AplicarEfecto(c, presa, {
							Tipo = "DanioTiempo",
							Escuela = "Fisico",
							Base = s.Base,
							Escala = "Ataque",
							Factor = s.Factor,
							Duracion = s.Duracion,
							Intervalo = s.Intervalo,
						}, hab.Id)
						break
					end
					task.wait(0.2)
				end
				trampa:Destroy()
			end)
		end,
	})

	R("Adrenalina", {
		Puede = function(c): string?
			local player = c.Player
			if player and typeof(player:GetAttribute("Montura")) == "string" then
				return "No se puede usar montado."
			end
			return nil
		end,
		Hacer = function(c)
			local player = c.Player
			if not player then
				return
			end
			CombatManager.Liberar(c)
			local h = c.Humanoid
			local rapida = h.WalkSpeed * CFG.Adrenalina.Factor
			h.WalkSpeed = rapida
			AntiCheat.SetVelocidadPermitida(player, rapida)
			CombatManager.Anunciar(c, "¡Adrenalina!")
			task.delay(CFG.Adrenalina.Duracion, function()
				-- Si en el medio se montó (u otra cosa cambió la velocidad), no se toca.
				if player.Parent == Players and typeof(player:GetAttribute("Montura")) ~= "string" then
					if h.Parent and math.abs(h.WalkSpeed - rapida) < 0.01 then
						h.WalkSpeed = rapida / CFG.Adrenalina.Factor
					end
					AntiCheat.SetVelocidadPermitida(player, nil)
				end
			end)
		end,
	})

	R("EscudoChatarra", {
		Hacer = function(c)
			local player = c.Player
			if not player then
				return
			end
			local metales = 0
			for _, itemId in CFG.Metales do
				metales += DataManager.CountItem(player, itemId)
			end
			metales = math.min(metales, CFG.Escudo.MaxMetales)
			CombatManager.DarEscudo(c, CFG.Escudo.Base + CFG.Escudo.PorMetal * metales, CFG.Escudo.Duracion)
		end,
	})

	R("Sobreaceleracion", {
		Hacer = function(c)
			local player = c.Player
			if player then
				sobreaceleracion[player] = ahora() + CFG.Sobreaceleracion.Duracion
				CombatManager.Anunciar(c, "¡Sobreaceleración!")
			end
		end,
	})

	R("Contrabandista", {
		Puede = function(c): string?
			local player = c.Player
			if player and DataManager.CountItem(player, CFG.Contrabandista.Item) > 0 then
				return nil
			end
			return "No tenés Chatarra para mandar."
		end,
		Hacer = function(c)
			local player = c.Player
			if not player then
				return
			end
			local item = CFG.Contrabandista.Item
			local cantidad = DataManager.CountItem(player, item)
			local def = ItemCatalog[item]
			if cantidad <= 0 or not def or not DataManager.RemoveItem(player, item, cantidad) then
				return
			end
			local oro = math.floor(cantidad * def.PrecioVenta * CFG.Contrabandista.Factor)
			Buzon.DarOro(player, oro, "Contrabandista")
			avisar(player, `El dron se llevó {cantidad} de Chatarra: +{oro} de oro.`, "Oro")
			-- El dron: sube y desaparece.
			local dron = pieza(
				Vector3.new(2, 0.8, 2),
				c.Raiz.CFrame * CFrame.new(0, 4, -3),
				Color3.fromRGB(60, 60, 70),
				Enum.Material.Metal,
				false
			)
			dron.Anchored = false
			local vuelo = Instance.new("BodyVelocity")
			vuelo.Velocity = Vector3.new(0, 14, 0)
			vuelo.MaxForce = Vector3.one * 1e5
			vuelo.Parent = dron
			local luz = Instance.new("PointLight")
			luz.Color = Color3.fromRGB(120, 255, 160)
			luz.Parent = dron
			dron.Parent = carpeta()
			Debris:AddItem(dron, 4)
		end,
	})

	R("Pared", {
		Hacer = function(c)
			local tam = CFG.Pared.Tam
			local pared = pieza(
				tam,
				alFrente(c, CFG.Pared.Distancia) * CFrame.new(0, tam.Y / 2, 0),
				COLOR_CHATARRA,
				Enum.Material.CorrodedMetal,
				true
			)
			pared.Name = "ParedChatarra"
			pared.Parent = carpeta()
			CombatManager.RegistrarObstaculo(pared)
			Debris:AddItem(pared, CFG.Pared.Duracion)
		end,
	})

	R("GranBotin", {
		Hacer = function(c)
			local player = c.Player
			if player then
				granBotin[player] = ahora() + CFG.GranBotin.Duracion
				CombatManager.Anunciar(c, "¡El Gran Botín!")
			end
		end,
	})

	R("Titan", {
		Hacer = function(c)
			local player = c.Player
			-- Sin aturdimientos mientras dura.
			c.InmuneAturdirHasta = math.max(c.InmuneAturdirHasta, ahora() + CFG.Titan.Duracion)
			CombatManager.Anunciar(c, "¡Titán de Hierro!")
			-- Crece (avatares R15: escalas del Humanoid).
			local h = c.Humanoid
			local originales: { [NumberValue]: number } = {}
			for _, nombre in { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" } do
				local v = h:FindFirstChild(nombre)
				if v and v:IsA("NumberValue") then
					originales[v] = v.Value
					v.Value *= CFG.Titan.Escala
				end
			end
			local function rehacerEquipo()
				task.wait(0.4)
				if player and player.Parent == Players then
					EquipoVisible.Actualizar(player, true)
				end
			end
			task.spawn(rehacerEquipo)
			task.delay(CFG.Titan.Duracion, function()
				for v, valor in originales do
					if v.Parent then
						v.Value = valor
					end
				end
				rehacerEquipo()
			end)
		end,
	})

	-- Aliado caído cerca: del grupo, o cualquiera que siga muerto.
	local function caidoCerca(c: Combatiente): Player?
		local player = c.Player
		if not player then
			return nil
		end
		local t = ahora()
		local mejor: Player? = nil
		local menor = CFG.Revivir.Radio
		for otro, caida in caidas do
			if otro == player or otro.Parent ~= Players or t - caida.Hora > CFG.Revivir.Ventana then
				continue
			end
			local co = CombatManager.DeJugador(otro)
			local sigueMuerto = co == nil or not CombatManager.EstaVivo(co)
			if BandoManager.SonRivales(player, otro) or not (sigueMuerto or GrupoManager.MismoGrupo(player, otro)) then
				continue
			end
			local d = (caida.Posicion - c.Raiz.Position).Magnitude
			if d <= menor then
				mejor, menor = otro, d
			end
		end
		return mejor
	end

	R("Revivir", {
		Puede = function(c): string?
			return if caidoCerca(c)
				then nil
				else "No hay ningún aliado caído cerca (hasta 2 minutos después de caer)."
		end,
		Hacer = function(c)
			local otro = caidoCerca(c)
			local caida = otro and caidas[otro]
			if not otro or not caida then
				return
			end
			caidas[otro] = nil
			task.spawn(function()
				local co = CombatManager.DeJugador(otro)
				if not co or not CombatManager.EstaVivo(co) then
					local ok = pcall(function()
						otro:LoadCharacterAsync()
					end)
					if not ok then
						return
					end
				end
				-- Espera a que el combate registre el personaje nuevo.
				local limite = os.clock() + 8
				repeat
					task.wait(0.2)
					co = CombatManager.DeJugador(otro)
				until (co and CombatManager.EstaVivo(co) and co.Modelo == otro.Character) or os.clock() > limite
				if not co or otro.Parent ~= Players then
					return
				end
				AntiCheat.Gracia(otro, 3)
				co.Modelo:PivotTo(CFrame.new(caida.Posicion + Vector3.new(0, 3, 0)))
				co.Humanoid.Health = co.Humanoid.MaxHealth
				CombatManager.Anunciar(co, "¡Revivido!")
				avisar(otro, `{c.Nombre} te revivió con el desfibrilador.`, "Oro")
			end)
		end,
	})

	R("Reingenieria", {
		Hacer = function(c)
			CombatManager.ReiniciarCooldowns(c, function(hab: ClassConfig.Habilidad): boolean
				return hab.Categoria == 2
			end)
			avisar(c.Player, "Recargas de la barra II reiniciadas.", "Oro")
		end,
	})

	R("Torreta", {
		Hacer = function(c, hab)
			local cfg = CFG.Torreta
			local base = alFrente(c, 6)
			local modelo = Instance.new("Model")
			modelo.Name = "TorretaChatarra"
			local cuerpo = pieza(
				Vector3.new(5, 4, 5),
				base * CFrame.new(0, 2, 0),
				COLOR_CHATARRA,
				Enum.Material.CorrodedMetal,
				true
			)
			cuerpo.Parent = modelo
			local canon = pieza(
				Vector3.new(1.2, 1.2, 5),
				base * CFrame.new(0, 5, -1),
				Color3.fromRGB(60, 60, 68),
				Enum.Material.Metal,
				false
			)
			canon.Parent = modelo
			local luz = Instance.new("PointLight")
			luz.Color = Color3.fromRGB(255, 170, 60)
			luz.Range = 14
			luz.Parent = canon
			cartel(cuerpo, "Torreta del Rey de la Chatarra", Color3.fromRGB(255, 170, 60))
			modelo.Parent = carpeta()
			Debris:AddItem(modelo, cfg.Duracion + 1)
			local boca = canon.Position
			local vence = ahora() + cfg.Duracion
			task.spawn(function()
				while modelo.Parent and ahora() < vence and CombatManager.EstaVivo(c) do
					local lista = CombatManager.EnemigosEnRadio(c, boca, cfg.Radio)
					for i = 1, math.min(#lista, cfg.Objetivos) do
						local o = lista[i]
						-- Rayo visible del disparo.
						local hasta = o.Raiz.Position
						local largo = (hasta - boca).Magnitude
						local rayo = pieza(
							Vector3.new(0.3, 0.3, largo),
							CFrame.lookAt(boca, hasta) * CFrame.new(0, 0, -largo / 2),
							Color3.fromRGB(255, 190, 80),
							Enum.Material.Neon,
							false
						)
						rayo.Parent = carpeta()
						Debris:AddItem(rayo, 0.15)
						CombatManager.AplicarEfecto(c, o, {
							Tipo = "Danio",
							Escuela = "Fisico",
							Base = cfg.Base,
							Escala = "Ataque",
							Factor = cfg.Factor,
						}, hab.Id)
					end
					task.wait(cfg.Cada)
				end
				modelo:Destroy()
			end)
		end,
	})
end

------------------------------------------------------------------------
-- Barras de habilidades
------------------------------------------------------------------------

local function alternarBarra(player: Player, id: string): Respuesta
	local datos = DataManager.GetData(player)
	local def = datos and ClassConfig.Clases[datos.Clase]
	if not datos or not def or not def.Barras then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local hab: ClassConfig.Habilidad? = nil
	for _, h in def.Habilidades do
		if h.Id == id then
			hab = h
		end
	end
	if not hab then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	-- Sin esto, se podría usar una ulti, sacarla y poner otra lista en su lugar.
	if CombatManager.EnRecarga(player, id) then
		avisar(player, "No podés mover una habilidad que está en recarga.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local barras = table.clone(DataManager.Barras(datos))
	local puesto = table.find(barras, id)
	if puesto then
		table.remove(barras, puesto)
	else
		local enCategoria = 0
		for _, otro in barras do
			for _, h in def.Habilidades do
				if h.Id == otro and h.Categoria == hab.Categoria then
					enCategoria += 1
				end
			end
		end
		if enCategoria >= CFG.RanurasPorBarra then
			avisar(player, "Esa barra ya tiene 4 habilidades: sacá una primero.", "Error")
			return NetworkBridge.Fail("NOT_ALLOWED")
		end
		table.insert(barras, id)
	end
	DataManager.Mutar(player, "Cosmeticos", function(d)
		d.Barras = barras
	end)
	return NetworkBridge.Ok(barras)
end

------------------------------------------------------------------------
-- Desmantelar (cerca del Yunque Portátil propio)
------------------------------------------------------------------------

local function yunqueCerca(player: Player): boolean
	local c = CombatManager.DeJugador(player)
	if not c then
		return false
	end
	for _, y in CollectionService:GetTagged("YunquePortatil") do
		if
			y:IsA("BasePart")
			and y:GetAttribute("Dueno") == player.UserId
			and (y.Position - c.Raiz.Position).Magnitude <= CFG.Yunque.Distancia
		then
			return true
		end
	end
	return false
end

-- Materiales que devuelve un ítem: la mitad de su receta, o Chatarra según su precio.
local function materialesDe(itemId: string): { [string]: number }
	for _, receta in ProfesionesConfig.Recetas do
		if receta.Resultado.ItemId == itemId then
			local salida: { [string]: number } = {}
			for material, n in receta.Materiales do
				salida[material] = math.max(1, n // 2)
			end
			return salida
		end
	end
	local def = ItemCatalog[itemId]
	return { Chatarra = math.clamp((if def then def.PrecioVenta else 0) // 8, 1, 8) }
end

local function desmantelar(player: Player, clave: string): Respuesta
	if not esChatarrero(player) then
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not yunqueCerca(player) then
		avisar(player, "Necesitás estar al lado de tu Yunque Portátil.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	local item = DataManager.ItemEnRanura(player, clave)
	local def = item and ItemCatalog[item.ItemId]
	if not item or not def then
		return NetworkBridge.Fail("NOT_FOUND")
	end
	if def.Tipo ~= "Equipo" or (item.Rareza ~= "Comun" and item.Rareza ~= "Raro") then
		avisar(player, "Solo se desmantela equipo Común o Raro.", "Error")
		return NetworkBridge.Fail("NOT_ALLOWED")
	end
	if not DataManager.QuitarDeRanura(player, clave, item.Cantidad) then
		return NetworkBridge.Fail("INTERNAL_ERROR")
	end
	local doble = duplica(player)
	local partes: { string } = {}
	for material, n in materialesDe(item.ItemId) do
		local cantidad = if doble then n * 2 else n
		dar(player, material, cantidad, "Desmantelar")
		local dm = ItemCatalog[material]
		table.insert(partes, `{if dm then dm.Nombre else material} x{cantidad}`)
	end
	table.sort(partes)
	avisar(player, `Desmantelaste {def.Nombre}: {table.concat(partes, ", ")}`, "Oro")
	return NetworkBridge.Ok(nil)
end

------------------------------------------------------------------------
-- Inicio
------------------------------------------------------------------------

function ChatarreroManager.Init()
	assert(not iniciado, "ChatarreroManager.Init() se llamó dos veces")
	iniciado = true

	registrar()
	EnemyManager.NpcMurio:Connect(alMorirNpc)
	CraftingManager.SetDuplicador(duplica)

	-- Dónde cayó cada jugador (para el desfibrilador) y limpieza de marcas.
	CombatManager.Murio:Connect(function(c: Combatiente)
		local player = c.Player
		if player then
			caidas[player] = { Posicion = c.Raiz.Position, Hora = ahora() }
		end
	end)

	local function conEspera(player: Player, segundos: number): boolean
		local t = os.clock()
		if t - (ultimoPedido[player] or 0) < segundos then
			return false
		end
		ultimoPedido[player] = t
		return true
	end

	NetworkBridge.Server.OnInvoke("BarraAlternar", function(player: Player, id: unknown): Respuesta
		local s = NetworkBridge.Guard.String(id, 40)
		if not s then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not conEspera(player, 0.2) then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return alternarBarra(player, s)
	end)
	NetworkBridge.Server.OnInvoke("ChatarreroDesmantelar", function(player: Player, ranura: unknown): Respuesta
		local n = NetworkBridge.Guard.Integer(ranura, 1, 200)
		if not n then
			return NetworkBridge.Fail("INVALID_ARGS")
		end
		if not conEspera(player, 0.4) then
			return NetworkBridge.Fail("RATE_LIMITED")
		end
		return desmantelar(player, tostring(n))
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		sobreaceleracion[player] = nil
		granBotin[player] = nil
		caidas[player] = nil
		ultimoPedido[player] = nil
		for _, m in marcados do
			m.Duenos[player] = nil
		end
		for _, r in table.clone(restos) do
			r.Duenos[player] = nil
			if next(r.Duenos) == nil then
				quitarRestos(r)
			end
		end
	end)

	-- Marcas de monstruos que desaparecieron sin morir (reinicios, mazmorras).
	task.spawn(function()
		while true do
			task.wait(30)
			for c in marcados do
				if not c.Modelo.Parent then
					marcados[c] = nil
				end
			end
		end
	end)
end

return ChatarreroManager
