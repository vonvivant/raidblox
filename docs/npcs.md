# NPCs por arquetipo

Los NPCs de servicio (vendedores, artesanos, guardianes de portales, etc.) salen de una sola base de datos:
`ReplicatedStorage/Configs/NpcArquetiposConfig.luau`, con los **38 arquetipos** en 8 categorías. El servidor los
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

Los `IQuestGiver` (Tabernero, Tablón) están definidos como datos; las misiones siguen saliendo de `MisionManager`.

Para sumar una acción de servicio desde otro sistema:

```lua
NpcManager.RegistrarAccion("Vault", function(player, npc, servicio): boolean
	-- abrir la bóveda...
	return true -- recién ahí se cobra `servicio.Costo`
end)
```

Las acciones no deben ceder el hilo (sin `task.wait` ni llamadas a DataStore): entre la verificación del oro y el
cobro no puede cambiar el saldo.

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

- **Listo** (11): funciona hablando con el NPC.
- **Parcial** (9): el sistema ya existe pero se usa desde otro lado; el NPC lo indica.
- **Pendiente** (18): falta el sistema. El NPC se puede colocar y dice qué falta; `Parametros` deja
  definidos precios, duraciones y reglas para cuando se programe.

En `Vende` solo hay ítems que existen hoy en el `ItemCatalog`, con precio de venta por encima de lo que paga un NPC
al comprarlos (así no se puede ganar oro comprando y revendiendo).

## Los 38 arquetipos

### Alquimia, magia y consumibles

| # | Arquetipo (clave) | Interfaces | Versiones | Estado |
|---|---|---|---|---|
| 1 | **Boticario** (`Boticario`): Herborista dedicado: pociones de salud y antídotos. | IVendor, ICrafter | Rojo, Azul y Neutral | ✅ Listo |
| 2 | **Boticario Espiritual** (`BoticarioEspiritual`): Místico: maná, stamina, enfoque y reducción de recargas. | IVendor, ICrafter | Rojo, Azul y Neutral | ✅ Listo |
| 3 | **Alquimista Experimental** (`AlquimistaExperimental`): Elixires temporales de atributos y de riesgo/recompensa. | IVendor, ICrafter | Rojo, Azul y Neutral | ⏳ Pendiente |
| 4 | **Borrador de Recuerdos** (`BorradorRecuerdos`): Chamán de restablecimiento: reinicia talentos, habilidades o atributos. | IServiceProvider | Rojo, Azul y Neutral | ⏳ Pendiente |
| 5 | **Inscriptor** (`Inscriptor`): Sastre de pergaminos: teletransporte, buffs de grupo y mapas. | IVendor, ICrafter | Rojo, Azul y Neutral | ⏳ Pendiente |

### Herrería, equipo y forja

| # | Arquetipo (clave) | Interfaces | Versiones | Estado |
|---|---|---|---|---|
| 6 | **Herrero General** (`HerreroGeneral`): Equipo básico de hierro y piezas iniciales con lingotes. | IVendor, ICrafter | Rojo, Azul y Neutral | ✅ Listo |
| 7 | **Afilador de Armas** (`AfiladorArmas`): Maestro de filo: mejora temporal del arma. | IServiceProvider | Rojo, Azul y Neutral | ✅ Listo |
| 8 | **Reparador de Armaduras** (`ReparadorArmaduras`): Remendador: restaura la durabilidad del equipo. | IServiceProvider | Rojo, Azul y Neutral | ⏳ Pendiente |
| 9 | **Maestro Encantador** (`MaestroEncantador`): Aumentos, gemas, encantamientos y runas con brillo. | IServiceProvider, ICrafter | Rojo, Azul y Neutral | ⏳ Pendiente |
| 10 | **Desencantador** (`Desencantador`): Desmantelador: destruye ítems mágicos para sacar esencias. | IServiceProvider | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Yunque Portátil del Chatarrero (desmantela equipo Común o Raro) |
| 11 | **Reforjador de Atributos** (`ReforjadorAtributos`): Cambia las estadísticas secundarias de un arma o armadura. | IServiceProvider | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Ficha de Re-roll (Tienda → Colección) |
| 12 | **Fundidor** (`Fundidor`): Metalúrgico: minerales en lingotes y transmutación. | ICrafter, IVendor | Rojo, Azul y Neutral | ✅ Listo |

### Economía, comercio y almacenamiento

| # | Arquetipo (clave) | Interfaces | Versiones | Estado |
|---|---|---|---|---|
| 13 | **Banquero** (`Banquero`): Guardián de la bóveda: almacén personal y compartido de la cuenta. | IServiceProvider | Rojo, Azul y Neutral | ✅ Listo |
| 14 | **Banquero de Clan** (`BanqueroClan`): Tesorero: inventario y fondos de la hermandad. | IServiceProvider | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Banco de hermandad (botón Hermandad del menú) |
| 15 | **Subastador** (`Subastador`): Corredor de bolsa: Casa de Subastas. | IServiceProvider | Rojo y Azul | ✅ Listo |
| 16 | **Comerciante de Excedentes** (`ComercianteExcedentes`): Chatarreo: compra lo que te sobra y vende herramientas básicas. | IVendor | Rojo, Azul y Neutral | ✅ Listo |
| 17 | **Prestamista** (`Prestamista`): Cambista: convierte monedas y divisas de eventos. | IServiceProvider | Rojo, Azul y Neutral | ⏳ Pendiente |
| 18 | **Vendedor del Mercado Negro** (`MercadoNegro`): Rarezas, recetas especiales y contenedores por oro, para cualquiera. | IVendor | Solo Neutral | ✅ Listo |

### Viajes, cartografía y logística

| # | Arquetipo (clave) | Interfaces | Versiones | Estado |
|---|---|---|---|---|
| 19 | **Guardián de Portales** (`GuardianPortales`): Teletransporta entre mapas respetando los territorios. | IServiceProvider | Rojo, Azul y Neutral | ✅ Listo |
| 20 | **Maestro de Establo** (`MaestroEstablo`): Criador: monturas básicas, alquiler y entrenamiento. | IVendor, IServiceProvider | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Monturas (tecla G): caballo gratis y Dragón de Fuego con pase |
| 21 | **Navegante** (`Navegante`): Transportista: barcos, dirigibles o carros entre puertos. | IServiceProvider | Rojo, Azul y Neutral | ⏳ Pendiente |
| 22 | **Cartógrafo** (`Cartografo`): Explorador: mapas de zonas ocultas y puntos de interés. | IVendor, IServiceProvider | Rojo, Azul y Neutral | ⏳ Pendiente |
| 23 | **Guardián de Piedra Teleport** (`GuardianPiedraTeleport`): Portalero: activa puntos de viaje rápido. | IServiceProvider | Rojo, Azul y Neutral | ⏳ Pendiente |

### Misiones, facciones y progresión

| # | Arquetipo (clave) | Interfaces | Versiones | Estado |
|---|---|---|---|---|
| 24 | **Tabernero** (`Tabernero`): Informante: misiones secundarias, rumores y descanso. | IQuestGiver, IServiceProvider | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Misiones (NPCs con ! del mapa) |
| 25 | **Tablón de Anuncios** (`TablonAnuncios`): Cazador de recompensas: misiones diarias y contratos de caza. | IQuestGiver | Rojo, Azul y Neutral | ⏳ Pendiente |
| 26 | **Emisario de Facción** (`EmisarioFaccion`): Intendente: recompensas exclusivas por reputación. | IVendor | Rojo y Azul | ⏳ Pendiente |
| 27 | **Entrenador de Clase** (`EntrenadorClase`): Maestro de habilidades: enseña técnicas y vende libros. | IServiceProvider, IVendor | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Las habilidades vienen con la clase (panel Personaje; el Chatarrero elige con K) |

### Cosméticos, personalización y estilo

| # | Arquetipo (clave) | Interfaces | Versiones | Estado |
|---|---|---|---|---|
| 28 | **Barbero** (`Barbero`): Estilista: peinado, marcas, color de piel y tatuajes. | IServiceProvider | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Género del personaje (panel Personaje) |
| 29 | **Transfigurador** (`Transfigurador`): Maestro del disfraz: cambia el aspecto del equipo sin tocar sus stats. | IServiceProvider | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Apariencias (Tienda → Colección) |
| 30 | **Tintorero** (`Tintorero`): Maestro de colores: tintes para armaduras y telas. | IVendor, ICrafter | Rojo, Azul y Neutral | ⏳ Pendiente |
| 31 | **Vendedor de Mascotas** (`VendedorMascotas`): Mascotas que acompañan y juntan botín. | IVendor | Rojo, Azul y Neutral | 🟡 Parcial — hoy: Mascotas (se ganan en el Pase de batalla; Tienda → Colección) |

### Vida social, casas y minijuegos

| # | Arquetipo (clave) | Interfaces | Versiones | Estado |
|---|---|---|---|---|
| 32 | **Arquitecto** (`Arquitecto`): Planos de casas, terrenos y decoración. | IVendor | Rojo, Azul y Neutral | ⏳ Pendiente |
| 33 | **Chef** (`Chef`): Maestro culinario: ingredientes, recetas y comida con buffs largos. | IVendor, ICrafter | Rojo, Azul y Neutral | ⏳ Pendiente |
| 34 | **Maestro de Pesca** (`MaestroPesca`): Biólogo marino: cañas, cebos por bioma y peces raros. | IVendor, ICrafter | Rojo, Azul y Neutral | ⏳ Pendiente |
| 35 | **Crupier** (`Crupier`): Maestro de juegos: dados, cartas y carreras en tabernas. | IServiceProvider | Solo Neutral | ⏳ Pendiente |

### PvP y guerra

| # | Arquetipo (clave) | Interfaces | Versiones | Estado |
|---|---|---|---|---|
| 36 | **Intendente de Guerra** (`IntendenteGuerra`): Equipo y consumibles PvP por puntos de honor. | IVendor | Rojo y Azul | ✅ Listo |
| 37 | **Reclutador de Arenas** (`ReclutadorArenas`): Inscribe jugadores o grupos en partidas clasificatorias. | IServiceProvider | Rojo, Azul y Neutral | ⏳ Pendiente |
| 38 | **Estratega de Asedio** (`EstrategaAsedio`): Maquinaria pesada para guerras de clanes y castillos. | IVendor, ICrafter | Rojo y Azul | ⏳ Pendiente |

## Colocar NPCs en un mapa

1. Poné un `Model` con una parte `HumanoidRootPart` (o `PrimaryPart`) anclada.
2. Agregale el tag **`NpcArquetipo`**.
3. Atributos: `Arquetipo` (la clave, por ejemplo `HerreroGeneral`) y `Faccion` (`Rojo`, `Azul` o `Neutral`).

`NpcManager` le pone el cartel de "Hablar" y lo registra. También se pueden crear por código:
`NpcManager.Crear("Boticario", "Rojo", posicion)`.

En Studio o con `ModoPruebas`, si el mapa no tiene ninguno, aparecen 12 de prueba (`NpcArquetiposConfig.DePrueba`)
al oeste del punto de inicio: tres Guardianes de Portales (uno por facción), Herrero, Boticarios, Comerciante,
Afilador, Mercado Negro, Subastador, Intendente de Guerra y Banquero (abre la [bóveda](vault.md)).

## Seguridad

- El cliente solo manda el id del NPC y qué quiere; precios, ofertas y destinos se leen del servidor.
- Cada pedido revalida: NPC existente, distancia (`DistanciaInteraccion`, 14 studs), bando y datos cargados.
- Cantidades con tope (99 por compra; 10 si el ítem no se apila) y todos los argumentos pasan por `Guard`.
- Compra: se verifica el saldo, se agrega el ítem (todo o nada) y se cobra, sin ceder el hilo en el medio.
- Venta: solo desde ranuras de la mochila (nunca lo equipado) y solo los tipos que ese NPC compra.

## Pendiente de decidir

**Subastas separadas por bando.** El diseño pide que el Subastador Rojo y el Azul tengan mercados distintos. Hoy
la Casa de Subastas es una sola; separarla parte la economía actual y deja fuera a los jugadores Violeta, así que
quedó apagado (`Subastador.Parametros.SeparacionActiva = false`) hasta confirmarlo.
