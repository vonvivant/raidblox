# Arenas clasificatorias

El **Reclutador de Arenas** (NPC-038) anota al jugador en partidas de 1v1, 2v2 o 3v3 con rating. Es el PvP
organizado, aparte de la [Guerra de Arquitectos](guerra-arquitectos.md) y del PvP libre entre [bandos](bandos.md).

Reglas en `Configs/ArenasConfig.luau`, servidor en `Systems/Guerra/ArenaManager.luau`, cartel en `ArenaUI`.

## Cómo se juega

1. **Anotarse.** Se le habla al NPC y se elige el modo. En 2v2 y 3v3, si el jugador tiene grupo del tamaño
   exacto del modo, se anota el grupo entero y lo hace el líder; si el grupo es más grande, no entra. Un
   jugador no puede estar en dos colas ni anotarse mientras juega, y hay 8 segundos entre intentos.
2. **Emparejar.** Cada 2 segundos el servidor arma dos lados del tamaño del modo juntando lo que haya en la
   cola (un grupo de 2 más dos solos, por ejemplo). La ventana de rating arranca en 150 y se abre 50 cada 10
   segundos de espera, hasta 1200: así nadie queda colgado en un servidor con poca gente.
3. **Jugar.** La partida pasa a una plataforma generada lejos de la ciudad (una por partida, hasta 6 a la
   vez). Se juega **al mejor de tres rondas**: cada ronda empieza con todos vivos, curados y quietos 6
   segundos, y termina cuando un lado queda sin nadie en pie. Si se acaban los 100 segundos, gana el lado con
   más vida sumada; si empatan, la ronda no es de nadie.
4. **Terminar.** Al ganar dos rondas (o al jugarse las tres) se mueve el rating, se paga el honor y, 8
   segundos después, cada uno vuelve **exactamente al lugar desde donde se anotó**, curado.

Morir en la arena no devuelve al jugador a la ciudad: reaparece en su punto de salida y espera la ronda
siguiente. Irse del juego o quedarse solo con todos los compañeros desconectados cuenta como **rendirse**, y
el rival gana la partida.

## PvP dentro de la arena

En la arena manda la partida y no el bando: dos jugadores del mismo color, o dos Violeta, pueden pelear ahí y
en ningún otro lado. Lo resuelve un gancho que `ArenaManager` le pasa a `BandoManager`
(`BandoManager.SetArena`), que corta antes de las reglas de bando en `PuedeAtacar` y `SonHostiles`. Fuera de
la arena nada cambia: el Violeta sigue siendo intocable y hace falta zona PvP.

## Rating y rangos

Elo clásico por modo, arranca en **1000** con K = 24 y no baja de 0. Ganarle a alguien mejor paga más que
ganarle a alguien peor, y ganar siempre suma al menos 1 punto (perder siempre resta al menos 1).

| Desde | Rango |
| --- | --- |
| 0 | Sin rango |
| 900 | Bronce |
| 1150 | Plata |
| 1400 | Oro |
| 1650 | Platino |
| 1900 | Diamante |
| 2200 | Leyenda |

El rating de un equipo es el promedio de sus jugadores, y cada uno se mueve contra el promedio del equipo
rival.

## Premios

- **30 de honor** por victoria, **10** por derrota.
- **+5 por victoria seguida**, hasta 5 seguidas (así una buena racha paga 55).
- Tope de **300 de honor por día**, con el mismo corte que las misiones diarias (19:00 UTC). Pasado el tope se
  sigue jugando y el rating se sigue moviendo; solo deja de pagar honor.

El honor se gasta con el [Intendente de Guerra](npcs.md) (NPC-037) y el Emisario de Facción.

## Qué se guarda

En `DatosJugador.Pvp` (sección sincronizada `Pvp`): por modo, rating, ganadas, perdidas, racha actual y mejor
rating alcanzado; y aparte el día y el honor ya cobrado hoy. No se guarda nada "en partida", así que si el
servidor se cae en medio de una, nadie queda encerrado ni pierde el rating que ya tenía.

## Lo que falta

- **Temporadas**: hoy el rating no se reinicia nunca ni reparte premios de cierre.
- **Tabla de posiciones** entre servidores (haría falta un DataStore ordenado).
- **Mapas de verdad**: la plataforma es generada, sin obstáculos ni decoración.
- Nada de esto se probó en Studio todavía: las pruebas de `python3 tests/run.py` cubren el emparejamiento, el
  Elo, los rangos, los premios y que los números del mapa cierren, no la partida andando.
