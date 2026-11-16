-- Stencils: libros, desbloqueo, límites de escala y opacidad, y codificación.
local S = cargar("ReplicatedStorage/Configs/StencilsConfig")
local P = cargar("ReplicatedStorage/Configs/PersonalizadorConfig")
local ITEMS = cargar("ReplicatedStorage/Configs/ItemCatalog")
local NPC = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")

prueba("stencils: tres libros, cada uno con su ítem y sus stencils", function()
	exigir(#S.Libros == 3, "tres libros")
	local inscriptor = NPC.Arquetipos.Inscriptor
	local vende: { [string]: number } = {}
	for _, oferta in inscriptor.Vende or {} do
		vende[oferta.ItemId] = oferta.Precio
	end
	for _, libro in S.Libros do
		local item = ITEMS[libro.Item]
		exigir(item ~= nil, "el libro no está en el catálogo: " .. libro.Item)
		exigir(item.Tipo == "Consumible", libro.Item .. " tiene que ser consumible (se lee una vez)")
		exigir(item.Apilable == false, libro.Item .. " no debería apilarse")
		exigir(S.LibroDeItem(libro.Item) ~= nil, "LibroDeItem() tiene que encontrarlo")
		exigir(#S.DelLibro(libro.Id) >= 2, libro.Id .. " tiene que traer varios stencils")
		exigir(vende[libro.Item] ~= nil, "el Inscriptor no vende " .. libro.Item)
		exigir(vende[libro.Item] > (item.PrecioVenta or 0), "se puede revender con ganancia: " .. libro.Item)
	end
	exigir(S.LibroDeItem("PocionVida") == nil, "no confunde cualquier ítem con un libro")

	-- Todo stencil pertenece a un libro que existe, y los ids no se repiten.
	local vistos: { [string]: boolean } = {}
	for _, stencil in S.Stencils do
		exigir(not vistos[stencil.Id], "stencil repetido: " .. stencil.Id)
		vistos[stencil.Id] = true
		exigir(S.Libro(stencil.Libro) ~= nil, stencil.Id .. " está en un libro que no existe")
		exigir(S.Stencil(stencil.Id) ~= nil, "Stencil() tiene que encontrarlo")
	end
	exigir(S.Stencil("NoExiste") == nil, "no inventa stencils")
end)

prueba("stencils: sin arte subida, no se pueden usar", function()
	-- Hoy ninguna textura está cargada: el usuario las tiene que subir. Esta
	-- prueba documenta el estado y avisa cuando empiecen a estar.
	local conArte = 0
	for _, stencil in S.Stencils do
		if S.Disponible(stencil) then
			conArte += 1
			exigir(stencil.Textura > 0, "Disponible() dijo que sí sin textura: " .. stencil.Id)
		else
			exigir(stencil.Textura == 0, "Disponible() dijo que no con textura: " .. stencil.Id)
			-- Sin arte, ni con el libro desbloqueado se puede elegir.
			exigir(not S.Permitido(stencil.Id, { stencil.Libro }), stencil.Id .. " no debería poder usarse sin arte")
		end
	end
end)

prueba("stencils: en pruebas hay una textura de relleno para probar sin arte", function()
	exigir(S.TexturaPrueba > 0, "hace falta una textura de relleno")
	local stencil = S.Stencils[1]
	if stencil.Textura == 0 then
		exigir(not S.Disponible(stencil), "fuera de pruebas, sin arte no está disponible")
		exigir(S.Disponible(stencil, true), "en pruebas, sí")
		exigir(S.TexturaDe(stencil) == 0, "fuera de pruebas no hay textura")
		exigir(S.TexturaDe(stencil, true) == S.TexturaPrueba, "en pruebas usa la de relleno")
		exigir(S.Permitido(stencil.Id, { stencil.Libro }, true), "en pruebas se puede elegir con el libro")
		exigir(not S.Permitido(stencil.Id, {}, true), "pero el libro sigue siendo obligatorio")
	else
		-- Ya hay arte subida: la de relleno no se usa más para este stencil.
		exigir(S.TexturaDe(stencil, true) == stencil.Textura, "con arte propia, se usa la propia")
	end
end)

prueba("stencils: hace falta el libro desbloqueado", function()
	local stencil = S.Stencils[1]
	exigir(not S.Permitido(stencil.Id, {}), "sin libros no se puede usar nada")
	exigir(not S.Permitido(stencil.Id, { "OtroLibro" }), "otro libro no habilita este stencil")
	exigir(not S.Permitido("NoExiste", { stencil.Libro }), "un stencil inventado nunca se permite")
end)

prueba("stencils: escala y opacidad se acomodan a los pasos y a los límites", function()
	exigir(S.AcomodarEscala(0) == S.EscalaMin, "por debajo del mínimo sube al mínimo")
	exigir(S.AcomodarEscala(9999) == S.EscalaMax, "por encima del máximo baja al máximo")
	exigir(S.AcomodarEscala(S.EscalaMin + 1) == S.EscalaMin, "redondea al paso")
	exigir(S.EscalaValida(S.AcomodarEscala(57)), "lo acomodado siempre es válido")
	exigir(not S.EscalaValida(S.EscalaMax + S.EscalaPaso), "pasarse no vale")
	exigir(not S.EscalaValida(S.EscalaMin - 1), "quedarse corto tampoco")

	exigir(S.AcomodarOpacidad(0) == S.OpacidadMin, "la opacidad tiene piso")
	exigir(S.AcomodarOpacidad(1000) == S.OpacidadMax, "y techo")
	exigir(S.OpacidadValida(S.AcomodarOpacidad(73)), "lo acomodado es válido")
	exigir(S.OpacidadMin > 0, "un stencil invisible no tendría sentido")
	exigir(S.OpacidadMax <= 100, "no se puede pasar del 100%")
end)

prueba("stencils: el costo respeta el tope por ítem", function()
	exigir(S.Costo(0) == 0, "sin stencils no se cobra")
	exigir(S.Costo(1) == S.CostoPorStencil, "uno")
	exigir(S.Costo(2) == S.CostoPorStencil * 2, "dos")
	exigir(S.Costo(99) == S.CostoPorStencil * S.MaxPorItem, "nunca cobra más que el tope")
	exigir(S.Costo(-3) == 0, "cantidades negativas no cobran")
	exigir(S.MaxPorItem >= 1 and S.MaxPorItem <= P.MaxPiezas, "el tope por ítem tiene que ser alcanzable")
end)

prueba("stencils: viajan en la personalización y se cuentan como cambio", function()
	local stencil = { Id = "RunaVida", Escala = S.AcomodarEscala(50), Opacidad = S.AcomodarOpacidad(80) }
	local pers = { Hoja = { Material = "Metal", Color = "A0B1C2", Stencil = stencil } }
	local texto = P.Codificar(pers)
	local vuelta = P.Decodificar(texto)
	exigir(vuelta ~= nil, "se decodifica")
	local puesto = vuelta.Hoja.Stencil
	exigir(puesto ~= nil, "el stencil sobrevive la ida y vuelta")
	exigir(puesto.Id == stencil.Id, "mismo stencil")
	exigir(puesto.Escala == stencil.Escala and puesto.Opacidad == stencil.Opacidad, "misma escala y opacidad")
	exigir(P.Codificar(vuelta) == texto, "codificar dos veces da lo mismo")
	exigir(P.CuantosStencils(vuelta) == 1, "cuenta uno")
	exigir(P.CuantosStencils({ Hoja = { Material = "Metal", Color = "A0B1C2" } }) == 0, "sin stencil, cero")

	-- Poner, cambiar o sacar el stencil cuenta como cambiar la pieza.
	local sin = { Hoja = { Material = "Metal", Color = "A0B1C2" } }
	exigir(P.Diferencias(sin, pers) == 1, "ponerlo es un cambio")
	exigir(P.Diferencias(pers, sin) == 1, "sacarlo también")
	exigir(P.Diferencias(pers, pers) == 0, "lo mismo no es cambio")
	local otraEscala = {
		Hoja = { Material = "Metal", Color = "A0B1C2", Stencil = { Id = "RunaVida", Escala = S.EscalaMax, Opacidad = 80 } },
	}
	exigir(P.Diferencias(pers, otraEscala) == 1, "cambiar el tamaño es un cambio")
	exigir(P.MismoStencil(nil, nil), "dos sin stencil son iguales")
	exigir(not P.MismoStencil(nil, stencil), "uno con y uno sin, distintos")
end)

prueba("stencils: el NPC Cosméticos aplica, el Inscriptor vende los libros", function()
	-- Los decals se aplican en un solo lugar: el NPC Cosméticos (#30).
	local cosmeticos = NPC.Arquetipos.Transfigurador
	exigir(cosmeticos.Numero == 30 and cosmeticos.Nombre == "Cosméticos", "el 030 es el NPC de cosméticos")
	local abre = false
	for _, servicio in cosmeticos.Servicios or {} do
		if servicio.Accion == "Cosmeticos" then
			abre = true
			exigir(servicio.Costo == 0, "abrir el panel no cobra: aplicar es gratis")
		end
	end
	exigir(abre, "el NPC Cosméticos tiene que abrir su panel")

	-- El Inscriptor conserva los libros (el desbloqueo) y los pergaminos.
	local inscriptor = NPC.Arquetipos.Inscriptor
	local libros = 0
	for _, oferta in inscriptor.Vende or {} do
		if S.LibroDeItem(oferta.ItemId) then
			libros += 1
		end
	end
	exigir(libros == #S.Libros, "el Inscriptor tiene que seguir vendiendo los tres libros")
	for _, servicio in inscriptor.Servicios or {} do
		exigir(servicio.Accion ~= "Grabar", "grabar ya no es del Inscriptor: es del NPC Cosméticos")
	end

	-- El Tintorero quedó absorbido y no atiende por su cuenta.
	local tintorero = NPC.Arquetipos.Tintorero
	exigir(tintorero.Absorbido == "Transfigurador", "el Tintorero tiene que figurar absorbido")
	exigir(#(tintorero.Servicios or {}) == 0, "y no puede seguir ofreciendo lo mismo por su cuenta")
end)

prueba("relieves: son otra cosa que las calcomanías y piden las dos texturas", function()
	exigir(#S.Relieves >= 3, "hacen falta relieves")
	local vistos: { [string]: boolean } = {}
	for _, relieve in S.Relieves do
		exigir(not vistos[relieve.Id], "relieve repetido: " .. relieve.Id)
		vistos[relieve.Id] = true
		exigir(S.Relieve(relieve.Id) ~= nil, "Relieve() tiene que encontrarlo")
		exigir(S.Libro(relieve.Libro) ~= nil, relieve.Id .. " está en un libro que no existe")
		exigir(relieve.Rugosidad >= 0 and relieve.Rugosidad <= 1, relieve.Id .. " con rugosidad fuera de rango")
		-- Un relieve necesita ColorMap y NormalMap: con una sola no alcanza.
		if relieve.ColorMap == 0 or relieve.NormalMap == 0 then
			exigir(not S.RelieveDisponible(relieve), relieve.Id .. " no debería estar disponible a medias")
			exigir(not S.RelievePermitido(relieve.Id, { relieve.Libro }), "sin arte no se puede usar")
		end
		-- No hay relleno de prueba para relieves, ni con el libro puesto.
		exigir(S.Relieve(relieve.Id) ~= nil, "sigue existiendo")
	end
	exigir(S.Relieve("NoExiste") == nil, "no inventa relieves")
	exigir(not S.RelievePermitido("NoExiste", { "Runas" }), "ni permite los inventados")

	-- Un id de calcomanía no es un id de relieve, y al revés tampoco.
	for _, stencil in S.Stencils do
		exigir(S.Relieve(stencil.Id) == nil, "una calcomanía no puede ser relieve: " .. stencil.Id)
	end
	for _, relieve in S.Relieves do
		exigir(S.Stencil(relieve.Id) == nil, "un relieve no puede ser calcomanía: " .. relieve.Id)
	end

	exigir(S.CostoRelieves(0) == 0, "sin relieves no se cobra")
	exigir(S.CostoRelieves(1) == S.CostoPorRelieve, "uno")
	exigir(S.CostoRelieves(99) == S.CostoPorRelieve * S.MaxRelievesPorItem, "nunca más que el tope")
	exigir(S.CostoPorRelieve > S.CostoPorStencil, "un relieve cuesta más que una calcomanía")
end)

prueba("relieves: viajan en la personalización y son un cambio aparte", function()
	local base = { Hoja = { Material = "Metal", Color = "A0B1C2" } }
	local conRelieve = { Hoja = { Material = "Metal", Color = "A0B1C2", Relieve = "RelieveRunico" } }
	local texto = P.Codificar(conRelieve)
	local vuelta = P.Decodificar(texto)
	exigir(vuelta ~= nil and vuelta.Hoja.Relieve == "RelieveRunico", "el relieve sobrevive la ida y vuelta")
	exigir(P.Codificar(vuelta) == texto, "codificar dos veces da lo mismo")
	exigir(P.CuantosRelieves(vuelta) == 1, "cuenta uno")
	exigir(P.CuantosRelieves(base) == 0, "sin relieve, cero")
	exigir(P.Diferencias(base, conRelieve) == 1, "ponerlo es un cambio")
	exigir(P.Diferencias(conRelieve, base) == 1, "sacarlo también")
	exigir(P.Diferencias(conRelieve, conRelieve) == 0, "lo mismo no es cambio")

	-- Calcomanía y relieve conviven en la misma pieza.
	local ambos = {
		Hoja = {
			Material = "Metal",
			Color = "A0B1C2",
			Stencil = { Id = "RunaVida", Escala = S.AcomodarEscala(40), Opacidad = S.AcomodarOpacidad(90) },
			Relieve = "RelieveRunico",
		},
	}
	local textoAmbos = P.Codificar(ambos)
	local vueltaAmbos = P.Decodificar(textoAmbos)
	exigir(vueltaAmbos ~= nil, "se decodifica")
	exigir(vueltaAmbos.Hoja.Stencil ~= nil and vueltaAmbos.Hoja.Relieve == "RelieveRunico", "los dos sobreviven")
	exigir(P.Codificar(vueltaAmbos) == textoAmbos, "ida y vuelta estable")

	-- Las versiones viejas no pueden traer relieves.
	exigir(P.Decodificar("2|Hoja=Metal,A0B1C2;R=RelieveRunico") == nil, "la versión 2 no tiene relieves")
	exigir(P.Decodificar(P.Version .. "|Hoja=Metal,A0B1C2;X=1") == nil, "basura con ; se rechaza")
end)

prueba("decals: están agrupados y cada grupo tiene contenido", function()
	exigir(#S.Grupos >= 3, "hacen falta grupos para que la lista sirva")
	local vistos: { [string]: boolean } = {}
	for _, grupo in S.Grupos do
		exigir(not vistos[grupo.Id], "grupo repetido: " .. grupo.Id)
		vistos[grupo.Id] = true
		exigir(grupo.Nombre ~= "", grupo.Id .. " sin nombre visible")
		exigir(#S.DelGrupo(grupo.Id) >= 1, "el grupo " .. grupo.Id .. " quedó vacío")
		exigir(S.Grupo(grupo.Id) ~= nil, "Grupo() tiene que encontrarlo")
	end
	exigir(S.Grupo("NoExiste") == nil, "no inventa grupos")
	exigir(#S.DelGrupo("NoExiste") == 0, "un grupo inexistente no devuelve nada")

	-- Todo decal pertenece a un grupo real, y cada uno sigue teniendo su libro.
	for _, stencil in S.Stencils do
		exigir(S.Grupo(stencil.Grupo) ~= nil, stencil.Id .. " está en un grupo que no existe: " .. stencil.Grupo)
		exigir(S.Libro(stencil.Libro) ~= nil, stencil.Id .. " está en un libro que no existe")
	end
	-- Cada libro tiene que desbloquear algo, o comprarlo no serviría de nada.
	for _, libro in S.Libros do
		exigir(#S.DelLibro(libro.Id) >= 1, "el libro " .. libro.Id .. " no desbloquea nada")
	end
end)
