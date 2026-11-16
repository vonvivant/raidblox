# Descanso, contratos diarios y reputación

Grupo E de los 39 NPC: Tabernero (025), Tablón de Anuncios (026) y Emisario de Facción (027). Números en
`Configs/ProgresionSocialConfig.luau`; servidor en `Systems/ProgresionSocialManager.luau` (y las diarias en
`MisionManager`).

**Sin probar en Studio.** Pasa el chequeo de tipos, el lint y las pruebas de datos.

## Descanso (NPC-025 Tabernero)

El Tabernero alquila una habitación por 50 de oro: suma 2.000 de **saldo de descanso** (tope 12.000). Mientras
haya saldo, toda la experiencia que gana el jugador rinde un **50% más**, y el extra se descuenta del saldo. No es
experiencia infinita: lo que se gana de más es exactamente lo que se compró. No se puede descansar en combate.

El saldo vive en `DatosJugador.Descanso` y se aplica en un gancho de `DataManager.AddExperience`
(`DataManager.SetBonusXp`), así que vale para cualquier fuente de experiencia: enemigos, misiones, mazmorras.

## Rumores (NPC-025)

Por 10 de oro, el Tabernero dice si hay un jefe de mundo vivo en el servidor y en qué coordenadas
(`RaidBloxManager.JefeActivo()`). Si no hay ninguno, lo dice.

## Contratos diarios (NPC-026 Tablón de Anuncios)

El **Tablón de Anuncios** es un NPC de misiones (como el Capitán o el Herrero): está en la plaza y tiene el signo
de misión. Da **5 contratos**, de los que se pueden tomar **3 por día**:

| Contrato | Objetivo | Nivel |
|---|---|---|
| Manada de lobos | 8 lobos | 1 |
| Mineral de hierro | 10 minerales | 1 |
| Hierbas sanadoras | 8 hierbas | 1 |
| Entrenamiento diario | 10 muñecos | 1 |
| Bandidos del camino | 6 bandidos | 3 |

- El día cambia a las **19:00 UTC** (16:00 en Argentina). El mismo contrato no se puede tomar dos veces el mismo
  día; el juego avisa cuántas horas faltan para los próximos.
- Las diarias **rinden el doble** de experiencia y oro que una misión normal del mismo tamaño
  (`Diarias.MultiplicadorRecompensa`).
- Se guardan en `DatosJugador.Diarias = { Dia, Tomadas }`; la lista se reinicia sola al cambiar el día.

En `MisionesConfig`, una misión diaria lleva `Diaria = true` y `Repetible = true`.

El arquetipo NPC-026 queda como "en desarrollo": existe como dato, pero los contratos se toman hablándole al
Tablón de misiones, no a ese NPC.

## Reputación de facción (NPC-027 Emisario)

Cada bando tiene su propia reputación (`DatosJugador.Reputacion`). Los jugadores Violeta no ganan reputación: hay
que elegir Rojo o Azul en el panel Personaje.

| Cómo se gana | Puntos |
|---|---|
| Ganar una partida de la Guerra de Arquitectos | 150 |
| Perderla (habiendo aportado) | 50 |
| Derrotar a un jugador del bando rival | 10 |

Hay un **tope de 1.500 por día** (`ReputacionHoy`) para que no se farmee sin límite, y un máximo de 50.000.

| Rango | Desde |
|---|---|
| Neutral | 0 |
| Amistoso | 1.000 |
| Honorable | 5.000 |
| Reverenciado | 15.000 |
| Exaltado | 35.000 |

El Emisario (uno Rojo y uno Azul) cambia **puntos de honor** por títulos y materiales, con reputación mínima:

| Recompensa | Rango | Honor |
|---|---|---|
| Título "Soldado" | Amistoso | 200 |
| Título "Veterano" | Honorable | 800 |
| Título "Campeón del Bando" | Reverenciado | 2.500 |
| Núcleo de Obsidiana | Honorable | 400 |
| Diamante de Guerra | Reverenciado | 900 |

La ventana (`EmisarioUI`) muestra tu rango, cuánto falta para el siguiente y qué podés canjear. El servidor
valida cercanía al NPC (`NpcManager.Cerca`), reputación y honor en cada compra, y entrega antes de cobrar sin
ceder el hilo.

## Lo que falta de este grupo

- **NPC-028 Entrenador de Clase:** pendiente, y necesita una decisión. Hoy las habilidades vienen con la clase y
  no hay puntos que gastar. Las dos opciones son que el entrenador venda habilidades extra por oro (acotado) o
  armar un sistema de talentos con puntos por nivel (mucho más grande, y también lo necesita el NPC-004 Borrador
  de Recuerdos).
- Contratos de PvP y semanales; monturas y equipo exclusivo por reputación; experiencia de descanso que se
  acumule sola con el tiempo desconectado.
