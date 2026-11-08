--!strict
-- VisualConfig: cómo se ve cada habilidad (animación y efectos). Solo visual:
-- el daño, el alcance y los tiempos los decide el servidor con ClassConfig.
--
-- Anim:        animación del que la usa (ver VisualesCombate: Tajo, Golpe,
--              Estocada, Pesado, Giro, Grito, Pisoton, Guardia, Lanzar,
--              Bendecir, Disparo, Zarpazo).
-- AnimCasteo:  animación en bucle mientras castea (Conjurar, Apuntar, Rezo).
-- AnimacionId: opcional. Si subís una animación hecha en el Animation Editor
--              ("rbxassetid://..."), se usa esa en lugar de la de código.
-- Arma:        color de la estela del arma durante el golpe.
-- Proyectil:   Orbe | Flecha | Espina, con color y velocidad (studs/s).
-- Impacto:     efecto sobre cada alcanzado: Chispas | Explosion | Veneno |
--              Hielo | Raices | Curacion | Escudo.
-- Area:        efecto en el centro del área: Onda | Meteoro | Lluvia |
--              Torbellino | Aura | Humo.
-- Haz:         rayo de luz del que la usa al objetivo (curas, provocación).
-- Casteo:      color del círculo mágico mientras castea.

export type Visual = {
	Anim: string?,
	AnimCasteo: string?,
	AnimacionId: string?,
	Arma: Color3?,
	Proyectil: { Estilo: "Orbe" | "Flecha" | "Espina", Color: Color3, Velocidad: number, Tamano: number? }?,
	Impacto: { Estilo: string, Color: Color3 }?,
	Area: { Estilo: string, Color: Color3 }?,
	Haz: Color3?,
	Casteo: Color3?,
}

local BLANCO = Color3.fromRGB(240, 245, 255)
local ORO = Color3.fromRGB(255, 205, 80)
local FUEGO = Color3.fromRGB(255, 120, 30)
local ARCANO = Color3.fromRGB(170, 100, 255)
local HIELO = Color3.fromRGB(150, 220, 255)
local VERDE = Color3.fromRGB(90, 230, 110)
local VENENO = Color3.fromRGB(120, 220, 60)
local ROJO = Color3.fromRGB(235, 50, 60)
local AZUL = Color3.fromRGB(80, 150, 255)
local TIERRA = Color3.fromRGB(150, 110, 70)
local CIAN = Color3.fromRGB(80, 230, 230)
local ROSA = Color3.fromRGB(255, 140, 200)

local VisualConfig: { [string]: Visual } = {
	-- Tanque
	GolpeDefensivo = { Anim = "Golpe", Arma = BLANCO, Impacto = { Estilo = "Chispas", Color = BLANCO } },
	Provocacion = { Anim = "Grito", Haz = ROJO, Impacto = { Estilo = "Chispas", Color = ROJO } },
	Terremoto = { Anim = "Pisoton", Area = { Estilo = "Onda", Color = TIERRA } },
	Muralla = { Anim = "Guardia", Impacto = { Estilo = "Escudo", Color = AZUL } },
	-- Guerrero
	Tajo = { Anim = "Tajo", Arma = BLANCO, Impacto = { Estilo = "Chispas", Color = BLANCO } },
	GolpeBrutal = { Anim = "Pesado", Arma = FUEGO, Impacto = { Estilo = "Explosion", Color = FUEGO } },
	Torbellino = { Anim = "Giro", Arma = BLANCO, Area = { Estilo = "Torbellino", Color = BLANCO } },
	GritoGuerra = { Anim = "Grito", Area = { Estilo = "Aura", Color = ROJO } },
	-- Mago
	ProyectilArcano = {
		Anim = "Lanzar",
		Proyectil = { Estilo = "Orbe", Color = ARCANO, Velocidad = 90 },
		Impacto = { Estilo = "Chispas", Color = ARCANO },
	},
	BolaFuego = {
		AnimCasteo = "Conjurar",
		Casteo = FUEGO,
		Anim = "Lanzar",
		Proyectil = { Estilo = "Orbe", Color = FUEGO, Velocidad = 70, Tamano = 1.8 },
		Impacto = { Estilo = "Explosion", Color = FUEGO },
	},
	NovaEscarcha = {
		Anim = "Pisoton",
		Area = { Estilo = "Onda", Color = HIELO },
		Impacto = { Estilo = "Hielo", Color = HIELO },
	},
	Meteoro = { AnimCasteo = "Rezo", Casteo = ROJO, Anim = "Lanzar", Area = { Estilo = "Meteoro", Color = FUEGO } },
	-- Arquero
	Disparo = { Anim = "Disparo", Proyectil = { Estilo = "Flecha", Color = BLANCO, Velocidad = 140 } },
	DisparoCertero = {
		AnimCasteo = "Apuntar",
		Casteo = ORO,
		Anim = "Disparo",
		Proyectil = { Estilo = "Flecha", Color = ORO, Velocidad = 190 },
		Impacto = { Estilo = "Chispas", Color = ORO },
	},
	FlechaVenenosa = {
		Anim = "Disparo",
		Proyectil = { Estilo = "Flecha", Color = VENENO, Velocidad = 140 },
		Impacto = { Estilo = "Veneno", Color = VENENO },
	},
	LluviaFlechas = { Anim = "Disparo", Area = { Estilo = "Lluvia", Color = BLANCO } },
	-- Asesino
	Punalada = {
		Anim = "Estocada",
		Arma = Color3.fromRGB(200, 200, 210),
		Impacto = { Estilo = "Chispas", Color = ROJO },
	},
	Veneno = { Anim = "Estocada", Arma = VENENO, Impacto = { Estilo = "Veneno", Color = VENENO } },
	Sombras = { Anim = "Guardia", Area = { Estilo = "Humo", Color = Color3.fromRGB(60, 50, 80) } },
	Ejecucion = { Anim = "Pesado", Arma = ROJO, Impacto = { Estilo = "Explosion", Color = ROJO } },
	-- Healer
	Castigo = {
		Anim = "Lanzar",
		Proyectil = { Estilo = "Orbe", Color = ORO, Velocidad = 90 },
		Impacto = { Estilo = "Chispas", Color = ORO },
	},
	Sanar = {
		AnimCasteo = "Conjurar",
		Casteo = VERDE,
		Anim = "Bendecir",
		Haz = VERDE,
		Impacto = { Estilo = "Curacion", Color = VERDE },
	},
	Renovar = { Anim = "Bendecir", Impacto = { Estilo = "Curacion", Color = Color3.fromRGB(160, 255, 170) } },
	Plegaria = {
		AnimCasteo = "Rezo",
		Casteo = ORO,
		Anim = "Grito",
		Area = { Estilo = "Aura", Color = ORO },
		Impacto = { Estilo = "Curacion", Color = ORO },
	},
	-- Druida
	Espinas = {
		Anim = "Lanzar",
		Proyectil = { Estilo = "Espina", Color = Color3.fromRGB(70, 140, 50), Velocidad = 100 },
		Impacto = { Estilo = "Chispas", Color = VERDE },
	},
	Rejuvenecer = { Anim = "Bendecir", Impacto = { Estilo = "Curacion", Color = VERDE } },
	Raices = { Anim = "Lanzar", Impacto = { Estilo = "Raices", Color = TIERRA } },
	Florecer = { Anim = "Bendecir", Haz = ROSA, Impacto = { Estilo = "Curacion", Color = ROSA } },
	-- Buffer
	GolpeRunico = {
		Anim = "Lanzar",
		Proyectil = { Estilo = "Orbe", Color = CIAN, Velocidad = 95 },
		Impacto = { Estilo = "Explosion", Color = CIAN },
	},
	AuraFuerza = { Anim = "Grito", Area = { Estilo = "Aura", Color = ROJO } },
	AuraProteccion = { Anim = "Guardia", Area = { Estilo = "Aura", Color = AZUL } },
	Inspiracion = { Anim = "Grito", Area = { Estilo = "Aura", Color = ORO } },
	-- Enemigos
	AtaqueNpc = { Anim = "Zarpazo", Impacto = { Estilo = "Chispas", Color = BLANCO } },
}

return VisualConfig
