# Datos del jugador

`DataManager` es el único módulo que toca DataStores. Usa [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore)
para tener **session locking**: un perfil solo puede estar abierto en un servidor a la vez, así nadie duplica ítems
entrando rápido a otro servidor.

## Esquema del perfil (versión 5)

```mermaid
classDiagram
    class DatosJugador {
        number Version
        number Nivel
        number Experiencia
        Clase Clase
        Bando Faccion
        number Oro
        number MonedasPremium
        number PuntosHonor
        string[] Titulos
        SkinEstructura[] SkinsEstructura
        boolean KitInicialEntregado
        number SecuenciaGuardado
    }
    class Inventario {
        number MaxSlots
        map~string, ItemInstancia~ Slots
    }
    class Equipamiento {
        ItemInstancia? Casco
        ItemInstancia? Pechera
        ItemInstancia? ArmaPrincipal
        ItemInstancia? ArmaSecundaria
        ItemInstancia? Accesorio1
        ItemInstancia? Accesorio2
        ItemInstancia? Herramienta
    }
    class ItemInstancia {
        string Uid
        string ItemId
        number Cantidad
        Rareza Rareza
        ItemMeta? Meta
    }
    class Ajustes {
        Genero Genero
        boolean ChatVisible
        number? ChatX, ChatY, ChatAncho, ChatAlto
        CanalVoz? CanalVoz
        boolean? Zurdo
        number? EscalaUI
        boolean? TextosCombate
        boolean? Minimapa
        boolean? IgnorarGuerra
    }
    class Pendientes {
        map Subastas
        map Compras
        map? Banco
    }
    class Opcionales {
        string? TituloPersonalizado
        number? BoosterXpHasta
        map? Fichas
        boolean? PackInicio
        PaseBatalla? PaseBatalla
        string[]? Mascotas
        string? MascotaEquipada
        string[]? Apariencias
        map? Transmog
        map? CodigosCanjeados
        string[]? Barras
        map? CooldownsLargos
        Vault? Vault
    }

    DatosJugador *-- Inventario
    DatosJugador *-- Equipamiento
    DatosJugador *-- Ajustes
    DatosJugador *-- Pendientes
    DatosJugador *-- Opcionales
    DatosJugador *-- "0..*" ProgresoMision : MisionesActivas
    DatosJugador *-- "0..5" ProgresoProfesion : Profesiones
    Inventario *-- "0..*" ItemInstancia
    Equipamiento o-- "0..7" ItemInstancia
```

La definición exacta está en `Shared/Types.luau` (`DatosJugador`). "Opcionales" no es una tabla aparte: son campos del
perfil que pueden faltar en perfiles viejos, y el código los trata como vacíos.

| Versión | Qué agregó |
| --- | --- |
| 1 | Nivel, oro, inventario, equipamiento, misiones, recibos |
| 2 | Honor, títulos y skins de estructura (Guerra de Arquitectos) |
| 3 | Profesiones y kit inicial |
| 4 | Bando (`Faccion`) y `Ajustes` |
| 5 | `Pendientes` (diario de subastas y compras), `MensajesSubasta`, `SecuenciaGuardado` |
| — | Opcionales, sin subir la versión: banco de hermandad en el diario, voz y chat en ajustes, monetización (título, booster, fichas, pack), pase de batalla, mascotas, apariencias y transmog, códigos, ajustes de interfaz, barras y recargas largas del Chatarrero |

Notas de diseño:

- **La rareza es de cada ítem**, no del jugador.
- **Las ranuras se indexan con texto** (`"1"`..`"MaxSlots"`): JSON corta un array en el primer `nil`, así que un
  inventario con huecos perdería ítems.
- **`MonedasPremium`** existe en el perfil pero hoy no se usa: los pases y productos se compran directo con Robux.
- **Campos nuevos = opcionales.** Si un campo puede faltar sin romper nada, se agrega como opcional y no se sube la
  versión (así no hay que republicar para migrar). La versión sube solo cuando hay que transformar datos viejos.
- **Diarios:** lo que sale del perfil hacia otro DataStore (subasta, banco de hermandad) se anota en `Pendientes` en
  el mismo paso; al entrar se reconcilia.
- `RecibosProcesados` y `MensajesProcesados` son listas acotadas (50 y 100) para la idempotencia de compras y del buzón.

## Ciclo de vida de una sesión

```mermaid
sequenceDiagram
    autonumber
    actor J as Jugador
    participant S as Servidor (DataManager)
    participant PS as ProfileStore
    participant C as Cliente

    J->>S: PlayerAdded
    S->>PS: StartSessionAsync(UserId, Cancel)
    alt otro servidor tiene la sesión
        PS-->>PS: espera a que se libere (session lock)
    end
    alt no carga en 60 s o falla
        PS-->>S: nil
        S->>J: Kick("No pudimos cargar tus datos")
    else carga
        PS-->>S: Perfil
        S->>S: migrar(copia) y Reconcile()
        S->>C: DatosIniciales(snapshot)
        loop mientras juega
            S->>S: cambios vía API (AddGold, AddItem...)
            S->>C: DataSync(sección, valor)
            PS-->>PS: autoguardado periódico
        end
        J->>S: PlayerRemoving
        S->>PS: EndSession() guarda y libera el lock
    end
```

Reglas clave:

- **Si el perfil no carga, el jugador es expulsado.** Nunca juega con un perfil vacío, porque al guardar pisaría sus
  datos reales.
- Si otro servidor toma la sesión (`OnLastSave` con motivo `External`), este servidor expulsa al jugador con un
  mensaje claro.
- ProfileStore guarda todos los perfiles en `game:BindToClose` cuando el servidor se apaga.

## Migraciones de esquema

```mermaid
flowchart TD
    A[Perfil cargado] --> B{Version del perfil}
    B -- mayor que la del servidor --> X[Error: expulsar sin tocar los datos]
    B -- igual --> R[Reconcile: completar campos nuevos]
    B -- menor --> C[Copia profunda de los datos]
    C --> D[Aplicar MIGRACIONES n → n+1 sobre la copia]
    D -- falla --> Y[EndSession con datos originales + expulsar]
    D -- ok --> E[Reemplazar los datos por la copia migrada]
    E --> R
    R --> F[Perfil listo]
```

- Para agregar un campo nuevo con valor por defecto alcanza con sumarlo a `PLANTILLA`: `Reconcile` lo completa.
- Para **transformar** datos existentes, subí `GameConfig.Datos.VersionEsquema` y agregá `MIGRACIONES[n]`.
- Migraciones actuales: `[1]` honor, títulos y skins; `[2]` profesiones y kit inicial; `[3]` bando y ajustes;
  `[4]` diario de subastas, mensajes de subasta y contador de guardados.
- **Cada vez que sube la versión hay que republicar el juego**: un servidor viejo expulsa a quien tenga datos más
  nuevos, para no pisarlos.

## Buzón offline

Sirve para pagar a jugadores que no están conectados (por ejemplo, ventas de la Casa de Subastas). Usa
`ProfileStore:MessageAsync`, que funciona entre servidores.

```mermaid
sequenceDiagram
    participant A as Servidor A (vende)
    participant PS as ProfileStore
    participant B as Servidor B (donde está o entrará el jugador)

    A->>PS: MessageAsync(UserId, {Id, Tipo="Oro", Cantidad, Motivo})
    Note over PS: El mensaje queda en cola en el perfil
    B->>PS: MessageHandler (al cargar o en vivo)
    PS-->>B: mensaje
    alt Id ya está en MensajesProcesados
        B->>B: descartar (evita pagar dos veces)
    else Tipo conocido
        B->>B: sumar oro, guardar Id
        B->>PS: procesado()
    else Tipo desconocido (versión más nueva)
        B->>B: dejar en cola para otro servidor
    end
```

## API del servidor

| Función | Devuelve | Notas |
| --- | --- | --- |
| `GetData(player)` | `DatosJugador?` | Solo lectura |
| `WaitForData(player, timeout?)` | `DatosJugador?` | Espera la carga |
| `SaveNowAsync(player, timeout?)` | `boolean` | Espera a que se escriba |
| `AddGold` / `SpendGold` | `boolean` | Todo o nada |
| `AddExperience(player, n)` | niveles ganados | Curva `100 · nivel^1.5` |
| `AddItem(player, id, n, rareza?, meta?)` | `boolean, CodigoError?` | Atómico: si no entra todo, no agrega nada |
| `RemoveItem` / `RemoveItemByUid` / `HasItem` / `CountItem` | — | `RemoveItem` gasta primero pilas sin metadatos |
| `SetMaxSlots` | `boolean` | No reduce por debajo de una ranura ocupada |
| `EnviarOroOffline(userId, n, motivo)` | `boolean` | Buzón entre servidores |
| `AddHonor`, `AddTitulo`, `UnlockSkinEstructura`, `SetSkinEstructura` | `boolean` | Fase 2 |
| `AddPremium`, `SpendPremium`, `ReciboYaProcesado`, `MarcarRecibo` | — | Solo para monetización |
| `SetClase`, `EquiparItem`, `DesequiparItem` | `boolean` | Fase 3 |
| `EnviarItemOffline(userId, itemId, n, rareza, meta, motivo)` | `boolean` | Buzón de ítems |
| `MoverRanura`, `DividirPila`, `QuitarDeRanura`, `AgregarInstancia`, `BuscarPorUid`, `RanurasLibres`, `RanurasNecesarias` | — | Fase 4: síncronas, todo o nada |
| `NivelProfesion`, `AddXpProfesion`, `MarcarKitInicial` | — | Profesiones |
| `SetFaccion`, `SetAjuste` | `boolean` | Bando y ajustes (valores validados contra listas y rangos) |
| `RegistrarPendiente*`, `QuitarPendiente*`, `PendientesBanco` | — | Diarios de subasta y banco de hermandad |
| `SetTituloPersonalizado`, `ExtenderBoosterXp`, `Fichas`, `AgregarFicha`, `UsarFicha`, `MarcarPackInicio` | — | Monetización |
| `SetMetaRanura` | `boolean` | Cambia los metadatos de un ítem (re-roll) |
| `Barras(datos)`, `SetCooldownLargo` | — | Chatarrero: barras equipadas y recargas largas |
| `Mutar(player, seccion, fn)` | `boolean` | Cambio genérico sin pausas; avisa la sección al cliente |

Señales: `PerfilCargado(player, datos)` y `DatosCambiados(player, seccion)`.
