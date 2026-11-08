# Roadmap

## Fases

```mermaid
flowchart LR
    F1[Fase 1<br/>Datos, red, anti-cheat]:::hecho --> F2[Fase 2<br/>Zonas, Guerra de Arquitectos]:::hecho
    F2 --> F3[Fase 3<br/>Combate, 8 clases,<br/>RaidBlox, rarezas]:::hecho
    F3 --> F4[Fase 4<br/>Inventario, crafteo,<br/>subastas, comercio]:::hecho
    F4 --> F5[Fase 5<br/>Voz, misiones,<br/>hermandades, dungeons]:::siguiente
    F5 --> F6[Fase 6<br/>Monetización<br/>y cosméticos]
    F6 --> F7[Fase 7<br/>HUD, combat text,<br/>minimapa, admin]

    classDef hecho fill:#2e7d32,color:#fff,stroke:#1b5e20
    classDef siguiente fill:#f9a825,color:#000,stroke:#f57f17
```

| Fase | Sistemas | Estado |
| --- | --- | --- |
| 1 | DataManager (ProfileStore), NetworkBridge, AntiCheat | ✅ |
| 2 | ZoneManager, pantalla de carga, Guerra de Arquitectos | ✅ |
| 3 | CombatManager (FSM, tab-targeting, parry), 8 clases, EnemyManager, RaidBloxManager, rarezas, botín | ✅ |
| 4 | Inventario drag & drop, profesiones (crafteo y recolección), AuctionManager, comercio 1v1 | ✅ |
| 5 | VoiceChannelManager, misiones, hermandades, dungeons instanciadas | ⏳ |
| 6 | Gamepasses, DevProducts, pase de batalla, transmog, mascotas | — |
| 7 | HUD, target frame, combat text, minimapa, panel de administración | — |

El detalle de cada prompt de diseño está en el documento de catálogo del proyecto.

## Decisiones tomadas

| Decisión | Motivo |
| --- | --- |
| ProfileStore en lugar de ProfileService | Sucesor del mismo autor; session locking y mensajes entre servidores |
| Rareza dentro de cada ítem | Es una propiedad del ítem, no del jugador |
| `MonedasRobux` → `MonedasPremium` | Solo la toca la monetización; nombre neutro |
| Ranuras de inventario con clave de texto | JSON corta los arrays con huecos |
| Expulsar si el perfil no carga en 60 s | Jugar con un perfil vacío pisaría los datos reales |
| Anti-cheat basado en lo que ve el servidor | Velocidad y FloorMaterial los reporta el cliente |
| Sin chequeo de atravesar paredes | Da falsos positivos; las acciones valiosas ya validan distancia |
| Nivel mínimo validado al llegar al place | El cliente puede iniciar teleports por su cuenta |
| Almacén por equipo en la Guerra | Ningún recurso es inútil; nadie se traba con la carga llena |
| Partida cancelada si un equipo queda vacío | Evita ganar solo con una cuenta alternativa |
| Botín personal (bolsa que solo ve su dueño) | Nadie puede robar; cumple "instanciado" y muestra el haz de rareza |
| Botín nunca se pierde | Se entrega solo a los 120 s o va al buzón si se desconecta |
| Stats y efectos del ítem guardados en su `Meta` | Cada copia es única y no cambia si se rebalancea la config |
| Vida/maná actuales no se guardan | Se aparece con vida y maná completos (simplifica la persistencia) |
| Parry solo contra golpes cuerpo a cuerpo de NPCs | Las zonas rojas de los jefes se esquivan saliendo |
| Subastas: DataStore como verdad, MemoryStore como índice | MemoryStore es rápido pero no durable; la compra la arbitra `UpdateAsync` |
| Entregas de subasta por el buzón | Llegan aunque el destinatario esté offline o en otro servidor |
| Vencimientos procesados al entrar el vendedor | No hace falta un proceso global que recorra todas las publicaciones |
| Comercio sin custodia intermedia | Los ítems no salen del inventario hasta el intercambio síncrono final: nada queda "en el aire" |
| Herramientas en un slot de equipo propio | "Requiere herramienta equipada" sin afectar las stats de combate |
| `EstadoCliente` como único receptor de datos | Ninguna interfaz pierde el snapshot inicial por cargar tarde |

## Pendientes conocidos

- **Fase 5/6:** monturas con `AntiCheat.SetVelocidadPermitida` y el atributo `Montado`.
- El buzón de ítems reintenta recién al volver a entrar si el inventario estaba lleno.
- **Fase 6:** el pase "Subasta Extra" sube `GameConfig.Subastas.MaxPublicaciones` por jugador (hoy es global).
- La búsqueda de subastas lee las 200 publicaciones más baratas del índice; con mucho volumen conviene un índice por
  tipo de ítem.
- **Fase 5:** el grupo (party) todavía no existe: el botín y las curas en área usan "todos los jugadores cercanos".
- **Fase 7:** `CombateUI`, `RaidBloxUI` y los números flotantes son versiones de prueba; el HUD definitivo los reemplaza.
- **Fase 6:** en `ProcessReceipt`, devolver `PurchaseGranted` solo si `DataManager.SaveNowAsync` confirma el guardado
  después de `MarcarRecibo`. Si no, `NotProcessedYet`. El re-roll pagado tiene que mostrar las probabilidades (política
  de Roblox sobre ítems aleatorios pagos).
- **Fase 7:** `GuerraUI` y `Avisos` son interfaces mínimas de prueba; se reemplazan con el HUD definitivo.
- **Fase 7.4:** los webhooks de Discord necesitan un proxy intermedio (Discord bloquea las peticiones de Roblox).
- Configurar los PlaceId reales en `ZoneConfig` cuando se creen los places.
- El texto de diseño del Prompt 7.4 (panel de administración) llegó incompleto.
