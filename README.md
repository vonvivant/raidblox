# RAIDBLOX

MMORPG multiplataforma (PC, móviles y consolas) para Roblox, inspirado en los clásicos del género.
Todo el código está en Luau con tipado estricto (`--!strict`) y sigue un modelo **server-authoritative**:
el cliente solo pide y muestra; el servidor valida y decide.

## Estado

| Fase | Contenido | Estado |
| --- | --- | --- |
| 1 | Guardado de datos, red segura, anti-cheat | ✅ Lista |
| 2 | Zonas y teletransporte, Guerra de Arquitectos | ✅ Lista |
| 3 | Combate tab-targeting, 8 clases, jefes RaidBlox, rarezas | ⏳ Siguiente |
| 4 | Inventario, crafteo, subastas y comercio | Pendiente |
| 5 | Voz, misiones, hermandades y dungeons | Pendiente |
| 6 | Monetización y cosméticos | Pendiente |
| 7 | HUD, combat text, minimapa y panel de admin | Pendiente |

Detalle por fase y pendientes en [docs/roadmap.md](docs/roadmap.md).

## Vista general

```mermaid
flowchart LR
    subgraph Cliente
        UI[Interfaces<br/>GuerraUI · Avisos · PantallaCarga]
        CC[Controladores<br/>ClientMain · TeleportClient]
    end
    subgraph Compartido[ReplicatedStorage]
        NB[NetworkBridge]
        CFG[Configs]
        TY[Types]
    end
    subgraph Servidor[ServerScriptService]
        MAIN[Main]
        DM[DataManager]
        AC[AntiCheat]
        ZM[ZoneManager]
        AW[ArchitectWarManager]
    end
    DS[(DataStores<br/>ProfileStore)]
    TS[[TeleportService]]

    CC <-->|remotes validados| NB
    UI --> CC
    NB <--> MAIN
    MAIN --> DM & AC & ZM & AW
    DM --> DS
    ZM --> TS
    AW --> DM
    ZM --> DM
```

## Documentación

- [Instalación y pruebas](docs/instalacion.md): cómo cargar el proyecto en Studio y qué probar.
- [Arquitectura](docs/arquitectura.md): estructura de carpetas, módulos, dependencias y arranque.
- [Datos del jugador](docs/datos.md): esquema del perfil, sesión, migraciones y buzón offline.
- [Red y seguridad](docs/red-y-seguridad.md): NetworkBridge, rate limiting, validación y anti-cheat.
- [Zonas y teletransporte](docs/zonas.md): portales, pantalla de carga y validaciones de llegada.
- [Guerra de Arquitectos](docs/guerra-arquitectos.md): ciclo de partida, recursos, construcción y recompensas.
- [Roadmap](docs/roadmap.md): fases, decisiones y pendientes.

## Inicio rápido

1. Instalá [Rojo](https://rojo.space) y su plugin de Studio (o cargá los scripts a mano: ver [instalación](docs/instalacion.md)).
2. `rojo serve` en la raíz del repo y conectá desde Studio.
3. Publicá el place y activá *Game Settings > Security > Enable Studio Access to API Services*.
4. Play: en Output tiene que aparecer `[RaidBlox] Servidor iniciado - Fase 2`.

## Herramientas

| Herramienta | Uso | Config |
| --- | --- | --- |
| [Rojo](https://rojo.space) | Sincroniza `src/` con Studio | `default.project.json` |
| [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) | Chequeo de tipos `--!strict` | — |
| [Selene](https://github.com/Kampfkarren/selene) | Lint | `selene.toml` |
| [StyLua](https://github.com/JohnnyMorganz/StyLua) | Formato | `stylua.toml` |

## Dependencias de terceros

- [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) de loleris (Apache 2.0), incluido en
  `src/ServerScriptService/Packages/` junto con su licencia.
