# NPC vendedor y personalizador 3D

El jugador habla con el vendedor, se prueba un arma o armadura sobre su propio avatar, le cambia material y color
pieza por pieza, ve el precio y la compra. El ítem que recibe guarda esa personalización y la conserva al
equiparlo, comerciarlo, guardarlo en la bóveda o volver a entrar.

**Estado:** implementado, **sin probar en Roblox Studio**. Pasa el chequeo de tipos estricto, el lint y las pruebas
automáticas de las reglas puras (formato, validadores y precio). La matriz de pruebas está al final.

## A. Auditoría: qué había y qué se reutiliza

| Sistema del juego | Cómo se usa acá |
|---|---|
| Perfil con ProfileStore (sesión única, guardado periódico y al salir) | El oro, el ítem comprado y el registro de la compra se guardan en el mismo perfil |
| Inventario (`ItemInstancia` con `Uid`, `ItemId`, `Rareza`, `Meta`) | El ítem comprado es un ítem normal; la personalización va en `Meta.Pers` |
| `ItemCatalog` | Estadísticas y slot del ítem. Un modelo solo se vende si su `ItemID` es un equipo del catálogo |
| `NetworkBridge` (remotes declarados, `Guard`, límite de frecuencia) | Cuatro remotes nuevos |
| `EquipoVisible` (dibuja el equipo puesto, en el servidor) | Ahora dibuja el modelo personalizado si el ítem tiene uno |
| `NpcFactory`, `UIKit`, `Avisos`, `EstadoCliente` | NPC de prueba e interfaz |

No se creó un inventario ni una moneda paralelos, y no hay ningún bloque "conectar acá tu sistema": ya está
conectado al del juego. Personajes: R15 (con respaldo para R6 en manos y torso).

**Lo que el juego no tiene:** modelos 3D propios de armas y armaduras. Hasta que los subas, el servidor arma al
arrancar un modelo de relleno por cada ítem que ya se dibujaba con piezas simples (espada, daga, báculo, cascos,
corona, pechera, túnica), con el mismo aspecto de antes. Son placeholders, no arte final.

## B. Arquitectura

- **El cliente solo muestra y pide.** La vista previa es un clon local; el servidor nunca recibe modelos, precios
  ni propiedades: recibe el `ItemID`, un id de pedido y, por pieza, un nombre de material y un color `RRGGBB`.
- **Un mismo módulo compartido** (`Modules/Personalizador`) calcula los ids de las piezas, aplica la
  personalización y monta el modelo, tanto en el probador (cliente) como en el equipo real (servidor). Por eso lo
  que se ve en la vista previa es lo que se entrega.
- **Reglas puras aparte** (`Configs/PersonalizadorConfig`): formato guardado, validadores y precio. Se prueban
  fuera de Roblox.
- **La compra es una sola operación** sobre un solo perfil, sin ceder el hilo entre verificar, entregar, cobrar y
  registrar.

## C. Archivos

```text
default.project.json                              carpetas CustomizableItems/Armas y /Armaduras (Rojo no borra lo que agregues en Studio)
src/ReplicatedStorage/
├── Configs/PersonalizadorConfig.luau             configuración, tipos, formato y validadores puros
└── Modules/Personalizador.luau                   materiales, catálogo, ids de piezas, aplicar y montar
src/ServerScriptService/Systems/
├── Economia/PersonalizadorManager.luau           catálogo, NPC, presupuesto, compra, idempotencia, auditoría
└── EquipoVisible.luau                            dibuja el modelo personalizado del ítem equipado
src/StarterPlayer/StarterPlayerScripts/
└── PersonalizadorUI.client.luau                  tienda, probador, cámara y edición
tests/personalizador.spec.luau                    pruebas de las reglas puras
```

En el juego: `ReplicatedStorage.CustomizableItems.Armas` y `.Armaduras` (modelos), y los NPC con el tag
`NpcPersonalizador`. Los remotes los crea `NetworkBridge` (no se duplican): `PersonalizadorAbrir`,
`PersonalizadorCerrar`, `PersonalizadorPresupuesto`, `PersonalizadorComprar`.

## D. Código

Está completo en los archivos de arriba, todos con `--!strict`.

## E. Cómo preparar un modelo

1. Poné el `Model` en `ReplicatedStorage.CustomizableItems.Armas` o `.Armaduras`. No hay que registrarlo en
   ningún script: aparece solo en el catálogo.
2. Atributos del modelo:

| Atributo | Obligatorio | Qué es |
|---|---|---|
| `ItemID` | Sí | Clave del ítem en `ItemCatalog` (tiene que ser un equipo). Única entre todos los modelos |
| `BasePrice` | Sí | Precio base en oro (0 o más) |
| `DisplayName` | No | Nombre visible. Por defecto, el del catálogo |
| `Description` | No | Descripción |
| `ItemType` | No | `Arma` o `Armadura`; si está, tiene que coincidir con la carpeta |
| `EquipSlot` | No | Si está, tiene que coincidir con el slot del catálogo |
| `RequiredLevel` | No | Nivel mínimo (por defecto 1) |
| `Anclaje` | Según el slot | Dónde se monta: `ManoDerecha`, `ManoIzquierda`, `Cabeza`, `Torso` o el nombre de una parte del cuerpo (`LeftFoot`, `RightLowerArm`…). Arma, casco y pechera tienen montaje por defecto; el resto de los slots lo necesita |

3. **Handle:** una pieza llamada `Handle` (o la `PrimaryPart`), normalmente invisible. Es el punto de montaje: se
   alinea con la mano, la cabeza o el torso, y las demás piezas conservan su posición respecto de ella. Para un
   arma, poné el Handle donde va la mano, con la hoja hacia adelante (−Z del Handle).
4. **Piezas editables:** toda `Part` o `MeshPart` visible, a cualquier profundidad. Para excluir una (colisiones,
   piezas técnicas), ponele el atributo `NoEditable = true` o dejala con transparencia 1. Máximo 32 por modelo.
5. **Varias partes del cuerpo** (hombreras, guantes, botas): agrupá las piezas en un `Model` hijo con su propio
   atributo `Anclaje` y su propio `Handle`.
6. **Nombres:** letras, números, espacio, guion, punto y `_`. Dos piezas pueden llamarse igual: se distinguen por
   su ruta (`Guarda/Gema`) y, si coinciden, por posición (`Gema`, `Gema#2`).
7. **Sin scripts** adentro del modelo.

Si un modelo está mal configurado no se vende, y la consola del servidor dice cuál y por qué (por ejemplo:
`falta la pieza "Handle"`).

**Texturas:** el color de una `MeshPart` con `TextureID` se multiplica con la textura, y una `SurfaceAppearance`
tapa material y color. La vista previa y el ítem entregado se ven igual entre sí, pero en esas piezas el cambio
puede notarse poco o nada: conviene marcarlas `NoEditable`.

## F. Integración

Ya está integrado:

- **Dinero:** `DataManager.SpendGold` sobre el perfil.
- **Inventario:** `DataManager.AgregarInstancia` crea el ítem con un `Uid` nuevo generado por el servidor.
- **Equipar:** se equipa como cualquier ítem; `EquipoVisible` lee `Meta.Pers` y dibuja el modelo personalizado
  para todos los jugadores.
- **Persistencia:** el ítem y sus metadatos viajan con el perfil; también por comercio, subastas, buzón y bóveda.

Para poner un vendedor en un mapa: un `Model` con `HumanoidRootPart` (o `PrimaryPart`) y el tag
**`NpcPersonalizador`**. Atributo opcional `Categoria` = `Armas` o `Armaduras` para que venda solo eso. En Studio
o con `ModoPruebas` aparece uno de prueba ("Maestro Personalizador") al oeste del punto de inicio.

Números ajustables en `PersonalizadorConfig`: distancia (15 studs), costo por pieza modificada (25 de oro),
máximo de piezas, paleta y cámara.

### Qué se guarda

```lua
-- En el ítem (inventario / equipado):
{ Uid = "GUID", ItemId = "EspadaHierro", Cantidad = 1, Rareza = "Comun",
  Meta = { Origen = "NPC", Pers = "1|Hoja=Neon,FF0000|Mango=Wood,7F5533" } }

-- En el perfil, las últimas 20 compras por id de pedido (para reintentos):
ComprasPersonalizador = { ["<id de pedido>"] = { Uid, ItemId, Precio, Firma, T } }
```

`Pers` lleva la versión del formato y solo las piezas que cambian. No se guardan modelos ni posiciones: el modelo
se reconstruye desde la plantilla. Si más adelante cambiás un modelo, las piezas que ya no existan se ignoran y el
resto se sigue aplicando.

## G. Seguridad

| Riesgo | Defensa |
|---|---|
| Comprar desde lejos o sin hablar con el NPC | Sesión de tienda en el servidor + distancia (15 studs), NPC existente y personaje vivo, revisados **en cada pedido**; el `ProximityPrompt` no autoriza nada |
| Ítem inexistente o mal configurado | Solo se vende lo que está en el catálogo validado por el servidor |
| Precio manipulado | El precio lo calcula el servidor. El cliente manda el precio que vio; si no coincide, **no se cobra** y se pide confirmar de nuevo |
| Materiales, colores o piezas inventados | Material contra la lista de `Enum.Material` permitidos; color `RRGGBB` exacto; pieza contra las piezas editables reales del modelo; cualquier campo extra se rechaza |
| Tablas enormes | Máximo 32 piezas, ids de hasta 64 caracteres, sin anidar más de un nivel |
| Doble clic, spam, pedidos simultáneos | Una compra a la vez por jugador + límite de frecuencia del remote |
| Reintentos y respuestas perdidas | Cada compra lleva un id de pedido. Repetirlo devuelve el mismo resultado sin cobrar ni entregar otra vez; el mismo id con otro contenido se rechaza. Se guarda en el perfil, así que vale también tras reconectarse o cambiar de servidor |
| Quedar a medias (cobrado sin ítem, o al revés) | Verificación, entrega, cobro y registro en el mismo perfil y sin ceder el hilo. El perfil se guarda entero o no se guarda |
| Duplicar con dos servidores | El perfil tiene sesión única (ProfileStore): no puede estar cargado en dos servidores |
| Convertir la vista previa en un ítem | El clon es local; el ítem real lo crea el servidor desde el catálogo |
| Cambiar estadísticas con la personalización | Las estadísticas salen de `ItemCatalog`; `Meta.Pers` solo se usa para dibujar |
| Scripts en modelos | Un modelo con scripts adentro no se vende |

**Auditoría:** cada intento queda en el log del servidor y en `PersonalizadorManager.Auditoria()` (últimos 200 de
ese servidor): jugador, id de pedido, `Uid`, ítem, precio, resultado y hora. No guarda datos personales.

## H. Pruebas

**Ejecutadas (automáticas, pasan):** `python3 tests/run.py` — colores hexadecimales y RGB (incluye NaN, infinitos
y tipos incorrectos), ids de pieza, nombres de material e ids de pedido, codificar y decodificar la
personalización, rechazo de datos corruptos o con más piezas que el máximo, y cálculo del precio.

**Pendientes (hay que correrlas en Studio; ninguna está aprobada):**

| # | Prueba | Estado |
|---|---|---|
| 1–2 | Abrir la tienda cerca / intentar desde lejos | Pendiente |
| 3–4 | Seleccionar un arma / una armadura | Pendiente |
| 5–7 | Cambiar cada material y color; restablecer | Pendiente |
| 8–10 | Rotar la vista; cambiar de objeto; cerrar el probador | Pendiente |
| 11–12 | Morir durante la edición; salir de la zona del NPC | Pendiente |
| 13–15 | Comprar con saldo, sin saldo y con la mochila llena | Pendiente |
| 16 | `ItemID` inexistente | Pendiente |
| 17–20 | Materiales, colores y piezas inválidos; tablas enormes | Formato y límites: automatizadas, pasan. Contra el servidor real: pendiente |
| 21–22 | Alterar el precio en el cliente; manipular el `ProximityPrompt` | Pendiente |
| 23–24 | 100 pedidos repetidos; pedidos simultáneos | Pendiente |
| 25–28 | Desconectarse durante la compra; error de persistencia; reingresar; cambiar de servidor | Pendiente |
| 29–31 | Equipar lo comprado; verlo desde otro jugador; estadísticas sin cambios | Pendiente |
| 32 | Que no queden clones temporales | Pendiente |
| 33–35 | Saldo correcto; un solo ítem entregado; metadatos guardados | Pendiente |

Cómo probar: `docs/instalacion.md`, sección "Probar el vendedor personalizador".

## I. Diagnóstico: límites y pendientes

- **No está probado en Studio.** Lo más delicado de verificar: el montaje sobre el avatar (posición y giro de cada
  modelo), la cámara del probador en celular y la selección de piezas con un toque.
- **Modelos:** hoy son los de relleno. Con modelos reales puede hacer falta ajustar el `Handle` de cada uno.
- **Gamepad:** se navega la interfaz y se gira con los botones ⟲ ⟳; no hay giro con el stick.
- **Zoom en táctil:** con los botones + y –; no hay gesto de pellizco.
- **Movimiento:** los controles del personaje se desactivan mientras el probador está abierto y se reactivan al
  cerrar. Si el juego reemplaza el `PlayerModule` de Roblox, eso no se aplica y el jugador puede caminar (al
  alejarse 15 studs el probador se cierra solo).
- **Apariencias (transmog):** si el jugador tiene una apariencia puesta en ese slot, se ve la apariencia y no la
  personalización.
- **Stencils, escala y opacidad** del pedido de forja estética: no están; este sistema cubre material y color.
- **Stock y reputación:** todos los modelos del catálogo están siempre a la venta (solo se filtra por nivel).
- El ítem comprado es de rareza Común, con las estadísticas del catálogo.
