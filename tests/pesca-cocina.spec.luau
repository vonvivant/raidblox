-- Pesca (NPC-035) y Cocina (NPC-034): coherencia de nodos, botín, recetas y comidas.
local PROF = cargar("ReplicatedStorage/Configs/ProfesionesConfig")
local ITEMS = cargar("ReplicatedStorage/Configs/ItemCatalog")
local CONS = cargar("ReplicatedStorage/Configs/ConsumiblesConfig")
local NPC = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")

prueba("pesca: las profesiones nuevas están declaradas", function()
	exigir(PROF.Profesiones.Pesca ~= nil and PROF.Profesiones.Pesca.Tipo == "Recoleccion", "Pesca recolecta")
	exigir(PROF.Profesiones.Cocina ~= nil and PROF.Profesiones.Cocina.Tipo == "Produccion", "Cocina produce")
end)

prueba("pesca: los nodos piden caña y su botín existe", function()
	local hay = 0
	for id, def in PROF.Nodos do
		if def.Profesion ~= "Pesca" then
			continue
		end
		hay += 1
		exigir(def.Herramienta == "Cana", id .. " tiene que pescarse con caña")
		exigir(ITEMS[def.ItemId] ~= nil, id .. " apunta a un ítem que no existe: " .. def.ItemId)
		exigir(def.Respawn > 0 and def.Xp > 0, id .. " necesita respawn y xp")
		local botin = def.Botin
		exigir(botin ~= nil and #botin > 0, id .. " no tiene botín")
		local total = 0
		local tieneElComun = false
		for _, captura in botin do
			exigir(ITEMS[captura.ItemId] ~= nil, "captura inexistente en " .. id .. ": " .. captura.ItemId)
			exigir(captura.Peso > 0, "peso inválido en " .. id)
			local minimo = captura.Min or 1
			local maximo = captura.Max or minimo
			exigir(minimo >= 1 and maximo >= minimo, "cantidades al revés en " .. id)
			total += captura.Peso
			if captura.ItemId == def.ItemId then
				tieneElComun = true
			end
		end
		exigir(total > 0, "el botín de " .. id .. " no suma peso")
		exigir(tieneElComun, def.ItemId .. " se muestra como lo común pero no está en el botín de " .. id)
		-- Con nivel 0 (recién empezado) tiene que poder salir algo.
		local disponibleAlEmpezar = 0
		for _, captura in botin do
			if (captura.NivelMinimo or 0) <= 0 then
				disponibleAlEmpezar += captura.Peso
			end
		end
		exigir(disponibleAlEmpezar > 0, "sin nivel no sale nada de " .. id)
	end
	exigir(hay >= 2, "hacen falta al menos dos lugares para pescar")
end)

prueba("pesca: hay una caña y la vende el Maestro de Pesca", function()
	local cana = ITEMS.CanaPescar
	exigir(cana ~= nil and cana.Herramienta == "Cana", "la caña es una herramienta de pesca")
	exigir(cana.SlotEquipo == "Herramienta", "la caña se equipa en la ranura de herramienta")

	local pescador = NPC.Arquetipos.MaestroPesca
	exigir(pescador.Numero == 35 and pescador.Estado == "Listo", "el Maestro de Pesca está listo")
	local vendeCana = false
	for _, oferta in pescador.Vende or {} do
		exigir(ITEMS[oferta.ItemId] ~= nil, "vende algo inexistente: " .. oferta.ItemId)
		-- Nada de comprar barato al NPC y revenderlo con ganancia.
		local venta = ITEMS[oferta.ItemId].PrecioVenta or 0
		exigir(oferta.Precio > venta, "se puede revender con ganancia: " .. oferta.ItemId)
		if oferta.ItemId == "CanaPescar" then
			vendeCana = true
		end
	end
	exigir(vendeCana, "el Maestro de Pesca tiene que vender la caña")
	-- Paga más que el comerciante común, pero menos de lo que cobra.
	local compra = pescador.Compra
	exigir(compra ~= nil and compra.Factor > 1, "el pescador paga mejor los materiales")
	exigir(compra.Factor < 30 / (ITEMS.CanaPescar.PrecioVenta or 1), "pagaría más de lo que cobra")
end)

prueba("cocina: las recetas usan ingredientes reales y salen en el fogón", function()
	local hay = 0
	for id, receta in PROF.Recetas do
		if receta.Profesion ~= "Cocina" then
			continue
		end
		hay += 1
		exigir(receta.Estacion == "Fogon", id .. " se cocina en el fogón")
		exigir(ITEMS[receta.Resultado.ItemId] ~= nil, id .. " produce un ítem inexistente")
		exigir(receta.Resultado.Cantidad >= 1, id .. " no produce nada")
		exigir(receta.Tiempo > 0 and receta.Xp > 0, id .. " necesita tiempo y xp")
		exigir(next(receta.Materiales) ~= nil, id .. " no pide materiales")
		for material, cantidad in receta.Materiales do
			exigir(ITEMS[material] ~= nil, id .. " pide un material inexistente: " .. material)
			exigir(cantidad >= 1, id .. " pide una cantidad inválida de " .. material)
		end
		-- La comida tiene que valer más que la suma de lo que lleva.
		local costo = 0
		for material, cantidad in receta.Materiales do
			costo += (ITEMS[material].PrecioVenta or 0) * cantidad
		end
		local vale = (ITEMS[receta.Resultado.ItemId].PrecioVenta or 0) * receta.Resultado.Cantidad
		exigir(vale > costo, "cocinar " .. id .. " da pérdida: cuesta " .. costo .. " y vale " .. vale)
	end
	exigir(hay >= 4, "hacen falta al menos cuatro comidas")
end)

prueba("cocina: las comidas son una categoría aparte y duran lo que dicen", function()
	exigir(CONS.NombresCategoria.Comida ~= nil, "falta el nombre de la categoría Comida")
	local comidas = 0
	for id, def in CONS.Definiciones do
		if def.Categoria ~= "Comida" then
			continue
		end
		comidas += 1
		exigir(ITEMS[id] ~= nil, "la comida " .. id .. " no está en el catálogo")
		exigir(ITEMS[id].Tipo == "Consumible", id .. " tiene que ser consumible")
		exigir(def.Duracion ~= nil and def.Duracion > 0, id .. " necesita duración")
		exigir(def.Efectos ~= nil and #def.Efectos > 0, id .. " no hace nada")
		exigir(def.Riesgo == nil, "la comida no debería tener riesgo: " .. id)
		for _, efecto in def.Efectos do
			local tipo = efecto.Tipo
			exigir(
				tipo == "Aura" or tipo == "RegenVida" or tipo == "RegenMana" or tipo == "Prisa",
				id .. " usa un efecto que el juego no aplica: " .. tipo
			)
			if tipo == "Aura" then
				local stat = efecto.Stat
				exigir(
					stat == "Ataque" or stat == "Poder" or stat == "Defensa",
					id .. " mejora una estadística que las auras no tocan: " .. tostring(stat)
				)
			end
			exigir(efecto.Porcentaje > 0, id .. " tiene un efecto en cero o negativo")
		end
		-- Cada comida tiene que poder cocinarse.
		local receta = false
		for _, r in PROF.Recetas do
			if r.Resultado.ItemId == id then
				receta = true
			end
		end
		exigir(receta, "no hay receta para " .. id)
	end
	exigir(comidas >= 4, "hacen falta al menos cuatro comidas con efecto")
end)

prueba("cocina: el Chef trabaja en el fogón y vende los ingredientes que no se pescan", function()
	local chef = NPC.Arquetipos.Chef
	exigir(chef.Numero == 34 and chef.Estado == "Listo", "el Chef está listo")
	exigir(chef.Estacion == "Fogon", "el Chef atiende en el fogón")
	local vende: { [string]: boolean } = {}
	for _, oferta in chef.Vende or {} do
		exigir(ITEMS[oferta.ItemId] ~= nil, "el Chef vende algo inexistente: " .. oferta.ItemId)
		exigir(oferta.Precio > (ITEMS[oferta.ItemId].PrecioVenta or 0), "revendible con ganancia: " .. oferta.ItemId)
		vende[oferta.ItemId] = true
	end
	-- Todo ingrediente que no sale de un nodo tiene que poder comprarse.
	local deNodo: { [string]: boolean } = {}
	for _, def in PROF.Nodos do
		deNodo[def.ItemId] = true
		for _, captura in def.Botin or {} do
			deNodo[captura.ItemId] = true
		end
	end
	local deReceta: { [string]: boolean } = {}
	for _, receta in PROF.Recetas do
		deReceta[receta.Resultado.ItemId] = true
	end
	for id, receta in PROF.Recetas do
		if receta.Profesion ~= "Cocina" then
			continue
		end
		for material in receta.Materiales do
			exigir(
				deNodo[material] or vende[material] or deReceta[material],
				id .. " pide " .. material .. ", que no se pesca, no se compra y no se fabrica"
			)
		end
	end
end)
