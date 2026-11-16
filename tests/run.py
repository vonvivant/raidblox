#!/usr/bin/env python3
"""Corre las pruebas de datos fuera de Roblox, con el intérprete `luau`.

Arma un solo archivo con los módulos de configuración (son datos puros) y un
entorno mínimo que imita lo que usan de Roblox (script.Parent, game:GetService,
Color3, Vector3, Enum), y después ejecuta tests/*.spec.luau.

    python3 tests/run.py            # usa `luau` del PATH o ~/tools/luau

Estas pruebas revisan coherencia de datos y lógica pura. No reemplazan las
pruebas dentro de Roblox Studio (red, DataStore, física, interfaz).
"""
import os
import shutil
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(RAIZ, "src")
CARPETAS = ["ReplicatedStorage/Configs", "ReplicatedStorage/Shared"]

PRELUDIO = r"""
local MODULOS = {}
local CACHE = {}

local Nodo = {}
local function nodo(ruta)
	return setmetatable({ __ruta = ruta }, Nodo)
end
Nodo.__index = function(self, clave)
	local ruta = rawget(self, "__ruta")
	if clave == "Parent" then
		return nodo((string.gsub(ruta, "/[^/]+$", "")))
	elseif clave == "Name" then
		return string.match(ruta, "[^/]+$")
	end
	return nodo(ruta .. "/" .. clave)
end

local game = { GetService = function(_, nombre) return nodo(nombre) end }

local function requerir(destino)
	local ruta = rawget(destino, "__ruta")
	if CACHE[ruta] == nil then
		local modulo = MODULOS[ruta]
		assert(modulo, "módulo no incluido en las pruebas: " .. ruta)
		CACHE[ruta] = modulo(nodo(ruta), requerir, game)
	end
	return CACHE[ruta]
end

local Color3 = {
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
	fromHex = function() return { R = 0, G = 0, B = 0 } end,
}
local Vector3 = { new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end }
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
local Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end }
local UDim2 = {
	new = function(...) return { ... } end,
	fromScale = function(...) return { ... } end,
	fromOffset = function(...) return { ... } end,
}
local CFrame = { new = function(...) return { ... } end, Angles = function(...) return { ... } end }
local EnumProxy = {}
EnumProxy.__index = function(self, clave)
	return setmetatable({ __nombre = rawget(self, "__nombre") .. "." .. clave }, EnumProxy)
end
local Enum = setmetatable({ __nombre = "Enum" }, EnumProxy)
local typeof = function(v)
	local t = type(v)
	if t == "table" and getmetatable(v) == Nodo then return "Instance" end
	return t
end
"""

ENVOLTORIO_INICIO = (
    'MODULOS["{ruta}"] = function(script, require, game)\n'
)


def luau():
    for candidato in ("luau", os.path.expanduser("~/tools/luau")):
        camino = shutil.which(candidato) or (candidato if os.path.exists(candidato) else None)
        if camino:
            return camino
    sys.exit("No encontré el intérprete `luau` (https://github.com/luau-lang/luau/releases).")


def base():
    """Preludio + módulos de configuración + la función cargar()."""
    partes = [PRELUDIO]
    for carpeta in CARPETAS:
        base = os.path.join(SRC, carpeta)
        for nombre in sorted(os.listdir(base)):
            if not nombre.endswith(".luau"):
                continue
            ruta = f"{carpeta}/{nombre[:-5]}"
            with open(os.path.join(base, nombre), encoding="utf-8") as f:
                fuente = f.read()
            partes.append(ENVOLTORIO_INICIO.format(ruta=ruta) + fuente + "\nend\n")
    partes.append("local function cargar(ruta) return requerir(nodo(ruta)) end\n")
    return partes


def ejecutar(partes, capturar=False):
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as tmp:
        tmp.write("".join(partes))
    try:
        return subprocess.run([luau(), tmp.name], capture_output=capturar, text=True)
    finally:
        os.unlink(tmp.name)


def main():
    partes = base()
    partes.append(
        "local PRUEBAS, FALLAS = 0, {}\n"
        "local function prueba(nombre, fn)\n"
        "\tPRUEBAS += 1\n"
        "\tlocal ok, err = pcall(fn)\n"
        "\tif not ok then table.insert(FALLAS, nombre .. ': ' .. tostring(err)) end\n"
        "end\n"
        "local function exigir(condicion, mensaje)\n"
        "\tif not condicion then error(mensaje, 2) end\n"
        "end\n"
    )
    carpeta_pruebas = os.path.join(RAIZ, "tests")
    for nombre in sorted(os.listdir(carpeta_pruebas)):
        if nombre.endswith(".spec.luau"):
            with open(os.path.join(carpeta_pruebas, nombre), encoding="utf-8") as f:
                partes.append(f"do -- {nombre}\n{f.read()}\nend\n")
    partes.append(
        "for _, falla in FALLAS do print('FALLA  ' .. falla) end\n"
        "print(string.format('%d pruebas, %d fallas', PRUEBAS, #FALLAS))\n"
        "if #FALLAS > 0 then error('hay pruebas que fallan') end\n"
    )
    resultado = ejecutar(partes)
    sys.exit(resultado.returncode)


if __name__ == "__main__":
    main()
