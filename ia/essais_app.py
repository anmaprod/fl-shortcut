"""Sons d'essai des tests de l'app (Tests/FLShortcutTests/Fixtures) et réponses attendues (attendus.json), pris parmi
les sons gardés pour la validation (chanteuse, locuteur, instrument jamais entendus) ou fabriqués. Les tests de l'app
vérifient que le modèle Core ML répond comme le modèle ONNX ici (famille, sorte quand elle est nette, probabilité de
voix), et que chaque famille est la bonne.
Usage (après exporter.py) : python ia/essais_app.py"""
import io
import json
import os
import tarfile
import zipfile

import numpy as np
import soundfile as sf

from classer import Classeur
from commun import ICI, SR, TRAVAIL, lire
import preparer

SORTIE = os.path.join(os.path.dirname(ICI), "Tests", "FLShortcutTests", "Fixtures")
D = os.path.join(TRAVAIL, "donnees")


def plus_fort(son, secondes):
    """Le passage le plus fort de `secondes` (comme l'Organiser, qui écoute le passage le plus fort)."""
    n = int(secondes * SR)
    if len(son) <= n:
        return son
    energie = np.convolve(son ** 2, np.ones(SR // 10), mode="valid")
    debut = int(np.clip(energie.argmax() - n // 2, 0, len(son) - n))
    return son[debut:debut + n]


def main():
    os.makedirs(SORTIE, exist_ok=True)
    sons = {}
    z = zipfile.ZipFile(os.path.join(D, "vocalset11.zip"))
    chant = sorted(n for n in z.namelist() if "/female2/" in n and n.endswith(".wav") and "/._" not in n)[3]
    brut, sr = sf.read(io.BytesIO(z.read(chant)), dtype="float32")
    brut = brut if brut.ndim == 1 else brut.mean(axis=1)
    debut = int(np.argmax(np.abs(brut)) - sr * 0.75) if len(brut) > sr * 1.5 else 0
    sons["voix-chant-44k.wav"] = (brut[max(0, debut): max(0, debut) + int(sr * 1.5)], sr, "voix", "vocalLead")
    t = tarfile.open(os.path.join(D, "librispeech-dev-clean.tar.gz"))
    locs = sorted({m.name.split("/")[2] for m in t if m.name.endswith(".flac")})
    t = tarfile.open(os.path.join(D, "librispeech-dev-clean.tar.gz"))
    parole = next(m for m in t if m.name.endswith(".flac") and m.name.split("/")[2] == locs[0])
    sons["voix-parole.wav"] = (plus_fort(lire(t.extractfile(parole).read()), 1.5), SR, "voix", "vocal")
    autre = sorted(n for n in z.namelist() if "/male3/" in n and n.endswith(".wav") and "/._" not in n)[5]
    preparer.rng.seed(3)
    chop = preparer.reverb(preparer.chop(plus_fort(lire(z.read(autre)), 2.0)), 1.2)
    sons["voix-chop-reverb.wav"] = (chop, SR, "voix", "adlib")
    t = tarfile.open(os.path.join(D, "nsynth-test.tar.gz"))
    meta = json.load(t.extractfile(next(m for m in t if m.name.endswith("examples.json"))))
    gardes = sorted({v["instrument_str"] for v in meta.values()})[::5]
    # Au-dessus du do 4 : une note plus grave d'un clavier ou d'une guitare est ambiguë même à l'oreille (le sol 3
    # pris avant était à 59 % mélodie, puis 57 % basse après l'apprentissage du 24/10).
    note = sorted(k for k, v in meta.items() if v["instrument_str"] in gardes
                  and v["instrument_family_str"] in ("keyboard", "guitar", "string") and 60 <= v["pitch"] <= 72)[0]
    sorte_note = preparer.sorte_nsynth(meta[note]["instrument_family_str"], meta[note]["instrument_source_str"])
    t = tarfile.open(os.path.join(D, "nsynth-test.tar.gz"))
    wav = next(m for m in t if m.name.endswith(f"/{note}.wav"))
    sons["melodie-note.wav"] = (plus_fort(lire(t.extractfile(wav).read()), 1.0), SR, "melodie", sorte_note)
    preparer.rng.seed(11)
    preparer.nrng = np.random.default_rng(11)
    sons["basse-808.wav"] = (preparer.synth_808(), SR, "basse", "bass808")
    sons["drums-clap.wav"] = (preparer.synth_clap(), SR, "drums", "clap")
    sons["drums-open-hat.wav"] = (preparer.synth_hihat(True), SR, "drums", "openHat")
    fx, sorte = preparer.synth_fx()
    while sorte != "riser":
        fx, sorte = preparer.synth_fx()
    sons["fx-riser.wav"] = (fx, SR, "fx", "riser")

    c = Classeur()
    attendus = {}
    for nom, (son, sr, famille, sorte) in sons.items():
        sf.write(os.path.join(SORTIE, nom), np.asarray(son, np.float32), int(sr), subtype="PCM_16")
        r = c.classer(lire(os.path.join(SORTIE, nom)))
        # La sorte n'est comparée à celle de l'app que si elle est nette (sinon le moindre écart la ferait changer).
        attendus[nom] = {"famille_voulue": famille, "famille": r["famille"], "voix_max": r["voix_max"],
                         "sorte_voulue": sorte, "sorte": r["meilleure"] if r["marge"] >= 0.1 else None,
                         "familles": r["familles"]}
        print(f"{nom:24s} voulu {famille:8s} {sorte:10s} → {r['famille']:8s} {r['meilleure']:10s} "
              f"(part {r['part']:.2f}) voix {r['voix_max']:.2f}")
    json.dump(attendus, open(os.path.join(SORTIE, "attendus.json"), "w"), indent=1, ensure_ascii=False)
    open(os.path.join(SORTIE, "CREDITS.md"), "w").write(
        "# Sons d'essai de l'IA intégrée\n\n"
        "- voix-chant-44k.wav : extrait de VocalSet (chanteuse « female2 », gardée hors apprentissage), "
        "Wilkins et al. 2018, CC BY 4.0.\n"
        "- voix-parole.wav : extrait de LibriSpeech dev-clean (locuteur gardé hors apprentissage), "
        "Panayotov et al. 2015, CC BY 4.0.\n"
        "- voix-chop-reverb.wav : chop d'un extrait de VocalSet (« male3 », gardé hors apprentissage) + réverb, "
        "CC BY 4.0.\n"
        "- melodie-note.wav : note de NSynth (instrument gardé hors apprentissage), Engel et al. 2017, CC BY 4.0.\n"
        "- basse-808.wav, drums-clap.wav, drums-open-hat.wav, fx-riser.wav : fabriqués par ia/preparer.py "
        "(domaine public).\n")


if __name__ == "__main__":
    main()
