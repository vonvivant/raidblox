# Matriz de seguimiento de los 39 NPC

Estado real de cada NPC del pedido "39 NPC". Se actualiza con cada etapa.

**Cómo leer el estado.** Ningún NPC fue probado todavía dentro de Roblox Studio, así que ninguno figura como
"Probado" ni "Integrado y validado":

| Estado | Significa |
|---|---|
| Implementado sin verificar | El código está escrito, pasa el chequeo de tipos estricto, el lint y las pruebas de datos, pero falta probarlo en Studio |
| En desarrollo | El sistema de fondo ya existe en el juego y se usa desde otro lado; el NPC lo indica pero todavía no lo opera él |
| Pendiente | Falta el sistema. El NPC se puede colocar, dice qué falta y tiene sus reglas definidas como datos |

Lo que comparten todos los NPC (ya implementado, sin verificar en Studio):

| Aspecto | Cómo está resuelto |
|---|---|
| Modelo 3D | Maniquí R15 genérico con color por profesión y contorno del color de la facción. **Es un placeholder**: faltan modelos, vestimenta, accesorios y animaciones propias |
| Spawn | Marcador en el mapa: `Model` con tag `NpcArquetipo` y atributos `Arquetipo` y `Faccion`. En pruebas, los puestos de `NpcArquetiposConfig.DePrueba` |
| Interacción | `ProximityPrompt` + validación en el servidor en cada pedido: NPC existente, distancia, facción y datos cargados |
| UI | Una sola ventana (`NpcUI`) que arma secciones según lo que ofrece el NPC; bóveda, crafteo y subastas abren sus propias ventanas |
| Seguridad | Remotes con `Guard` y límite de frecuencia; precios, ofertas y destinos solo del servidor; operaciones de todo o nada |
| Persistencia | Perfil del jugador con ProfileStore (sesión única, guardado periódico y al salir) |
| Pruebas | `python3 tests/run.py`: coherencia de datos y reglas puras de la forja, el personalizador, la exploración y la progresión social (44 pruebas, pasan). Pruebas en Studio: **pendientes** |

## Por NPC

Esta tabla se genera con `python3 tests/matriz.py` a partir de `NpcArquetiposConfig`.

<!-- MATRIZ:INICIO -->
Hoy: **31** implementados sin verificar, **2** en desarrollo y **6** pendientes (total 39).

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
| NPC-009 | Reparador de Armaduras (`ReparadorArmaduras`) | Rojo, Azul, Neutral | Reparar lo equipado, Reparar todo | Tarifa de emergencia dentro de mazmorras (x3) | Implementado sin verificar |
| NPC-010 | Maestro Encantador (`MaestroEncantador`) | Rojo, Azul, Neutral | Engarzar gema | Runas con brillo; Sacar o reemplazar gemas | Implementado sin verificar |
| NPC-011 | Desencantador (`Desencantador`) | Rojo, Azul, Neutral | Desencantar | — | Implementado sin verificar |
| NPC-012 | Reforjador de Atributos (`ReforjadorAtributos`) | Rojo, Azul, Neutral | Reforjar | Elegir qué efecto reemplazar; Vista previa antes de confirmar | Implementado sin verificar |
| NPC-013 | Fundidor (`Fundidor`) | Rojo, Azul, Neutral | vende 2 ítems, fabrica en Yunque | — | Implementado sin verificar |

### Grupo C — Economía, comercio y almacenamiento

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-014 | Banquero (`Banquero`) | Rojo, Azul, Neutral | Abrir la bóveda | — | Implementado sin verificar |
| NPC-015 | Banquero de Clan (`BanqueroClan`) | Rojo, Azul, Neutral | Banco de la hermandad | Límite diario de retiro por rango; Exigir estar junto al NPC para operar | Implementado sin verificar |
| NPC-016 | Subastador (`Subastador`) | Rojo, Azul | Casa de Subastas | Pujas con reserva de fondos y devolución al superado; Filtro por nivel | Implementado sin verificar |
| NPC-017 | Comerciante de Excedentes (`ComercianteExcedentes`) | Rojo, Azul, Neutral | vende 2 ítems, compra excedentes | Hacha; Caña de pescar | Implementado sin verificar |
| NPC-018 | Cambista (`Prestamista`) | Rojo, Azul, Neutral | Cambiar 10 de honor, Cambiar 100 de honor, Cambiar 1.000 de honor | Divisas de evento; Mostrar el oro como Bronce / Plata / Oro | Implementado sin verificar |
| NPC-019 | Vendedor del Mercado Negro (`MercadoNegro`) | Neutral | vende 9 ítems | Requisito de reputación; Recetas exclusivas; Cosméticos raros | Implementado sin verificar |

### Grupo D — Viajes, cartografía y logística

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-020 | Guardián de Portales (`GuardianPortales`) | Rojo, Azul, Neutral | viajes por territorio | — | Implementado sin verificar |
| NPC-021 | Maestro de Establo (`MaestroEstablo`) | Rojo, Azul, Neutral | Comprar el Corcel de Guerra, Comprar el Lobo de las Nieves, Alquilar un corcel por una hora, Entrenar velocidad | Alimentar monturas; Restricciones de montura por zona | Implementado sin verificar |
| NPC-022 | Navegante (`Navegante`) | Rojo, Azul, Neutral | — | Rutas con vehículo (hoy se puede usar el Guardián de Portales) | Pendiente |
| NPC-023 | Cartógrafo (`Cartografo`) | Rojo, Azul, Neutral | Comprar el mapa de la zona | Mapas de otras zonas; Coleccionables de exploración | Implementado sin verificar |
| NPC-024 | Guardián de Piedra Teleport (`GuardianPiedraTeleport`) | Rojo, Azul, Neutral | Activar la piedra cercana | Costo en cristales en lugar de oro | Implementado sin verificar |

### Grupo E — Misiones, facciones y progresión

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-025 | Tabernero (`Tabernero`) | Rojo, Azul, Neutral | Alquilar una habitación, Preguntar por rumores | — | Implementado sin verificar |
| NPC-026 | Tablón de Anuncios (`TablonAnuncios`) | Rojo, Azul, Neutral | el sistema existe en: El Tablón de Anuncios de las misiones (3 contratos diarios; hablale a él, no a este NPC) | Contratos de PvP; Contratos semanales | En desarrollo |
| NPC-027 | Emisario de Facción (`EmisarioFaccion`) | Rojo, Azul | Ver recompensas de facción | Monturas y equipo exclusivo por reputación | Implementado sin verificar |
| NPC-028 | Entrenador de Clase (`EntrenadorClase`) | Rojo, Azul, Neutral | el sistema existe en: Las habilidades vienen con la clase (panel Personaje; el Chatarrero elige con K) | Habilidades que se aprenden | En desarrollo |

### Grupo F — Cosméticos y personalización

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-029 | Barbero (`Barbero`) | Rojo, Azul, Neutral | Cambiar de estilo | — | Implementado sin verificar |
| NPC-030 | Transfigurador (`Transfigurador`) | Rojo, Azul, Neutral | Transfigurar equipo | — | Implementado sin verificar |
| NPC-031 | Tintorero (`Tintorero`) | Rojo, Azul, Neutral | Volver a pintar mi equipo | — | Implementado sin verificar |
| NPC-032 | Vendedor de Mascotas (`VendedorMascotas`) | Rojo, Azul, Neutral | Comprar a Hojita, Comprar a Piedrín, Comprar a Lucero, Ver mis mascotas | — | Implementado sin verificar |

### Grupo G — Vida social, vivienda y minijuegos

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-033 | Arquitecto (`Arquitecto`) | Rojo, Azul, Neutral | — | Parcelas | Pendiente |
| NPC-034 | Chef (`Chef`) | Rojo, Azul, Neutral | vende 3 ítems, fabrica en Fogon | — | Implementado sin verificar |
| NPC-035 | Maestro de Pesca (`MaestroPesca`) | Rojo, Azul, Neutral | vende 1 ítems, compra excedentes, ¿Dónde pican hoy? | Cebos por bioma; Peces raros por temporada | Implementado sin verificar |
| NPC-036 | Crupier (`Crupier`) | Neutral | — | Minijuegos | Pendiente |

### Grupo H — PvP, arenas y guerra

| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |
|---|---|---|---|---|---|
| NPC-037 | Intendente de Guerra (`IntendenteGuerra`) | Rojo, Azul | vende 3 ítems | Set de armadura PvP por bando | Implementado sin verificar |
| NPC-038 | Reclutador de Arenas (`ReclutadorArenas`) | Rojo, Azul, Neutral | Anotarme en 1v1, Anotarme en 2v2, Anotarme en 3v3, Sacarme de la cola | — | Implementado sin verificar |
| NPC-039 | Estratega de Asedio (`EstrategaAsedio`) | Rojo, Azul | — | Asedios de castillos entre hermandades | Pendiente |
<!-- MATRIZ:FIN -->

## Pruebas del pedido (sección 13) y su estado

| # | Prueba | Estado |
|---|---|---|
| 4 | Validar precios (lo vendido existe y no se puede revender con ganancia) | Automatizada, pasa (`tests/datos.spec.luau`) |
| 8 | Recetas: materiales y resultados existen | Automatizada, pasa |
| 11 | Reparar y mejorar equipo: reglas de durabilidad, costos, qué acepta cada operación | Automatizada, pasa (reglas puras de `ForjaConfig`); el flujo en juego, pendiente |
| 19 | Restricciones de facción: cada zona tiene territorio y hay destinos de los tres | Automatizada, pasa (datos); el flujo en juego, pendiente |
| 1–3, 5–7, 9–18, 20–30 | Todo lo que necesita un servidor de Roblox (abrir NPC, comprar, lejos, remotes inválidos, buffs, banco, subastas, reconexión, viajes, multi-servidor, fallas de DataStore, memoria) | **Pendiente**: hay que correrlas en Studio o en un servidor publicado |

## Orden de trabajo

1. ~~Infraestructura: registro, facciones, vendedor, artesano, servicios, viajes~~ (hecho).
2. ~~Efectos de consumibles y Grupo A: NPC 001, 002, 003 y 006~~ (hecho). Faltan 004 (necesita talentos) y 005 (pergaminos).
3. ~~Grupo B: durabilidad y reparación (009), gemas (010), desencantar (011), reforja (012), transmutación (013)~~ (hecho). Quedan mejoras menores anotadas en cada fila.
4. ~~Grupo C: banco de clan desde el NPC (015), filtros de subastas (016), cambista (018), stock rotativo del mercado negro (019)~~ (hecho). **Falta decidir** las pujas y la separación de subastas por bando.
5. Grupo D: waypoints (024), cartógrafo (023), establo (021), rutas con vehículo (022), pergaminos de viaje (005).
6. ~~Grupo E: descanso y rumores (025), diarias (026), reputación (027)~~ (hecho, ver [progresión social](progresion-social.md)). Queda 028 (entrenador): **falta decidir** si vende habilidades por oro o si se hace un sistema de talentos.
7. ~~Grupo F completo: barbero (029), transfigurador (030), tintorero (031, retoca lo que ya tenés) y mascotas por oro (032)~~ (hecho, ver [cosméticos](cosmeticos.md)).
8. Grupo G: ~~cocina (034) y pesca (035)~~ (hecho, ver [economía](economia.md)). Quedan vivienda (033, con las parcelas) y minijuegos sin apuestas (036).
9. Grupo H: ~~equipo PvP (037) y arenas clasificatorias (038, ver [arenas](arenas.md))~~ (hecho). Queda 039 (asedio), que depende de los castillos de hermandad.
