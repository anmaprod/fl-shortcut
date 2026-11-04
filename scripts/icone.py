#!/usr/bin/env python3
# Icônes de FL Shortcuts : le logo « A » choisi par le propriétaire le 04/11 (marque/ de la session du site : « le A
# c'est parfait… le logo du rond dans l'icône et le logo du logiciel », « dans les couleurs… pas en noir et blanc ») :
# un rond rouge plein (#FF3B1F) devant un grand cercle fin, formes seules, sans lettre. Il remplace le petit clavier
# du 02/11. Recadré le 04/11 (« pour que le rond blanc soit au centre ») : le cercle au centre, le rond en bas à gauche.
# - Icône de l'app (Mac et Windows) : tuile noire « squircle » (grille des icônes de macOS, 824 sur 1024), cercle blanc,
#   rond rouge ; 64 pixels et moins : le cercle plus épais (rond-A-petit), sinon il disparaît.
# - Zone de notification de Windows (--tray DOSSIER) : sans fond, cercle épais blanc pour une barre sombre
#   (TraySombre.ico), noir pour une barre claire (TrayClaire.ico) ; le rond toujours rouge (rond-A-barre-*).
# Usage : python3 scripts/icone.py Resources [--ico CHEMIN.ico] [--tray DOSSIER]  (Pillow et numpy ; écrit
# AppIcon-1024.png et AppIcon.icns, morceaux PNG icp4/icp5/ic07…ic14 comme iconutil, absent sous Linux).
import sys, os, struct, io
import numpy as np
from PIL import Image

args = [a for a in sys.argv[1:] if not a.startswith("--") and sys.argv[sys.argv.index(a) - 1] not in ("--ico", "--tray")]
OUT = args[0] if args else "."
ICO = sys.argv[sys.argv.index("--ico") + 1] if "--ico" in sys.argv else None
TRAY = sys.argv[sys.argv.index("--tray") + 1] if "--tray" in sys.argv else None

RED = np.array([0xFF, 0x3B, 0x1F], dtype=np.float32) / 255
WHITE = np.ones(3, dtype=np.float32)
BLACK = np.zeros(3, dtype=np.float32)


def grid(n):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
    return xx, yy


def superellipse(n, cx, cy, w, h, power=5.0):
    """Masque anticrénelé d'une super-ellipse (forme « squircle » d'Apple), en pixels."""
    xx, yy = grid(n)
    px, py = np.abs(xx - cx) / (w / 2), np.abs(yy - cy) / (h / 2)
    f = (px ** power + py ** power) ** (1.0 / power)
    gy, gx = np.gradient(f)
    d = (f - 1.0) / (np.sqrt(gx * gx + gy * gy) + 1e-6)
    return np.clip(0.5 - d, 0.0, 1.0)


def disc(n, cx, cy, r):
    xx, yy = grid(n)
    return np.clip(r - np.hypot(xx - cx, yy - cy) + 0.5, 0.0, 1.0)


def ring(n, cx, cy, r, width):
    xx, yy = grid(n)
    return np.clip(width / 2 - np.abs(np.hypot(xx - cx, yy - cy) - r) + 0.5, 0.0, 1.0)


def over(rgb, a, color, mask):
    """Peint `color` (opaque) là où est `mask`, par-dessus (rgb, a)."""
    m = mask[..., None]
    return rgb * (1 - m) + color * m, a + mask * (1 - a)


def logo(n, circle, dot=(392, 652, 290), tile=True, ring_color=WHITE):
    """Le logo dans une image de n pixels. Coordonnées du dessin sur 1024 ; avec la tuile, ramenées dans la grille
    des icônes (824 sur 1024, centrée)."""
    k, o = (824 / 1024, 100) if tile else (1.0, 0)
    s = n / 1024

    def p(v):
        return (o + v * k) * s

    rgb = np.zeros((n, n, 3), dtype=np.float32)
    a = np.zeros((n, n), dtype=np.float32)
    if tile:
        a = superellipse(n, 512 * s, 512 * s, 824 * s, 824 * s)
        rgb[:] = BLACK
    cx, cy, r, w = circle
    rgb, a = over(rgb, a, ring_color, ring(n, p(cx), p(cy), r * k * s, max(w * k * s, 1.0)))
    rgb, a = over(rgb, a, RED, disc(n, p(dot[0]), p(dot[1]), dot[2] * k * s))
    if tile:                                   # rien ne dépasse de la tuile
        tile_mask = superellipse(n, 512 * s, 512 * s, 824 * s, 824 * s)
        a = np.minimum(a, tile_mask)
    return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)]) * 255 + 0.5).astype(np.uint8), mode="RGBA")


FINE = (512, 512, 394, 12)                     # rond-A-noir : cercle fin
THICK = (512, 512, 380, 40)                    # rond-A-petit : 16 à 64 pixels
BAR = (512, 512, 370, 60)                      # rond-A-barre-* : barre des menus, zone de notification


def icon(size):
    """Icône de l'app à `size` pixels : dessinée 4 fois plus grande puis réduite (anticrénelage)."""
    big = logo(size * 4 if size <= 256 else 2048, THICK if size <= 64 else FINE)
    return big.resize((size, size), Image.LANCZOS)


def png_bytes(im):
    b = io.BytesIO()
    im.save(b, format="PNG", optimize=True)
    return b.getvalue()


os.makedirs(OUT, exist_ok=True)
master = icon(1024)
master.save(os.path.join(OUT, "AppIcon-1024.png"), optimize=True)

# ICNS : en-tête « icns » + morceaux PNG (mêmes types que iconutil).
chunks = [("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64), ("ic07", 128), ("ic13", 256),
          ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)]
cache = {}
body = b""
for kind, size in chunks:
    data = cache.setdefault(size, png_bytes(master if size == 1024 else icon(size)))
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


# Icône Windows de l'app (.ico : 16 à 256), la même tuile.
if ICO:
    write_ico(ICO, [icon(s) for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
    print("ico", ICO)

# Zone de notification de Windows : sans fond, cercle épais blanc (barre sombre) ou noir (barre claire).
if TRAY:
    os.makedirs(TRAY, exist_ok=True)
    for name, color in (("TraySombre.ico", WHITE), ("TrayClaire.ico", BLACK)):
        sizes = (16, 20, 24, 32, 40, 48, 64)
        write_ico(os.path.join(TRAY, name),
                  [logo(s * 4, BAR, tile=False, ring_color=color).resize((s, s), Image.LANCZOS) for s in sizes])
        print("tray", name)
