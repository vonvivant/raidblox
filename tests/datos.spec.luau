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
			local sirve = a.Viajes or a.Estacion ~= nil or (a.Vende and #a.Vende > 0) or a.Compra ~= nil or (a.SobreItem and #a.SobreItem > 0)
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

-- Forja: reglas puras de durabilidad, desencantar, reforjar y engarzar.
local Forja = cargar("ReplicatedStorage/Configs/ForjaConfig")
local Rarezas = cargar("ReplicatedStorage/Configs/ItemRarityConfig")

local function equipo(rareza, meta)
	return { Uid = "x", ItemId = "EspadaHierro", Cantidad = 1, Rareza = rareza, Meta = meta }
end

prueba("forja: durabilidad entera por defecto, rota en 0 y costo proporcional", function()
	exigir(Forja.DurabilidadDe(equipo("Comun")) == Forja.Durabilidad.Maxima, "sin dato debería estar entera")
	exigir(Forja.CostoReparar(equipo("Comun")) == 0, "reparar algo entero no cuesta")
	exigir(Forja.Roto(equipo("Raro", { Dur = 0 })), "durabilidad 0 es roto")
	exigir(not Forja.Roto(equipo("Raro", { Dur = 1 })), "durabilidad 1 no es roto")
	exigir(Forja.DurabilidadDe(equipo("Raro", { Dur = -5 })) == 0, "no baja de 0")
	exigir(Forja.DurabilidadDe(equipo("Raro", { Dur = 999 })) == Forja.Durabilidad.Maxima, "no pasa del máximo")
	local mitad = Forja.CostoReparar(equipo("Epico", { Dur = 50 }))
	local todo = Forja.CostoReparar(equipo("Epico", { Dur = 0 }))
	exigir(mitad == 100 and todo == 200, "costo épico: " .. mitad .. " / " .. todo)
	exigir(Forja.CostoReparar({ Uid = "x", ItemId = "PocionVida", Cantidad = 1, Rareza = "Comun" }) == 0, "una poción no se repara")
	exigir(not Forja.TieneDurabilidad({ Uid = "x", ItemId = "PicoHierro", Cantidad = 1, Rareza = "Comun" }), "las herramientas no se desgastan")
end)

prueba("forja: qué ítems acepta cada operación", function()
	exigir(not Forja.Aplica("Desencantar", equipo("Comun")), "el equipo Común no se desencanta")
	exigir(Forja.Aplica("Desencantar", equipo("Raro", { Mult = 1.3 })), "el Raro sí")
	exigir(not Forja.Aplica("Reforjar", equipo("Comun")), "el Común no se reforja")
	exigir(not Forja.Aplica("Engarzar", equipo("Comun")), "el Común no tiene ranuras")
	exigir(Forja.Aplica("Engarzar", equipo("Raro")), "el Raro tiene una ranura")
	exigir(not Forja.Aplica("Engarzar", equipo("Raro", { Gema1 = "Rubi" })), "ranura ya ocupada")
	exigir(Forja.Aplica("Engarzar", equipo("Unico", { Gema1 = "Rubi", Gema2 = "Zafiro" })), "el Único tiene tres")
	exigir(not Forja.Aplica("Engarzar", { Uid = "x", ItemId = "PocionVida", Cantidad = 1, Rareza = "Raro" }), "solo equipo")
	exigir(not Forja.Aplica("Inventada", equipo("Unico")), "operación desconocida")
end)

prueba("forja: la reforja se encarece con cada uso y tiene tope", function()
	local base = Forja.Costo("Reforjar", equipo("Raro"))
	exigir(base == 500, "costo base " .. base)
	exigir(Forja.Costo("Reforjar", equipo("Raro", { Reforjas = 2 })) == 750, "con 2 reforjas")
	local tope = Forja.Costo("Reforjar", equipo("Raro", { Reforjas = 1000 }))
	exigir(tope == 500 * (1 + Forja.Reforjar.MaximoAumento), "tope " .. tope)
end)

prueba("forja: catálogos coherentes (gemas, esencias, materiales y rarezas)", function()
	for gemaId, gema in Forja.Engarzar.Gemas do
		exigir(ItemCatalog[gemaId] ~= nil, "gema inexistente: " .. gemaId)
		exigir(Rarezas.Efectos[gema.Efecto] ~= nil, gemaId .. " con efecto desconocido")
		exigir(gema.Valor > 0, gemaId .. " sin valor")
	end
	for rareza, resultado in Forja.Desencantar.Resultado do
		exigir(Rarezas.Rarezas[rareza] ~= nil, "rareza inexistente: " .. rareza)
		for itemId, cantidad in resultado do
			exigir(ItemCatalog[itemId] ~= nil and cantidad >= 1, "esencia inválida: " .. itemId)
		end
	end
	for _, operacion in { "Reforjar", "Engarzar" } do
		local material, cantidad = Forja.Material(operacion)
		exigir(material and ItemCatalog[material] ~= nil and cantidad >= 1, operacion .. " sin material válido")
	end
	for rareza in Rarezas.Rarezas do
		exigir(Forja.Durabilidad.CostoPorPunto[rareza] ~= nil, "falta costo de reparación para " .. rareza)
		exigir(Forja.Engarzar.RanurasPorRareza[rareza] ~= nil, "faltan ranuras para " .. rareza)
	end
end)

prueba("NPCs: las operaciones sobre ítems que declaran existen en la forja", function()
	local validas = { Desencantar = true, Reforjar = true, Engarzar = true }
	for id, a in Npcs.Arquetipos do
		for _, operacion in a.SobreItem or {} do
			exigir(validas[operacion.Id], id .. " declara una operación desconocida: " .. operacion.Id)
		end
	end
end)
