# Bandos, PvP y apariencia

## Bandos

Todo jugador empieza **Violeta** (neutral). Los bandos se guardan en el perfil (`DatosJugador.Faccion`, datos v4) y se
replican como atributo `Bando` del jugador (color del nombre y del marco de vida).

| Bando | Reglas |
|---|---|
| 🟣 Violeta | Neutral. **Nadie lo puede atacar.** Puede atacar a Rojos y Azules en contexto PvP, y al hacerlo cambia de bando. |
| 🔴 Rojo | Pelea contra Azules en contexto PvP. |
| 🔵 Azul | Pelea contra Rojos en contexto PvP. |

**Contexto PvP**: dentro de una parte con la etiqueta `ZonaPvP`, en una zona con `PvP = true` en `ZoneConfig`, o
jugando una partida de la Guerra de Arquitectos (atributo `EnGuerra`). En modo de pruebas hay una **Arena PvP** al
oeste del spawn.

```mermaid
stateDiagram-v2
    [*] --> Violeta
    Violeta --> Azul: ataca a un Rojo
    Violeta --> Rojo: ataca a un Azul
    Violeta --> Rojo: aporta al Reino Rojo (Guerra)
    Violeta --> Azul: aporta al Reino Azul (Guerra)
    Rojo --> Violeta: paga CostoVolverNeutral, fuera de combate
    Azul --> Violeta: paga CostoVolverNeutral, fuera de combate
```

- Volver a Violeta cuesta `GameConfig.Bandos.CostoVolverNeutral` de oro (5000), no se puede en combate (10 s desde el
  último golpe) ni durante una partida de la Guerra.
- En la Guerra, Rojos y Azules juegan para su reino; los Violeta se reparten para emparejar los equipos y, al aportar,
  quedan en ese bando.
- Las curas de área y en un aliado no alcanzan a jugadores del bando rival.

Módulos: `Systems/BandoManager` (reglas, arena de prueba, remote `BandoVolverNeutral`) y `CombatManager`
(`puedeAtacar`, `enemigosEnRadio`, `aliadosEnRadio`; convierte al Violeta al concretar el ataque).

## Panel Personaje

Botón **Personaje** (a la izquierda, debajo del chat):

- **Clase**: abre el selector. En modo de pruebas se cambia libremente; fuera de pruebas, solo la primera vez.
- **Bando**: muestra el actual y el botón para volver a Violeta.
- **Género**: *Mi avatar* (sin cambios), *Masculino* o *Femenino*. Lo aplica `AparienciaManager` con
  `HumanoidDescription` (proporciones de `AparienciaConfig`; ahí se pueden poner ids de partes del Catálogo).
- **Chat**: posición (izquierda/derecha), tamaño (chico/normal/grande) y mostrar/minimizar, sobre la ventana de chat
  de Roblox (`ChatWindowConfiguration`).

Todo se guarda en `DatosJugador.Ajustes` con el remote `GuardarAjuste`, que valida clave y valor contra una lista
cerrada.
