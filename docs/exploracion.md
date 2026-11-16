# Viajes y exploración

Viaje rápido por piedras de teletransporte, puntos de interés en el mapa y monturas del establo. Son el Grupo D
del pedido de los 39 NPC (ver [matriz](npcs-matriz.md)). Módulos: `Configs/ExploracionConfig.luau`,
`Systems/ExploracionManager.luau`, `PiedrasUI.client.luau`, y el establo en `Monetizacion/MonturaManager.luau`.

**Sin probar en Studio.** Pasa el chequeo de tipos, el lint y las pruebas de datos.

## Piedras de teletransporte (NPC-024)

- Hay que **activarlas una vez** tocándolas (gratis). Quedan guardadas en el perfil (`Waypoints`).
- Estando junto a una piedra activada se puede **viajar a cualquier otra activada**: 30 de oro dentro de la zona,
  90 si es a otra zona. Entre zonas el viaje lo hace `ZoneManager`, que valida el nivel y el place.
- El **Guardián de Piedra Teleport** activa la piedra que cuida sin que haya que tocarla.
- En el mapa del mundo (M) las piedras activadas se ven en azul y las que faltan en gris; en el minimapa son
  rombos violetas, como los portales.

En un mapa real: una parte con el tag `PiedraTeleport` y el atributo `Piedra` (la clave de
`ExploracionConfig.Piedras`). En la zona de pruebas, las que falten se crean solas como obeliscos con cartel.

## Puntos de interés (NPC-023)

Lugares marcados en el mapa del mundo: minas, claros de hierbas, el campo de práctica, la plaza de mercaderes, la
arena. Se consiguen de dos formas:

1. **Caminando** a menos de 35 studs (se revisa cada 2 segundos).
2. **Comprándole el mapa de la zona al Cartógrafo** (200 de oro). Si ya los tenés todos, el botón queda apagado.

Se guardan en el perfil (`Interes`) y el mapa del mundo los dibuja con su ícono y su nombre.

## Maestro de Establo (NPC-021)

| Servicio | Costo | Qué hace |
|---|---|---|
| Corcel de Guerra | 1.500 de oro | Montura propia, velocidad 26 (el caballo es 24). Nivel 5 |
| Lobo de las Nieves | 6.000 de oro | Velocidad 28, la más rápida que se compra con oro. Nivel 12 |
| Alquilar un corcel | 150 de oro | El Corcel por una hora, sin quedárselo |
| Entrenar velocidad | 1.000 de oro y sube | +2% a **todas** tus monturas, hasta +10% |

Las monturas compradas quedan en el perfil (`MonturasCompradas`), el alquiler vence por hora de reloj
(`MonturaAlquiler`) y el entrenamiento es un porcentaje (`MonturaVelocidad`). El Dragón de Fuego sigue siendo del
pase.

El servidor publica en el jugador el atributo **`MonturaMejor`** con la montura más rápida que puede usar; el
botón del menú (G) la muestra, pero al montar el servidor revalida pase, compra, alquiler y nivel. Si vence un
alquiler mientras el jugador va montado, se baja.

## Seguridad

- El cliente manda ids (piedra, destino, servicio), nunca posiciones ni precios.
- Viajar exige estar a 14 studs de una piedra **activada**, y que el destino también esté activado. Se cobra
  antes; si el viaje entre zonas no arranca, el oro vuelve.
- Un viaje entre zonas no se puede pedir si ya hay otro en curso (`ZoneManager.Viajando`).
- Los descubrimientos y las compras del establo se validan y guardan en el servidor.

## Lo que falta de este grupo

- **NPC-022 Navegante** (barcos, dirigibles, carros): pendiente. Sin mapas reales no hay rutas que valgan la pena;
  el Guardián de Portales ya cubre el viaje entre zonas.
- **NPC-005 Inscriptor** (pergaminos de teletransporte y de buff de grupo): pendiente.
- Costo de viaje en cristales en lugar de oro, mapas de otras zonas y coleccionables de exploración: pendientes.
