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

## Lo que falta

Esto es la **primera mitad** del pedido: la propiedad. Todavía no están:

- **Construcción y muebles**: poner piezas dentro de la parcela, con el Arquitecto vendiendo planos.
- **Huerta** (plantar y cosechar) y **patio de mascotas**.
- **Subasta con pujas**: hoy la parcela libre se compra al precio del barrio, el primero que llega. Las pujas
  esperan la misma decisión que las de la [casa de subastas](economia.md), que el usuario todavía no tomó.
- **Alquilar tu parcela a otro jugador** (hoy el alquiler es el que se le paga al barrio, no entre jugadores).

Por eso el NPC-033 figura como **Parcial** en la [matriz](npcs-matriz.md). Nada de esto se probó en Studio: las
pruebas de `python3 tests/run.py` cubren la grilla, la vecindad, la fusión, los plazos del alquiler y los
permisos, no el DataStore andando.
