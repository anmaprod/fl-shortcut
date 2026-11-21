"""Classe des sons hors-ligne avec le modèle ONNX de l'IA intégrée (Windows, macOS, Linux ; rien ne part sur
internet). Même règle que l'app : le son est ramené en mono 16 kHz, crête à 0,7, coupé en tranches de 0,975 s
(pas 0,48 s ; au-delà de 16, les plus fortes) ; la famille est la moyenne des tranches, mais c'est une voix dès que
la tranche la plus « voix » passe le seuil ; la sorte (les choix de l'aperçu de l'Organiser : Voix lead, Chœur,
Pad, Piano, 808, Sub, Kick, Open Hat, Riser…) est la plus probable parmi celles de sa famille, si elle l'emporte
nettement (sinon le mot général de la famille : Voix, Mélodie, Basse, Drums, FX).

Usage :
  python ia/classer.py son.wav autre.aiff …              → famille, sorte, probabilités, temps
  python ia/classer.py ~/Samples --ranger ~/Desktop/Tri  → COPIE chaque son dans Voix/Chœur, Drums/Kick, Basse/808…
                                                            (les originaux ne sont jamais déplacés ni effacés)
Dépendances : numpy, scipy, soundfile, onnxruntime (onnxruntime-gpu ou onnxruntime-directml pour la carte
graphique)."""
import argparse
import json
import os
import shutil
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from commun import FAMILLE_DE_SORTE, MODELE, NOMS, lire, tranches  # noqa: E402

EXTENSIONS = {".wav", ".aif", ".aiff", ".flac", ".ogg", ".mp3"}
# Dossiers des familles (noms de l'aperçu) ; le mot général de chaque famille quand la sorte n'est pas nette.
DOSSIERS = {"voix": "Voix", "melodie": "Mélodies", "basse": "Basse", "drums": "Drums", "fx": "FX"}
GENERAL = {"voix": "vocal", "melodie": "melody", "basse": "bass", "drums": "drums", "fx": "fx"}
PART_MIN = 0.5                   # comme l'app (ClasseurSons.partMin)


class Classeur:
    def __init__(self, modele=os.path.join(MODELE, "classeur_sons.onnx")):
        import onnxruntime as ort
        self.meta = json.load(open(os.path.splitext(modele)[0] + ".json"))
        voulus = ["CUDAExecutionProvider", "DmlExecutionProvider", "CoreMLExecutionProvider", "CPUExecutionProvider"]
        dispo = set(ort.get_available_providers())
        options = ort.SessionOptions()
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        self.session = ort.InferenceSession(modele, options, providers=[p for p in voulus if p in dispo])
        self.familles, self.sortes = self.meta["familles"], self.meta["sortes"]
        self.seuil = self.meta["seuil_voix"]

    def classer(self, son):
        """son : mono 16 kHz, crête à 0,7 (commun.lire). → dict famille, sorte (nette, sinon le mot général),
        meilleure sorte de la famille, sa part et son avance sur la suivante, probabilités."""
        lot = tranches(son)
        if len(lot) == 0:
            return None
        p_famille, p_sorte = self.session.run(["famille", "sorte"], {"son": lot})
        moy = p_famille.mean(axis=0)
        voix_max = float(p_famille[:, 0].max())
        if voix_max >= self.seuil:
            famille = "voix"
        else:
            autres = moy.copy()
            autres[0] = -1
            famille = self.familles[int(autres.argmax())]
        s = p_sorte.mean(axis=0)
        permises = sorted((i for i, n in enumerate(self.sortes) if FAMILLE_DE_SORTE[n] == famille), key=lambda i: -s[i])
        parts = s[permises] / max(float(s[permises].sum()), 1e-9)
        sorte = self.sortes[permises[0]] if parts[0] >= PART_MIN else GENERAL[famille]
        return {"famille": famille, "sorte": sorte, "meilleure": self.sortes[permises[0]],
                "part": round(float(parts[0]), 3), "marge": round(float(parts[0] - parts[1]), 3),
                "voix_max": round(voix_max, 3),
                "familles": {n: round(float(v), 3) for n, v in zip(self.familles, moy)}}


def fichiers(chemins):
    for c in chemins:
        if os.path.isdir(c):
            for racine, _, noms in os.walk(c):
                for n in sorted(noms):
                    if os.path.splitext(n)[1].lower() in EXTENSIONS and not n.startswith("._"):
                        yield os.path.join(racine, n)
        else:
            yield c


def copier(chemin, dossier):
    os.makedirs(dossier, exist_ok=True)
    base, ext = os.path.splitext(os.path.basename(chemin))
    cible, k = os.path.join(dossier, base + ext), 2
    while os.path.exists(cible):
        cible, k = os.path.join(dossier, f"{base} {k}{ext}"), k + 1
    shutil.copy2(chemin, cible)


def main():
    a = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    a.add_argument("chemins", nargs="+")
    a.add_argument("--ranger", help="dossier où COPIER les sons, rangés par famille et sorte")
    a.add_argument("--modele", default=os.path.join(MODELE, "classeur_sons.onnx"))
    args = a.parse_args()
    c = Classeur(args.modele)
    temps, compte = [], {}
    for chemin in fichiers(args.chemins):
        try:
            son = lire(chemin)
        except Exception as e:
            print(f"illisible : {chemin} ({type(e).__name__})")
            continue
        debut = time.perf_counter()
        r = c.classer(son)
        temps.append((time.perf_counter() - debut) * 1000)
        if r is None:
            continue
        nom = os.path.join(DOSSIERS[r["famille"]], NOMS[r["sorte"]])
        compte[nom] = compte.get(nom, 0) + 1
        print(f"{nom:20s} voix {r['voix_max']:.2f}  {temps[-1]:5.1f} ms  {chemin}")
        if args.ranger:
            copier(chemin, os.path.join(args.ranger, nom))
    if temps:
        print(f"\n{len(temps)} sons, {np.mean(temps):.1f} ms par son en moyenne (lecture du fichier non comptée)")
        print("  ".join(f"{k} {v}" for k, v in sorted(compte.items())))


if __name__ == "__main__":
    main()
