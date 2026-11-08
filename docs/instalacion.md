# Instalación y pruebas

Cómo cargar el proyecto en Roblox Studio y qué probar en cada fase. Para el diseño de cada sistema, ver el
[README](../README.md).

## Dónde va cada archivo

| Archivo | Tipo en Studio | Ubicación en Studio |
| --- | --- | --- |
| `Shared/Types` | ModuleScript | ReplicatedStorage > Shared |
| `Configs/GameConfig` | ModuleScript | ReplicatedStorage > Configs |
| `Configs/ItemCatalog` | ModuleScript | ReplicatedStorage > Configs |
| `Modules/NetworkBridge` | ModuleScript | ReplicatedStorage > Modules |
| `Modules/Signal` | ModuleScript | ReplicatedStorage > Modules |
| `Main` | **Script** | ServerScriptService |
| `Systems/DataManager` | ModuleScript | ServerScriptService > Systems |
| `Systems/AntiCheat` | ModuleScript | ServerScriptService > Systems |
| `Packages/ProfileStore` | ModuleScript | ServerScriptService > Packages |
| `ClientMain` | **LocalScript** | StarterPlayer > StarterPlayerScripts |
| `Configs/ZoneConfig` | ModuleScript | ReplicatedStorage > Configs |
| `Configs/GuerraConfig` | ModuleScript | ReplicatedStorage > Configs |
| `Modules/PantallaCarga` | ModuleScript | ReplicatedStorage > Modules |
| `Modules/Avisos` | ModuleScript | ReplicatedStorage > Modules |
| `LlegadaTeleport` | **LocalScript** | ReplicatedFirst |
| `Systems/ZoneManager` | ModuleScript | ServerScriptService > Systems |
| `Systems/Guerra/ArenaGuerra` | ModuleScript | ServerScriptService > Systems > Guerra (Folder) |
| `Systems/Guerra/ArchitectWarManager` | ModuleScript | ServerScriptService > Systems > Guerra (Folder) |
| `TeleportClient` | **LocalScript** | StarterPlayer > StarterPlayerScripts |
| `GuerraUI` | **LocalScript** | StarterPlayer > StarterPlayerScripts |

Las carpetas (`Shared`, `Configs`, `Modules`, `Systems`, `Packages`) son objetos **Folder**.
`ProfileStore` es la librería de loleris (licencia Apache 2.0, incluida en `ProfileStore.LICENSE.txt`).

## Opción A: Rojo (recomendada)

1. Instalá Rojo (https://rojo.space) y su plugin de Studio.
2. En la raíz del repo: `rojo serve`.
3. En Studio: plugin Rojo > Connect. Los archivos se sincronizan solos.

Con Rojo además podés usar `selene` (lint) y `stylua` (formato); ya están configurados.

## Opción B: a mano en Studio

1. Creá las carpetas de la tabla con *Insert Object > Folder*.
2. Para cada archivo, creá el objeto del tipo indicado, poné el nombre **sin** la extensión
   (`DataManager`, no `DataManager.luau`) y pegá el contenido.
3. Los archivos `.server.luau` van en un **Script** y los `.client.luau` en un **LocalScript**; todo lo demás es **ModuleScript**.

## Antes de probar

- *Game Settings > Security > Enable Studio Access to API Services*: activalo para que Studio guarde datos de verdad.
  Sin eso, ProfileStore funciona en modo simulado y no guarda nada entre sesiones.
- Publicá el place al menos una vez: los DataStores necesitan un juego publicado.

## Cómo comprobar que funciona

1. Play en Studio. En la consola tiene que aparecer `[RaidBlox] Servidor iniciado - Fase 2`
   y, del cliente, `Datos cargados: nivel 1, oro 0`.
2. En la barra de comandos (lado servidor) podés probar la API:
   ```lua
   local DM = require(game.ServerScriptService.Systems.DataManager)
   local p = game.Players:GetPlayers()[1]
   DM.AddGold(p, 500)
   DM.AddItem(p, "Madera", 150)   -- llena una pila de 99 y abre otra de 51
   DM.AddExperience(p, 1000)       -- sube varios niveles
   ```
   Cada cambio aparece en la consola del cliente (`Cambió Oro: 500`, etc.).
3. Pará y volvé a darle Play: el oro, la madera y el nivel tienen que seguir ahí.

## Probar la Fase 2 en Studio

**Portales (2.1).** Al darle Play aparecen dos portales cerca del spawn: *Bosque Susurrante* (nivel 1+) y *Reino de Fuego* (nivel 20+).
- Tocá el del Bosque: sale la pantalla de carga verde, el aviso `[Studio] Teleport simulado` y la pantalla se va.
- Tocá el de Fuego con nivel 1: aparece un aviso rojo "Necesitás nivel 20...". Subí de nivel con
  `DM.AddExperience(p, 100000)` y probá de nuevo.
- El teleport real solo funciona en un juego publicado. Creá los places en *Asset Manager > Places*, copiá sus
  PlaceId a `ZoneConfig` y probá desde Roblox (no desde Studio).

**Guerra de Arquitectos (2.2).** En Studio se genera sola una arena a unos 220 studs del spawn (hacia +Z):
dos castillos holográficos, nodos de recursos en el medio y depósitos.
1. Con 1 jugador la partida arranca a los 5 segundos y te lleva a la base de tu equipo.
2. Mantené presionado el botón sobre árboles (Madera), rocas (Piedra) y vetas (Hierro). Abajo a la izquierda ves la carga.
3. Llevá los recursos al depósito de tu base. Todo va al **almacén del equipo**, que completa sola la etapa actual y las siguientes, así que ningún recurso se desperdicia. Arriba se ve el progreso y lo que hay en el almacén.
4. Al completar una etapa, el holograma se vuelve sólido con partículas. En Studio los requisitos se dividen por 5 para que la partida dure pocos minutos.
5. Al colocar el Estandarte ganás: +500 de oro, +100 de honor y el título "Gran Arquitecto".
- Para probar las skins: `DM.UnlockSkinEstructura(p, "Jade"); DM.SetSkinEstructura(p, "Jade")` y completá una etapa.
- Con 2 jugadores (*Test > Clients and Servers > 2 Players*) se prueba el reparto de equipos.
- Para no generar la arena mientras probás otras cosas: `GuerraConfig.ProbarEnStudio = false`.
- Las recompensas de Studio se guardan en tu perfil real. Para probar sin tocarlo: `GuerraConfig.DarRecompensasEnStudio = false`.
- Fuera de Studio, si un equipo queda vacío, la partida se cancela sin recompensas (evita ganar solo con una cuenta alternativa).

**Mapa propio.** Si armás la arena a mano, seguí la convención del comentario de `ArenaGuerra` (carpeta
`GuerraArquitectos` con `Base_Azul`, `Base_Rojo` y `Recursos`). Si existe, se usa esa en vez de generar una.

## API del servidor (resumen)

**DataManager**
- `GetData(player)`, `WaitForData(player, timeout?)`, `IsLoaded(player)`, `SaveNowAsync(player, timeout?)` (espera a que se escriba)
- `AddGold`, `SpendGold` (falla sin tocar nada si no alcanza)
- `AddExperience(player, n)`: devuelve los niveles ganados
- `AddItem(player, itemId, cantidad, rareza?, meta?)`: todo o nada; si no entra, devuelve `false, "INVENTORY_FULL"`
- `RemoveItem`, `RemoveItemByUid`, `HasItem`, `CountItem`, `SetMaxSlots`
- `EnviarOroOffline(userId, cantidad, motivo)`: buzón para jugadores desconectados (lo usa la Casa de Subastas)
- `AddPremium`, `SpendPremium`, `ReciboYaProcesado`, `MarcarRecibo`: **solo** para el futuro MonetizationManager
- Señales: `PerfilCargado(player, datos)`, `DatosCambiados(player, seccion)`

**NetworkBridge**
- Registrar remotes nuevos en la tabla `DEFINICIONES` del módulo (marcando `Critico` para ataques/uso de ítems).
- Servidor: `OnEvent`, `OnInvoke`, `FireClient`, `FireAll`, `FireList`
- Cliente: `Fire`, `Invoke` (devuelve siempre `{ Success, ErrorCode, Data }`), `OnEvent`
- `Guard.Number / Integer / String / Boolean / OneOf / InstanceOf`: validar **todo** argumento del cliente

- `AddHonor`, `AddTitulo`, `UnlockSkinEstructura`, `SetSkinEstructura`

**ZoneManager**
- `Teleportar(player, zonaId, spawnId?)`: valida nivel y avisa al jugador si no puede
- El nivel mínimo se valida también al llegar al place: si alguien entra sin nivel, se lo manda a la Ciudad Principal (o se lo expulsa si esa zona no está configurada)
- Portales: Part con tag `Portal` y atributo `Destino` (opcional `Spawn`, que tiene que ser un Part dentro de la carpeta `PuntosDeLlegada` del place de destino)

**AntiCheat**
- `Gracia(player, segundos)`: llamalo antes de mover al jugador desde el servidor (teleports, empujones)
- `SetVelocidadPermitida(player, n)`: monturas y buffs de velocidad
- Atributos del jugador `Montado` / `Volando` = `true` para vuelo legítimo
- Señal `Infraccion(player, tipo, detalle)` para logs o el panel de admin

## Cambios respecto al prompt original

- **ProfileStore en vez de ProfileService**: es el sucesor del mismo autor, con session locking incluido, y su
  sistema de mensajes resuelve el buzón offline.
- **La rareza vive en cada ítem**, no en el jugador.
- **`MonedasRobux` pasó a llamarse `MonedasPremium`** y no se puede modificar desde la API general.
- **Anti-noclip**: se detecta levitación (más de 3 s en el aire). Atravesar paredes no se chequea con rayos porque
  da falsos positivos al doblar esquinas. Igual no sirve de nada, porque cada acción valiosa valida la distancia en el servidor.
