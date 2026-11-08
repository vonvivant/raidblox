from PIL import Image, ImageDraw
import math

N = 64
img = Image.new("RGB", (N, N), "#0e0a1f")
d = ImageDraw.Draw(img)
P = img.load()

def px(x, y, c):
    if 0 <= x < N and 0 <= y < N:
        P[x, y] = Image.new("RGB", (1, 1), c).getpixel((0, 0)) if isinstance(c, str) else c

# ---------- Fondo: halo en bandas con tramado ----------
bandas = [(31, "#140f2b"), (26, "#1a1436"), (21, "#211943"), (16, "#291f52"), (11, "#32275f")]
cx, cy = 32, 29
for r, col in bandas:
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
# tramado en los bordes de cada banda
prev = "#0e0a1f"
for r, col in bandas:
    for a in range(0, 360, 3):
        x = int(round(cx + r * math.cos(math.radians(a))))
        y = int(round(cy + r * math.sin(math.radians(a))))
        if (x + y) % 2 == 0:
            px(x, y, prev)
    prev = col
# estrellitas
for (x, y) in [(5, 4), (58, 5), (4, 44), (60, 40), (12, 2), (51, 61), (3, 22), (61, 23)]:
    px(x, y, "#8f7fd6")

def linea(p0, p1, w, col):
    d.line([p0, p1], fill=col, width=w)

# ---------- Espada (abajo-derecha a arriba-izquierda) ----------
linea((9, 7), (41, 39), 5, "#1f2430")      # contorno
linea((9, 7), (41, 39), 3, "#aab4c3")      # hoja
linea((10, 8), (40, 38), 1, "#eef3f9")     # filo brillante
px(8, 6, "#eef3f9"); px(9, 6, "#1f2430"); px(8, 7, "#1f2430")
# guarda
linea((36, 45), (46, 35), 5, "#3d2606")
linea((36, 45), (46, 35), 3, "#e6a93a")
px(41, 40, "#ffe9a3"); px(39, 42, "#ffe9a3")
# empuñadura
linea((43, 43), (49, 49), 4, "#2e1a0c")
linea((43, 43), (49, 49), 2, "#7a4a24")
# pomo
d.ellipse([48, 48, 54, 54], fill="#3d2606")
d.ellipse([49, 49, 53, 53], fill="#e6a93a")
px(50, 50, "#ffe9a3")

# ---------- Báculo de mago (abajo-izquierda a arriba-derecha) ----------
linea((11, 54), (48, 17), 5, "#2a160a")
linea((11, 54), (48, 17), 3, "#8b5a2b")
linea((12, 53), (47, 18), 1, "#b07a43")
# regatón dorado
d.ellipse([8, 52, 13, 57], fill="#3d2606"); d.ellipse([9, 53, 12, 56], fill="#e6a93a")
# garras doradas que sostienen el cristal
for (a, b) in [((47, 18), (49, 11)), ((47, 18), (56, 16)), ((48, 17), (52, 13))]:
    linea(a, b, 3, "#3d2606")
for (a, b) in [((47, 18), (49, 12)), ((47, 18), (55, 16))]:
    linea(a, b, 1, "#e6a93a")
# cristal
d.ellipse([49, 5, 59, 15], fill="#1b0f3d")
d.ellipse([50, 6, 58, 14], fill="#7b3fe4")
d.ellipse([51, 7, 57, 13], fill="#a970ff")
d.ellipse([52, 8, 55, 11], fill="#d9c2ff")
px(53, 8, "#ffffff")
# destellos mágicos
for (x, y) in [(60, 6), (47, 4), (61, 12), (58, 3)]:
    px(x, y, "#d9c2ff")

# ---------- Escudo ----------
def escudo(inset):
    i = inset
    return [(17 + i, 12 + i), (32, 8 + i), (47 - i, 12 + i), (46 - i, 33), (42 - i, 42 - i // 2),
            (32, 51 - i), (22 + i, 42 - i // 2), (18 + i, 33)]
d.polygon(escudo(0), fill="#3d2606")
d.polygon(escudo(1), fill="#e6a93a")
d.polygon(escudo(3), fill="#3d2606")
d.polygon(escudo(4), fill="#2a62c4")
# brillo diagonal en el campo
for k in range(0, 9):
    px(22 + k, 15 + k // 2, "#3f7fe0")
# franja de luz en el borde dorado (arriba-izquierda)
for (x, y) in [(18, 13), (19, 13), (20, 12), (22, 11), (24, 11), (26, 10), (28, 9), (30, 9)]:
    px(x, y, "#ffe9a3")

# ---------- Arco con flechas en el escudo ----------
# arco (curva a la izquierda), continuo y grueso
d.arc([22, 17, 38, 41], 90, 270, fill="#2e1a0c", width=4)
d.arc([23, 18, 37, 40], 90, 270, fill="#a0662f", width=2)
d.arc([24, 19, 36, 39], 120, 200, fill="#c98a4a", width=1)
for (x, y) in [(29, 17), (30, 17), (29, 41), (30, 41)]:
    px(x, y, "#e6a93a")
# cuerda
for y in range(19, 40):
    px(30, y, "#e8e1cf")
# tres flechas en abanico desde la cuerda
def flecha(x0, y0, x1, y1):
    pasos = max(abs(x1 - x0), abs(y1 - y0))
    for s in range(pasos + 1):
        x = round(x0 + (x1 - x0) * s / pasos)
        y = round(y0 + (y1 - y0) * s / pasos)
        px(x, y, "#e0b06a")
        px(x, y + 1, "#8a5a24")
    # punta
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy); ux, uy = dx / L, dy / L
    for t in range(0, 3):
        bx, by = x1 + ux * t, y1 + uy * t
        px(round(bx), round(by), "#eef3f9")
    px(round(x1 - uy), round(y1 + ux), "#aab4c3")
    px(round(x1 + uy), round(y1 - ux), "#aab4c3")
    # plumas
    px(round(x0 - uy), round(y0 + ux), "#e23b4a")
    px(round(x0 + uy), round(y0 - ux), "#e23b4a")
    px(round(x0 + ux - uy), round(y0 + uy + ux), "#e23b4a")
    px(round(x0 + ux + uy), round(y0 + uy - ux), "#e23b4a")
flecha(29, 29, 39, 29)
flecha(29, 29, 38, 23)
flecha(29, 29, 38, 35)

# ---------- Gemas ----------
def gema(cx, cy, oscuro, medio, claro):
    for (x, y) in [(0, -2), (-1, -1), (0, -1), (1, -1), (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)]:
        px(cx + x, cy + y, medio)
    for (x, y) in [(0, -3), (-1, -2), (1, -2), (-2, -1), (2, -1), (-3, 0), (3, 0), (-2, 1), (2, 1), (-1, 2), (1, 2), (0, 3)]:
        px(cx + x, cy + y, oscuro)
    px(cx - 1, cy - 1, claro); px(cx, cy - 1, claro)
gema(32, 13, "#4a060c", "#e0262f", "#ffb3b3")    # rubí arriba
gema(32, 46, "#04331a", "#21b35a", "#a8f5c4")    # esmeralda abajo
gema(19, 25, "#1b0f3d", "#8a4fe8", "#dcc8ff")    # amatista izquierda
gema(45, 25, "#062a3d", "#1fa3d6", "#b8ecff")    # zafiro derecha

# ---------- Corona ----------
corona = "#3d2606"
d.rectangle([24, 4, 40, 8], fill=corona)
d.rectangle([25, 5, 39, 7], fill="#e6a93a")
for (x, h) in [(25, 0), (32, -2), (39, 0)]:
    d.polygon([(x - 2, 5), (x, 1 + h), (x + 2, 5)], fill=corona)
    d.polygon([(x - 1, 5), (x, 2 + h), (x + 1, 5)], fill="#e6a93a")
for x in (28, 36):
    d.polygon([(x - 1, 5), (x, 3), (x + 1, 5)], fill="#e6a93a")
px(25, 1, "#e0262f"); px(32, -1 + 1, "#21b35a"); px(39, 1, "#1fa3d6")
for x in range(26, 39, 2):
    px(x, 6, "#ffe9a3")
px(30, 6, "#e0262f"); px(34, 6, "#1fa3d6")

# ---------- Medallas colgando a los costados ----------
def medalla(cx, top, cinta1, cinta2, disco, brillo):
    for y in range(top, top + 6):
        px(cx - 1, y, cinta1); px(cx, y, cinta2); px(cx + 1, y, cinta1)
    px(cx - 2, top, "#2a0a0a"); px(cx + 2, top, "#2a0a0a")
    d.ellipse([cx - 3, top + 5, cx + 3, top + 11], fill="#3d2606")
    d.ellipse([cx - 2, top + 6, cx + 2, top + 10], fill=disco)
    px(cx, top + 7, brillo); px(cx - 1, top + 8, brillo); px(cx, top + 8, brillo); px(cx + 1, top + 8, brillo); px(cx, top + 9, brillo)
medalla(9, 23, "#c8202f", "#f2f2f2", "#e6a93a", "#fff2b8")
medalla(55, 23, "#2a62c4", "#f2f2f2", "#c9d2de", "#ffffff")

# ---------- Cinta con el nombre ----------
d.polygon([(2, 50), (62, 50), (59, 55), (62, 60), (2, 60), (5, 55)], fill="#3a060c")
d.polygon([(4, 51), (60, 51), (58, 55), (60, 59), (4, 59), (6, 55)], fill="#c8202f")
for x in range(6, 59):
    px(x, 51, "#e2414e")
for x in range(6, 59):
    px(x, 59, "#7a0f19")

FUENTE = {
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
}
texto = "RAIDBLOX"
x0 = (N - (len(texto) * 6 - 1)) // 2
for i, ch in enumerate(texto):
    for fy, fila in enumerate(FUENTE[ch]):
        for fx, b in enumerate(fila):
            if b == "1":
                px(x0 + i * 6 + fx + 1, 52 + fy + 1, "#3a060c")  # sombra
    for fy, fila in enumerate(FUENTE[ch]):
        for fx, b in enumerate(fila):
            if b == "1":
                px(x0 + i * 6 + fx, 52 + fy, "#ffe9a3")

img.save("/home/claude/icono/pixel-64.png")
img.resize((512, 512), Image.NEAREST).save("/home/claude/icono/raidblox-icono-pixel-512.png")
print("ok")
