-- NPC Cosméticos: pestañas y el costo escalonado de deshacer.
local C = cargar("ReplicatedStorage/Configs/CosmeticosConfig")

prueba("cosméticos: las cuatro pestañas están declaradas y se validan", function()
	exigir(#C.Pestanas == 4, "cuatro pestañas")
	for _, pestana in C.Pestanas do
		exigir(C.PestanaValida(pestana), "la pestaña " .. pestana .. " tiene que validar")
		exigir(C.NombrePestana[pestana] ~= nil, "falta el nombre visible de " .. pestana)
	end
	exigir(not C.PestanaValida("Otra"), "no acepta pestañas inventadas")
	exigir(not C.PestanaValida(nil) and not C.PestanaValida(7), "ni cualquier cosa")

	-- Tres pestañas tocan la personalización del ítem; Visual es el transmog.
	exigir(not C.EsDePersonalizacion("Visual"), "Visual es transmog, no personalización")
	exigir(C.EsDePersonalizacion("Colores"), "Colores va en la personalización")
	exigir(C.EsDePersonalizacion("Decals"), "Decals también")
	exigir(C.EsDePersonalizacion("Marcas"), "Marcas también")
end)

prueba("cosméticos: deshacer es gratis la primera vez y después duplica", function()
	exigir(C.CostoDeshacer(0) == 0, "el primer deshacer es gratis")
	exigir(C.CostoDeshacer(1) == C.DeshacerBase, "el segundo cuesta la base")
	exigir(C.CostoDeshacer(2) == C.DeshacerBase * 2, "el tercero, el doble del segundo")
	exigir(C.CostoDeshacer(3) == C.DeshacerBase * 4, "y así, duplicando")
	-- Nunca baja, y tiene techo para no llegar a números absurdos.
	local anterior = -1
	for previos = 0, 30 do
		local costo = C.CostoDeshacer(previos)
		exigir(costo >= anterior, "el costo no puede bajar")
		exigir(costo <= C.DeshacerTope, "nunca se pasa del techo")
		anterior = costo
	end
	exigir(C.CostoDeshacer(99) == C.DeshacerTope, "muy arriba, queda en el techo")
	exigir(C.CostoDeshacer(-5) == 0, "un contador raro no cobra de más")

	exigir(C.TextoDeshacer(0) == "gratis", "el primero se anuncia gratis")
	exigir(C.TextoDeshacer(2) ~= "gratis", "los demás muestran el precio")
	exigir(C.DeshacerBase > 0 and C.DeshacerFactor > 1, "tiene que escalar de verdad")
end)

prueba("cosméticos: la cámara del preview tiene límites sanos", function()
	local cam = C.Camara
	exigir(cam.DistanciaMin > 0, "no puede meterse adentro del personaje")
	exigir(cam.DistanciaMax > cam.DistanciaMin, "el rango de zoom tiene que existir")
	exigir(cam.Distancia >= cam.DistanciaMin and cam.Distancia <= cam.DistanciaMax, "arranca dentro del rango")
	exigir(cam.Altura > 0, "mira desde arriba del piso")
	exigir(C.Distancia > 0, "hay que poder estar cerca del NPC")
end)

prueba("cosméticos: el NPC atiende lo que absorbió y nadie lo duplica", function()
	local NPC = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")
	local cosmeticos = NPC.Arquetipos.Transfigurador
	exigir(cosmeticos.Numero == 30, "es el 030")
	exigir(cosmeticos.Estado == "Listo", "está listo")
	exigir(cosmeticos.Sistema ~= nil, "tiene que decir qué sistema lo atiende")

	-- Nadie más puede ofrecer tintar ni grabar: era el punto de unificarlo.
	for id, a in NPC.Arquetipos do
		for _, servicio in a.Servicios or {} do
			exigir(servicio.Accion ~= "Tintar", id .. " todavía ofrece tintar")
			exigir(servicio.Accion ~= "Grabar", id .. " todavía ofrece grabar")
		end
	end

	-- Los absorbidos apuntan a un arquetipo real y no aparecen en la plaza.
	for id, a in NPC.Arquetipos do
		if a.Absorbido then
			exigir(NPC.Arquetipos[a.Absorbido] ~= nil, id .. " apunta a un arquetipo inexistente")
			for _, prueba_ in NPC.DePrueba do
				exigir(prueba_.Arquetipo ~= id, id .. " está absorbido pero igual aparece en la plaza de prueba")
			end
		end
	end
end)
