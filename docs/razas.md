# Razas

Dos razas: **Humano** (la de por defecto) y **Artesano**. Reglas en `Configs/RazasConfig.luau`, servidor en
`Systems/RazaManager.luau`, y se elige en el panel **Personaje**.

La raza **no toca el combate**: eso es cosa de la clase. Lo que cambia son cosas de oficio y de economía, así
que elegir raza nunca es elegir "la que pega más fuerte". Hay una prueba que verifica que ninguna raza tenga
campos de ataque, defensa, poder, vida, maná o velocidad, para que eso no se cuele más adelante.

| Raza | Qué le da |
| --- | --- |
| Humano | +10% de oro cuando un NPC te compra algo |
| Artesano | Firma con su nombre el equipo que fabrica · +5% de probabilidad de obra maestra · 25% menos en reparaciones |

## Elegirla

Se elige en el panel Personaje. La **primera vez es gratis**; cambiarla después cuesta **5.000 de oro** y hay
una hora de espera entre cambios. No se cambia en combate. Se guarda en `DatosJugador.Raza` (sección
sincronizada `Raza`), con la hora del último cambio.

Si el perfil trae una raza que ya no existe (porque se sacó del config), el jugador juega como la de por
defecto en vez de quedarse sin nada.

## Firma de autoría

Es lo que distingue al Artesano: **el equipo que fabrica lleva su nombre** en `Meta.Autor`. No es decorativo:
la [bóveda](vault.md) ya permite buscar por ese campo, así que se puede juntar lo hecho por tal persona, y el
nombre viaja con el ítem cuando se vende o se regala. Solo los ítems de tipo Equipo se firman (una poción con
autor no tiene sentido), y el nombre se corta a 24 caracteres.

## Cómo está enganchado

`RazaManager` no modifica ningún sistema: cada uno expone un registro y pregunta. Así se puede sacar la raza
sin romper nada.

| Sistema | Gancho | Para qué |
| --- | --- | --- |
| `NpcManager` | `RegistrarBonusVenta` | lo que paga un NPC por tu ítem |
| `CraftingManager` | `RegistrarBonusMasterpiece` | probabilidad de obra maestra |
| `CraftingManager` | `RegistrarFirma` | `Meta.Autor` al fabricar equipo |
| `ForjaManager` | `RegistrarDescuentoReparacion` | el costo de reparar |

## Lo que falta

- **Más razas**: con dos alcanza para que la elección signifique algo, pero el sistema admite las que se
  quieran agregar sin tocar código.
- **Aspecto propio** por raza (hoy la raza no cambia cómo se ve el personaje).
- Nada se probó en Studio: las pruebas cubren los bonos, los topes, la firma y los plazos del cambio.
