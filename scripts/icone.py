#!/usr/bin/env python3
# Icône FL Shortcuts au style suisse (choisie par le propriétaire le 02/11 : « le petit clavier, c'est très bien pour
# l'icône ») : une tuile blanche en forme de « squircle » d'Apple, un clavier noir dessiné à traits pleins (cadre,
# quatre touches, barre d'espace), sans reflet ni dégradé. Rendu 2x puis réduit (anticrénelage).
# Usage : python3 scripts/icone.py Resources   (Pillow et numpy ; écrit AppIcon-1024.png et AppIcon.icns,
# morceaux PNG icp4/icp5/ic07…ic14 comme iconutil, absent sous Linux) ; avec --ico CHEMIN : aussi l'icône Windows.
import sys, os, struct, io
import numpy as np
from PIL import Image, ImageFilter

args = [a for a in sys.argv[1:] if not a.startswith("--")]
OUT = args[0] if args else "."
ICO = sys.argv[sys.argv.index("--ico") + 1] if "--ico" in sys.argv else None
SS = 2                      # suréchantillonnage
N = 1024 * SS               # toile de travail
U = SS                      # 1 unité de la grille 1024 = U pixels

yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) + 0.5


def superellipse_alpha(cx, cy, w, h, n=5.0):
    """Masque anticrénelé d'une super-ellipse (forme « squircle » d'Apple), unités 1024."""
    a, b = w * U / 2, h * U / 2
    px = np.abs(xx - cx * U) / a
    py = np.abs(yy - cy * U) / b
    f = (px ** n + py ** n) ** (1.0 / n)
    gy, gx = np.gradient(f)
    g = np.sqrt(gx * gx + gy * gy) + 1e-6
    d = (f - 1.0) / g
    return np.clip(0.5 - d, 0.0, 1.0)


def rect(x, y, w, h):
    """Rectangle plein anticrénelé (unités 1024)."""
    ax = np.clip(np.minimum(xx - x * U, (x + w) * U - xx) + 0.5, 0, 1)
    ay = np.clip(np.minimum(yy - y * U, (y + h) * U - yy) + 0.5, 0, 1)
    return ax * ay


# Tuile : la grille des icônes de macOS (824 sur 1024, centrée).
tile = superellipse_alpha(512, 512, 824, 824)

# Le clavier, d'après le dessin de la barre des menus (15 × 11 unités : cadre de 1,2, touches de 1,6, espace de 7).
k = 36.0                    # 1 unité du dessin = 36 points de l'icône (clavier de 540 de large)
ox, oy = 512 - 7.5 * k, 512 - 5.5 * k
frame = np.clip(rect(ox + 0.6 * k - 0.6 * k, oy, 13.8 * k + 1.2 * k, 11 * k)
                - rect(ox + 1.2 * k, oy + 1.2 * k, 12.6 * k, 8.6 * k), 0, 1)
keys = sum(rect(ox + x * k, oy + 2.6 * k, 1.6 * k, 1.6 * k) for x in (2.5, 5.2, 7.9, 10.6))
space = rect(ox + 4.0 * k, oy + 6.6 * k, 7.0 * k, 1.6 * k)
glyph = np.clip(frame + keys + space, 0, 1) * tile

white = np.ones((N, N, 3), dtype=np.float32)
rgb = white * (1 - glyph[..., None])          # noir là où est le clavier
A = tile

# --- Export --------------------------------------------------------------------------------------------
out = np.dstack([np.clip(rgb, 0, 1), np.clip(A, 0, 1)])
img = Image.fromarray((out * 255 + 0.5).astype(np.uint8), mode="RGBA").resize((1024, 1024), Image.LANCZOS)
os.makedirs(OUT, exist_ok=True)
img.save(os.path.join(OUT, "AppIcon-1024.png"), optimize=True)


def png_bytes(size):
    im = img.resize((size, size), Image.LANCZOS)
    if size <= 64:
        im = im.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=0))
    b = io.BytesIO()
    im.save(b, format="PNG", optimize=True)
    return b.getvalue()


# ICNS : en-tête « icns » + morceaux PNG (mêmes types que iconutil).
chunks = [("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64), ("ic07", 128), ("ic13", 256),
          ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)]
cache = {}
body_bytes = b""
for kind, size in chunks:
    data = cache.setdefault(size, png_bytes(size))
    body_bytes += kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data
icns = b"icns" + struct.pack(">I", len(body_bytes) + 8) + body_bytes
with open(os.path.join(OUT, "AppIcon.icns"), "wb") as f:
    f.write(icns)
print("ok", len(icns))

# Icône Windows (.ico : 16 à 256), la même tuile.
if ICO:
    img.save(ICO, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("ico", ICO)
