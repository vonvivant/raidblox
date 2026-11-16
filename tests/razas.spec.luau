-- Razas (Humano y Artesano): bonos, firma de autoría y cambio de raza.
local R = cargar("ReplicatedStorage/Configs/RazasConfig")
local PROF = cargar("ReplicatedStorage/Configs/ProfesionesConfig")

prueba("razas: las dos existen y la de por defecto está entre ellas", function()
	exigir(#R.Razas >= 2, "al menos dos razas")
	local ids: { [string]: boolean } = {}
	for _, raza in R.Razas do
		exigir(not ids[raza.Id], "raza repetida: " .. raza.Id)
		ids[raza.Id] = true
		exigir(raza.Nombre ~= "" and raza.Descripcion ~= "", raza.Id .. " sin texto")
		exigir(#raza.Ventajas >= 1, raza.Id .. " tiene que servir para algo")
		exigir(R.Valida(raza.Id), "Valida() tiene que aceptarla")
		-- Los bonos son porcentajes razonables, no números locos.
		exigir(raza.BonusVenta >= 0 and raza.BonusVenta <= 0.5, raza.Id .. " con bono de venta irreal")
		exigir(raza.DescuentoReparacion >= 0 and raza.DescuentoReparacion < 1, raza.Id .. " no puede regalar reparaciones")
		exigir(raza.BonusMasterpiece >= 0 and raza.BonusMasterpiece <= 0.2, raza.Id .. " con bono de obra maestra irreal")
	end
	exigir(ids[R.PorDefecto], "la raza por defecto tiene que existir")
	exigir(not R.Valida("Elfo") and not R.Valida(nil) and not R.Valida(42), "no acepta cualquier cosa")
end)

prueba("razas: ninguna toca el combate", function()
	-- Si una raza tuviera stats de pelea, elegir raza sería elegir poder.
	for _, raza in R.Razas do
		local libre: { [string]: any } = raza
		for _, campo in { "Ataque", "Defensa", "Poder", "Vida", "Mana", "Velocidad" } do
			exigir(libre[campo] == nil, raza.Id .. " no debería tocar " .. campo)
		end
	end
end)

prueba("razas: Raza() siempre devuelve algo usable", function()
	exigir(R.Raza("Artesano").Id == "Artesano", "encuentra la pedida")
	exigir(R.Raza(nil).Id == R.PorDefecto, "sin raza, la de por defecto")
	exigir(R.Raza("RazaBorrada").Id == R.PorDefecto, "una raza vieja no rompe la partida")
end)

prueba("razas: los bonos se aplican en la dirección correcta", function()
	-- Venta: el humano cobra más, el artesano lo normal.
	exigir(R.PagoConBono(100, "Humano") > 100, "el humano cobra más")
	exigir(R.PagoConBono(100, "Artesano") == 100, "el artesano cobra lo normal")
	exigir(R.PagoConBono(0, "Humano") == 0, "de cero no sale oro")
	exigir(R.PagoConBono(1, "Humano") >= 1, "nunca paga menos que el base")

	-- Reparación: el artesano paga menos, nunca negativo.
	exigir(R.CostoConDescuento(100, "Artesano") < 100, "el artesano repara más barato")
	exigir(R.CostoConDescuento(100, "Humano") == 100, "el humano paga lo normal")
	exigir(R.CostoConDescuento(0, "Artesano") == 0, "reparar nada es gratis")
	exigir(R.CostoConDescuento(1, "Artesano") >= 0, "el costo nunca es negativo")

	-- Obra maestra: suma, pero respeta el tope del sistema de profesiones.
	local tope = PROF.MasterpieceMaximo
	exigir(R.MasterpieceConBono(0.1, "Artesano", tope) > 0.1, "el artesano mejora la probabilidad")
	exigir(R.MasterpieceConBono(0.1, "Humano", tope) == 0.1, "el humano, igual")
	exigir(R.MasterpieceConBono(tope, "Artesano", tope) == tope, "no se pasa del tope")
	exigir(R.MasterpieceConBono(0.9, "Artesano", tope) <= tope, "ni siquiera partiendo de muy alto")
end)

prueba("razas: solo el Artesano firma lo que fabrica", function()
	local firman = 0
	for _, raza in R.Razas do
		if raza.Firma then
			firman += 1
			exigir(raza.Id == "Artesano", "la firma es del Artesano")
		end
	end
	exigir(firman == 1, "una sola raza firma")
	exigir(R.LargoAutorMaximo > 0 and R.LargoAutorMaximo <= 50, "el nombre del autor tiene que tener un tope sano")
end)

prueba("razas: el primer cambio es gratis y después hay espera", function()
	exigir(R.Costo(false) == 0, "elegir por primera vez es gratis")
	exigir(R.Costo(true) == R.CostoCambio and R.CostoCambio > 0, "después cuesta")

	local ahora = 1000000
	exigir(R.PuedeCambiar(nil, ahora), "sin cambios previos, se puede")
	exigir(R.FaltaParaCambiar(nil, ahora) == 0, "y no falta nada")
	exigir(not R.PuedeCambiar(ahora, ahora), "recién cambiado, no")
	exigir(R.FaltaParaCambiar(ahora, ahora) == R.EsperaEntreCambios, "falta toda la espera")
	exigir(not R.PuedeCambiar(ahora, ahora + R.EsperaEntreCambios - 1), "un segundo antes tampoco")
	exigir(R.PuedeCambiar(ahora, ahora + R.EsperaEntreCambios), "cumplida la espera, sí")
	exigir(R.FaltaParaCambiar(ahora, ahora + R.EsperaEntreCambios * 2) == 0, "nunca negativo")
end)
