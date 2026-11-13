--!strict
-- HabilidadTipos: tipos de las habilidades y sus efectos. Están en un módulo
-- aparte para que ClassConfig y las clases con archivo propio (Chatarrero)
-- los compartan sin requerirse entre sí.

export type Stat = "Ataque" | "Poder" | "Defensa"

export type Efecto =
	{ Tipo: "Danio", Escuela: "Fisico" | "Magico", Base: number, Escala: Stat, Factor: number }
	| { Tipo: "Cura", Base: number, Factor: number }
	| { Tipo: "CuraTiempo", Base: number, Factor: number, Duracion: number, Intervalo: number }
	| {
		Tipo: "DanioTiempo",
		Escuela: "Fisico" | "Magico",
		Base: number,
		Escala: Stat,
		Factor: number,
		Duracion: number,
		Intervalo: number,
	}
	| { Tipo: "Aturdir", Duracion: number }
	| { Tipo: "Provocar", Duracion: number }
	-- Porcentaje negativo = debilita (se muestra como debuff).
	| { Tipo: "Aura", Stat: Stat, Porcentaje: number, Duracion: number }
	| { Tipo: "Invisible", Duracion: number }
	-- Empuja al objetivo lejos de quien lanza (solo NPCs que no sean jefes).
	| { Tipo: "Empujar", Fuerza: number }
	-- Corta el casteo del objetivo.
	| { Tipo: "Interrumpir" }
	-- Devuelve maná / stamina.
	| { Tipo: "Recurso", Cantidad: number }
	-- Escudo que absorbe daño.
	| { Tipo: "Escudo", Base: number, Duracion: number }
	-- Los golpes de quien lo tiene ignoran la defensa del objetivo.
	| { Tipo: "IgnorarArmadura", Duracion: number }
	-- Recibe `Porcentaje` % menos de daño.
	| { Tipo: "Reduccion", Porcentaje: number, Duracion: number }
	-- No puede usar habilidades (los jefes no lanzan sus ataques especiales).
	| { Tipo: "Silenciar", Duracion: number }
	-- El NPC (no jefe) deja de perseguir a quien lanza.
	| { Tipo: "PerderAgro", Duracion: number }
	-- No se puede mover (sí atacar).
	| { Tipo: "Inmovilizar", Duracion: number }

-- A quién afecta la habilidad:
--   Enemigo / Aliado: un objetivo seleccionado (Aliado acepta al propio jugador).
--   Propio: solo quien la lanza.
--   AreaEnemigos / AreaAliados: todos en `Radio` alrededor de `Centro`.
export type TipoObjetivo = "Enemigo" | "Aliado" | "Propio" | "AreaEnemigos" | "AreaAliados"

export type Calidad = "Comun" | "Inusual" | "Rara" | "Epica" | "Legendaria"

export type Habilidad = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	CostoMana: number, -- maná o stamina, según el recurso de la clase
	Cooldown: number, -- segundos
	Rango: number, -- studs hasta el objetivo (o hasta el centro del área)
	TiempoCasteo: number, -- 0 = instantánea
	Objetivo: TipoObjetivo,
	Centro: ("Objetivo" | "Propio")?, -- solo áreas
	Radio: number?, -- solo áreas y auras
	Efectos: { Efecto },
	-- Opcionales (clases con barras de habilidades, como el Chatarrero):
	Numero: number?, -- número en el catálogo de la clase
	Calidad: Calidad?,
	Categoria: number?, -- barra a la que pertenece (1..4)
	EfectosPropios: { Efecto }?, -- se aplican a quien la lanza
	Cono: number?, -- áreas centradas en uno mismo: medio ángulo (grados) hacia adelante
	ObjetivoOpcional: boolean?, -- "Enemigo" que también se puede usar sin objetivo
	Especial: string?, -- mecánica propia, registrada con CombatManager.RegistrarEspecial
	Pendiente: string?, -- sistema que falta para el efecto original (hoy usa uno parecido)
}

return nil
