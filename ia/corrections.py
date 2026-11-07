"""Les corrections partagées par les utilisateurs (bouton « Pas content ? » et aperçu de l'Organiser, avec leur
accord) ajoutées à l'apprentissage : chaque correction donne les 1216 mesures de ses tranches (celles que l'app a
calculées avec le modèle) et la bonne famille et sorte. Rien d'autre n'existe sur le serveur : ni le son, ni son
nom, ni un texte tapé (supabase/corrections-ia.sql).

Deux façons de les lire :
  python ia/corrections.py export.csv     → export CSV de Supabase (Table Editor › corrections_ia › Export)
  FLS_SUPABASE_SECRET=… python ia/corrections.py --serveur
      → lues directement (adresse du projet dans Resources/Info.plist ; clé secrète donnée au moment de s'en servir,
        JAMAIS écrite dans le dépôt)
Sortie : TRAVAIL/corrections.npz, que entrainer.py ajoute à l'apprentissage (une correction compte comme un son de
plus ; une même correction envoyée deux fois ne compte qu'une fois)."""
import base64
import csv
import hashlib
import json
import os
import plistlib
import sys
import urllib.request

import numpy as np

from commun import FAMILLES, ICI, INCONNUE, SORTES, TRAVAIL

TAILLE = 1216


def lignes_serveur():
    secret = os.environ.get("FLS_SUPABASE_SECRET")
    if not secret:
        sys.exit("FLS_SUPABASE_SECRET manquante (clé secrète du projet, à ne jamais écrire dans le dépôt)")
    info = plistlib.load(open(os.path.join(os.path.dirname(ICI), "Resources", "Info.plist"), "rb"))
    base = info["FLSCommunityURL"].rstrip("/") + "/rest/v1/corrections_ia?select=*&order=created_at"
    lignes, debut = [], 0
    while True:
        r = urllib.request.Request(base, headers={"apikey": secret, "Authorization": f"Bearer {secret}",
                                                  "Range": f"{debut}-{debut + 999}"})
        page = json.load(urllib.request.urlopen(r, timeout=120))
        lignes += page
        if len(page) < 1000:
            return lignes
        debut += 1000


def lignes_csv(chemin):
    return list(csv.DictReader(open(chemin, newline="", encoding="utf-8")))


def convertir(lignes):
    """Mesures de chaque tranche, famille et sorte (INCONNUE si la bonne réponse n'en dit pas), un numéro par
    correction ; les doublons (mêmes mesures, même réponse) sont retirés."""
    x, famille, sorte, clip, vus = [], [], [], [], set()
    for ligne in lignes:
        if ligne.get("famille") not in FAMILLES:
            continue
        brut = base64.b64decode(ligne["mesures"])
        tranches = int(ligne["tranches"])
        if len(brut) != tranches * TAILLE * 2:
            continue
        cle = hashlib.sha256(brut + ligne["famille"].encode() + (ligne.get("sorte") or "").encode()).hexdigest()
        if cle in vus:
            continue
        vus.add(cle)
        mesures = np.frombuffer(brut, dtype="<f2").reshape(tranches, TAILLE).astype(np.float16)
        if not np.isfinite(mesures).all():
            continue
        s = ligne.get("sorte") or ""
        x.append(mesures)
        famille += [FAMILLES.index(ligne["famille"])] * tranches
        sorte += [SORTES.index(s) if s in SORTES else INCONNUE] * tranches
        clip += [len(vus) - 1] * tranches
    return x, famille, sorte, clip


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    lignes = lignes_serveur() if sys.argv[1] == "--serveur" else lignes_csv(sys.argv[1])
    x, famille, sorte, clip = convertir(lignes)
    if not x:
        sys.exit(f"aucune correction utilisable sur {len(lignes)}")
    chemin = os.path.join(TRAVAIL, "corrections.npz")
    np.savez_compressed(chemin, x=np.concatenate(x), famille=np.array(famille), sorte=np.array(sorte),
                        clip=np.array(clip))
    print(f"{len(x)} corrections ({len(famille)} tranches) sur {len(lignes)} lignes → {chemin}")


if __name__ == "__main__":
    main()
