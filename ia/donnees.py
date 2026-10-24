"""Télécharge, une seule fois, YAMNet et les sons d'apprentissage (≈ 4,5 Go) dans FLS_IA_TRAVAIL
(par défaut ~/.cache/fl-shortcuts-ia). Seulement des sources libres d'usage commercial :
- YAMNet : code et poids de Google (tensorflow/models, licence Apache 2.0) ;
- VocalSet : chant, 20 chanteurs (Wilkins et al., 2018 ; CC BY 4.0) ;
- LibriSpeech dev-clean et test-clean : parole, 80 locuteurs (Panayotov et al., 2015 ; CC BY 4.0) ;
- NSynth test et valid : notes de 53 instruments (Engel et al., 2017 ; CC BY 4.0) ; nsynth-train (≈ 1000 autres
  instruments) et Medley-solos-DB (Lostanlen et al., 2019 ; CC BY 4.0) sont lus au fil du téléchargement par
  preparer.py (24 Go et 8 Go, rien n'est gardé sur le disque) ;
- Freesound One-Shot Percussive Sounds (Ramires et al., 2020) : sons de batterie, chacun sous sa licence Freesound ;
  preparer.py ne garde que CC0 et CC BY (pas de NC) ;
- Groove MIDI Dataset (Gillick et al., 2019 ; CC BY 4.0) : batteurs enregistrés, boucles et fills (Drum loop, Fill).
Les packs de batterie du propriétaire (FLS_IA_KITS) ne sont jamais téléchargés ici : il les donne lui-même.
Usage : python ia/donnees.py"""
import os
import urllib.request

from commun import TRAVAIL, yamnet_dir

YAMNET = "https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/"
SOURCES = {
    "vocalset11.zip": "https://zenodo.org/records/1442513/files/VocalSet11.zip?download=1",
    "librispeech-dev-clean.tar.gz": "https://www.openslr.org/resources/12/dev-clean.tar.gz",
    "librispeech-test-clean.tar.gz": "https://www.openslr.org/resources/12/test-clean.tar.gz",
    "nsynth-test.tar.gz": "http://download.magenta.tensorflow.org/datasets/nsynth/nsynth-test.jsonwav.tar.gz",
    "nsynth-valid.tar.gz": "http://download.magenta.tensorflow.org/datasets/nsynth/nsynth-valid.jsonwav.tar.gz",
    "oneshot.zip": "https://zenodo.org/records/3665275/files/one_shot_percussive_sounds.zip?download=1",
    "oneshot-licenses.txt": "https://zenodo.org/records/3665275/files/licenses.txt?download=1",
    "groove-v1.0.0.zip": "https://storage.googleapis.com/magentadata/datasets/groove/groove-v1.0.0.zip",
}


def telecharger(url, chemin):
    if os.path.exists(chemin) and os.path.getsize(chemin) > 0:
        print("déjà là :", os.path.basename(chemin))
        return
    print("téléchargement :", os.path.basename(chemin), flush=True)
    tmp = chemin + ".part"
    urllib.request.urlretrieve(url, tmp)
    os.replace(tmp, chemin)


def main():
    os.makedirs(os.path.join(TRAVAIL, "donnees"), exist_ok=True)
    os.makedirs(yamnet_dir(), exist_ok=True)
    for f in ["yamnet.py", "params.py", "features.py", "yamnet_class_map.csv"]:
        telecharger(YAMNET + f, os.path.join(yamnet_dir(), f))
    telecharger("https://storage.googleapis.com/audioset/yamnet.h5", os.path.join(yamnet_dir(), "yamnet.h5"))
    # Le code récent de YAMNet importe tf_keras ; avec TensorFlow 2.15, tf.keras est la même chose.
    chemin = os.path.join(yamnet_dir(), "yamnet.py")
    code = open(chemin).read().replace("from tf_keras import Model, layers",
                                       "from tensorflow.keras import Model, layers")
    open(chemin, "w").write(code)
    for nom, url in SOURCES.items():
        telecharger(url, os.path.join(TRAVAIL, "donnees", nom))
    print("prêt dans", TRAVAIL)


if __name__ == "__main__":
    main()
