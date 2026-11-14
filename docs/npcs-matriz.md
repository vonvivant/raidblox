# Matriz de seguimiento de los 39 NPC

Estado real de cada NPC del pedido "39 NPC". Se actualiza con cada etapa.

**Cómo leer el estado.** Ningún NPC fue probado todavía dentro de Roblox Studio, así que ninguno figura como
"Probado" ni "Integrado y validado":

| Estado | Significa | Cantidad |
|---|---|---|
| Implementado sin verificar | El código está escrito, pasa el chequeo de tipos estricto, el lint y las pruebas de datos, pero falta probarlo en Studio | 13 |
| En desarrollo | El sistema de fondo ya existe en el juego y se usa desde otro lado; el NPC lo indica pero todavía no lo opera él | 9 |
| Pendiente | Falta el sistema. El NPC se puede colocar, dice qué falta y tiene sus reglas definidas como datos | 17 |

Lo que comparten todos los NPC (ya implementado, sin verificar en Studio):

| Aspecto | Cómo está resuelto |
|---|---|
| Modelo 3D | Maniquí R15 genérico con color por profesión y contorno del color de la facción. **Es un placeholder**: faltan modelos, vestimenta, accesorios y animaciones propias |
| Spawn | Marcador en el mapa: `Model` con tag `NpcArquetipo` y atributos `Arquetipo` y `Faccion`. En pruebas, 14 puestos de `NpcArquetiposConfig.DePrueba` |
| Interacción | `ProximityPrompt` + validación en el servidor en cada pedido: NPC existente, distancia, facción y datos cargados |
| UI | Una sola ventana (`NpcUI`) que arma secciones según lo que ofrece el NPC; bóveda, crafteo y subastas abren sus propias ventanas |
| Seguridad | Remotes con `Guard` y límite de frecuencia; precios, ofertas y destinos solo del servidor; operaciones de todo o nada |
| Persistencia | Perfil del jugador con ProfileStore (sesión única, guardado periódico y al salir) |
| Pruebas | `python3 tests/run.py`: coherencia de datos (9 pruebas, pasan). Pruebas en Studio: **pendientes** |

## Por NPC

### Grupo A — Alquimia, magia y consumibles

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-001 | Boticario (`Boticario`) | Rojo, Azul, Neutral | vende 5 ítems, fabrica en MesaAlquimia | — | Implementado sin verificar |
| NPC-002 | Boticario Espiritual (`BoticarioEspiritual`) | Rojo, Azul, Neutral | vende 4 ítems, fabrica en MesaAlquimia | — | Implementado sin verificar |
| NPC-003 | Alquimista Experimental (`AlquimistaExperimental`) | Rojo, Azul, Neutral | vende 5 ítems, fabrica en MesaAlquimia | — | Implementado sin verificar |
| NPC-004 | Borrador de Recuerdos (`BorradorRecuerdos`) | Rojo, Azul, Neutral | — | Sistema de talentos (hoy la clase define todas las habilidades) | Pendiente |
| NPC-005 | Inscriptor (`Inscriptor`) | Rojo, Azul, Neutral | — | Pergaminos: usar el viaje del Guardián desde un ítem, buff a todo el grupo e ítems sin identificar | Pendiente |
| NPC-006 | Barista de Tés (`BaristaTes`) | Rojo, Azul, Neutral | vende 4 ítems, fabrica en MesaAlquimia | Recetas raras por bioma; Resistencia a estados negativos (hoy: +defensa) | Implementado sin verificar |

### Grupo B — Herrería, equipamiento y forja

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-007 | Herrero General (`HerreroGeneral`) | Rojo, Azul, Neutral | vende 3 ítems, fabrica en Yunque | Línea de acero | Implementado sin verificar |
| NPC-008 | Afilador de Armas (`AfiladorArmas`) | Rojo, Azul, Neutral | Afilar el arma | Precisión; Penetración de armadura; Pago con piedras de afilar | Implementado sin verificar |
| NPC-009 | Reparador de Armaduras (`ReparadorArmaduras`) | Rojo, Azul, Neutral | — | Durabilidad del equipo | Pendiente |
| NPC-010 | Maestro Encantador (`MaestroEncantador`) | Rojo, Azul, Neutral | — | Gemas engarzables (las gemas ya existen como material) | Pendiente |
| NPC-011 | Desencantador (`Desencantador`) | Rojo, Azul, Neutral | el sistema existe en: Yunque Portátil del Chatarrero (desmantela equipo Común o Raro) | Ítems de esencia | En desarrollo |
| NPC-012 | Reforjador de Atributos (`ReforjadorAtributos`) | Rojo, Azul, Neutral | el sistema existe en: Ficha de Re-roll (Tienda → Colección) | — | En desarrollo |
| NPC-013 | Fundidor (`Fundidor`) | Rojo, Azul, Neutral | vende 2 ítems, fabrica en Yunque | Receta de transmutación | Implementado sin verificar |

### Grupo C — Economía, comercio y almacenamiento

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-014 | Banquero (`Banquero`) | Rojo, Azul, Neutral | Abrir la bóveda | — | Implementado sin verificar |
| NPC-015 | Banquero de Clan (`BanqueroClan`) | Rojo, Azul, Neutral | el sistema existe en: Banco de hermandad (botón Hermandad del menú) | — | En desarrollo |
| NPC-016 | Subastador (`Subastador`) | Rojo, Azul | Casa de Subastas | — | Implementado sin verificar |
| NPC-017 | Comerciante de Excedentes (`ComercianteExcedentes`) | Rojo, Azul, Neutral | vende 2 ítems, compra excedentes | Hacha; Caña de pescar | Implementado sin verificar |
| NPC-018 | Prestamista (`Prestamista`) | Rojo, Azul, Neutral | — | Divisas de evento | Pendiente |
| NPC-019 | Vendedor del Mercado Negro (`MercadoNegro`) | Neutral | vende 5 ítems | Cosméticos raros; Recetas especiales; Contenedores aleatorios por oro (con probabilidades a la vista) | Implementado sin verificar |

### Grupo D — Viajes, cartografía y logística

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-020 | Guardián de Portales (`GuardianPortales`) | Rojo, Azul, Neutral | viajes por territorio | — | Implementado sin verificar |
| NPC-021 | Maestro de Establo (`MaestroEstablo`) | Rojo, Azul, Neutral | el sistema existe en: Monturas (tecla G): caballo gratis y Dragón de Fuego con pase | Monturas compradas con oro y entrenamiento | En desarrollo |
| NPC-022 | Navegante (`Navegante`) | Rojo, Azul, Neutral | — | Rutas con vehículo (hoy se puede usar el Guardián de Portales) | Pendiente |
| NPC-023 | Cartógrafo (`Cartografo`) | Rojo, Azul, Neutral | — | Puntos de interés por zona | Pendiente |
| NPC-024 | Guardián de Piedra Teleport (`GuardianPiedraTeleport`) | Rojo, Azul, Neutral | — | Waypoints guardados en el perfil | Pendiente |

### Grupo E — Misiones, facciones y progresión

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-025 | Tabernero (`Tabernero`) | Rojo, Azul, Neutral | el sistema existe en: Misiones (NPCs con ! del mapa) | Experiencia de descanso | En desarrollo |
| NPC-026 | Tablón de Anuncios (`TablonAnuncios`) | Rojo, Azul, Neutral | — | Misiones diarias con reinicio | Pendiente |
| NPC-027 | Emisario de Facción (`EmisarioFaccion`) | Rojo, Azul | — | Reputación por bando | Pendiente |
| NPC-028 | Entrenador de Clase (`EntrenadorClase`) | Rojo, Azul, Neutral | el sistema existe en: Las habilidades vienen con la clase (panel Personaje; el Chatarrero elige con K) | Habilidades que se aprenden | En desarrollo |

### Grupo F — Cosméticos y personalización

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-029 | Barbero (`Barbero`) | Rojo, Azul, Neutral | el sistema existe en: Género del personaje (panel Personaje) | Catálogo de peinados y tatuajes (Stencils) | En desarrollo |
| NPC-030 | Transfigurador (`Transfigurador`) | Rojo, Azul, Neutral | el sistema existe en: Apariencias (Tienda → Colección) | — | En desarrollo |
| NPC-031 | Tintorero (`Tintorero`) | Rojo, Azul, Neutral | — | Personalización de color por partes | Pendiente |
| NPC-032 | Vendedor de Mascotas (`VendedorMascotas`) | Rojo, Azul, Neutral | el sistema existe en: Mascotas (se ganan en el Pase de batalla; Tienda → Colección) | Mascotas compradas con oro | En desarrollo |

### Grupo G — Vida social, vivienda y minijuegos

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-033 | Arquitecto (`Arquitecto`) | Rojo, Azul, Neutral | — | Parcelas | Pendiente |
| NPC-034 | Chef (`Chef`) | Rojo, Azul, Neutral | — | Profesión de cocina y buffs por consumible | Pendiente |
| NPC-035 | Maestro de Pesca (`MaestroPesca`) | Rojo, Azul, Neutral | — | Pesca | Pendiente |
| NPC-036 | Crupier (`Crupier`) | Neutral | — | Minijuegos | Pendiente |

### Grupo H — PvP, arenas y guerra

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-037 | Intendente de Guerra (`IntendenteGuerra`) | Rojo, Azul | vende 3 ítems | Set de armadura PvP por bando | Implementado sin verificar |
| NPC-038 | Reclutador de Arenas (`ReclutadorArenas`) | Rojo, Azul, Neutral | — | Arenas con emparejamiento | Pendiente |
| NPC-039 | Estratega de Asedio (`EstrategaAsedio`) | Rojo, Azul | — | Asedios de castillos entre hermandades | Pendiente |

## Pruebas del pedido (sección 13) y su estado

| # | Prueba | Estado |
|---|---|---|
| 4 | Validar precios (lo vendido existe y no se puede revender con ganancia) | Automatizada, pasa (`tests/datos.spec.luau`) |
| 8 | Recetas: materiales y resultados existen | Automatizada, pasa |
| 19 | Restricciones de facción: cada zona tiene territorio y hay destinos de los tres | Automatizada, pasa (datos); el flujo en juego, pendiente |
| 1–3, 5–7, 9–18, 20–30 | Todo lo que necesita un servidor de Roblox (abrir NPC, comprar, lejos, remotes inválidos, buffs, banco, subastas, reconexión, viajes, multi-servidor, fallas de DataStore, memoria) | **Pendiente**: hay que correrlas en Studio o en un servidor publicado |

## Orden de trabajo

1. ~~Infraestructura: registro, facciones, vendedor, artesano, servicios, viajes~~ (hecho).
2. ~~Efectos de consumibles y Grupo A: NPC 001, 002, 003 y 006~~ (hecho). Faltan 004 (necesita talentos) y 005 (pergaminos).
3. Grupo B: durabilidad y reparación (009), gemas y engarces (010), desencantar (011), reforja con vista previa (012), transmutación (013).
4. Grupo C: banco de clan desde el NPC (015), filtros y pujas en subastas (016), cambista (018), stock rotativo del mercado negro (019).
5. Grupo D: waypoints (024), cartógrafo (023), establo (021), rutas con vehículo (022), pergaminos de viaje (005).
6. Grupo E: descanso y rumores (025), diarias y contratos (026), reputación (027), entrenador (028).
7. Grupo F: barbero (029), transfigurador desde el NPC (030), tintes (031), mascotas por oro (032).
8. Grupo G: vivienda (033, con las parcelas), cocina (034), pesca (035), minijuegos sin apuestas (036).
9. Grupo H: equipo PvP (037), arenas (038), asedio (039).
