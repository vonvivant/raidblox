--!strict
-- Radar: lista de lo que se dibuja en el minimapa y en el mapa del mundo.
-- Solo cliente. Buscar entidades es lo caro, así que la lista se rehace cada
-- medio segundo; las posiciones se leen de cada parte en el momento de dibujar
-- (por frame), y por eso los puntos se mueven suaves.
--
-- De dónde sale cada cosa (qué hay que respetar al armar los mapas):
--   Grupo     jugadores con el mismo atributo "GrupoId" que el jugador local.
--   Enemigo   modelos de la carpeta Workspace.Enemigos con Humanoid vivo.
--   Elite     lo mismo, con el atributo "Elite" = true (jefes y RaidBlox).
--   Mision    tag "NpcMision" + atributo local "MarcaMinimapa" ("!" o "?").
--   Recurso   tag "NodoRecoleccion" (vetas y plantas).
--   Restos    tag "RestosSpoil" (restos del Spoil del Chatarrero).
--   Portal    tag "Portal".
--   Estacion  tags "EstacionCrafteo" y "CasaSubastas".

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

export type Tipo = "Grupo" | "Enemigo" | "Elite" | "Mision" | "Recurso" | "Restos" | "Portal" | "Estacion"
export type Entidad = { Parte: BasePart, Tipo: Tipo, Texto: string? }

local Radar = {}

local MAX_ENEMIGOS = 60
local INTERVALO = 0.5

local jugador = Players.LocalPlayer
local lista: { Entidad } = {}
local ultima = 0

local function parteDe(objeto: Instance?): BasePart?
	if not objeto then
		return nil
	end
	if objeto:IsA("BasePart") then
		return objeto
	end
	local raiz = objeto:FindFirstChild("HumanoidRootPart")
	if raiz and raiz:IsA("BasePart") then
		return raiz
	end
	if objeto:IsA("Model") then
		return objeto.PrimaryPart or objeto:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

Radar.ParteDe = parteDe

local function rehacer()
	local nueva: { Entidad } = {}
	local function agregar(objeto: Instance?, tipo: Tipo, texto: string?)
		local parte = parteDe(objeto)
		if parte then
			table.insert(nueva, { Parte = parte, Tipo = tipo, Texto = texto })
		end
	end
	for _, p in CollectionService:GetTagged("Portal") do
		agregar(p, "Portal")
	end
	for _, tag in { "EstacionCrafteo", "CasaSubastas" } do
		for _, e in CollectionService:GetTagged(tag) do
			agregar(e, "Estacion")
		end
	end
	for _, n in CollectionService:GetTagged("NodoRecoleccion") do
		agregar(n, "Recurso")
	end
	for _, r in CollectionService:GetTagged("RestosSpoil") do
		agregar(r, "Restos")
	end
	for _, npc in CollectionService:GetTagged("NpcMision") do
		local signo = npc:GetAttribute("MarcaMinimapa")
		if typeof(signo) == "string" and signo ~= "" then
			agregar(npc, "Mision", signo)
		end
	end
	local carpeta = Workspace:FindFirstChild("Enemigos")
	if carpeta then
		local n = 0
		for _, e in carpeta:GetChildren() do
			local h = e:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then
				agregar(e, if e:GetAttribute("Elite") == true then "Elite" else "Enemigo")
				n += 1
				if n >= MAX_ENEMIGOS then
					break
				end
			end
		end
	end
	local miGrupo = jugador:GetAttribute("GrupoId")
	if miGrupo ~= nil then
		for _, otro in Players:GetPlayers() do
			if otro ~= jugador and otro:GetAttribute("GrupoId") == miGrupo then
				agregar(otro.Character, "Grupo", otro.DisplayName)
			end
		end
	end
	lista = nueva
end

-- Entidades a dibujar. Barato de llamar en cada frame.
function Radar.Entidades(): { Entidad }
	local t = os.clock()
	if t - ultima >= INTERVALO then
		ultima = t
		rehacer()
	end
	return lista
end

return Radar
