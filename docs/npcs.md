# NPCs por arquetipo

Los NPCs de servicio (vendedores, artesanos, guardianes de portales, etc.) salen de una sola base de datos:
`ReplicatedStorage/Configs/NpcArquetiposConfig.luau`, con los **39 arquetipos** en 8 categorías. El servidor los
maneja con `ServerScriptService/Systems/NpcManager.luau` y el cliente los muestra con `NpcUI.client.luau`.

No reemplaza a los NPCs de misiones (`MisionManager`) ni a los de prueba (`NpcsPrueba`): convive con ellos.

## Facciones y regla de interacción

Cada NPC tiene una facción: `Rojo`, `Azul` o `Neutral`. Un jugador del bando Violeta cuenta como Neutral.

| Jugador | Puede hablar con |
|---|---|
| Rojo | NPCs Rojos y Neutrales |
| Azul | NPCs Azules y Neutrales |
| Neutral (Violeta) | Todos |

La regla está en `NpcManager.PuedeInteractuar(player, faccionNpc)` (y `NpcManager.Compatibles` para compararla sin
jugador). Si un jugador le habla a un NPC del bando contrario, el NPC lo rechaza con una frase hostil
(`NpcArquetiposConfig.Rechazos`) y no se abre nada. La regla se vuelve a validar **en cada pedido**, no solo al
abrir la ventana.

## Servicios acoplables

Un arquetipo declara qué ofrece y `NpcManager` conecta cada parte:

| En el arquetipo | Interfaz | Qué hace | Remote |
|---|---|---|---|
| `Vende` | IVendor | Vende ítems del `ItemCatalog` por oro u honor | `NpcComprar(npcId, indiceOferta, cantidad)` |
| `Compra` | IVendor | Compra ítems de la mochila a `PrecioVenta × Factor` | `NpcVender(npcId, ranura, cantidad)` |
| `Estacion` | ICrafter | Abre las recetas de esa estación; el NPC cuenta como estación | `NpcFabricar(npcId)` |
| `Servicios` | IServiceProvider | Acciones al instante, con costo en oro | `NpcServicio(npcId, servicioId)` |
| `Viajes` | IServiceProvider | Guardián de Portales | `NpcViajar(npcId, zonaId)` |
| `SobreItem` | IServiceProvider | Operación sobre un ítem de la mochila: desencantar, reforjar, engarzar ([forja](forja.md)) | `NpcSobreItem(npcId, operacion, ranura, extra?)` |

Los `IQuestGiver` (Tabernero, Tablón) están definidos como datos; las misiones siguen saliendo de `MisionManager`.

Para sumar una acción de servicio desde otro sistema:

```lua
NpcManager.RegistrarAccion("Vault", function(player, npc, servicio): boolean
	-- abrir la bóveda...
	return true -- recién ahí se cobra `servicio.Costo`
end)
```

Un servicio con `Cotiza = true` tiene costo variable (por ejemplo, reparar): la acción valida y cobra por su
cuenta, y `NpcManager.RegistrarCotizacion` informa el costo al abrir la ventana. Las operaciones sobre un ítem se
registran con `NpcManager.RegistrarAccionItem`.

Las acciones no deben ceder el hilo (sin `task.wait` ni llamadas a DataStore): entre la verificación del oro y el
cobro no puede cambiar el saldo.

## Stock rotativo (Mercado Negro)

Un arquetipo con `Rotacion = { Cada, Cantidad }` tiene ofertas marcadas `Rotativa`: en cada ciclo salen a la venta
solo `Cantidad` de ellas. El ciclo sale de la hora (`os.time() // Cada`) y el sorteo usa una semilla fija, así que
todos los servidores muestran lo mismo sin coordinarse. Cada oferta rotativa tiene un `Limite` de compras **por
jugador y por ciclo**, guardado en el perfil (`ComprasRotativas`); no es un stock compartido entre servidores.
El Mercado Negro rota cada 6 horas y muestra 3 de 8.

## Cambista

Cambia puntos de honor por oro en lotes fijos (10, 100 y 1.000), a `NpcArquetiposConfig.Cambio.OroPorHonor`
(0,5). Es de una sola vía: no vende honor. La tasa queda por debajo de lo que rinde gastar el honor en el
Intendente y revender, y una prueba automática lo verifica. Cada cambio queda en el log del servidor. No hace
préstamos. El juego usa una sola moneda (oro); mostrarla como Bronce / Plata / Oro queda pendiente.

## Banquero de Clan

Abre la ventana de la hermandad en la pestaña Banco. Los permisos por rango, el registro de movimientos y el
candado entre servidores son los de `HermandadManager` ([hermandades](hermandades.md)). El banco se sigue
pudiendo abrir desde el menú: exigir estar junto al NPC queda pendiente.

## Guardián de Portales

Cada zona de `ZoneConfig` tiene un `Territorio` (`Rojo`, `Azul` o `Neutral`).

| Guardián | Destinos | Costo |
|---|---|---|
| Rojo | Zonas Rojas y Neutrales | `CostoBase + CostoPorNivel × NivelMinimo` |
| Azul | Zonas Azules y Neutrales | Igual |
| Neutral | Cualquier zona | El doble (`FactorNeutral`) |

Flujo: el servidor valida distancia, bando, destino permitido y oro; cobra; y llama a `ZoneManager.Teleportar`
(que valida el nivel mínimo). Si el viaje no arranca o falla después, el oro vuelve (`ZoneManager.Cancelado`).

Se agregaron dos zonas para que la regla tenga sentido: `CapitalRoja` (Bastión Carmesí) y `CapitalAzul`
(Ciudadela Azur), con `PlaceId = 0` hasta que existan los places.

## Estados

- **Listo**: funciona hablando con el NPC.
- **Parcial**: el sistema ya existe pero se usa desde otro lado; el NPC lo indica.
- **Pendiente**: falta el sistema. El NPC se puede colocar y dice qué falta; `Parametros` deja definidos
  precios, duraciones y reglas para cuando se programe.

Cuántos hay de cada uno figura en la [matriz](npcs-matriz.md), que se genera desde la configuración.

En `Vende` solo hay ítems que existen hoy en el `ItemCatalog`, con precio de venta por encima de lo que paga un NPC
al comprarlos (así no se puede ganar oro comprando y revendiendo).

## Los 39 arquetipos

La lista completa, con qué funciona hoy, qué falta y el estado de cada uno, está en la
[matriz de seguimiento](npcs-matriz.md).

## Colocar NPCs en un mapa

1. Poné un `Model` con una parte `HumanoidRootPart` (o `PrimaryPart`) anclada.
2. Agregale el tag **`NpcArquetipo`**.
3. Atributos: `Arquetipo` (la clave, por ejemplo `HerreroGeneral`) y `Faccion` (`Rojo`, `Azul` o `Neutral`).

`NpcManager` le pone el cartel de "Hablar" y lo registra. Cada NPC lleva sobre la cabeza un cartel con su **número** (#1 a #39, el mismo
de la [matriz](npcs-matriz.md)), del color de su facción. También se pueden crear por código:
`NpcManager.Crear("Boticario", "Rojo", posicion)`.

En Studio o con `ModoPruebas`, si el mapa no tiene ninguno, aparecen los de prueba (`NpcArquetiposConfig.DePrueba`)
al oeste del punto de inicio: los que ya funcionan, incluidos tres Guardianes de Portales (uno por facción).

## Seguridad

- El cliente solo manda el id del NPC y qué quiere; precios, ofertas y destinos se leen del servidor.
- Cada pedido revalida: NPC existente, distancia (`DistanciaInteraccion`, 14 studs), bando y datos cargados.
- Cantidades con tope (99 por compra; 10 si el ítem no se apila) y todos los argumentos pasan por `Guard`.
- Compra: se verifica el saldo, se agrega el ítem (todo o nada) y se cobra, sin ceder el hilo en el medio.
- Venta: solo desde ranuras de la mochila (nunca lo equipado) y solo los tipos que ese NPC compra. Vender
  equipo que no es Común pide un segundo clic.

## Pendiente de decidir

**Subastas separadas por bando.** El diseño pide que el Subastador Rojo y el Azul tengan mercados distintos. Hoy
la Casa de Subastas es una sola; separarla parte la economía actual y deja fuera a los jugadores Violeta, así que
quedó apagado (`Subastador.Parametros.SeparacionActiva = false`) hasta confirmarlo.
