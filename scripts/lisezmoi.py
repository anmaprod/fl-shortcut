#!/usr/bin/env python3
# Modes d'emploi des téléchargements (LISEZMOI.html, Mac et Windows), au style suisse de l'app (02/11) : les modèles
# docs/telechargement/modele-*.html, avec leurs images collées dedans ({{ICON}}, {{MIDI1}}…) pour qu'un seul fichier
# s'ouvre d'un double-clic, sans rien d'autre à côté.
# Usage : python3 scripts/lisezmoi.py   (depuis la racine du dépôt ; Pillow)
#   → docs/telechargement/LISEZMOI-Mac.html et LISEZMOI-Windows.html (français), README-Mac.html et
#     README-Windows.html (la même page en anglais, scripts/lisezmoi_en.py)
# À refaire quand l'icône, l'image de MIDI Settings, le tuto de l'Organiser ou un modèle change.
import base64
import io
import os
import sys
from PIL import Image, ImageDraw, ImageFont

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOSSIER = os.path.join(RACINE, "docs", "telechargement")
RES = os.path.join(RACINE, "Resources")


def uri(im):
    b = io.BytesIO()
    im.save(b, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(b.getvalue()).decode()


def paquet():
    """Un paquet d'installation au style suisse : carré blanc à traits pleins, rabat, « PKG »."""
    n = 224
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((24, 56, n - 24, n - 24), outline="white", width=12)
    d.rectangle((24, 56, n - 24, 96), fill="white")
    d.rectangle((n // 2 - 14, 24, n // 2 + 14, 96), fill="white")
    try:
        police = ImageFont.truetype("DejaVuSans-Bold.ttf", 44)
    except OSError:
        police = ImageFont.load_default()
    d.text((n // 2, 150), "PKG", fill="white", font=police, anchor="mm")
    return im.resize((112, 112), Image.LANCZOS)


def images(langue="fr"):
    icone = Image.open(os.path.join(RES, "AppIcon-1024.png")).convert("RGBA").resize((168, 168), Image.LANCZOS)
    midi = Image.open(os.path.join(RES, "MIDISettings.png")).convert("RGB")
    # Les 4 cases, dans l'ordre et aux places de l'app (MIDISettingsCrops, pixels sur 1428 de large) : les deux
    # ports en 1 et 2, puis Enable, puis Controller type.
    cases = [(1090, 478, 250, 112), (1090, 955, 250, 112), (80, 958, 210, 105), (284, 932, 815, 132)]
    k = midi.width / 1428
    vals = {"ICON": uri(icone), "PKG": uri(paquet())}
    for i, (x, y, w, h) in enumerate(cases, 1):
        vals[f"MIDI{i}"] = uri(midi.crop((round(x * k), round(y * k), round((x + w) * k), round((y + h) * k))))
    vals["MIDIFULL"] = uri(midi.resize((1000, round(midi.height * 1000 / midi.width)), Image.LANCZOS))
    return vals


def main():
    import lisezmoi_en
    for langue, prefixe in (("fr", "LISEZMOI"), ("en", "README")):
        vals = images(langue)
        for nom in ("mac", "windows"):
            modele = os.path.join(DOSSIER, f"modele-{nom}.html")
            anglais = os.path.join(DOSSIER, f"modele-{nom}-en.html")
            # 08/11 : l'anglais est écrit à côté du français (scripts/lisezmoi_modeles.py) ; sinon, l'ancienne
            # traduction morceau par morceau.
            if langue == "en" and os.path.exists(anglais):
                modele, langue_ecrite = anglais, True
            else:
                langue_ecrite = False
            s = open(modele, encoding="utf-8").read()
            if langue == "en" and not langue_ecrite:
                s = lisezmoi_en.traduire(s)
                oubli = lisezmoi_en.reste_du_francais(s)
                if oubli:
                    raise SystemExit(f"{modele} : pas encore traduit en anglais : {oubli}")
            for cle, valeur in vals.items():
                s = s.replace("{{" + cle + "}}", valeur)
            if "{{" in s:
                raise SystemExit(f"{modele} : image inconnue")
            # Un vrai fichier HTML qui s'ouvre seul dans le navigateur.
            page = (f'<!doctype html>\n<html lang="{langue}">\n<head>\n<meta charset="utf-8">\n'
                    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
                    + s.replace("</style>", "</style>\n</head>\n<body>", 1) + "\n</body>\n</html>\n")
            sortie = os.path.join(DOSSIER, f"{prefixe}-{nom.capitalize()}.html")
            with open(sortie, "w", encoding="utf-8") as f:
                f.write(page)
            print(sortie, len(page) // 1024, "Ko")


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    main()
