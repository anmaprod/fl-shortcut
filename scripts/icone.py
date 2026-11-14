#!/usr/bin/env python3
# Icônes de FL Shortcuts.
# - Icône de l'app (Mac et Windows), choisie le 05/11 (marque/icone-app-fl*.svg, session du site : « je te prends la
#   noire… à l'icône de l'app ») : « fl. » en blanc, minuscules grasses serrées, sur une tuile noire, le point final
#   carré en rouge #FF3B1F, calé en bas à gauche. Grille des icônes du Mac : toile de 1024, tuile de 824 centrée,
#   coins arrondis de 185, ombre douce dessous. Lettres : tracés de Nimbus Sans Bold (aucune police). 64 pixels et
#   moins : les lettres plus grandes (icone-app-fl-petit). Windows (.ico) : la tuile seule, qui prend toute la place
#   (ses icônes n'ont pas les marges du Mac).
# - Barre des menus du Mac et zone de notification de Windows : PAS cette icône, le rond A tout en blanc
#   (rond-A-barre-blanc.svg, 05/11 : « on gardera le logo qu'il a déjà mais tout en blanc »), noir sur une barre
#   claire. Le Mac le dessine lui-même (MenuBarIcon.swift) ; ici, Windows (--tray DOSSIER) : TraySombre.ico (blanc,
#   barre sombre) et TrayClaire.ico (noir, barre claire).
# Usage : python3 scripts/icone.py Resources [--ico CHEMIN.ico] [--tray DOSSIER]  (Pillow et numpy ; écrit
# AppIcon-1024.png et AppIcon.icns, morceaux PNG icp4/icp5/ic07…ic14 comme iconutil, absent sous Linux).
import sys, os, re, struct, io
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

args = [a for a in sys.argv[1:] if not a.startswith("--") and sys.argv[sys.argv.index(a) - 1] not in ("--ico", "--tray")]
OUT = args[0] if args else "."
ICO = sys.argv[sys.argv.index("--ico") + 1] if "--ico" in sys.argv else None
TRAY = sys.argv[sys.argv.index("--tray") + 1] if "--tray" in sys.argv else None

RED = (0xFF, 0x3B, 0x1F, 255)
WHITE = (255, 255, 255, 255)

# Lettres de « fl. » (marque/icone-app-fl.svg) : tracé d'origine de la police, puis translate(tx ty) scale(s -s).
F = "M313 529H230V582C230 610 242 624 268 624C281 624 294 623 308 621V726C278 728 249 729 228 729C135 729 90 685 90 594V529H14V436H90V0H230V436H313Z"
L = "M207 729H67V0H207Z"
DOT = "M214 146H64V0H214Z"
LETTERS = {
    False: [(F, WHITE, 210.97, 794.00), (L, WHITE, 380.53, 794.00), (DOT, RED, 515.93, 794.00)],   # 128 et plus
    True: [(F, WHITE, 179.25, 834.00), (L, WHITE, 381.28, 834.00), (DOT, RED, 542.59, 834.00)],    # 64 et moins
}
SCALE = {False: 0.64472, True: 0.76818}
TILE = (100, 100, 924, 924)
RADIUS = 185


def contours(d):
    """Contours d'un tracé SVG en commandes absolues M, L, H, V, C, Z ; les courbes coupées en petits segments."""
    tokens = re.findall(r"[MLHVCZ]|-?\d+(?:\.\d+)?", d)
    out, cur, x, y, i, cmd = [], [], 0.0, 0.0, 0, None
    while i < len(tokens):
        t = tokens[i]
        if t in "MLHVCZ":
            cmd = t
            i += 1
            if cmd == "Z":
                if cur:
                    out.append(cur)
                cur = []
            continue
        if cmd == "M":
            x, y = float(tokens[i]), float(tokens[i + 1]); i += 2
            if cur:
                out.append(cur)
            cur = [(x, y)]
            cmd = "L"
        elif cmd == "L":
            x, y = float(tokens[i]), float(tokens[i + 1]); i += 2
            cur.append((x, y))
        elif cmd == "H":
            x = float(tokens[i]); i += 1
            cur.append((x, y))
        elif cmd == "V":
            y = float(tokens[i]); i += 1
            cur.append((x, y))
        elif cmd == "C":
            x1, y1, x2, y2, x3, y3 = (float(v) for v in tokens[i:i + 6]); i += 6
            x0, y0 = x, y
            for step in range(1, 25):
                u = step / 24
                a, b, c, e = (1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u ** 3
                cur.append((a * x0 + b * x1 + c * x2 + e * x3, a * y0 + b * y1 + c * y2 + e * y3))
            x, y = x3, y3
        else:
            raise ValueError("tracé inattendu : " + d)
    if cur:
        out.append(cur)
    return out


def app_icon(n, small=None):
    """Icône de l'app à n pixels (toile entière, avec ses marges et son ombre) : dessinée plus grande, puis réduite."""
    small = n <= 64 if small is None else small
    big = max(n * 4, 1024) if n <= 512 else n * 2
    k = big / 1024
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    # Ombre douce sous la tuile (feDropShadow : dy 10, écart 12, noir à 35 %).
    shadow = Image.new("L", (big, big), 0)
    x0, y0, x1, y1 = (v * k for v in TILE)
    ImageDraw.Draw(shadow).rounded_rectangle((x0, y0 + 10 * k, x1, y1 + 10 * k), radius=RADIUS * k, fill=255)
    shadow = shadow.filter(ImageFilter.GaussianBlur(12 * k)).point(lambda v: int(v * 0.35))
    canvas.paste((0, 0, 0, 255), (0, 0), shadow)
    tile = Image.new("L", (big, big), 0)
    ImageDraw.Draw(tile).rounded_rectangle((x0, y0, x1, y1), radius=RADIUS * k, fill=255)
    canvas.paste((0, 0, 0, 255), (0, 0), tile)
    draw = ImageDraw.Draw(canvas)
    s = SCALE[small]
    for d, color, tx, ty in LETTERS[small]:
        for contour in contours(d):
            draw.polygon([((tx + s * px) * k, (ty - s * py) * k) for px, py in contour], fill=color)
    return canvas.resize((n, n), Image.LANCZOS)


def tile_icon(n):
    """Windows : la tuile seule, à n pixels (sans les marges ni l'ombre du Mac)."""
    full = round(n * 1024 / 824 * 4)
    big = app_icon(full, small=n <= 64)
    k = full / 1024
    return big.crop((round(100 * k), round(100 * k), round(924 * k), round(924 * k))).resize((n, n), Image.LANCZOS)


def tray(n, color):
    """Rond A tout blanc (ou noir) de la barre (marque/rond-A-barre-blanc.svg) : le cercle, coupé par un jour autour
    du rond, et le rond plein, sans fond."""
    big = n * 8
    k = big / 1024
    yy, xx = np.mgrid[0:big, 0:big].astype(np.float32) + 0.5
    ring = np.clip(35 * k - np.abs(np.hypot(xx - 590 * k, yy - 440 * k) - 365 * k) + 0.5, 0, 1)
    gap = np.clip(345 * k - np.hypot(xx - 470 * k, yy - 580 * k) + 0.5, 0, 1)
    dot = np.clip(290 * k - np.hypot(xx - 470 * k, yy - 580 * k) + 0.5, 0, 1)
    alpha = np.maximum(ring * (1 - gap), dot)
    rgba = np.zeros((big, big, 4), dtype=np.uint8)
    rgba[..., :3] = color[:3]
    rgba[..., 3] = (alpha * 255 + 0.5).astype(np.uint8)
    return Image.fromarray(rgba, mode="RGBA").resize((n, n), Image.LANCZOS)


def png_bytes(im):
    b = io.BytesIO()
    im.save(b, format="PNG", optimize=True)
    return b.getvalue()


os.makedirs(OUT, exist_ok=True)
master = app_icon(1024)
master.save(os.path.join(OUT, "AppIcon-1024.png"), optimize=True)

# ICNS : en-tête « icns » + morceaux PNG (mêmes types que iconutil).
chunks = [("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64), ("ic07", 128), ("ic13", 256),
          ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)]
cache = {}
body = b""
for kind, size in chunks:
    data = cache.setdefault(size, png_bytes(master if size == 1024 else app_icon(size)))
    body += kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data
icns = b"icns" + struct.pack(">I", len(body) + 8) + body
with open(os.path.join(OUT, "AppIcon.icns"), "wb") as f:
    f.write(icns)
print("ok", len(icns))


def write_ico(path, images):
    """.ico fait de PNG (Windows Vista et plus), une image par taille."""
    head = struct.pack("<HHH", 0, 1, len(images))
    entries, blobs, offset = b"", b"", 6 + 16 * len(images)
    for im in images:
        data = png_bytes(im)
        w = im.width if im.width < 256 else 0
        entries += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    with open(path, "wb") as f:
        f.write(head + entries + blobs)


# Icône Windows de l'app (.ico : 16 à 256) : la tuile seule.
if ICO:
    write_ico(ICO, [tile_icon(s) for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
    print("ico", ICO)

# Zone de notification de Windows : le rond A tout blanc (barre sombre) ou noir (barre claire).
if TRAY:
    os.makedirs(TRAY, exist_ok=True)
    for name, color in (("TraySombre.ico", WHITE), ("TrayClaire.ico", (0, 0, 0, 255))):
        write_ico(os.path.join(TRAY, name), [tray(s, color) for s in (16, 20, 24, 32, 40, 48, 64)])
        print("tray", name)
