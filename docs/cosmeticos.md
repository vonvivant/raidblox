# Cosméticos: barbero, transfigurador y mascotas

Grupo F de los 39 NPC: Barbero (029), Transfigurador (030), Tintorero (031) y Vendedor de Mascotas (032).

**Sin probar en Studio.** Pasa el chequeo de tipos, el lint y las pruebas de datos.

## Barbero (NPC-029)

Cambia el estilo del personaje por **100 de oro** por cambio. La ventana (`BarberoUI`) muestra el color de piel al
instante sobre tu propio personaje (solo para vos) y recién al confirmar el servidor cobra y lo guarda.

| Qué | Estado |
|---|---|
| **Color de piel** (9 opciones, incluida "el de mi avatar") | Funciona |
| **Peinados** (corto, largo, trenza, rapado) | Falta subir los accesorios |
| **Marcas faciales** (cicatriz, pintura de guerra, tatuaje rúnico) | Falta subir los accesorios |

Los peinados y las marcas son accesorios del Catálogo de Roblox: hay que subirlos y poner su id en
`AparienciaConfig.Barbero.Peinados` / `.Marcas`. Mientras el id sea 0, la opción aparece como "próximamente" y el
servidor la rechaza. No hay forma de hacer peinados sin assets.

El estilo se guarda en `DatosJugador.Apariencia` y lo aplica `AparienciaManager` con la `HumanoidDescription`, junto
con el género: sobrevive a morir, reaparecer y volver a entrar, y lo ven todos los jugadores.

## Transfigurador (NPC-030)

Abre la pestaña **Colección** de la tienda, donde ya estaba el sistema de apariencias de equipo (transmog): se
elige qué apariencia usa cada pieza, de las desbloqueadas, sin tocar las estadísticas.

## Vendedor de Mascotas (NPC-032)

Tres mascotas nuevas que se compran con oro, además de Lumi y Brasa (que siguen siendo del pase de batalla):

| Mascota | Precio |
|---|---|
| Hojita | 2.500 de oro |
| Piedrín | 4.000 de oro |
| Lucero | 9.000 de oro |

Hacen lo mismo que las del pase: acompañan y juntan el botín cercano. Se equipan en la Colección (el NPC también
la abre). Van en `MascotasConfig.Mascotas` con el campo `Precio`.

## Tintorero (NPC-031)

Vuelve a pintar el equipo **que ya tenés**. Al hablarle y elegir "Volver a pintar mi equipo" se abre el mismo
probador del [vendedor personalizador](personalizador.md), pero en **modo retoque**:

- El panel izquierdo lista **tus objetos** (los de la mochila que tengan modelo), no el catálogo de venta.
- La vista previa arranca con la personalización que el objeto ya tiene.
- Se cambia el **color** de cada pieza; el material queda como está (para cambiarlo, el Maestro Personalizador).
- Se paga **40 de oro por pieza que cambia** respecto de cómo está hoy. Volver una pieza a su color original
  también cuenta como cambio.
- Al confirmar no llega un objeto nuevo: se actualiza el que elegiste (su `Meta.Pers`), así que conserva su Uid,
  su durabilidad y sus gemas.

El servidor valida que el objeto siga en tu mochila, que la personalización sea válida y que el material no
cambie; el precio lo calcula él y, si no coincide con el que viste, no cobra y te pide confirmar de nuevo. Los
reintentos usan el mismo id de pedido, así que no se cobra dos veces.

Esto también cierra el pedido de **re-personalizar un ítem ya comprado**. Un NPC "Maestro de Armas" o "Maestro de
Armaduras" se arma poniendo el tag `NpcPersonalizador` con el atributo `Categoria`.
