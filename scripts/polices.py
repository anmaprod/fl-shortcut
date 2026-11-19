#!/usr/bin/env python3
"""Polices de la direction A (17/11, « J'aime bien le A ») : Inter (texte) et Inter Display (titres serrés), de Rasmus
Andersson, licence libre SIL Open Font License 1.1 (gratuite, peut être intégrée à une app).

    python3 scripts/polices.py Inter-4.1.zip

L'archive vient de https://github.com/rsms/inter/releases (Inter-4.1.zip). Le script garde six graisses, les allège
aux caractères dont l'app se sert (latin, ponctuation, flèches, ⌘ ⌥ ⇧ ⌃ ⌫, formes), les réunit dans une seule
collection Resources/Fonts/Inter-FLS.ttc (une seule police pour le Mac et pour Windows, toutes les graisses dedans) et
copie la licence à côté. Il faut fontTools (pip install fonttools).
"""
import io
import os
import sys
import zipfile

from fontTools import subset
from fontTools.ttLib import TTCollection, TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "Fonts")

FACES = [
    "extras/ttf/Inter-Regular.ttf",
    "extras/ttf/Inter-Medium.ttf",
    "extras/ttf/Inter-SemiBold.ttf",
    "extras/ttf/Inter-Bold.ttf",
    "extras/ttf/InterDisplay-SemiBold.ttf",
    "extras/ttf/InterDisplay-Bold.ttf",
]

# Latin (accents compris), ponctuation, monnaies, lettres-symboles, flèches (⇧ ↺), maths, signes techniques
# (⌘ ⌥ ⌃ ⌫ ⏎), formes (■ ▸ ●), coche ✓, ligatures fi fl.
UNICODES = ("U+0000-024F,U+0300-036F,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2200-22FF,"
            "U+2300-23FF,U+25A0-25FF,U+2700-27BF,U+FB01-FB02")


def light(data: bytes) -> TTFont:
    font = TTFont(io.BytesIO(data))
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.glyph_names = False
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=subset.parse_unicodes(UNICODES))
    subsetter.subset(font)
    return font


def main(archive: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        fonts = [light(z.read(name)) for name in FACES]
        licence = z.read("LICENSE.txt")
    collection = TTCollection()
    collection.fonts = fonts
    target = os.path.join(OUT, "Inter-FLS.ttc")
    collection.save(target, shareTables=True)
    with open(os.path.join(OUT, "LICENCE-Inter.txt"), "wb") as f:
        f.write(licence)
    for font in fonts:
        name = font["name"]
        family = name.getDebugName(16) or name.getDebugName(1)
        print(family, "·", name.getDebugName(17) or name.getDebugName(2))
    print(target, os.path.getsize(target) // 1024, "Ko")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
