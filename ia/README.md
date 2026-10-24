# IA intégrée : classement des sons, hors-ligne, Mac et Windows

L'Organiser range chaque son d'un projet (ou d'un pack) par **famille** — Voix, Mélodies, Basse, Drums, FX — puis
par **sorte** : les mêmes choix que l'aperçu de l'Organiser, ceux qu'on peut changer à la main (tableau ci-dessous).
Cette IA tourne sur la machine de l'utilisateur, sans internet ni service payant : un seul modèle, au format ONNX
(Windows, macOS, Linux ; processeur ou carte graphique) et Core ML (app Mac), de **≈ 8 Mo**, qui classe un sample
court en **une vingtaine de millisecondes** sur un simple processeur.

## 1. Stratégie

### Le modèle
```
son → mono 16 kHz, crête 0,7 → tranches de 0,975 s (pas 0,48 s ; 16 au plus, les plus fortes)
    → spectre log-mel (64 bandes, 125–7500 Hz)  ─┬→ YAMNet (MobileNet, Google, Apache 2.0) → empreinte 1024
                                                 └→ 192 mesures : moyenne, écart-type, variation de chaque bande
    → 1216 nombres normalisés → 5 têtes (couches de 512 et 256 → « famille » (5) + « sorte » (44)), moyennées
```
- **YAMNet** est appris par Google sur AudioSet (2 millions de sons, 521 classes dont chant, parole, rap, chœur,
  chuchotement) : son empreinte sait déjà distinguer une voix d'un instrument. On ne le réentraîne pas (il reste
  général et rapide) ; on apprend seulement les têtes.
- Les **192 mesures du spectre** ajoutent ce qui trahit une voix même traitée : les formants (bosses fixes du
  spectre, moyenne par bande), leur mouvement et le débit syllabique (écart-type et variation dans le temps). Elles
  sont calculées dans le modèle lui-même : rien à recoder dans l'app.
- Le spectre est fait de multiplications de matrices (pas d'opération de spectre propre à une plateforme) : le même
  calcul tourne sous ONNX Runtime et Core ML (macOS 13 et plus).
- **Cinq têtes moyennées** : apprises chacune de leur côté (départs au hasard différents), leur moyenne ne dépend
  plus du hasard (une seule tête donnait de 92,4 à 93,7 % selon le départ) ; elles ne coûtent presque rien à côté de
  YAMNet.
- **Deux sorties** plutôt qu'une liste plate : la famille apprend sur tous les sons (même un son de batterie au nom
  muet), la sorte seulement sur les sons dont on la connaît sûrement. C'est aussi la logique de l'Organiser : la
  sorte est choisie **parmi celles de la famille décidée**, et donnée seulement si elle l'emporte nettement (plus de
  la moitié de la probabilité de sa famille) ; sinon le mot général de la famille (Voix, Mélodie, Basse, Drums, FX),
  ou, dans l'app, la sorte trouvée par les règles d'avant pour des drums et des mélodies.

### Les sortes (les choix de l'aperçu)
| Famille | Sortes apprises | D'où viennent les exemples |
|---|---|---|
| Voix | Voix, Voix lead, Chœur, Adlib, Ambiance | parole ; chant ; voix superposées et désaccordées ; chops et stutters ; longue réverb |
| Mélodies | Lead, Pluck, Pad, Keys, Piano, Arp, Chords, Guitare, Strings, Bell, Flûte, Brass, Orgue, Mélodie | instruments NSynth (piano acoustique = Piano, autres claviers = Keys, mallets = Bell, anches = Mélodie) ; plucks, arpèges, pads et accords fabriqués avec leurs notes |
| Basse | 808, Sub, Reese, Basse | 808 (glissés, saturés), subs, reese désaccordées, basses de synthé et NSynth |
| Drums | Kick, Snare, Clap, Rim, Snap, Hi-hat, Open Hat, Perc, Tom, Shaker, Crash, Ride, Cymbal, Drum loop, Fill, Drums | sons Freesound d'après leur nom (« open hat » = Open Hat, « crash cymbal » = Crash) ; boucles et fills de vrais batteurs (Groove MIDI Dataset) et des packs du propriétaire = Drum loop, Fill ; boucles fabriquées = Drum loop ; claps, hats, snaps, shakers, crashs fabriqués |
| FX | Riser, Downlifter, Impact, Sweep, FX | fabriqués ; cymbales à l'envers = Riser ; notes à l'envers, lasers, vinyle, drones = FX |

« Back » et « Synth » ne sont pas appris : ils se décident au nom du son (une voix de back n'a rien qui s'entende
seul, « Synth » ne dit pas plus que Lead, Pad ou Pluck).

### Les voix (le point faible)
L'IA de macOS donnait trop souvent moins de 0,5 aux voix de production : elles finissaient en Mélodies (une voix
chantée a des notes nettes), FX ou Drums. Ici :
1. **Beaucoup de voix, déclinées comme en production** : chant (VocalSet, 20 chanteurs, techniques variées), parole
   (LibriSpeech, 80 locuteurs), et pour chacune 1 ou 2 variantes : réverb, hauteur ET formants décalés (voix
   pitchée), saturation, filtre téléphone, chops de 0,12 à 1 s, stutter, voix à l'envers, chœur, ambiance, et des
   combinaisons ; plus une série à part de voix hachées (chops et stutters, le plus dur à reconnaître).
2. **Des pièges fabriqués exprès** dans les autres familles : leads de synthé, flûtes et cordes au vibrato (une
   hauteur qui ondule comme une voix), notes et cymbales à l'envers avec réverb (FX), risers, impacts, drones.
3. **Un son est une voix dès que sa tranche la plus « voix » passe le seuil** (un chop ou une phrase entourée de
   silence reste une voix) ; sinon la famille est la moyenne des tranches.
4. **Seuil réglé contre les faux positifs** : le plus bas qui garde au plus 2 % des autres sons (FX, mélodies,
   drums…) pris pour des voix, réglé sur une moitié des sons de validation et mesuré sur l'autre.

### Les données (libres d'usage commercial, plus les packs du propriétaire à sa demande)
| Source | Contenu | Licence | Famille |
|---|---|---|---|
| VocalSet (Wilkins et al., 2018) | chant, 20 chanteurs | CC BY 4.0 | voix |
| LibriSpeech dev-clean et test-clean (Panayotov et al., 2015) | parole, 80 locuteurs | CC BY 4.0 | voix |
| NSynth test et valid (Engel et al., 2017) | notes de 53 instruments, chacune dans sa tessiture (basse jusqu'au do 4, mélodie du do 2 au do 7) | CC BY 4.0 | mélodie, basse |
| NSynth train (Engel et al., 2017) | 16 notes de chacun des ≈ 1000 autres instruments (24 Go lus au fil du téléchargement) | CC BY 4.0 | mélodie, basse |
| Medley-solos-DB (Lostanlen et al., 2019) | extraits de vrais morceaux : chanteuses, clarinette, guitare saturée, flûte, piano, saxophone, trompette, violon (lus au fil du téléchargement) | CC BY 4.0 | voix, mélodie |
| Freesound One-Shot Percussive Sounds (Ramires et al., 2020) | ~9 500 sons de batterie | CC0 et CC BY gardés, NC exclus | drums (sorte d'après le nom) |
| Groove MIDI Dataset (Gillick et al., 2019) | 10 batteurs enregistrés : boucles (« beat », coupées en 1, 2 ou 4 mesures) et fills | CC BY 4.0 | drums (Drum loop, Fill) |
| Packs du propriétaire (`FLS_IA_KITS`, jamais dans le dépôt) | fills, drum loops, sons seuls, basses, textures ; sorte d'après le type du son dans son nom (« © FILL -- … » ; « LOW -- … (C) » = basse sans sorte précise, et seulement s'il est vraiment grave), puis le nom entier, puis ses dossiers (jamais un dossier mélangé comme « fill + chop ») ; tous les packs appris pour la version livrée (chiffres mesurés avant sur deux packs gardés) | à sa demande (24/10) | drums, basse, FX |
| Fabriqués par `preparer.py` | 808, subs, reese, basses, pads, plucks, arpèges, accords, claps, hats, snaps, shakers, crashs, FX, boucles | domaine public | toutes |

**Validation honnête** : des chanteurs, des locuteurs, des instruments et des sons de batterie entiers sont mis de
côté avant l'apprentissage ; les chiffres annoncés (`RESULTATS.md`) sont mesurés sur eux seuls.

## 2. Refaire l'apprentissage
```
python3.11 -m venv .venv && . .venv/bin/activate && pip install -r ia/requirements.txt
python ia/donnees.py      # ≈ 4,5 Go, une seule fois (dossier FLS_IA_TRAVAIL, par défaut ~/.cache/fl-shortcuts-ia)
python ia/preparer.py     # sons, variantes, mesures de chaque tranche (≈ 1 h 15 sur 4 cœurs ; reprend après une erreur)
                          # FLS_IA_KITS=dossier : ajoute des packs de batterie (une étape à part, refaite seule)
python ia/entrainer.py    # têtes, seuil des voix, RESULTATS.md (≈ 5 min)
python ia/exporter.py     # vérifie, puis écrit ia/modele/classeur_sons.onnx (+ .json) et Resources/ClasseurSons.mlpackage
python ia/essais_app.py   # sons d'essai et réponses attendues pour les tests de l'app
```
Essai (non retenu) : réapprendre aussi la dernière couche de YAMNet. `FLS_IA_COUCHE13=1 python ia/preparer.py`
garde la sortie de sa couche 13 (≈ 4,5 Go), `python ia/affiner.py` réapprend la couche 14 (≈ 25 min) et écrit
`jeu_affine.npz`, puis `FLS_IA_JEU=jeu_affine.npz python ia/entrainer.py` ; `exporter.py` pose la couche réapprise
si `couche14.npz` est là. Le 23/10, sur les mêmes 7 379 sons jamais entendus : 92,6 % comme sans elle (voix +0,6,
basse +0,4, FX −2,9) ; le modèle livré, appris avant, fait 92,7 % sur ces mêmes sons. Pas de gain : non livrée.

## 3. Classer des sons (hors-ligne)
- **Script (Windows, macOS, Linux)** : `python ia/classer.py mon_pack/ --ranger ~/Desktop/Tri` copie chaque son dans
  le dossier de sa famille et de sa sorte (`Voix/Chœur/`, `Drums/Open Hat/`, `Basse/808/`, `FX/Riser/`…, les
  originaux ne bougent jamais) et affiche le temps par son. Carte graphique utilisée si ONNX Runtime en trouve une
  (CUDA, DirectML, Core ML).
- **App Mac** : `Sources/FLShortcut/ClasseurSons.swift` (Core ML, compilé par `build.sh`). L'organisation de
  l'Organiser ne change pas : l'IA intégrée prend la place de l'IA de macOS dans les mêmes règles (le nom du son
  d'abord, puis ce que les mesures disent sûrement : boucle de batterie, hi-hat à ses aigus, trois notes nettes =
  mélodie…). Règle `voix-iv` juste après `voix-ia` ; ses drums et instruments s'ajoutent à ceux de macOS ;
  `famille-iv` seulement quand les règles hésitent ; sorte des drums et des mélodies à la place des étiquettes de
  macOS, sorte des voix, basses et FX. Le diagnostic ajoute `+ivNN` (probabilité de voix en %, un nombre seulement).
- **App Windows** : `ia/integration/ClasseurSons.cs` (ONNX Runtime ; exemple de référence, l'app Windows étant en
  pause).

## 4. Vitesse et précision
- **Poids en 8 bits, calculs en 32 bits** (YAMNet et têtes ; linéaire symétrique par canal, dans Core ML comme
  dans l'ONNX) : ≈ 8 Mo au lieu de 29, mêmes réponses (même famille pour 100 % des tranches d'essai, même sorte pour
  99,5 %). Le spectre reste en 32 bits. Mettre aussi les calculs en 8 bits (quantification dynamique ou statique
  d'ONNX Runtime) a été essayé et refusé : même famille pour 78 % et 37 % des tranches seulement (les convolutions
  de YAMNet le supportent mal). `exporter.py` refait cette comparaison à chaque export et garde la version la plus
  légère qui répond comme la 32 bits.
- **Une seule passe par son**, toutes ses tranches ensemble (lot) ; 16 tranches au plus (les plus fortes). Mesuré
  (ONNX Runtime, 4 cœurs d'un Xeon à 2,8 GHz, sans carte graphique) : sample de 0,3 s ≈ 21 ms, 1 s ≈ 28 ms,
  3 s ≈ 46 ms, 10 s ≈ 76 ms.
- **Rien au repos** : le modèle est chargé pour une écoute et libéré après ; le classement et la sorte d'un même son
  ne l'écoutent qu'une fois.
- **Faux positifs voix / FX** : seuil réglé à 2 % de faux positifs, pièges FX dans l'apprentissage, et l'Organiser
  garde ses autres règles (nom du son, mesures) quand l'IA n'entend pas de voix.

## 5. L'IA apprend de ses erreurs (« Pas content ? »)
- **Sur le Mac, tout de suite** : un son écouté puis corrigé (dans l'aperçu, ou avec le bouton « Pas content ? » à
  la fin de l'Organiser) est retenu par son empreinte (moyenne des empreintes YAMNet de ses tranches, des nombres,
  `CorrectionsIA.swift`) avec la bonne famille et sorte. Un son presque identique (ressemblance ≥ 0,97 : le même
  sample, coupé ou un peu traité) est ensuite rangé comme corrigé, avant toute règle (règle `corrige` du diagnostic).
- **Pour tout le monde, avec l'accord de la personne** (case « Aider l'IA de tout le monde », une fois pour toutes) :
  les mesures du son (1216 nombres par tranche, 8 tranches au plus, en 16 bits) et les familles et sortes (avant,
  après) partent au serveur (`supabase/corrections-ia.sql`). Jamais le son, son nom ni ce qu'elle écrit.
- **Réapprendre avec elles** :
  ```
  python ia/corrections.py export.csv            # export CSV de Supabase (Table Editor › corrections_ia › Export)
  FLS_SUPABASE_SECRET=… python ia/corrections.py --serveur   # ou lues directement (clé JAMAIS dans le dépôt)
  python ia/entrainer.py && python ia/exporter.py && python ia/essais_app.py
  ```
  Les corrections s'ajoutent à l'apprentissage comme des sons de plus (les doublons comptent une fois).
- Les cases Playlist, Mixer et aspect, et « Autre » (texte libre), partent à l'équipe comme un message « Écrire à
  l'équipe » : l'IA ne peut pas les apprendre.

## 6. Limites connues
- Pas de vraies voix de production sous licence libre en grand nombre : elles sont imitées par les variantes. Les
  packs des utilisateurs ne quittent jamais leur ordinateur ; seuls ceux que le propriétaire a donnés (fills, drum
  loops) ont servi à apprendre.
- Les 808, les subs, les reese, les pads et les FX sont surtout fabriqués : à surveiller sur de vrais packs.
- Plafond de l'IA seule ≈ 92–93 % sur les notes isolées de NSynth : plus de sons (72 643) ou la couche 14 réapprise
  n'y changent rien. Les erreurs restantes sont des notes seules ambiguës même à l'oreille : note grave de clavier
  prise pour une basse, note courte de pluck pour une percussion, cuivre de synthé étrange pour un FX. Dans
  l'Organiser, le nom et les règles sûres passent avant (3 notes nettes ou plus → mélodie, jamais drums ni FX).
- Les sortes de voix (Voix lead, Chœur, Adlib, Ambiance) sont apprises sur des imitations : un nom de son qui dit
  la sorte reste prioritaire dans l'Organiser.
