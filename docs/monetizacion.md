# Monetización (Fase 6)

## 6.1 Pases permanentes

Configurados en `MonetizacionConfig.Pases`. Botón **🛒 Tienda** (a la izquierda).

| Pase | Qué da |
| --- | --- |
| VIP | +15% de experiencia y de oro **de juego** (enemigos, misiones, mazmorras; nunca oro de comercio ni subastas), `[VIP]` dorado en el chat y sobre la cabeza |
| Mochila Extra | la mochila pasa de 30 a 50 lugares |
| Puesto en la Subasta | hasta 15 publicaciones a la vez (en vez de 5) |
| Dragón de Fuego | montura con llamas, 15% más rápida que el caballo |
| Título Personalizado | un título propio (filtrado por Roblox, hasta 24 letras) sobre la cabeza |

### Cómo se activan

- Al entrar, el servidor consulta `UserOwnsGamePassAsync` por cada pase; las
  compras en vivo llegan por `PromptGamePassPurchaseFinished`. La compra la abre
  el servidor (`PromptGamePassPurchase`).
- **Id = 0** = el pase todavía no existe en Roblox: no se puede comprar. En modo
  pruebas, el creador y `ConfigServidor.Probadores` lo pueden **simular** desde
  la tienda (solo en memoria).
- Para ponerlos a la venta: Creator Hub → tu experiencia → **Monetización →
  Pases**, creá cada uno, ponele precio y pegá su Id en `MonetizacionConfig`.

### Bonos

`Systems/Monetizacion/Bonos.luau` guarda los multiplicadores por jugador (VIP y,
en 6.2, el booster de experiencia). Lo leen `EnemyManager.Recompensar`,
`MisionManager` y `MazmorraManager`.

## Monturas

`MonetizacionConfig.Monturas`: **Caballo** (gratis, velocidad 24) y **Dragón de
Fuego** (pase, 27,6). Tecla **G** (L3 en joystick) o botón **Montar**.

- Solo fuera de combate (5 s sin pelear) y fuera de la Guerra.
- Montado: el modelo va soldado al personaje, sube la altura de cadera y la
  velocidad pasa a la de la montura; el anti-cheat la conoce
  (`AntiCheat.SetVelocidadPermitida`).
- Se desmonta al recibir o hacer daño, al morir o tocando G otra vez.

## 6.2 Compras repetibles (Developer Products) y cajas

Configuradas en `MonetizacionConfig.Productos`. Pestañas **Productos** y **Mis
fichas** de la Tienda.

| Producto | Qué da |
| --- | --- |
| Booster de Experiencia | 2× experiencia de juego por 1 hora; si ya hay uno, se suma otra hora (`BoosterXpHasta` en el perfil) |
| Pack de Inicio | 1.000 de oro, Espada de Hierro Rara, 3 pociones de vida y 3 de maná; **una vez por cuenta** |
| Ficha de Re-roll | se usa en "Mis fichas" sobre un equipo de la mochila: calidad (`Meta.Mult`) nueva entre x0,9 y x1,1 del multiplicador de su rareza (x1,1 extra si es Masterpiece) y efectos secundarios de nuevo en su rango |
| Ficha de Cambio de Bando | pasar a Rojo, Azul o Violeta sin pagar oro (no durante la Guerra) |
| Cajas (5) | Materiales (5 ítems), Armadura (1, rareza al azar), Consumibles (3), Mágica (1, mínimo Raro), Gemas (2) |

Decisiones del usuario (2026-11-13): lo que sale de las cajas **se puede
comerciar, subastar y guardar en el banco** como cualquier ítem. Las mazmorras
siguen **sin límite de entradas**, así que no hay boletos.

### ProcessReceipt (atómico e idempotente)

1. Si el `PurchaseId` ya está en `RecibosProcesados` → se confirma el guardado
   (`SaveNowAsync`) y `PurchaseGranted`.
2. Si no → se entrega en memoria sin pausas y se anota el `PurchaseId`.
3. `PurchaseGranted` solo si `SaveNowAsync` confirma; si no, `NotProcessedYet`
   y Roblox reintenta (ya anotado: no se duplica).

Lo que no entra en la mochila va por buzón con id fijo (`recibo:<id>:<n>`).

### Cajas: reglas de Roblox

- Las **probabilidades** de cada ítem y de cada rareza se calculan de los pesos
  de `MonetizacionConfig.Cajas` y se **muestran antes de comprar**.
- Con `PolicyService:GetPolicyInfoForPlayerAsync(...).ArePaidRandomItemsRestricted`
  (o si no se puede consultar) las cajas **no se ofrecen** a ese jugador.
- En el cuestionario de madurez ya está marcado "ítems aleatorios pagos: Sí".

### Gemas

Nuevas en `ItemCatalog`: Amatista, Esmeralda, Zafiro, Rubí y Diamante
(materiales). Por ahora salen de la Caja de Gemas; más adelante se engarzan.

### Para ponerlos a la venta

Creator Hub → tu experiencia → **Monetización → Productos para desarrolladores**,
creá cada uno y pegá su Id en `MonetizacionConfig.Productos`. Mientras el Id sea
0, el creador y los probadores los pueden **simular** desde la tienda.

## 6.3 Pase de batalla, cosméticos y mascotas

Todo vive en la tienda (botón 🛒), en las pestañas **Pase**, **Colección** y
**Códigos**.

### Pase de batalla (`PaseBatallaConfig`)

- 50 niveles, 1000 XP cada uno. Temporada actual: `T1` "El Despertar". Al
  cambiar `Temporada` en el config, el progreso de todos vuelve a cero.
- XP del pase: enemigo 15, jefe 150, misión 250, mazmorra ganada 600.
- Cada nivel tiene una recompensa **Gratis** y una **Premium**; se reclaman a
  mano (no se pierden si no las reclamás). La vía Premium se habilita con el
  pase permanente `PaseBatalla` (pestaña Pases; Id 0 = simulable en pruebas).
- Tipos de recompensa: oro, ítem (con rareza), título, skin del castillo,
  ficha, booster, mascota y apariencia. Si la mochila está llena, el ítem va al
  buzón. Todo pasa por `Recompensas.Dar`.

### Skins del castillo

Gótica (Premium 10), Hielo (Premium 20) y Jade (Premium 30). Se equipan en
**Colección** y se usan en la Guerra de Arquitectos en las etapas donde seas
quien más aportó.

### Códigos de creador (`PaseBatallaConfig.Codigos`)

Uno por cuenta. Cada canje suma 1 al contador del código en el DataStore
`CodigosUso` (`CodigosUso_Studio` en Studio), para medir cuánto trae cada
creador. Iniciales: `RAIDBLOX` (500 oro + 3 pociones) y `BIENVENIDA`
(booster de 30 min). Para agregar uno: una línea en `Codigos`.

### Equipo visible y transmog (`AparienciaEquipoConfig`)

- El arma principal (mano derecha), la secundaria (izquierda), el casco y la
  pechera puestos se dibujan en el personaje con modelos hechos de piezas
  simples; los ven todos. `Items` dice qué modelo y color usa cada ítem.
- **Transmog**: en Colección → Apariencias elegís cómo se ve un slot
  (Espada Llameante, Báculo Arcano, Casco de Dragón). Solo cambia el aspecto,
  y se ve mientras tengas un ítem puesto en ese slot.

### Mascotas coleccionistas (`MascotasConfig`)

Lumi (Premium 1) y Brasa (Premium 25). La equipada flota a tu lado y cada
segundo te junta el botín personal a menos de **25 studs** (si la mochila se
llena, para; las bolsas siguen ahí y al vencer van al buzón). No pelean ni dan
stats.
