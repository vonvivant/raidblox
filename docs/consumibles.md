# Consumibles con efecto y mejoras temporales

Las pociones simples de vida y maná siguen como antes (`ItemCatalog.Consumo`). Este sistema agrega los consumibles
con efecto propio y las mejoras temporales que dan los NPC. Módulos: `Configs/ConsumiblesConfig.luau` (datos) y
`Systems/Combate/BuffManager.luau` (servidor). Se usan igual que una poción: desde la mochila.

## Dos clases

| Clase | Ejemplos | Regla |
|---|---|---|
| **Instantáneos** | Poción de Regeneración, Poción de Vitalidad, Antídoto | Hacen su efecto en el momento y comparten la recarga de las pociones (10 s) |
| **Temporales** | Elixires, tónicos, infusiones, arma afilada | Quedan activos por su duración |

## Reglas de acumulación (temporales)

- **Uno solo activo por categoría.** Tomar otro de la misma categoría lo reemplaza (el juego avisa cuál reemplazó).
- **Categorías distintas se suman**: se puede tener a la vez un elixir, un tónico, una infusión y el arma afilada.
- La reducción de recargas sumada nunca pasa de 30% (`PrisaMaxima`).
- **No se pierden** al morir, cambiar de zona o desconectarse: se guardan en el perfil (`Buffs`) con su hora de
  vencimiento y se vuelven a aplicar al reaparecer con el tiempo que les queda. El tiempo corre aunque el jugador
  esté desconectado.
- El ítem se gasta **solo si el efecto se aplicó** (un Antídoto sin nada que curar no se consume).

## Catálogo

| Ítem | Categoría | Efecto | Lo vende | Receta (Alquimia) |
|---|---|---|---|---|
| Poción de Regeneración | Instantáneo | Cura 4% de la vida cada 2 s por 20 s | Boticario | Nivel 2 |
| Antídoto | Instantáneo | Quita debilitamientos, sangrados y quemaduras | Boticario | Nivel 3 |
| Poción de Vitalidad | Instantáneo | Escudo por 20% de la vida máxima, 60 s | Boticario | Nivel 4 |
| Tónico de Energía | Tónico | +3% de maná o stamina cada 5 s, 5 min | Boticario Espiritual | Nivel 3 |
| Tónico de Enfoque | Tónico | -10% a las recargas, 2 min | Boticario Espiritual | Nivel 5 |
| Elixir de Fuerza | Elixir | +15% de ataque, 10 min | Alquimista | Nivel 5 |
| Elixir de Resistencia | Elixir | +15% de defensa, 10 min | Alquimista | Nivel 5 |
| Elixir de Agilidad | Elixir | -10% a las recargas, 10 min | Alquimista | Nivel 6 |
| Poción Experimental | Elixir | 5 min. 65%: +25% de ataque y poder. 35%: -15% de defensa | Alquimista | Nivel 6 |
| Mezcla Inestable | Elixir | +30% de ataque y -20% de defensa, 5 min | Alquimista | Nivel 8 |
| Té de Manantial | Infusión | +2% de maná o stamina cada 5 s, 15 min | Barista de Tés | Nivel 1 |
| Té de Raíces | Infusión | +10% de defensa, 15 min | Barista de Tés | Nivel 2 |
| Té de Jazmín Lunar | Infusión | -6% a las recargas, 15 min | Barista de Tés | Nivel 4 |
| (Afilar el arma) | Filo | +10% de ataque, 10 min | Servicio del Afilador | — |

Material nuevo: **Agua de Manantial** (lo vende el Barista; va en tés y tónicos).

## Riesgo

La Poción Experimental se sortea **en el servidor** al tomarla, y sus probabilidades están escritas en la
descripción del ítem. El resultado se guarda con el buff, así que reaparecer no lo vuelve a sortear.

## Aproximaciones (para no inventar sistemas que no existen)

- "Vitalidad temporal" es un escudo que absorbe daño, no vida máxima extra.
- "Agilidad" y "velocidad de lanzamiento" son reducción de recargas (el combate no tiene velocidad de casteo ni
  agilidad modificable por buffs).
- "Resistencia a estados negativos" del té es +defensa; quitar estados lo hace el Antídoto.

## Agregar un consumible nuevo

1. El ítem en `ItemCatalog` (Tipo `Consumible`, con `Descripcion`).
2. Su definición en `ConsumiblesConfig.Definiciones` con la **misma clave**.
3. Opcional: receta en `ProfesionesConfig.Recetas` y oferta en el `Vende` de un NPC.
4. `python3 tests/run.py` revisa que todo cierre.

## En el combate

`CombatManager` no conoce a `BuffManager` (evita dependencia circular); este le registra dos ganchos:
`SetPrisa` (fracción que se descuenta de las recargas) y `SetEfectosExtra` (efectos que se muestran con los buffs
del marco del jugador). Además se agregaron `CombatManager.JugadorListo`, `QuitarAuras` y `Purificar`.
