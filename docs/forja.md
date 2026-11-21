# Forja: durabilidad, reparación, desencantar, reforjar y gemas

Servicios de herrería sobre el equipo. Reglas y números en `Configs/ForjaConfig.luau` (funciones puras que usan
el servidor para validar y el cliente para mostrar costos); servidor en `Systems/Economia/ForjaManager.luau`.
Se usan hablando con los NPC del Grupo B ([matriz](npcs-matriz.md)).

Todo se guarda en los metadatos del ítem (`Meta`), así que viaja con él por comercio, subastas, buzón y bóveda:

| Clave | Qué es |
|---|---|
| `Dur` | Durabilidad actual, 0 a 100. Sin valor = entera |
| `Reforjas` | Cuántas veces se reforjó |
| `Gema1`, `Gema2`, `Gema3` | Gema engarzada en cada ranura |

## Durabilidad (nuevo)

- Solo el **equipo** se desgasta (no las herramientas ni los cosméticos).
- Al **morir**, cada pieza equipada pierde 5 puntos.
- Al **recibir un golpe**, 4% de probabilidad de que una pieza al azar pierda 1 punto.
- El juego avisa cuando una pieza baja de 20 y cuando se rompe.
- Con durabilidad **0 la pieza no da estadísticas** (ni atributos, ni efectos, ni pasiva, ni gemas) hasta repararla.
  No se destruye ni se desequipa.

## NPC-009 Reparador de Armaduras

Dos servicios: **Reparar lo equipado** y **Reparar todo** (suma lo de la mochila). El costo es por punto
reparado, según la rareza: Común 0,5 · Raro 1 · Épico 2 · Místico 3,5 · Único 5 de oro. La ventana muestra el
costo exacto para ese jugador. No se repara en combate.

### Reparación de campo (tarifa de emergencia)

Arreglar lo que llevás puesto **sin volver hasta el NPC**, desde el pie del panel de equipo de la mochila. Lo
que se paga es la comodidad: cuesta el **triple** de lo que cobraría el Reparador y se puede usar **una vez cada
15 minutos**. Sigue sin funcionar en combate — se paga no volver a la ciudad, no arreglarse en medio de una
pelea — y no se cobra si al equipo le faltan menos de 5 puntos en total.

El descuento de la raza Artesano se aplica **antes** del recargo, así que también vale acá. La espera se marca
recién después de cobrar: si no alcanzaba el oro, no se gasta el uso. El botón muestra el precio calculado en el
cliente, pero el servidor lo vuelve a calcular y es el que cobra.

## NPC-011 Desencantador

Destruye un equipo **Raro o mejor** de la mochila (lo equipado no se toca) por 25 de oro y devuelve esencias.
Pide confirmación con un segundo clic.

| Rareza | Devuelve |
|---|---|
| Raro | 2 Polvo de Encantamiento |
| Épico | 2 Esencia Mágica + 1 Polvo de Encantamiento |
| Místico | 1 Esencia Mayor + 2 Esencia Mágica |
| Único | 1 Fragmento de Reliquia + 2 Esencia Mayor |

El equipo Común no se desencanta: lo desmantela el Chatarrero en su Yunque Portátil. La Esencia Mayor y el
Fragmento de Reliquia todavía no tienen uso (quedan para runas y recetas altas).

## NPC-012 Reforjador de Atributos

Cambia **cuáles** son los efectos secundarios de un equipo (prefiere efectos que no tenía). Conserva la calidad,
la pasiva, las gemas y la durabilidad. Cuesta 2 Polvo de Encantamiento y oro según la rareza: 500 · 1.500 ·
4.000 · 10.000, con 25% de recargo por cada reforja anterior del mismo ítem (tope +300%). Pide confirmación y deja
registro en el log del servidor.

**Vista previa.** Antes de pagar, la ventana muestra qué efectos tiene el ítem ahora, cuánto encarece la reforja
lo que ya se reforjó, cuántos efectos va a sacar y la lista de los que pueden salir, con los que todavía no tiene
primero. Lo que **no** muestra es el resultado, y es a propósito: el sorteo pasa en el servidor al confirmar, así
que no hay forma de mirar el premio y decidir después.

La **Ficha de Re-roll** de la tienda es otra cosa: vuelve a tirar los valores y la calidad, sin cambiar qué
efectos son.

## NPC-010 Maestro Encantador

Engarza gemas. Ranuras por rareza: Raro 1 · Épico 2 · Místico 2 · Único 3. Cuesta 300 de oro, 1 Esencia Mágica y
la gema.

**Sacar gema** devuelve la gema entera a la mochila: 400 · 900 · 1.800 · 3.500 de oro según la rareza, más 1
Polvo de Encantamiento. Cuesta más que ponerla a propósito: si fuera barato, mover gemas de un ítem a otro
saldría casi gratis. La ventana muestra las gemas del ítem y se elige cuál sacar, con confirmación. Las que
quedan **se corren** para no dejar huecos, porque las ranuras libres se cuentan por cuántas gemas hay y un hueco
haría desaparecer las de atrás. Si la gema no entra en la mochila (no debería: se revisa antes), va al buzón.

| Gema | Efecto |
|---|---|
| Rubí | +6 ataque |
| Amatista | +6 poder |
| Zafiro | +8 defensa |
| Esmeralda | +2 maná por segundo |
| Diamante | +3% de crítico |

Las gemas se compran en el Mercado Negro o al Intendente de Guerra (Diamante, por honor).

## NPC-013 Fundidor

Además de fundir minerales, nueva receta de Herrería 8 en el Yunque: **5 lingotes de hierro → 1 de plata**.

## Seguridad

- El cliente manda solo la operación, la ranura y (para engarzar) la gema. Costos, resultados y sorteos son del
  servidor.
- Cada operación verifica todo antes de tocar nada (que el ítem sirva, oro, materiales, lugar en la mochila) y
  después cobra y aplica sin ceder el hilo: no puede quedar a medias.
- El servidor revalida NPC, distancia y facción en cada pedido, como en el resto de los NPC.

## Pruebas

`python3 tests/run.py` cubre las reglas puras: durabilidad por defecto y límites, costo de reparación, qué ítems
acepta cada operación, recargo de la reforja y coherencia de gemas, esencias y rarezas. También que sacar una
gema cueste más que ponerla y corra las que quedan sin dejar huecos, que la tarifa de campo sea más cara que ir
al NPC y nunca salga gratis, y que la vista previa de la reforja liste todos los efectos posibles sin adelantar
ninguno. El desgaste en combate y
las operaciones contra el perfil hay que probarlos en Studio.
