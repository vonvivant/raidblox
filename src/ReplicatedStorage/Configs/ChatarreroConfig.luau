--!strict
-- ChatarreroConfig: la clase Chatarrero. Base de datos de sus 30 habilidades
-- y los números del Spoil y de sus construcciones.
--
-- * Recurso: Stamina (usa la misma barra que el maná de las otras clases).
-- * 4 barras de 4 botones. Cada barra es una categoría de recarga y el
--   jugador equipa 4 habilidades de cada una (16 de 30):
--     I   Instantes      2-3 s
--     II  Mid Spells     120 s (2 min)
--     III Mid Ultis      600 s (10 min)
--     IV  Ultis Masivas  1200 s (20 min)
--   Las recargas de 60 s o más sobreviven a morir y a desconectarse.
-- * Spoil (ver ChatarreroManager): "Extracción Rápida" marca a un monstruo
--   vivo; si al morir el Spoil tiene éxito, sus restos quedan resaltados unos
--   segundos y el Chatarrero les saca materiales con sus habilidades de
--   extracción.
-- * `Especial` = mecánica propia programada en ChatarreroManager. Lo demás lo
--   resuelve el combate normal con `Efectos`.
-- * `Pendiente` = la habilidad original necesita un sistema que el juego
--   todavía no tiene (durabilidad del equipo, banco personal); mientras tanto
--   hace un efecto parecido, explicado en su descripción.

local HabilidadTipos = require(script.Parent.HabilidadTipos)

type Habilidad = HabilidadTipos.Habilidad
type Efecto = HabilidadTipos.Efecto

export type EntradaSpoil = { ItemId: string, Min: number, Max: number, Probabilidad: number }

local SIN_EFECTOS: { Efecto } = {}

local Habilidades: { Habilidad } = {
	--------------------------------------------------------------------
	-- Categoría I: Básicas / Instantes (2-3 s)
	--------------------------------------------------------------------
	{
		Numero = 1,
		Id = "GolpePalanca",
		Nombre = "Golpe de Palanca",
		Calidad = "Comun",
		Categoria = 1,
		Descripcion = "Golpe cuerpo a cuerpo con la palanca. Genera poca amenaza.",
		CostoMana = 0,
		Cooldown = 2,
		Rango = 8,
		TiempoCasteo = 0,
		Objetivo = "Enemigo",
		Efectos = { { Tipo = "Danio", Escuela = "Fisico", Base = 9, Escala = "Ataque", Factor = 0.85 } },
	},
	{
		Numero = 2,
		Id = "MarcaSaqueador",
		Nombre = "Marca de Saqueador",
		Calidad = "Comun",
		Categoria = 1,
		Descripcion = "Marca a un monstruo: duplica la probabilidad de que el Spoil tenga éxito cuando muera.",
		CostoMana = 5,
		Cooldown = 3,
		Rango = 25,
		TiempoCasteo = 0,
		Objetivo = "Enemigo",
		Efectos = SIN_EFECTOS,
		Especial = "Marca",
	},
	{
		Numero = 3,
		Id = "ExtraccionRapida",
		Nombre = "Extracción Rápida",
		Calidad = "Inusual",
		Categoria = 1,
		Descripcion = "Spoil Menor. Sobre un monstruo vivo: lo prepara para dejar restos al morir. Con restos tuyos a menos de 10 studs: les saca los materiales.",
		CostoMana = 8,
		Cooldown = 3,
		Rango = 25,
		TiempoCasteo = 0,
		Objetivo = "Enemigo",
		ObjetivoOpcional = true,
		Efectos = SIN_EFECTOS,
		Especial = "Spoil",
	},
	{
		Numero = 4,
		Id = "VarapaloDefensivo",
		Nombre = "Varapalo Defensivo",
		Calidad = "Inusual",
		Categoria = 1,
		Descripcion = "Golpe rápido que empuja al enemigo y te da +15% de defensa por 4 s.",
		CostoMana = 10,
		Cooldown = 3,
		Rango = 8,
		TiempoCasteo = 0,
		Objetivo = "Enemigo",
		Efectos = {
			{ Tipo = "Danio", Escuela = "Fisico", Base = 6, Escala = "Ataque", Factor = 0.6 },
			{ Tipo = "Empujar", Fuerza = 38 },
		},
		EfectosPropios = { { Tipo = "Aura", Stat = "Defensa", Porcentaje = 15, Duracion = 4 } } :: { Efecto },
	},
	{
		Numero = 5,
		Id = "OlfatoChatarrero",
		Nombre = "Olfato de Chatarrero",
		Calidad = "Rara",
		Categoria = 1,
		Descripcion = "Pasiva activa: por 20 s resalta las vetas de metal y los restos cercanos (150 studs).",
		CostoMana = 5,
		Cooldown = 3,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "Olfato",
	},
	{
		Numero = 6,
		Id = "CortePreciso",
		Nombre = "Corte Preciso",
		Calidad = "Comun",
		Categoria = 1,
		Descripcion = "Daño físico menor que baja 5% la defensa del objetivo por 8 s.",
		CostoMana = 6,
		Cooldown = 2.5,
		Rango = 8,
		TiempoCasteo = 0,
		Objetivo = "Enemigo",
		Efectos = {
			{ Tipo = "Danio", Escuela = "Fisico", Base = 5, Escala = "Ataque", Factor = 0.5 },
			{ Tipo = "Aura", Stat = "Defensa", Porcentaje = -5, Duracion = 8 },
		},
	},
	{
		Numero = 7,
		Id = "BebidaEnergetica",
		Nombre = "Bebida Energética Casera",
		Calidad = "Inusual",
		Categoria = 1,
		Descripcion = "Recupera 15 de Stamina al instante.",
		CostoMana = 0,
		Cooldown = 3,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = { { Tipo = "Recurso", Cantidad = 15 } },
	},
	{
		Numero = 8,
		Id = "LanzamientoTuercas",
		Nombre = "Lanzamiento de Tuercas",
		Calidad = "Comun",
		Categoria = 1,
		Descripcion = "Proyectil rápido a distancia que interrumpe lo que el enemigo esté casteando.",
		CostoMana = 8,
		Cooldown = 3,
		Rango = 30,
		TiempoCasteo = 0,
		Objetivo = "Enemigo",
		Efectos = {
			{ Tipo = "Danio", Escuela = "Fisico", Base = 5, Escala = "Ataque", Factor = 0.5 },
			{ Tipo = "Interrumpir" },
		},
	},

	--------------------------------------------------------------------
	-- Categoría II: Avanzadas / Mid Spells (120 s)
	--------------------------------------------------------------------
	{
		Numero = 9,
		Id = "BarridoProfundo",
		Nombre = "Barrido Profundo",
		Calidad = "Rara",
		Categoria = 2,
		Descripcion = "Spoil Masivo: saca los materiales de todos tus restos marcados a 15 studs.",
		CostoMana = 20,
		Cooldown = 120,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Radio = 15,
		Efectos = SIN_EFECTOS,
		Especial = "Barrido",
	},
	{
		Numero = 10,
		Id = "KitRemiendos",
		Nombre = "Kit de Remiendos de Emergencia",
		Calidad = "Rara",
		Categoria = 2,
		Descripcion = "Remienda el equipo propio o de un aliado: +20% de defensa por 15 s. (Cuando exista la durabilidad, además la va a restaurar.)",
		CostoMana = 20,
		Cooldown = 120,
		Rango = 20,
		TiempoCasteo = 0,
		Objetivo = "Aliado",
		Efectos = { { Tipo = "Aura", Stat = "Defensa", Porcentaje = 20, Duracion = 15 } },
		Pendiente = "Durabilidad",
	},
	{
		Numero = 11,
		Id = "BombaHumo",
		Nombre = "Bomba de Humo Artesanal",
		Calidad = "Rara",
		Categoria = 2,
		Descripcion = "Nube de humo de 12 studs: ciega 2 s a los monstruos comunes y te deja en sigilo por 6 s.",
		CostoMana = 25,
		Cooldown = 120,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Radio = 12,
		Efectos = { { Tipo = "Invisible", Duracion = 6 } },
		Especial = "Humo",
	},
	{
		Numero = 12,
		Id = "YunquePortatil",
		Nombre = "Yunque Portátil",
		Calidad = "Epica",
		Categoria = 2,
		Descripcion = "Planta un yunque por 60 s. Sirve para fabricar como cualquier yunque y, a vos, para desmantelar equipo común o raro en materiales (menú del ítem en la mochila).",
		CostoMana = 30,
		Cooldown = 120,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "Yunque",
	},
	{
		Numero = 13,
		Id = "TrampaOso",
		Nombre = "Trampa de Oso Mecánica",
		Calidad = "Inusual",
		Categoria = 2,
		Descripcion = "Deja una trampa por 60 s: el primer enemigo que la pisa queda inmóvil 3 s y sangra.",
		CostoMana = 20,
		Cooldown = 120,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "Trampa",
	},
	{
		Numero = 14,
		Id = "EstimulanteAdrenalina",
		Nombre = "Estimulante de Adrenalina",
		Calidad = "Rara",
		Categoria = 2,
		Descripcion = "Te libera si estás inmovilizado y corrés 20% más rápido por 10 s.",
		CostoMana = 15,
		Cooldown = 120,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "Adrenalina",
	},
	{
		Numero = 15,
		Id = "EscudoChatarra",
		Nombre = "Escudo de Chatarra Soldada",
		Calidad = "Epica",
		Categoria = 2,
		Descripcion = "Escudo que absorbe daño por 20 s. Crece con los metales que lleves en la mochila (hasta 60 piezas).",
		CostoMana = 25,
		Cooldown = 120,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "EscudoChatarra",
	},
	{
		Numero = 16,
		Id = "NegociacionTurbia",
		Nombre = "Negociación Turbia",
		Calidad = "Rara",
		Categoria = 2,
		Descripcion = "Confunde a un monstruo común: te deja de perseguir por 6 s. No funciona con jefes.",
		CostoMana = 15,
		Cooldown = 120,
		Rango = 25,
		TiempoCasteo = 0,
		Objetivo = "Enemigo",
		Efectos = { { Tipo = "PerderAgro", Duracion = 6 } },
	},

	--------------------------------------------------------------------
	-- Categoría III: Épicas / Mid Ultis (600 s)
	--------------------------------------------------------------------
	{
		Numero = 17,
		Id = "OjoTasador",
		Nombre = "Ojo del Tasador",
		Calidad = "Epica",
		Categoria = 3,
		Descripcion = "Analiza los restos de un jefe o élite (a 12 studs): la extracción garantiza al menos un material raro.",
		CostoMana = 30,
		Cooldown = 600,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Radio = 12,
		Efectos = SIN_EFECTOS,
		Especial = "Tasador",
	},
	{
		Numero = 18,
		Id = "GolpeArtesano",
		Nombre = "Golpe del Artesano Maestro",
		Calidad = "Epica",
		Categoria = 3,
		Descripcion = "Martillazo de daño masivo que aturde 3 s.",
		CostoMana = 35,
		Cooldown = 600,
		Rango = 8,
		TiempoCasteo = 0,
		Objetivo = "Enemigo",
		Efectos = {
			{ Tipo = "Danio", Escuela = "Fisico", Base = 40, Escala = "Ataque", Factor = 2.6 },
			{ Tipo = "Aturdir", Duracion = 3 },
		},
	},
	{
		Numero = 19,
		Id = "Sobreaceleracion",
		Nombre = "Sobreaceleración de Producción",
		Calidad = "Legendaria",
		Categoria = 3,
		Descripcion = "Por 60 s, 50% de probabilidad de duplicar los materiales del Spoil y lo que fabriques.",
		CostoMana = 30,
		Cooldown = 600,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "Sobreaceleracion",
	},
	{
		Numero = 20,
		Id = "LlamadoContrabandista",
		Nombre = "Llamado del Contrabandista",
		Calidad = "Epica",
		Categoria = 3,
		Descripcion = "Un dron se lleva toda la Chatarra de tu mochila y te la paga a 1,5 veces su precio. (Cuando exista el banco personal, va a llevar ítems al banco.)",
		CostoMana = 20,
		Cooldown = 600,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "Contrabandista",
		Pendiente = "Banco",
	},
	{
		Numero = 21,
		Id = "SobrecargaPolvora",
		Nombre = "Sobrecarga de Pólvora",
		Calidad = "Epica",
		Categoria = 3,
		Descripcion = "Explosión en cono hacia adelante (16 studs): daña, empuja y baja 40% la defensa por 10 s.",
		CostoMana = 40,
		Cooldown = 600,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "AreaEnemigos",
		Centro = "Propio",
		Radio = 16,
		Cono = 45,
		Efectos = {
			{ Tipo = "Danio", Escuela = "Fisico", Base = 25, Escala = "Ataque", Factor = 1.6 },
			{ Tipo = "Empujar", Fuerza = 60 },
			{ Tipo = "Aura", Stat = "Defensa", Porcentaje = -40, Duracion = 10 },
		},
	},
	{
		Numero = 22,
		Id = "ExtraccionQuirurgica",
		Nombre = "Extracción Quirúrgica",
		Calidad = "Legendaria",
		Categoria = 3,
		Descripcion = "Saca un Núcleo de Titán (componente legendario) garantizado de los restos de un jefe de mazmorra o RaidBlox a 12 studs.",
		CostoMana = 30,
		Cooldown = 600,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Radio = 12,
		Efectos = SIN_EFECTOS,
		Especial = "Quirurgica",
	},
	{
		Numero = 23,
		Id = "CatalizadorVolatil",
		Nombre = "Catalizador Volátil",
		Calidad = "Epica",
		Categoria = 3,
		Descripcion = "Por 12 s tus golpes ignoran toda la defensa del enemigo.",
		CostoMana = 30,
		Cooldown = 600,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = { { Tipo = "IgnorarArmadura", Duracion = 12 } },
	},
	{
		Numero = 24,
		Id = "FortificacionPosicion",
		Nombre = "Fortificación de Posición",
		Calidad = "Rara",
		Categoria = 3,
		Descripcion = "Levanta una pared de chatarra por 20 s: corta el paso y las habilidades a distancia que la crucen.",
		CostoMana = 25,
		Cooldown = 600,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "Pared",
	},

	--------------------------------------------------------------------
	-- Categoría IV: Legendarias / Ultis Masivas (1200 s)
	--------------------------------------------------------------------
	{
		Numero = 25,
		Id = "GranBotin",
		Nombre = "El Gran Botín",
		Calidad = "Legendaria",
		Categoria = 4,
		Descripcion = "Por 30 s, cada monstruo que muere a 30 studs tuyos deja un cofre de materiales raros para quienes pelearon.",
		CostoMana = 40,
		Cooldown = 1200,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Radio = 30,
		Efectos = SIN_EFECTOS,
		Especial = "GranBotin",
	},
	{
		Numero = 26,
		Id = "ApagonGeneral",
		Nombre = "Apagón General",
		Calidad = "Legendaria",
		Categoria = 4,
		Descripcion = "Desmantelamiento: a 20 studs, los enemigos quedan 6 s en silencio y con el equipo apagado (-30% ataque, poder y defensa).",
		CostoMana = 50,
		Cooldown = 1200,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "AreaEnemigos",
		Centro = "Propio",
		Radio = 20,
		Efectos = {
			{ Tipo = "Silenciar", Duracion = 6 },
			{ Tipo = "Aura", Stat = "Ataque", Porcentaje = -30, Duracion = 6 },
			{ Tipo = "Aura", Stat = "Poder", Porcentaje = -30, Duracion = 6 },
			{ Tipo = "Aura", Stat = "Defensa", Porcentaje = -30, Duracion = 6 },
		},
	},
	{
		Numero = 27,
		Id = "AvatarTitan",
		Nombre = "Avatar del Titán de Hierro",
		Calidad = "Legendaria",
		Categoria = 4,
		Descripcion = "Por 25 s crecés, recibís la mitad del daño, no te pueden aturdir y tenés +300% de ataque.",
		CostoMana = 50,
		Cooldown = 1200,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = {
			{ Tipo = "Aura", Stat = "Ataque", Porcentaje = 300, Duracion = 25 },
			{ Tipo = "Reduccion", Porcentaje = 50, Duracion = 25 },
		},
		Especial = "Titan",
	},
	{
		Numero = 28,
		Id = "ResurreccionDesfibrilador",
		Nombre = "Resurrección por Desfibrilador",
		Calidad = "Legendaria",
		Categoria = 4,
		Descripcion = "Revive con toda la vida a un aliado que cayó hace menos de 2 minutos a 30 studs tuyos, en el lugar donde cayó.",
		CostoMana = 50,
		Cooldown = 1200,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Radio = 30,
		Efectos = SIN_EFECTOS,
		Especial = "Revivir",
	},
	{
		Numero = 29,
		Id = "ReingenieriaEmergencia",
		Nombre = "Reingeniería de Emergencia",
		Calidad = "Legendaria",
		Categoria = 4,
		Descripcion = "Reinicia las recargas de tu barra II y da +25% de defensa por 20 s a los aliados a 30 studs. (Cuando exista la durabilidad, además va a reparar todo el equipo del grupo.)",
		CostoMana = 40,
		Cooldown = 1200,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "AreaAliados",
		Centro = "Propio",
		Radio = 30,
		Efectos = { { Tipo = "Aura", Stat = "Defensa", Porcentaje = 25, Duracion = 20 } },
		Especial = "Reingenieria",
		Pendiente = "Durabilidad",
	},
	{
		Numero = 30,
		Id = "LegadoReyChatarra",
		Nombre = "El Legado del Rey de la Chatarra",
		Calidad = "Legendaria",
		Categoria = 4,
		Descripcion = "Invoca una torreta-taller por 40 s que dispara cada 2 s a hasta 5 enemigos a 25 studs.",
		CostoMana = 60,
		Cooldown = 1200,
		Rango = 0,
		TiempoCasteo = 0,
		Objetivo = "Propio",
		Efectos = SIN_EFECTOS,
		Especial = "Torreta",
	},
}

-- Barras iniciales: las primeras 4 habilidades de cada categoría.
local function barrasPorDefecto(): { string }
	local lista: { string } = {}
	local cuenta: { [number]: number } = {}
	for _, h in Habilidades do
		local cat = h.Categoria or 1
		if (cuenta[cat] or 0) < 4 then
			cuenta[cat] = (cuenta[cat] or 0) + 1
			table.insert(lista, h.Id)
		end
	end
	return lista
end

return {
	Habilidades = Habilidades,
	BarrasPorDefecto = barrasPorDefecto(),
	RanurasPorBarra = 4,

	Categorias = {
		{ Nombre = "I · Instantes", Recarga = "2-3 s" },
		{ Nombre = "II · Mid Spells", Recarga = "2 min" },
		{ Nombre = "III · Mid Ultis", Recarga = "10 min" },
		{ Nombre = "IV · Ultis Masivas", Recarga = "20 min" },
	},

	Calidades = {
		Comun = { Nombre = "Común", Color = Color3.fromRGB(200, 200, 205) },
		Inusual = { Nombre = "Inusual", Color = Color3.fromRGB(90, 210, 110) },
		Rara = { Nombre = "Rara", Color = Color3.fromRGB(80, 150, 255) },
		Epica = { Nombre = "Épica", Color = Color3.fromRGB(180, 90, 255) },
		Legendaria = { Nombre = "Legendaria", Color = Color3.fromRGB(255, 170, 40) },
	} :: { [string]: { Nombre: string, Color: Color3 } },

	Spoil = {
		Probabilidad = 0.4, -- éxito al morir un monstruo común (con Marca: el doble). Jefes y élites: siempre.
		DuracionRestos = 20, -- segundos que quedan los restos resaltados
		RadioExtraccion = 10, -- Extracción Rápida
		-- Materiales de una extracción (cada entrada se tira por separado).
		Comun = {
			{ ItemId = "Chatarra", Min = 1, Max = 3, Probabilidad = 1 },
			{ ItemId = "Hierro", Min = 1, Max = 1, Probabilidad = 0.25 },
			{ ItemId = "Engranaje", Min = 1, Max = 1, Probabilidad = 0.15 },
		} :: { EntradaSpoil },
		Jefe = {
			{ ItemId = "Chatarra", Min = 4, Max = 8, Probabilidad = 1 },
			{ ItemId = "Engranaje", Min = 1, Max = 3, Probabilidad = 0.7 },
			{ ItemId = "LingotePlata", Min = 1, Max = 2, Probabilidad = 0.4 },
		} :: { EntradaSpoil },
		Raro = { ItemId = "Engranaje", Min = 2, Max = 3, Probabilidad = 1 } :: EntradaSpoil, -- Ojo del Tasador
		Legendario = { ItemId = "NucleoTitan", Min = 1, Max = 1, Probabilidad = 1 } :: EntradaSpoil, -- Extracción Quirúrgica
		-- Cofre de "El Gran Botín".
		Cofre = {
			{ ItemId = "Engranaje", Min = 1, Max = 2, Probabilidad = 1 },
			{ ItemId = "LingotePlata", Min = 1, Max = 1, Probabilidad = 0.35 },
			{ ItemId = "Amatista", Min = 1, Max = 1, Probabilidad = 0.15 },
		} :: { EntradaSpoil },
	},

	-- Metales que cuentan para el Escudo de Chatarra Soldada.
	Metales = { "Chatarra", "Engranaje", "Hierro", "MineralHierro", "MineralPlata", "LingotePlata", "NucleoTitan" },
	Escudo = { Base = 40, PorMetal = 3, MaxMetales = 60, Duracion = 20 },

	Yunque = { Duracion = 60, Distancia = 12 },
	Trampa = {
		Duracion = 60,
		Radio = 4,
		Inmovil = 3,
		Sangrado = { Base = 4, Factor = 0.3, Duracion = 6, Intervalo = 1 },
	},
	Adrenalina = { Duracion = 10, Factor = 1.2 },
	Pared = { Duracion = 20, Tam = Vector3.new(16, 9, 2), Distancia = 6 },
	Titan = { Duracion = 25, Escala = 1.35 },
	Revivir = { Ventana = 120, Radio = 30 },
	GranBotin = { Duracion = 30, Radio = 30 },
	Sobreaceleracion = { Duracion = 60, Probabilidad = 0.5 },
	Contrabandista = { Item = "Chatarra", Factor = 1.5 },
	Torreta = { Duracion = 40, Cada = 2, Radio = 25, Objetivos = 5, Base = 15, Factor = 1 },
	Olfato = { Duracion = 20, Radio = 150 },
	Humo = { Ceguera = 2 },
}
