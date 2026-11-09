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
