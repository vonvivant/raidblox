-- Pergaminos del Inscriptor (NPC-005): definiciones, recetas y recargas.
local PG = cargar("ReplicatedStorage/Configs/PergaminosConfig")
local ITEMS = cargar("ReplicatedStorage/Configs/ItemCatalog")
local PROF = cargar("ReplicatedStorage/Configs/ProfesionesConfig")
local CONS = cargar("ReplicatedStorage/Configs/ConsumiblesConfig")
local ZONAS = cargar("ReplicatedStorage/Configs/ZoneConfig")
local NPC = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")

prueba("pergaminos: cada uno es un ítem real y se puede conseguir", function()
	exigir(#PG.Pergaminos == 3, "tres pergaminos")
	local inscriptor = NPC.Arquetipos.Inscriptor
	exigir(inscriptor.Numero == 5 and inscriptor.Estado == "Listo", "el Inscriptor está listo")
	local vende: { [string]: number } = {}
	for _, oferta in inscriptor.Vende or {} do
		vende[oferta.ItemId] = oferta.Precio
	end

	local efectos: { [string]: boolean } = {}
	for _, pergamino in PG.Pergaminos do
		local item = ITEMS[pergamino.Id]
		exigir(item ~= nil, "el pergamino no está en el catálogo: " .. pergamino.Id)
		exigir(item.Tipo == "Consumible", pergamino.Id .. " tiene que ser consumible")
		exigir(PG.Es(pergamino.Id), "Es() tiene que reconocerlo")
		exigir(PG.Pergamino(pergamino.Id) ~= nil, "Pergamino() tiene que encontrarlo")
		exigir(not efectos[pergamino.Efecto], "dos pergaminos con el mismo efecto: " .. pergamino.Efecto)
		efectos[pergamino.Efecto] = true
		exigir(pergamino.Cooldown > 0, pergamino.Id .. " sin recarga sería spam")
		exigir(pergamino.Castea >= 0, pergamino.Id .. " con rezo negativo")

		-- Se compra o se fabrica, y comprarlo no puede dar ganancia al revenderlo.
		local receta = false
		for _, r in PROF.Recetas do
			if r.Resultado.ItemId == pergamino.Id then
				receta = true
				exigir(r.Estacion == "Telar", pergamino.Id .. " se hace en el Telar")
				for material in r.Materiales do
					exigir(ITEMS[material] ~= nil, "material inexistente en " .. pergamino.Id .. ": " .. material)
				end
			end
		end
		exigir(receta, "no hay receta para " .. pergamino.Id)
		exigir(vende[pergamino.Id] ~= nil, "el Inscriptor no vende " .. pergamino.Id)
		exigir(vende[pergamino.Id] > (item.PrecioVenta or 0), "se puede revender con ganancia: " .. pergamino.Id)
	end
	exigir(PG.Es("PocionVida") == false, "no reconoce lo que no es pergamino")
	exigir(PG.Pergamino("Inventado") == nil, "no inventa pergaminos")
end)

prueba("pergaminos: los que mueven al jugador piden quedarse quieto", function()
	for _, pergamino in PG.Pergaminos do
		if pergamino.Efecto == "Regreso" or pergamino.Efecto == "Reunion" then
			exigir(pergamino.Castea > 0, pergamino.Id .. " te mueve, así que tiene que tener rezo")
			exigir(pergamino.Cooldown >= 60, pergamino.Id .. " con recarga muy corta para lo que hace")
		end
	end
	exigir(PG.ProhibidoEnCombate, "en combate no se leen pergaminos")
	exigir(#PG.ModosCerrados >= 3, "Guerra, arena y mazmorra tienen que estar cerrados")
end)

prueba("pergaminos: cada bando tiene a dónde volver", function()
	for bando, zona in PG.CasaPorBando do
		exigir(ZONAS.Zonas[zona] ~= nil, bando .. " vuelve a una zona que no existe: " .. zona)
	end
	exigir(PG.Casa("Rojo") ~= PG.Casa("Azul"), "cada bando vuelve a su capital")
	exigir(PG.Casa("Neutral") ~= nil, "los neutrales también vuelven a algún lado")
	exigir(PG.Casa(nil) == PG.Casa("Neutral"), "sin bando, se vuelve como neutral")
	exigir(PG.Casa("Inventado") == PG.Casa("Neutral"), "un bando raro no rompe nada")
end)

prueba("pergaminos: el buff de grupo existe y no es un ítem", function()
	local buff = CONS.Definiciones[PG.BuffFortaleza]
	exigir(buff ~= nil, "falta la definición del buff de fortaleza")
	exigir(buff.SinItem == true, "el buff no es un ítem: lo reparte el pergamino")
	exigir(ITEMS[PG.BuffFortaleza] == nil, "y por eso no está en el catálogo")
	exigir(buff.Duracion == PG.DuracionFortaleza, "la duración tiene que coincidir con la del config")
	exigir(buff.Categoria ~= nil and CONS.NombresCategoria[buff.Categoria] ~= nil, "categoría válida")
	-- Es su propia categoría: no puede pisar al elixir ni al tónico.
	for id, def in CONS.Definiciones do
		if id ~= PG.BuffFortaleza and def.Categoria == buff.Categoria then
			exigir(false, "otra cosa usa la categoría del pergamino: " .. id)
		end
	end
end)

prueba("pergaminos: las recargas se cuentan bien", function()
	local pergamino = PG.Pergamino("PergaminoRegreso")
	exigir(pergamino ~= nil, "el de regreso")
	local ahora = 1000
	exigir(PG.Listo(pergamino, nil, ahora), "sin usarlo nunca, está listo")
	exigir(PG.Faltan(pergamino, nil, ahora) == 0, "y no falta nada")
	exigir(not PG.Listo(pergamino, ahora, ahora), "recién usado, no")
	exigir(PG.Faltan(pergamino, ahora, ahora) == pergamino.Cooldown, "falta toda la recarga")
	exigir(not PG.Listo(pergamino, ahora, ahora + pergamino.Cooldown - 1), "un segundo antes tampoco")
	exigir(PG.Listo(pergamino, ahora, ahora + pergamino.Cooldown), "justo a tiempo sí")
	exigir(PG.Faltan(pergamino, ahora, ahora + pergamino.Cooldown + 50) == 0, "nunca negativo")
end)
