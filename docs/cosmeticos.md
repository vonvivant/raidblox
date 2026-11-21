# Cosméticos

> **El NPC Cosméticos (#30)** es desde ahora el único lugar donde se cambia el aspecto del equipo que tenés
> **puesto**: visual, colores, decals y marcas, con vista previa de tu personaje. Absorbió al Transfigurador
> (su número y su puesto son los mismos) y al **Tintorero (#31)**, que ya no atiende por su cuenta; el
> **Inscriptor (#5)** se quedó con los pergaminos y con la venta de los libros que desbloquean los decals.
> Detalle de las pestañas y del costo de deshacer: [personalizador](personalizador.md) y la config
> `CosmeticosConfig`.

Grupo F de los 39 NPC: Barbero (029), Cosméticos (030, antes Transfigurador), Tintorero (031, absorbido por el
anterior) y Vendedor de Mascotas (032).

## El NPC Cosméticos (#30)

Reglas en `Configs/CosmeticosConfig.luau`, servidor en `Systems/Economia/CosmeticosManager.luau`, ventana en
`CosmeticosUI`. Trabaja sobre los **ítems equipados** en los slots visibles (arma principal, secundaria, casco y
pechera).

Al hablarle se abre una **cámara mirando a tu personaje**, con dos paneles a los costados y el medio libre: a la
izquierda los slots y las piezas del objeto elegido, a la derecha las cuatro pestañas. La cámara gira sola
despacio, se arrastra con el mouse y se acerca con la rueda.

| Pestaña | Qué hace |
| --- | --- |
| Visual | Le cambia el aspecto al objeto sin tocar sus estadísticas, con las apariencias desbloqueadas (el transmog de siempre) |
| Colores | El color de cada pieza |
| Decals | Calcomanías de color, agrupadas en Rasguños, Adornos, Símbolos y Bestias |
| Marcas | Grabados con normal map (solo en piezas que son mallas) |

**Vista previa de verdad.** Los cambios de color, decal y marca se dibujan al instante sobre el modelo que ya
lleva tu personaje, con el mismo código que usa el equipo real (`Personalizador.Aplicar`), así que lo que ves es
lo que vas a tener. Nada se guarda hasta que apretás *Aplicar*, y cerrar la ventana descarta lo pendiente.

**Qué se paga.** Aplicar lo que ya tenés desbloqueado es **gratis**, y cambiar de visual también: podés probar
todo lo que quieras. Lo que cuesta es **deshacer**, o sea pedirle al NPC que devuelva el slot al estado exacto
que tenía antes del último cambio:

| Deshacer | Costo |
| --- | --- |
| El primero | gratis |
| El segundo | 2.500 de oro |
| El tercero | 5.000 |
| El cuarto | 10.000 |
| … | el doble del anterior, hasta 320.000 |

El contador es del jugador y no se reinicia. Por eso la cámara importa: la idea es decidir mirando el preview, no
probando a ciegas. Deshacer es un **solo paso atrás** por slot: antes de cada cambio el servidor guarda una foto
de ese slot (su personalización y su visual) y deshacer la restaura y la consume.

**Qué valida el servidor.** Que estés junto al NPC en cada pedido, que el slot sea uno de los visibles, y que
cada pestaña solo toque lo suyo: un pedido que llegue por la pestaña de colores y de paso traiga un decal se
rechaza. El material no se cambia acá (eso se elige al comprar el objeto, con el Maestro Personalizador).

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
