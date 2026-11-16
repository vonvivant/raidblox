# Parcelas

Terrenos que el jugador compra, mantiene, comparte y fusiona. Los atiende el **Arquitecto de Viviendas**
(NPC-033). Reglas en `Configs/ParcelasConfig.luau`, servidor en `Systems/Economia/ParcelaManager.luau`, ventana
en `ParcelasUI`.

## Por qué no vive en el perfil

Una parcela es de un jugador **en todos los servidores a la vez**. Si el dueño viviera en el perfil, dos
jugadores en dos servidores distintos podrían comprar la misma parcela y los dos tendrían razón. Así que la
verdad está en un **DataStore global** (`Parcelas_v1`), una clave por parcela, y toda operación pasa por
`UpdateAsync`, que es lo único que garantiza "o la gano yo, o la ganó otro".

El perfil guarda igual la lista de parcelas del jugador (`DatosJugador.Parcelas`, sección sincronizada
`Parcelas`), pero solo como copia para el límite y la interfaz. Ante una diferencia, manda el DataStore.

**Orden de las operaciones que cobran:** se cobra primero y después se escribe; si la escritura no entra (otro
servidor ganó la parcela, o el DataStore falla), se devuelve el oro. Al revés sería peor: una parcela marcada
como vendida y sin cobrar quedaría trabada para todos, mientras que un cobro con devolución es un problema de
un jugador y de un segundo. Si la devolución también falla (el jugador se fue en el medio), queda en el log del
servidor.

## Los barrios

Las parcelas viven en una grilla por barrio, así que se sabe cuáles son vecinas sin consultar nada. El id de
una parcela es `Barrio:Numero` (por ejemplo `CiudadNorte:7`).

| Barrio | Zona | Grilla | Lado | Precio |
| --- | --- | --- | --- | --- |
| Barrio Norte | Ciudad Principal | 3 × 4 | 48 studs | 12.000 |
| La Ribera | Ciudad Principal | 3 × 4 | 48 studs | 7.000 |
| Claro del Bosque | Bosque | 2 × 3 | 64 studs | 4.500 |

Cada servidor arma solo los barrios de su zona (en el servidor de pruebas arma todos, para poder verlos). De
cada parcela se generan el piso, cuatro postes que marcan el límite, un **cartel** que dice si está en venta,
de quién es y si el alquiler está vencido, y un **cofre de bóveda**.

## Comprar y mantener

- **Comprar:** el precio del barrio, y viene con **7 días de alquiler pagos**. Hasta **2 parcelas** por jugador.
- **Alquiler:** 150 de oro por día. Se puede pagar hasta 30 días adelantados.
- **Vencimiento:** pasado el plazo hay **3 días de gracia** en los que la parcela sigue siendo tuya (podés
  ponerte al día y el alquiler cuenta desde ese momento, no desde el vencimiento), pero los permisos que les
  diste a otros no valen. Pasada la gracia, la parcela **vuelve al mercado** y cualquiera puede comprarla.
- **Abandonar:** la suelta en el momento, sin devolución.

## Permisos

El dueño puede dar hasta 12 permisos, por nombre de alguien que esté en el servidor:

| Permiso | Qué puede |
| --- | --- |
| Visita | Entrar y nada más |
| Invitado | Entrar y usar lo que esté puesto |
| Socio | Construir y abrir el cofre de bóveda |

El cofre de la parcela usa el tag `CofreVault` de la [bóveda](vault.md) más un atributo `Parcela` con el id.
`VaultManager` consulta a `ParcelaManager` (gancho `SetPermisoParcela`) antes de abrirlo: si no sos el dueño ni
socio, el cofre no te responde aunque estés al lado.

## Fusionar

Dos parcelas **vecinas por un lado** (no en diagonal), del **mismo barrio** y las dos tuyas y al día se pueden
fusionar: comparten nombre y cofre, y el área de construcción pasa a ser la suma. Siguen contando como dos
parcelas para el límite. Si una de las dos escrituras no entra, se deshace la otra, así no queda una fusión a
medias.

## Construir

Reglas en `Configs/ConstruccionConfig.luau`, servidor en `Systems/Economia/ConstruccionManager.luau`, ventana en
`ConstruccionUI`. Lo construido se guarda en el mismo registro de la parcela, con las posiciones **relativas al
centro**, así vale igual en todos los servidores.

Se abre con el Arquitecto ("Construir en mi parcela"): se elige una pieza y aparece una vista fantasma que sigue
al mouse sobre el terreno; **clic** la pone, **R** la gira, **Q** la sube, **E** la baja, **clic derecho**
cancela. En modo sacar, el clic sobre algo puesto lo saca y devuelve **la mitad** de lo que costó.

Hay diez piezas en cuatro grupos: estructura (piso, pared, techo, marco de puerta), muebles (mesa, silla,
fogata, estandarte), huerta (cantero) y mascotas (patio). Hasta **40 piezas por parcela**, con límites propios:
seis canteros y un solo patio.

Tres muebles hacen algo además de estar:

- **Silla:** es un asiento de verdad, el jugador se sienta.
- **Fogata:** es un **fogón** como el del Chef, con su propio cartel: las recetas de [cocina](economia.md) se
  hacen ahí mismo, sin volver a la ciudad. Cocina cualquiera que llegue hasta ella, no solo el dueño.
- **Estandarte:** toma el color del bando del dueño (rojo, azul o violeta). El bando se guarda en la parcela
  junto con la lista de mascotas, por lo mismo: para que se vea igual aunque el dueño no esté.

El servidor revalida todo en cada pieza: que seas dueño o socio, que estés cerca, que la pieza exista, que no te
hayas pasado de los topes, que **entre adentro del terreno** (con dos studs de margen y sin pasar los 24 de
alto) y que **no se pise** con otra ya puesta. Las posiciones se acomodan a una grilla de 2 studs *antes* de
validar, así lo que se valida es exactamente lo que se guarda. Se cobra y después se escribe; si la escritura no
entra, se devuelve el oro.

## Huerta

Un **cantero** se planta con una semilla del inventario (las vende el Arquitecto) y se cosecha cuando está
lista. El cartel del cantero dice cuánto falta.

| Semilla | Da | Tarda | Cosecha |
| --- | --- | --- | --- |
| Hierba sanadora | Hierba Sanadora | 1 h | 3–5 |
| Hierbas de cocina | Hierbas de Cocina | 2 h | 3–6 |
| Lino | Lino | 4 h | 4–7 |
| Flor lunar | Flor Lunar | 6 h | 2–4 |

El tiempo se mide con la hora guardada en la pieza, así que **corre con el servidor apagado** y no se puede
acelerar desde el cliente. Si al cosechar no entra en la mochila, el cantero queda plantado y se puede volver;
si la cosecha se entrega pero el registro no se puede limpiar, se saca lo entregado, para que un cantero no se
coseche dos veces.

Esto conecta la casa con las profesiones: la huerta da ingredientes de [cocina](economia.md) y de alquimia sin
salir a buscarlos.

## Patio de mascotas

Una pieza, única por parcela. Una vez puesta, **las mascotas del dueño se pasean solas adentro**: cada una va
flotando de un punto al azar a otro del patio, con tiempos y pausas distintas, así que no se mueven todas
igual. Nunca salen del borde (hay dos studs de margen) y son solo decoración: no juntan botín ni dan nada.

La lista de mascotas se guarda como una **foto en el registro de la parcela**, no se lee del perfil al
dibujarlas. Por eso el patio se ve igual aunque el dueño no esté en ese servidor, o no esté jugando. La foto se
actualiza sola cuando el dueño está presente (al poner el patio y después cada minuto), y solo se escribe al
DataStore si la lista cambió.

Se muestran hasta cinco, que es todo lo que hay hoy en `MascotasConfig`.

## Lo que falta

- **Subasta con pujas**: hoy la parcela libre se compra al precio del barrio, el primero que llega. Las pujas
  esperan la misma decisión que las de la [casa de subastas](economia.md), que el usuario todavía no tomó.
- **Alquilar tu parcela a otro jugador** (hoy el alquiler es el que se le paga al barrio, no entre jugadores).

Por eso el NPC-033 sigue figurando como **Parcial** en la [matriz](npcs-matriz.md). Nada de esto se probó en
Studio: las pruebas de `python3 tests/run.py` cubren la grilla, la vecindad, la fusión, los plazos del alquiler,
los permisos, el encaje y la superposición de piezas, los tiempos de la huerta y que las mascotas no se escapen
del patio, no el DataStore andando.
