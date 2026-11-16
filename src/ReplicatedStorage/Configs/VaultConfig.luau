--!strict
-- VaultConfig: bóveda global del jugador (banco personal). Se abre hablando con
-- un Banquero, en un banco de ciudad o en el cofre de bóveda de una parcela.

return {
	MaxPestanas = 8,
	RanurasPorPestana = 30,
	Columnas = 6, -- la ventana dibuja 6 × 5
	PestanasIniciales = 1,

	-- Oro que cuesta comprar la próxima pestaña, según cuántas compradas
	-- (o iniciales) tiene: la 2ª cuesta 1.000, la 3ª 2.500, y así.
	CostoPestana = { 1000, 2500, 6000, 15000, 35000, 80000, 150000 },

	-- Pase que regala pestañas (además de las compradas, sin pasar el máximo).
	Pase = "VIP",
	PestanasConPase = 1,

	-- Distancia máxima (studs) a un punto de bóveda para poder operar.
	Distancia = 16,
	-- Tags de CollectionService de los puntos de bóveda (BasePart):
	--   BancoVault: banco de ciudad o Banquero.   CofreVault: cofre de una parcela.
	Tags = { "BancoVault", "CofreVault" },

	LargoNombre = 16,
	Iconos = { "📦", "⚔", "🛡", "💎", "🧪", "⛏", "🌿", "🧵", "⭐", "💰", "🔑", "🎁" },

	-- Clave de los metadatos del ítem con la firma de autoría; el buscador
	-- también busca por ese texto.
	MetaAutor = "Autor",
}
