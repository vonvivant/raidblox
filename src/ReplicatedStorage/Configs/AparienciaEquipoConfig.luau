--!strict
-- AparienciaEquipoConfig: cómo se VE el equipo puesto (Fase 6.3).
--
-- * Modelos: formas hechas con piezas simples (Parts), sin assets externos.
--   Cada pieza se ubica respecto de la mano, la cabeza o el torso. Las que
--   tienen Tinte = true toman el color/material del ítem o de la apariencia;
--   las demás conservan los suyos (mango, guarda, etc.).
--   Ejes: las armas de mano "Hoja" crecen hacia +Y desde el mango; al
--   empuñarlas se giran para apuntar adelante.
-- * Items: qué modelo usa cada ítem equipable y su color base. Si un ítem no
--   figura acá no se dibuja (anillos, capas y herramientas, por ahora).
-- * Apariencias: transmog. Cambian solo el aspecto de un slot; las stats son
--   siempre las del ítem equipado. Se ganan en el pase de batalla y pueden
--   salir de cajas o eventos.
--
-- Para agregar una apariencia nueva: sumala en Apariencias (con su Slot) y
-- dala como recompensa { Tipo = "Apariencia", Id = "<Clave>" }.

local Types = require(script.Parent.Parent.Shared.Types)

export type Anclaje = "ManoDerecha" | "ManoIzquierda" | "Cabeza" | "Torso"

export type Pieza = {
	Tam: Vector3,
	Pos: Vector3, -- desplazamiento desde el anclaje
	Rot: Vector3?, -- grados
	Forma: Enum.PartType?,
	Material: Enum.Material?,
	Color: Color3?,
	Tinte: boolean?, -- usa el color/material del ítem o de la apariencia
	Efecto: boolean?, -- acá se pegan el fuego / las chispas de la apariencia
}

export type Modelo = {
	Anclaje: Anclaje,
	Empunadura: boolean?, -- arma que apunta hacia adelante desde la mano
	Piezas: { Pieza },
}

export type VisualItem = { Modelo: string, Color: Color3, Material: Enum.Material }

export type Apariencia = {
	Nombre: string,
	Slot: Types.SlotEquipo,
	Modelo: string,
	Color: Color3,
	Material: Enum.Material,
	Efecto: ("Fuego" | "Chispas" | "Humo")?,
	ColorEfecto: Color3?,
}

local MADERA = Color3.fromRGB(105, 70, 40)
local CUERO = Color3.fromRGB(90, 60, 35)
local ACERO = Color3.fromRGB(165, 170, 180)

local Modelos: { [string]: Modelo } = {
	Espada = {
		Anclaje = "ManoDerecha",
		Empunadura = true,
		Piezas = {
			{
				Tam = Vector3.new(0.25, 0.9, 0.25),
				Pos = Vector3.new(0, 0, 0),
				Material = Enum.Material.Wood,
				Color = CUERO,
			},
			{
				Tam = Vector3.new(1.1, 0.18, 0.3),
				Pos = Vector3.new(0, 0.5, 0),
				Material = Enum.Material.Metal,
				Color = ACERO,
			},
			{ Tam = Vector3.new(0.3, 3, 0.1), Pos = Vector3.new(0, 2.1, 0), Tinte = true, Efecto = true },
		},
	},
	Daga = {
		Anclaje = "ManoDerecha",
		Empunadura = true,
		Piezas = {
			{
				Tam = Vector3.new(0.22, 0.6, 0.22),
				Pos = Vector3.new(0, 0, 0),
				Material = Enum.Material.Wood,
				Color = CUERO,
			},
			{
				Tam = Vector3.new(0.7, 0.14, 0.25),
				Pos = Vector3.new(0, 0.35, 0),
				Material = Enum.Material.Metal,
				Color = ACERO,
			},
			{ Tam = Vector3.new(0.26, 1.6, 0.08), Pos = Vector3.new(0, 1.2, 0), Tinte = true, Efecto = true },
		},
	},
	Baculo = {
		Anclaje = "ManoDerecha",
		Piezas = {
			{
				Tam = Vector3.new(0.3, 5.2, 0.3),
				Pos = Vector3.new(0, 0.9, 0),
				Material = Enum.Material.Wood,
				Color = MADERA,
				Forma = Enum.PartType.Cylinder,
				Rot = Vector3.new(0, 0, 90),
			},
			{
				Tam = Vector3.new(0.75, 0.75, 0.75),
				Pos = Vector3.new(0, 3.7, 0),
				Forma = Enum.PartType.Ball,
				Tinte = true,
				Efecto = true,
			},
		},
	},
	Casco = {
		Anclaje = "Cabeza",
		Piezas = {
			{ Tam = Vector3.new(1.35, 0.7, 1.35), Pos = Vector3.new(0, 0.42, 0), Tinte = true },
			{ Tam = Vector3.new(0.18, 0.55, 0.1), Pos = Vector3.new(0, 0.05, -0.66), Tinte = true },
		},
	},
	CascoCuernos = {
		Anclaje = "Cabeza",
		Piezas = {
			{ Tam = Vector3.new(1.4, 0.75, 1.4), Pos = Vector3.new(0, 0.42, 0), Tinte = true, Efecto = true },
			{
				Tam = Vector3.new(0.22, 0.9, 0.22),
				Pos = Vector3.new(-0.62, 0.95, 0.1),
				Rot = Vector3.new(0, 0, 30),
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(235, 225, 200),
			},
			{
				Tam = Vector3.new(0.22, 0.9, 0.22),
				Pos = Vector3.new(0.62, 0.95, 0.1),
				Rot = Vector3.new(0, 0, -30),
				Material = Enum.Material.Marble,
				Color = Color3.fromRGB(235, 225, 200),
			},
			{ Tam = Vector3.new(0.2, 0.35, 0.5), Pos = Vector3.new(0, 0.85, 0.2), Tinte = true },
		},
	},
	Corona = {
		Anclaje = "Cabeza",
		Piezas = {
			{ Tam = Vector3.new(1.25, 0.3, 1.25), Pos = Vector3.new(0, 0.75, 0), Tinte = true },
			{ Tam = Vector3.new(0.2, 0.4, 0.2), Pos = Vector3.new(0, 1.05, -0.55), Tinte = true, Efecto = true },
			{ Tam = Vector3.new(0.2, 0.4, 0.2), Pos = Vector3.new(-0.55, 1.05, 0), Tinte = true },
			{ Tam = Vector3.new(0.2, 0.4, 0.2), Pos = Vector3.new(0.55, 1.05, 0), Tinte = true },
		},
	},
	Pechera = {
		Anclaje = "Torso",
		Piezas = {
			{ Tam = Vector3.new(2.1, 1.3, 1.15), Pos = Vector3.new(0, 0.15, 0), Tinte = true, Efecto = true },
			{ Tam = Vector3.new(0.9, 0.35, 1.2), Pos = Vector3.new(-0.8, 0.75, 0), Tinte = true },
			{ Tam = Vector3.new(0.9, 0.35, 1.2), Pos = Vector3.new(0.8, 0.75, 0), Tinte = true },
		},
	},
	Tunica = {
		Anclaje = "Torso",
		Piezas = {
			{ Tam = Vector3.new(2.05, 1.6, 1.1), Pos = Vector3.new(0, -0.05, 0), Tinte = true, Efecto = true },
			{
				Tam = Vector3.new(2.1, 0.2, 1.15),
				Pos = Vector3.new(0, -0.5, 0),
				Material = Enum.Material.Fabric,
				Color = CUERO,
			},
		},
	},
}

local Items: { [string]: VisualItem } = {
	EspadaHierro = { Modelo = "Espada", Color = ACERO, Material = Enum.Material.Metal },
	ColmilloReina = { Modelo = "Daga", Color = Color3.fromRGB(150, 220, 120), Material = Enum.Material.Glass },
	BaculoRoble = { Modelo = "Baculo", Color = Color3.fromRGB(110, 190, 255), Material = Enum.Material.Neon },
	CascoHierro = { Modelo = "Casco", Color = ACERO, Material = Enum.Material.Metal },
	CascoCuero = { Modelo = "Casco", Color = CUERO, Material = Enum.Material.Fabric },
	CoronaObsidiana = { Modelo = "Corona", Color = Color3.fromRGB(40, 30, 55), Material = Enum.Material.Glass },
	PecheraCuero = { Modelo = "Pechera", Color = CUERO, Material = Enum.Material.Fabric },
	TunicaLino = { Modelo = "Tunica", Color = Color3.fromRGB(215, 205, 175), Material = Enum.Material.Fabric },
}

local Apariencias: { [string]: Apariencia } = {
	EspadaLlameante = {
		Nombre = "Espada Llameante",
		Slot = "ArmaPrincipal",
		Modelo = "Espada",
		Color = Color3.fromRGB(255, 120, 40),
		Material = Enum.Material.Neon,
		Efecto = "Fuego",
		ColorEfecto = Color3.fromRGB(255, 140, 40),
	},
	BaculoArcano = {
		Nombre = "Báculo Arcano",
		Slot = "ArmaPrincipal",
		Modelo = "Baculo",
		Color = Color3.fromRGB(170, 90, 255),
		Material = Enum.Material.Neon,
		Efecto = "Chispas",
		ColorEfecto = Color3.fromRGB(200, 140, 255),
	},
	CascoDragon = {
		Nombre = "Casco de Dragón",
		Slot = "Casco",
		Modelo = "CascoCuernos",
		Color = Color3.fromRGB(150, 30, 30),
		Material = Enum.Material.Slate,
		Efecto = "Humo",
		ColorEfecto = Color3.fromRGB(90, 80, 80),
	},
}

return {
	Modelos = Modelos,
	Items = Items,
	Apariencias = Apariencias,
	-- Slots que se dibujan (los demás no tienen modelo todavía).
	SlotsVisibles = { "ArmaPrincipal", "ArmaSecundaria", "Casco", "Pechera" } :: { Types.SlotEquipo },
}
