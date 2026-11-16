#!/usr/bin/env python3
"""Regenera la tabla "Por NPC" de docs/npcs-matriz.md a partir de
NpcArquetiposConfig (entre las marcas MATRIZ:INICIO y MATRIZ:FIN).

    python3 tests/matriz.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run  # noqa: E402

LUAU = r"""
local Npcs = cargar("ReplicatedStorage/Configs/NpcArquetiposConfig")
local lista = {}
for id, a in Npcs.Arquetipos do table.insert(lista, { id = id, a = a }) end
table.sort(lista, function(x, y) return x.a.Numero < y.a.Numero end)
for _, e in lista do
	local a = e.a
	local hoy = {}
	if a.Estado ~= "Pendiente" then
		if a.Vende then table.insert(hoy, "vende " .. #a.Vende .. " ítems") end
		if a.Compra then table.insert(hoy, "compra excedentes") end
		if a.Estacion then table.insert(hoy, "fabrica en " .. a.Estacion) end
		if a.Viajes then table.insert(hoy, "viajes por territorio") end
		for _, s in a.Servicios or {} do
			if s.Accion then table.insert(hoy, s.Nombre) end
		end
		for _, o in a.SobreItem or {} do table.insert(hoy, o.Nombre) end
	end
	local falta = a.Parametros.Requiere
	if type(falta) ~= "string" then
		local f = a.Parametros.Futuro
		falta = if type(f) == "table" then table.concat(f, "; ") else ""
	end
	print(table.concat({ "ROW", a.Numero, e.id, a.Nombre, a.Categoria, table.concat(a.Facciones, ", "),
		a.Estado, table.concat(hoy, ", "), a.Sistema or "", falta }, "|"))
end
"""

GRUPOS = {
    "Alquimia": "A — Alquimia, magia y consumibles",
    "Herreria": "B — Herrería, equipamiento y forja",
    "Economia": "C — Economía, comercio y almacenamiento",
    "Viajes": "D — Viajes, cartografía y logística",
    "Misiones": "E — Misiones, facciones y progresión",
    "Cosmeticos": "F — Cosméticos y personalización",
    "Social": "G — Vida social, vivienda y minijuegos",
    "PvP": "H — PvP, arenas y guerra",
}
ESTADOS = {"Listo": "Implementado sin verificar", "Parcial": "En desarrollo", "Pendiente": "Pendiente"}
INICIO, FIN = "<!-- MATRIZ:INICIO -->", "<!-- MATRIZ:FIN -->"


def main():
    salida = run.ejecutar(run.base() + [LUAU], capturar=True)
    if salida.returncode != 0:
        sys.exit(salida.stderr or salida.stdout)
    filas = [l.split("|")[1:] for l in salida.stdout.splitlines() if l.startswith("ROW|")]
    cuenta = {k: sum(1 for f in filas if f[5] == k) for k in ESTADOS}
    lineas = [
        f"Hoy: **{cuenta['Listo']}** implementados sin verificar, **{cuenta['Parcial']}** en desarrollo "
        f"y **{cuenta['Pendiente']}** pendientes (total {len(filas)}).",
    ]
    grupo = None
    for num, clave, nombre, categoria, facciones, estado, hoy, sistema, falta in filas:
        if categoria != grupo:
            grupo = categoria
            lineas += ["", f"### Grupo {GRUPOS[categoria]}", "",
                       "| ID | NPC (clave) | Versiones | Funciona hoy | Falta | Estado |", "|---|---|---|---|---|---|"]
        if estado == "Parcial":
            hoy = (hoy + "; " if hoy else "") + f"el sistema existe en: {sistema}"
        lineas.append(f"| NPC-{int(num):03d} | {nombre} (`{clave}`) | {facciones} | {hoy or '—'} | {falta or '—'} | {ESTADOS[estado]} |")
    ruta = os.path.join(run.RAIZ, "docs", "npcs-matriz.md")
    with open(ruta, encoding="utf-8") as f:
        texto = f.read()
    a, b = texto.index(INICIO) + len(INICIO), texto.index(FIN)
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(texto[:a] + "\n" + "\n".join(lineas) + "\n" + texto[b:])
    print(f"docs/npcs-matriz.md actualizado: {cuenta}")


if __name__ == "__main__":
    main()
