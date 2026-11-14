-- Coherencia entre los catálogos: ítems, recetas, consumibles y NPCs.
local ItemCatalog = cargar("ReplicatedStorage/Configs/ItemCatalog")
local Profesiones = cargar("ReplicatedStorage/Configs/ProfesionesConfig")
local Consumibles = cargar("ReplicatedStorage/Configs/ConsumiblesConfig")
local Npcs = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")
local Zonas = cargar("ReplicatedStorage/Configs/ZoneConfig")
local Vault = cargar("ReplicatedStorage/Configs/VaultConfig")

local FACCIONES = { Rojo = true, Azul = true, Neutral = true }

prueba("ítems: los consumibles tienen efecto y los apilables un stack válido", function()
	for id, def in ItemCatalog do
		exigir(type(def.Nombre) == "string" and def.Nombre ~= "", id .. " sin nombre")
		exigir(def.PrecioVenta >= 0, id .. " con precio negativo")
		if def.Tipo == "Consumible" then
			exigir(def.Consumo ~= nil or Consumibles.Definiciones[id] ~= nil, id .. " es consumible pero no hace nada")
		end
		if def.MaxStack then
			exigir(def.Apilable and def.MaxStack >= 1, id .. " con MaxStack inválido")
		end
	end
end)

prueba("recetas: materiales y resultado existen en el catálogo", function()
	for id, receta in Profesiones.Recetas do
		exigir(ItemCatalog[receta.Resultado.ItemId] ~= nil, id .. " produce un ítem inexistente")
		exigir(receta.Resultado.Cantidad >= 1, id .. " no produce nada")
		for material, cantidad in receta.Materiales do
			exigir(ItemCatalog[material] ~= nil, id .. " usa un material inexistente: " .. material)
			exigir(cantidad >= 1, id .. " con cantidad inválida de " .. material)
		end
		exigir(receta.NivelRequerido >= 1 and receta.NivelRequerido <= Profesiones.NivelMaximo, id .. " con nivel fuera de rango")
	end
end)

prueba("consumibles: definiciones completas y dentro de los límites", function()
	for id, def in Consumibles.Definiciones do
		if def.Instantaneo then
			exigir(def.EfectosInstantaneos and #def.EfectosInstantaneos > 0, id .. " instantáneo sin efectos")
			exigir(ItemCatalog[id] and ItemCatalog[id].Tipo == "Consumible", id .. " no es un consumible del catálogo")
		else
			exigir(def.Categoria and Consumibles.NombresCategoria[def.Categoria], id .. " sin categoría válida")
			exigir(def.Duracion and def.Duracion > 0, id .. " sin duración")
			exigir(def.Efectos and #def.Efectos > 0, id .. " sin efectos")
			if string.sub(id, 1, 8) ~= "Servicio" then
				exigir(ItemCatalog[id] and ItemCatalog[id].Tipo == "Consumible", id .. " no es un consumible del catálogo")
			end
			local listas = { def.Efectos }
			if def.Riesgo then
				exigir(def.Riesgo.Probabilidad > 0 and def.Riesgo.Probabilidad < 1, id .. " con probabilidad inválida")
				table.insert(listas, def.Riesgo.Malos)
			end
			for _, lista in listas do
				for _, efecto in lista do
					if efecto.Tipo == "Aura" then
						exigir(efecto.Stat == "Ataque" or efecto.Stat == "Poder" or efecto.Stat == "Defensa", id .. " con stat inválido")
					elseif efecto.Tipo == "Prisa" then
						exigir(efecto.Porcentaje > 0 and efecto.Porcentaje <= Consumibles.PrisaMaxima, id .. " con prisa fuera de rango")
					else
						exigir(efecto.Tipo == "RegenMana" or efecto.Tipo == "RegenVida", id .. " con efecto desconocido: " .. tostring(efecto.Tipo))
					end
				end
			end
		end
	end
end)

prueba("NPCs: 39 arquetipos numerados del 1 al 39 sin repetir", function()
	local vistos, cantidad = {}, 0
	for id, a in Npcs.Arquetipos do
		cantidad += 1
		exigir(not vistos[a.Numero], "número repetido: " .. a.Numero)
		vistos[a.Numero] = id
		exigir(Npcs.NombresCategoria[a.Categoria] ~= nil, id .. " con categoría inválida")
		exigir(#a.Facciones >= 1, id .. " sin facciones")
		for _, f in a.Facciones do
			exigir(FACCIONES[f], id .. " con facción inválida")
		end
		exigir(#a.Interfaces >= 1, id .. " sin interfaces")
	end
	exigir(cantidad == 39, "hay " .. cantidad .. " arquetipos")
	for n = 1, 39 do
		exigir(vistos[n], "falta el NPC número " .. n)
	end
end)

prueba("NPCs: lo que venden existe y cuesta más de lo que paga un NPC al comprarlo", function()
	local factorMaximo = 0
	for _, a in Npcs.Arquetipos do
		if a.Compra then
			factorMaximo = math.max(factorMaximo, a.Compra.Factor)
		end
	end
	for id, a in Npcs.Arquetipos do
		for _, oferta in a.Vende or {} do
			local def = ItemCatalog[oferta.ItemId]
			exigir(def ~= nil, id .. " vende un ítem inexistente: " .. oferta.ItemId)
			exigir(oferta.Precio >= 1, id .. " con precio inválido")
			if oferta.Moneda ~= "Honor" then
				exigir(oferta.Precio > def.PrecioVenta * factorMaximo, id .. " vende " .. oferta.ItemId .. " por debajo de su precio de reventa")
			end
		end
	end
end)

prueba("NPCs: un arquetipo Listo ofrece al menos un servicio que funciona", function()
	for id, a in Npcs.Arquetipos do
		if a.Estado == "Listo" then
			local sirve = a.Viajes or a.Estacion ~= nil or (a.Vende and #a.Vende > 0) or a.Compra ~= nil
			for _, s in a.Servicios or {} do
				sirve = sirve or s.Accion ~= nil
			end
			exigir(sirve, id .. " figura Listo pero no ofrece nada")
		elseif a.Estado == "Parcial" then
			exigir(type(a.Sistema) == "string", id .. " es Parcial y no dice dónde está el sistema")
		else
			exigir(a.Estado == "Pendiente", id .. " con estado inválido")
		end
	end
end)

prueba("NPCs de prueba: arquetipo existente, facción con versión y sin superponerse", function()
	local ocupados = {}
	for _, puesto in Npcs.DePrueba do
		local a = Npcs.Arquetipos[puesto.Arquetipo]
		exigir(a ~= nil, "arquetipo inexistente: " .. puesto.Arquetipo)
		exigir(table.find(a.Facciones, puesto.Faccion) ~= nil, puesto.Arquetipo .. " no tiene versión " .. puesto.Faccion)
		local clave = puesto.Posicion.X .. "," .. puesto.Posicion.Z
		exigir(not ocupados[clave], "dos NPC en " .. clave)
		ocupados[clave] = true
	end
end)

prueba("zonas: todas tienen territorio y hay destinos Rojos, Azules y Neutrales", function()
	local hay = {}
	for id, zona in Zonas.Zonas do
		exigir(FACCIONES[zona.Territorio], id .. " sin territorio válido")
		hay[zona.Territorio] = true
	end
	exigir(hay.Rojo and hay.Azul and hay.Neutral, "falta algún territorio")
end)

prueba("bóveda: un precio por cada pestaña que se puede comprar, siempre creciente", function()
	exigir(#Vault.CostoPestana == Vault.MaxPestanas - Vault.PestanasIniciales, "cantidad de precios")
	for i = 2, #Vault.CostoPestana do
		exigir(Vault.CostoPestana[i] > Vault.CostoPestana[i - 1], "los precios no crecen")
	end
	exigir(Vault.RanurasPorPestana % Vault.Columnas == 0, "las ranuras no llenan la grilla")
end)
