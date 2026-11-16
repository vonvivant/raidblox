# Juegos del Crupier

El **Crupier** (NPC-036) tiene dos minijuegos de habilidad. Reglas en `Configs/JuegosConfig.luau`, servidor en
`Systems/JuegosManager.luau`, ventana en `JuegosUI`.

## Sin apuestas, a propósito

Roblox no permite apostar con nada que se compre con Robux, así que acá **no se apuesta nada y no se paga ni se
gana oro**. Jugar es gratis y lo único que se gana son **títulos** y el **récord personal**. El Crupier no vende
ni compra nada (hay una prueba que lo verifica, para que no se cuele una apuesta más adelante).

Entre partida y partida hay 15 segundos de espera, y solo se puede tener una partida abierta a la vez.

## Memoria de Runas

Cuatro runas de color. El servidor arma una secuencia y el cliente la enciende una por una; después el jugador la
repite. Cada ronda **agrega una runa** a la secuencia, hasta la ronda 20. Un error o quedarse sin tiempo termina
la partida, y el resultado son las rondas completas.

El tiempo crece con la secuencia: 3,5 segundos por runa para responder.

| Rondas | Título |
| --- | --- |
| 5 | Aprendiz de Runas |
| 9 | Memoria de Acero |
| 14 | Oráculo de la Taberna |

**Honestidad sobre las trampas:** este juego necesita que el cliente conozca la secuencia para poder mostrarla,
así que un cliente modificado podría responder perfecto. Como no hay premios de oro, de equipo ni de combate, el
que hace trampa se hace trampa a sí mismo. Si algún día se le pone una recompensa de valor, hay que cambiar el
juego (mostrar la secuencia desde el servidor, con partes que el cliente no vea de antemano).

## Encontrá los Pares

16 cartas, 8 pares, 16 intentos y 150 segundos. Se dan vuelta dos cartas: si coinciden, quedan descubiertas; si
no, se tapan de nuevo y se gasta un intento. El resultado son los **intentos usados** al limpiar el tablero, así
que acá menos es mejor. Quedarse sin intentos o sin tiempo cuenta como no terminado (no da título).

| Intentos | Título |
| --- | --- |
| 14 o menos | Ojo Rápido |
| 11 o menos | Buena Mano |
| 9 o menos | Mente de Crupier |

Este juego **sí es a prueba de trampas**: el tablero vive en el servidor y solo se le manda al cliente lo que el
jugador dio vuelta. Cuando un par no coincide, el servidor manda las dos cartas reveladas y, aparte, la vista
real a la que el cliente vuelve un segundo después; el cliente no tiene que adivinar nada ni recuerda lo que no
le toca saber.

## Qué se guarda

En `DatosJugador.Juegos` (sección sincronizada `Juegos`): por juego, el mejor resultado y cuántas partidas se
jugaron. Los títulos van a `Titulos` como cualquier otro, y darlos dos veces no hace nada (`AddTitulo` devuelve
`false` si ya estaba).

## Lo que falta

- **Carreras en la taberna** (el tercer juego que pedía el diseño) y un **tablero de récords** del servidor.
- Nada se probó en Studio: las pruebas de `python3 tests/run.py` cubren récords, premios, marcas imposibles y
  tiempos, no el juego andando.
