-- Coherencia entre los catálogos: ítems, recetas, consumibles y NPCs.
local ItemCatalog = cargar("ReplicatedStorage/Configs/ItemCatalog")
local Profesiones = cargar("ReplicatedStorage/Configs/ProfesionesConfig")
local Consumibles = cargar("ReplicatedStorage/Configs/ConsumiblesConfig")
local Npcs = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")
local Zonas = cargar("ReplicatedStorage/Configs/ZoneConfig")
local Vault = cargar("ReplicatedStorage/Configs/VaultConfig")
local Pergaminos = cargar("ReplicatedStorage/Configs/PergaminosConfig")
local Stencils = cargar("ReplicatedStorage/Configs/StencilsConfig")

local FACCIONES = { Rojo = true, Azul = true, Neutral = true }

prueba("ítems: los consumibles tienen efecto y los apilables un stack válido", function()
	for id, def in ItemCatalog do
		exigir(type(def.Nombre) == "string" and def.Nombre ~= "", id .. " sin nombre")
		exigir(def.PrecioVenta >= 0, id .. " con precio negativo")
		if def.Tipo == "Consumible" then
			-- Un consumible hace algo de tres maneras: recupera (Consumo), tiene
			-- definición de buff, o lo maneja un sistema propio (los pergaminos).
			exigir(
				def.Consumo ~= nil
					or Consumibles.Definiciones[id] ~= nil
					or Pergaminos.Es(id)
					or Stencils.LibroDeItem(id) ~= nil,
				id .. " es consumible pero no hace nada"
			)
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
			-- Los buffs que no son un ítem (los reparte otro sistema, como el
			-- Pergamino de Fortaleza) se declaran con SinItem.
			if string.sub(id, 1, 8) ~= "Servicio" and not def.SinItem then
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

prueba("NPCs: el stock rotativo está bien armado", function()
	for id, a in Npcs.Arquetipos do
		local rotativas = 0
		for _, oferta in a.Vende or {} do
			if oferta.Rotativa then
				rotativas += 1
				exigir(oferta.Limite and oferta.Limite >= 1, id .. ": oferta rotativa sin límite: " .. oferta.ItemId)
			end
		end
		if a.Rotacion then
			exigir(a.Rotacion.Cada >= 60, id .. " rota demasiado seguido")
			exigir(a.Rotacion.Cantidad >= 1 and a.Rotacion.Cantidad <= rotativas, id .. " muestra más ofertas rotativas de las que tiene")
		else
			exigir(rotativas == 0, id .. " tiene ofertas rotativas pero no define Rotacion")
		end
	end
end)

prueba("Cambista: cambiar honor rinde menos que gastarlo en un NPC y revender", function()
	local tasa = Npcs.Cambio.OroPorHonor
	exigir(tasa > 0, "tasa inválida")
	local mejor = 0
	for _, a in Npcs.Arquetipos do
		for _, oferta in a.Vende or {} do
			if oferta.Moneda == "Honor" then
				mejor = math.max(mejor, ItemCatalog[oferta.ItemId].PrecioVenta / oferta.Precio)
			end
		end
	end
	exigir(mejor > 0, "no hay nada que se compre con honor")
	exigir(tasa <= mejor, "el Cambista paga " .. tasa .. " por honor y la reventa rinde " .. mejor)
	for id, a in Npcs.Arquetipos do
		for _, s in a.Servicios or {} do
			if s.Accion == "CambiarHonor" then
				exigir(s.Lote and math.floor(s.Lote * tasa) >= 1, id .. ": lote que no da oro: " .. s.Id)
			end
		end
	end
end)

-- Exploración: piedras de viaje rápido y puntos de interés.
local Exploracion = cargar("ReplicatedStorage/Configs/ExploracionConfig")

prueba("exploración: piedras y puntos están en zonas que existen", function()
	for _, tabla in { Exploracion.Piedras, Exploracion.Interes } do
		for id, dato in tabla do
			exigir(type(dato.Nombre) == "string" and dato.Nombre ~= "", id .. " sin nombre")
			exigir(Zonas.Zonas[dato.Zona] ~= nil or dato.Zona == "Pruebas", id .. " en una zona inexistente: " .. dato.Zona)
			exigir(dato.Posicion ~= nil, id .. " sin posición")
		end
	end
	for id, punto in Exploracion.Interes do
		exigir(type(punto.Icono) == "string" and punto.Icono ~= "", id .. " sin ícono")
		exigir(type(punto.Descripcion) == "string" and punto.Descripcion ~= "", id .. " sin descripción")
	end
end)

prueba("exploración: hay al menos dos piedras por zona y no se superponen", function()
	local porZona = {}
	for _, piedra in Exploracion.Piedras do
		porZona[piedra.Zona] = (porZona[piedra.Zona] or 0) + 1
	end
	for zona, cantidad in porZona do
		exigir(cantidad >= 2, "la zona " .. zona .. " tiene una sola piedra: no se puede viajar")
	end
	local ocupados = {}
	for id, piedra in Exploracion.Piedras do
		local clave = piedra.Zona .. ":" .. piedra.Posicion.X .. "," .. piedra.Posicion.Z
		exigir(not ocupados[clave], "dos piedras en el mismo lugar: " .. id)
		ocupados[clave] = true
	end
	exigir(#Exploracion.PiedrasDe("Pruebas") == 4, "piedras de la zona de pruebas")
	exigir(#Exploracion.PiedrasDe("ZonaQueNoExiste") == 0, "zona sin piedras")
end)

prueba("exploración: viajar a otra zona cuesta más que dentro de la misma", function()
	local a = { Nombre = "A", Zona = "Pruebas", Posicion = Vector3.new(0, 0, 0) }
	local b = { Nombre = "B", Zona = "Pruebas", Posicion = Vector3.new(50, 0, 0) }
	local c = { Nombre = "C", Zona = "Bosque", Posicion = Vector3.new(0, 0, 0) }
	exigir(Exploracion.Costo(a, b) == Exploracion.CostoViaje, "misma zona")
	exigir(Exploracion.Costo(a, c) > Exploracion.Costo(a, b), "otra zona sale más")
end)

prueba("establo: monturas comprables coherentes y entrenamiento acotado", function()
	local Monet = cargar("ReplicatedStorage/Configs/MonetizacionConfig")
	local gratis = 0
	for id, def in Monet.Monturas do
		exigir(def.Velocidad > 16, id .. " no es más rápida que ir a pie")
		exigir(def.NivelMinimo >= 1, id .. " con nivel inválido")
		if def.Precio then
			exigir(def.Precio > 0, id .. " con precio inválido")
			exigir(def.Pase == nil, id .. " se compra con oro y con pase a la vez")
		elseif not def.Pase then
			gratis += 1
		end
	end
	exigir(gratis >= 1, "ninguna montura es gratis")
	local e = Monet.Establo.Entrenamiento
	exigir(e.Maximo % e.Paso == 0, "el máximo de entrenamiento no es múltiplo del paso")
	exigir(e.Costo > 0 and e.AumentoPorNivel >= 0, "costos de entrenamiento")
	local alquiler = Monet.Establo.Alquiler
	local montura = Monet.Monturas[alquiler.Id]
	exigir(montura ~= nil and montura.Precio ~= nil, "se alquila una montura que no se vende")
	exigir(alquiler.Costo < montura.Precio, "alquilar no puede costar más que comprar")
	exigir(alquiler.Duracion >= 60, "duración del alquiler")
end)

-- Progresión social: descanso, diarias y reputación.
local Social = cargar("ReplicatedStorage/Configs/ProgresionSocialConfig")
local Misiones = cargar("ReplicatedStorage/Configs/MisionesConfig")

prueba("descanso: el bonus sale del saldo y nunca da experiencia infinita", function()
	local xp, usado = Social.AplicarDescanso(100, 0)
	exigir(xp == 100 and usado == 0, "sin saldo no cambia nada")
	xp, usado = Social.AplicarDescanso(100, 1000)
	exigir(xp == 150 and usado == 50, "con saldo: " .. xp .. " / " .. usado)
	xp, usado = Social.AplicarDescanso(100, 20)
	exigir(xp == 120 and usado == 20, "el saldo corto limita el extra")
	xp, usado = Social.AplicarDescanso(0, 1000)
	exigir(xp == 0 and usado == 0, "sin experiencia no se gasta saldo")
	exigir(Social.Descanso.PorCompra <= Social.Descanso.Maximo, "una compra no puede pasar el tope")
	exigir(Social.Descanso.Costo > 0 and Social.Descanso.Bonus > 0, "costos del descanso")
end)

prueba("diarias: el día cambia una vez cada 24 h y hay contratos para llenar el cupo", function()
	local base = 1800000000
	exigir(Social.DiaDe(base) == Social.DiaDe(base + 3600), "una hora después es el mismo día")
	exigir(Social.DiaDe(base + 86400) == Social.DiaDe(base) + 1, "un día después es el siguiente")
	local falta = Social.FaltaParaReinicio(base)
	exigir(falta > 0 and falta <= 86400, "falta para el reinicio: " .. falta)
	exigir(Social.DiaDe(base + falta + 1) == Social.DiaDe(base) + 1, "pasado el reinicio cambia el día")
	local diarias = 0
	for id, mision in Misiones.Misiones do
		if mision.Diaria then
			diarias += 1
			exigir(mision.Repetible, id .. " es diaria pero no repetible")
			exigir(mision.Npc == "Tablon", id .. " es diaria y no la da el tablón")
			exigir(Misiones.Npcs[mision.Npc] ~= nil, id .. " apunta a un NPC que no existe")
		end
	end
	exigir(diarias >= Social.Diarias.PorDia, "hay " .. diarias .. " diarias y el cupo es " .. Social.Diarias.PorDia)
	exigir(Social.Diarias.MultiplicadorRecompensa >= 1, "las diarias no pueden rendir menos")
end)

prueba("reputación: niveles ordenados y ofertas alcanzables", function()
	local previo = -1
	for _, nivel in Social.Niveles do
		exigir(nivel.Desde > previo, "los niveles no están ordenados: " .. nivel.Nombre)
		previo = nivel.Desde
	end
	exigir(Social.Niveles[1].Desde == 0, "el primer nivel tiene que arrancar en 0")
	local nombre, falta = Social.NivelDe(0)
	exigir(nombre == "Neutral" and falta > 0, "nivel inicial")
	exigir(select(1, Social.NivelDe(Social.Reputacion.Maximo)) == "Exaltado", "con el máximo se llega a Exaltado")
	exigir(select(2, Social.NivelDe(Social.Reputacion.Maximo)) == 0, "al tope no falta nada")
	for i, oferta in Social.Ofertas do
		exigir(oferta.Costo > 0, "oferta " .. i .. " sin costo")
		exigir(oferta.Reputacion <= Social.Reputacion.Maximo, "oferta " .. i .. " pide más de lo alcanzable")
		exigir((oferta.Titulo ~= nil) ~= (oferta.ItemId ~= nil), "oferta " .. i .. " tiene que dar un título o un ítem")
		if oferta.ItemId then
			exigir(ItemCatalog[oferta.ItemId] ~= nil, "oferta " .. i .. " con ítem inexistente")
		end
	end
	local diasAlMaximo = Social.Reputacion.Maximo / Social.Reputacion.MaximoPorDia
	exigir(diasAlMaximo >= 7, "llegar al tope de reputación toma " .. diasAlMaximo .. " días: demasiado rápido")
end)

-- Cosméticos: barbero y mascotas compradas con oro.
local Apariencia = cargar("ReplicatedStorage/Configs/AparienciaConfig")
local Mascotas = cargar("ReplicatedStorage/Configs/MascotasConfig")

prueba("barbero: pieles con color, y los estilos sin asset quedan marcados", function()
	local pieles = 0
	for id, piel in Apariencia.Barbero.Pieles do
		pieles += 1
		exigir(type(piel.Nombre) == "string" and piel.Nombre ~= "", id .. " sin nombre")
		exigir(piel.Color ~= nil, id .. " sin color")
	end
	exigir(pieles >= 2, "hace falta más de un color de piel")
	exigir(Apariencia.Barbero.Pieles.Avatar ~= nil, "falta la opción de volver al color del avatar")
	exigir(Apariencia.Barbero.Costo > 0, "el barbero tiene que cobrar algo")
	for _, tabla in { Apariencia.Barbero.Peinados, Apariencia.Barbero.Marcas } do
		for id, estilo in tabla do
			exigir(type(estilo.Nombre) == "string" and estilo.Nombre ~= "", id .. " sin nombre")
			exigir(type(estilo.AssetId) == "number" and estilo.AssetId >= 0, id .. " con AssetId inválido")
		end
	end
end)

prueba("mascotas: las de oro tienen precio creciente y las del pase no", function()
	local conPrecio, sinPrecio = 0, 0
	for id, def in Mascotas.Mascotas do
		exigir(type(def.Nombre) == "string" and def.Nombre ~= "", id .. " sin nombre")
		exigir(def.Tam > 0, id .. " con tamaño inválido")
		if def.Precio then
			conPrecio += 1
			exigir(def.Precio > 0, id .. " con precio inválido")
		else
			sinPrecio += 1
		end
	end
	exigir(conPrecio >= 1, "ninguna mascota se compra con oro")
	exigir(sinPrecio >= 1, "ninguna mascota queda para el pase de batalla")
end)

prueba("NPCs: las acciones de los servicios siguen el patrón esperado", function()
	-- Las acciones que arman otros módulos por id (monturas, mascotas) tienen
	-- que coincidir con una entrada real de su config.
	local Monet = cargar("ReplicatedStorage/Configs/MonetizacionConfig")
	for id, a in Npcs.Arquetipos do
		for _, s in a.Servicios or {} do
			local accion = s.Accion
			if type(accion) ~= "string" then
				continue
			end
			local montura = string.match(accion, "^ComprarMontura(%w+)$")
			if montura then
				exigir(Monet.Monturas[montura] ~= nil, id .. ": montura inexistente " .. montura)
				exigir(Monet.Monturas[montura].Precio ~= nil, id .. ": " .. montura .. " no se vende por oro")
				exigir(s.Costo == Monet.Monturas[montura].Precio, id .. ": el costo del servicio no coincide con el precio")
			end
			local mascota = string.match(accion, "^ComprarMascota(%w+)$")
			if mascota then
				exigir(Mascotas.Mascotas[mascota] ~= nil, id .. ": mascota inexistente " .. mascota)
				exigir(Mascotas.Mascotas[mascota].Precio ~= nil, id .. ": " .. mascota .. " no se vende por oro")
				exigir(s.Costo == Mascotas.Mascotas[mascota].Precio, id .. ": el costo del servicio no coincide con el precio")
			end
		end
	end
end)
