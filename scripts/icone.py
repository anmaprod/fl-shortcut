#!/usr/bin/env python3
# Icône FL Shortcuts façon macOS 26 (Liquid Glass) : fond en dégradé doux, deux touches de clavier en verre
# superposées (⌃ derrière, ♫ devant), reflets spéculaires. Rendu 2x puis réduit (anticrénelage).
# Usage : python3 scripts/icone.py Resources   (Pillow et numpy ; écrit AppIcon-1024.png et AppIcon.icns,
# morceaux PNG icp4/icp5/ic07…ic14 comme iconutil, absent sous Linux)
import sys, os, struct, io
import numpy as np
from PIL import Image, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SS = 2                      # suréchantillonnage
N = 1024 * SS               # toile de travail
U = SS                      # 1 unité de la grille 1024 = U pixels

yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) + 0.5


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def superellipse_alpha(cx, cy, w, h, n=5.0, x=None, y=None):
    """Masque anticrénelé d'une super-ellipse (forme « squircle » d'Apple), unités 1024."""
    x = xx if x is None else x
    y = yy if y is None else y
    a, b = w * U / 2, h * U / 2
    px = np.abs(x - cx * U) / a
    py = np.abs(y - cy * U) / b
    f = (px ** n + py ** n) ** (1.0 / n)
    gy, gx = np.gradient(f)
    g = np.sqrt(gx * gx + gy * gy) + 1e-6
    d = (f - 1.0) / g                      # distance approchée au bord, en pixels
    return np.clip(0.5 - d, 0.0, 1.0)


def blur(alpha, radius):
    im8 = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), mode="L")
    im8 = im8.filter(ImageFilter.GaussianBlur(radius * U))
    return np.asarray(im8).astype(np.float32) / 255.0


def blur_rgb(rgb, radius):
    im = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), mode="RGB")
    im = im.filter(ImageFilter.GaussianBlur(radius * U))
    return np.asarray(im).astype(np.float32) / 255.0


def shift(alpha, dx, dy):
    out = np.zeros_like(alpha)
    dx, dy = int(round(dx * U)), int(round(dy * U))
    src = alpha[max(0, -dy):N - max(0, dy), max(0, -dx):N - max(0, dx)]
    out[max(0, dy):max(0, dy) + src.shape[0], max(0, dx):max(0, dx) + src.shape[1]] = src
    return out


def over(dst_rgb, dst_a, src_rgb, src_a):
    """Composition « over » (couleurs non prémultipliées en entrée)."""
    sa = src_a[..., None]
    da = dst_a[..., None]
    out_a = sa + da * (1 - sa)
    out_rgb = (src_rgb * sa + dst_rgb * da * (1 - sa)) / np.maximum(out_a, 1e-6)
    return out_rgb, out_a[..., 0]


def gradient3(c0, c1, c2, t):
    t = np.clip(t, 0, 1)[..., None]
    lo = c0 + (c1 - c0) * np.clip(t * 2, 0, 1)
    hi = c1 + (c2 - c1) * np.clip(t * 2 - 1, 0, 1)
    return np.where(t < 0.5, lo, hi)


# --- Toile -------------------------------------------------------------------------------------------
rgb = np.zeros((N, N, 3), np.float32)
A = np.zeros((N, N), np.float32)

# Corps : grille macOS (824 px centrés sur 1024), ombre portée douce.
BODY = (512, 512, 824, 824)
body = superellipse_alpha(*BODY, n=5.0)

shadow = blur(shift(body, 0, 14), 22) * 0.34 + blur(shift(body, 0, 3), 4) * 0.16
rgb, A = over(rgb, A, np.zeros_like(rgb), np.clip(shadow, 0, 1))

# Fond : dégradé doux orange → rose → violet (diagonale), lumière en haut à gauche.
t = ((xx - 100 * U) * 0.45 + (yy - 100 * U) * 0.9) / (824 * U * 1.35)
bg = gradient3(hexrgb("#FFA25C"), hexrgb("#F2577E"), hexrgb("#7B5CF5"), t)
glow = np.exp(-(((xx - 300 * U) / (360 * U)) ** 2 + ((yy - 220 * U) / (300 * U)) ** 2))[..., None]
bg = bg + (1 - bg) * glow * 0.30
deep = np.exp(-(((xx - 820 * U) / (420 * U)) ** 2 + ((yy - 900 * U) / (300 * U)) ** 2))[..., None]
bg = bg * (1 - deep * 0.18)
rgb, A = over(rgb, A, bg, body)
base = rgb.copy()                         # ce que les verres « voient » derrière eux


def glass_key(rgb, A, cx, cy, size, milk, face_milk, tilt_shadow=1.0):
    """Touche de clavier en verre : jupe (forme extérieure) + plateau (forme intérieure décalée vers le haut)."""
    outer = superellipse_alpha(cx, cy, size, size, n=4.2) * body
    inset = size * 0.085
    face = superellipse_alpha(cx, cy - size * 0.035, size - 2 * inset, size - 2 * inset - size * 0.04, n=4.2) * body

    # Ombre portée de la touche sur ce qui est dessous (teinte violette profonde).
    sh = blur(shift(outer, 0, size * 0.06), size * 0.07) * 0.30 * tilt_shadow
    rgb, A = over(rgb, A, np.broadcast_to(hexrgb("#2B0E57"), rgb.shape), sh * body)

    # Verre dépoli : ce qui est derrière, flouté, éclairci.
    behind = blur_rgb(rgb, size * 0.09)
    skirt = behind + (1 - behind) * milk
    vy = np.clip((yy - (cy - size / 2) * U) / (size * U), 0, 1)[..., None]
    skirt = skirt * (1 - 0.07 * vy)                                   # jupe plus sombre vers le bas
    rgb, A = over(rgb, A, skirt, outer)

    top = blur_rgb(rgb, size * 0.05)
    plate = top + (1 - top) * face_milk
    fy = np.clip((yy - (cy - size / 2) * U) / (size * U), 0, 1)[..., None]
    plate = plate * (1 - 0.06 * fy) + 0.05 * (1 - fy)                 # plateau un peu plus clair en haut
    rgb, A = over(rgb, A, np.clip(plate, 0, 1), face)

    # Reflets : liseré lumineux en haut à gauche (jupe et plateau), liseré sombre discret en bas.
    def rim(mask, width, strength):
        inner = blur(mask, width) if width > 0 else mask
        edge = np.clip(mask - np.clip((inner - 0.5) * 2, 0, 1), 0, 1)
        lx = (xx - (cx - size / 2) * U) / (size * U)
        ly = (yy - (cy - size / 2) * U) / (size * U)
        light = np.clip(1.15 - (lx * 0.55 + ly * 1.0), 0, 1)
        return edge * light * strength, edge * np.clip(ly - 0.55, 0, 1) * 0.9
    hi, lo = rim(outer, 2.2, 0.95)
    rgb, A = over(rgb, A, np.ones_like(rgb), hi * 0.9)
    rgb, A = over(rgb, A, np.broadcast_to(hexrgb("#3A1670"), rgb.shape), lo * 0.25)
    hi2, _ = rim(face, 1.6, 0.8)
    rgb, A = over(rgb, A, np.ones_like(rgb), hi2 * 0.75)
    return rgb, A, face


# Touche du fond (⌃), en haut à droite : verre clair.
rgb, A, back_face = glass_key(rgb, A, 640, 372, 318, milk=0.34, face_milk=0.46, tilt_shadow=0.7)


def stroke_polyline(points, width, x=None, y=None):
    """Trait épais à bouts ronds (masque anticrénelé), points en unités 1024."""
    m = np.zeros((N, N), np.float32)
    r = width * U / 2
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        x0, y0, x1, y1 = x0 * U, y0 * U, x1 * U, y1 * U
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy
        tt = np.clip(((xx - x0) * dx + (yy - y0) * dy) / L2, 0, 1)
        d = np.sqrt((xx - x0 - tt * dx) ** 2 + (yy - y0 - tt * dy) ** 2) - r
        m = np.maximum(m, np.clip(0.5 - d, 0, 1))
    return m


# Glyphe ⌃ (contrôle) sur la touche du fond.
chev = stroke_polyline([(588, 390), (640, 336), (692, 390)], 30)
rgb, A = over(rgb, A, np.ones_like(rgb), chev * 0.92)

# Touche du devant (♫), en bas à gauche : verre dépoli plus laiteux.
rgb, A, front_face = glass_key(rgb, A, 420, 610, 384, milk=0.62, face_milk=0.80)


def ellipse_rot(cx, cy, rx, ry, angle_deg):
    a = np.deg2rad(angle_deg)
    X = (xx - cx * U) * np.cos(a) + (yy - cy * U) * np.sin(a)
    Y = -(xx - cx * U) * np.sin(a) + (yy - cy * U) * np.cos(a)
    f = np.sqrt((X / (rx * U)) ** 2 + (Y / (ry * U)) ** 2)
    gy, gx = np.gradient(f)
    g = np.sqrt(gx * gx + gy * gy) + 1e-6
    return np.clip(0.5 - (f - 1) / g, 0, 1)


def polygon(points):
    """Polygone convexe anticrénelé (demi-plans)."""
    m = np.ones((N, N), np.float32)
    pts = [(px * U, py * U) for px, py in points]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
        nx, ny = y1 - y0, -(x1 - x0)
        L = np.hypot(nx, ny)
        d = ((xx - x0) * nx + (yy - y0) * ny) / L
        m = np.minimum(m, np.clip(0.5 - d, 0, 1))
    return m


# Glyphe : forme d'onde (barres arrondies centrées), teintée comme le fond (verre coloré).
gx0, gy0 = 420, 596
heights = [92, 176, 236, 150, 74]
bars = [stroke_polyline([(gx0 + (i - 2) * 58, gy0 - h / 2), (gx0 + (i - 2) * 58, gy0 + h / 2)], 36)
        for i, h in enumerate(heights)]
note = np.clip(np.maximum.reduce(bars), 0, 1) * front_face
tn = ((xx - 290 * U) * 0.55 + (yy - 470 * U)) / (300 * U)
note_rgb = gradient3(hexrgb("#FF8A3D"), hexrgb("#E8456F"), hexrgb("#6A47E8"), tn)
# Ombre intérieure légère sous la note (gravée dans le verre).
note_sh = blur(shift(note, 0, 3), 3) * 0.25 * front_face
rgb, A = over(rgb, A, np.broadcast_to(hexrgb("#4A1E7A"), rgb.shape), note_sh)
rgb, A = over(rgb, A, note_rgb, note * 0.96)

# Reflet du corps : liseré clair en haut, discret en bas ; voile spéculaire en haut à gauche.
inner = blur(body, 3)
edge = np.clip(body - np.clip((inner - 0.5) * 2, 0, 1), 0, 1)
ly = (yy - 100 * U) / (824 * U)
lx = (xx - 100 * U) / (824 * U)
rgb, A = over(rgb, A, np.ones_like(rgb), edge * np.clip(1.0 - ly * 1.3 - lx * 0.25, 0, 1) * 0.85)
rgb, A = over(rgb, A, np.broadcast_to(hexrgb("#2A0B4D"), rgb.shape), edge * np.clip(ly - 0.6, 0, 1) * 0.5)
sheen = ellipse_rot(380, 250, 420, 210, -18) * body
sheen = blur(sheen, 30) * np.clip(1 - ly * 2.2, 0, 1)
rgb, A = over(rgb, A, np.ones_like(rgb), sheen * 0.10)

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
