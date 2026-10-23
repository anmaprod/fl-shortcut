# IA intégrée de FL Shortcuts : crédits

Le modèle `classeur_sons.onnx` (et sa version Core ML `ClasseurSons.mlpackage` dans l'app Mac) réunit :

- **YAMNet**, Google, extrait de [tensorflow/models](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet),
  sous licence Apache 2.0 (texte complet : `LICENCE-YAMNET.txt`). Utilisé tel quel (poids ramenés à 8 bits) ; le
  calcul du spectre est réécrit en multiplications de matrices, aux mêmes réglages.
- **Deux petites têtes** (famille et sorte) apprises par FL Shortcuts sur des sons libres d'usage commercial :
  - VocalSet, Wilkins, Seiple, Pardo et Ganguly, 2018 — CC BY 4.0 ;
  - LibriSpeech (dev-clean, test-clean), Panayotov, Chen, Povey et Khudanpur, 2015 — CC BY 4.0 ;
  - NSynth (test, valid), Engel et al., 2017 — CC BY 4.0 ;
  - Freesound One-Shot Percussive Sounds, Ramires et al., 2020 — seuls les sons CC0 et CC BY, auteurs listés dans
    le fichier de licences du jeu de données ;
  - sons fabriqués par `ia/preparer.py` (domaine public).

Aucun son d'utilisateur n'a servi à l'apprentissage.
