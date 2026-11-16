# Bóveda global (Vault)

Banco personal del jugador: lo que guarda en un banco lo encuentra en cualquier otro. Módulos:
`Configs/VaultConfig.luau`, `Systems/Economia/VaultManager.luau` y `VaultUI.client.luau`.

## Qué es

- Hasta **8 pestañas de 30 ranuras**. Se empieza con 1.
- Las pestañas se compran con oro, cada una más cara: 1.000, 2.500, 6.000, 15.000, 35.000, 80.000 y 150.000
  (`VaultConfig.CostoPestana`). El pase **VIP** suma una pestaña sin costo.
- Cada pestaña tiene **nombre** (hasta 16 letras, pasa por el filtro de texto de Roblox) e **ícono** (lista fija).
- Los ítems conservan su Uid, rareza y metadatos al entrar y salir. Los apilables sin metadatos se suman a pilas
  iguales.

## Dónde se abre

Solo cerca (16 studs) de un punto de bóveda:

| Punto | Cómo se marca |
|---|---|
| Banquero (NPC 13) | Automático: el arquetipo lleva el tag `BancoVault` |
| Banco de ciudad | Una `Part` con el tag `BancoVault` |
| Cofre de bóveda de una parcela | Una `Part` con el tag `CofreVault` |

A las partes con esos tags se les agrega solo el cartel "Abrir". El servidor revisa la cercanía **en cada
operación**, no solo al abrir.

## Operaciones (todas en el servidor)

| Remote | Qué hace |
|---|---|
| `VaultDepositar(ranuraMochila, pestana, cantidad)` | Mochila → bóveda |
| `VaultRetirar(pestana, ranura, cantidad)` | Bóveda → mochila |
| `VaultMover(pestanaA, ranuraA, pestanaB, ranuraB)` | Mueve o intercambia ranuras; suma a la pila si es el mismo ítem. `ranuraB = 0` manda a la primera ranura libre de la otra pestaña |
| `VaultExpandir()` | Compra la próxima pestaña |
| `VaultPersonalizar(pestana, nombre, icono)` | Cambia nombre e ícono |

Cada operación es de **todo o nada**: primero se verifica que entre entera y recién después se mueven los ítems,
sin ceder el hilo en el medio, así que no hay forma de duplicar ni de perder ítems. Los argumentos pasan por
`Guard` y los remotes tienen el límite de frecuencia de `NetworkBridge`.

## Ventana

- **Izquierda:** pestañas, nombre e ícono, buscador, filtros por categoría y rareza, y las 30 ranuras.
- **Derecha:** la mochila.
- **Buscador:** por nombre del ítem o por la firma de autoría (`Meta.Autor`, que va a llenar el sistema de firma
  cuando se programe). Con texto o un filtro puesto, muestra resultados de todas las pestañas.
- **Un clic** selecciona y muestra el detalle. **Shift + clic, doble clic o doble toque** pasa la pila entera al
  otro lado.
- Con un ítem de la bóveda elegido, tocar otra ranura lo mueve o intercambia, y tocar otra pestaña lo manda ahí.

## Datos

`DatosJugador.Vault` (opcional; se crea al usarla por primera vez):

```lua
Vault = {
	Compradas = 1, -- pestañas iniciales + compradas (las del pase no se guardan)
	Pestanas = {
		["1"] = { Nombre = "Pestaña 1", Icono = "📦", Slots = { ["1"] = ItemInstancia, ... } },
	},
}
```

Se sincroniza al cliente como la sección `Vault`.
