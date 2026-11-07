# Résultats de l'IA intégrée

Sons de validation B : 7610 (jamais entendus à l'apprentissage). Seuil des voix : 0.37.

- Justesse de la famille : **92.4 %**
- Voix reconnues : **96.3 %** (YAMNet seul, ses classes de voix ≥ 0,5 : 59.8 %)
- Autres sons pris pour des voix : **2.2 %** (YAMNet seul : 0.3 %)

## Par famille (objectif : 99 %)

| Famille | Sons | Bien classés |
|---|---|---|
| voix | 2659 | 96.3 % |
| melodie | 2891 | 86.0 % |
| basse | 677 | 95.4 % |
| drums | 1003 | 97.2 % |
| fx | 380 | 95.0 % |

## Par source

| Source | Sons | Famille attendue | Bien classés | Pris pour des voix |
|---|---|---|---|---|
| 808 | 100 | basse | 99.0 % | 0.0 % |
| accord | 175 | melodie | 89.7 % | 3.4 % |
| accords-synth | 50 | melodie | 88.0 % | 0.0 % |
| arp | 96 | melodie | 95.8 % | 0.0 % |
| basse-synth | 100 | basse | 98.0 % | 0.0 % |
| batterie | 572 | drums | 95.1 % | 0.7 % |
| boucle | 50 | drums | 100.0 % | 0.0 % |
| cymbale-envers | 3 | fx | 100.0 % | 0.0 % |
| fx | 100 | fx | 100.0 % | 0.0 % |
| groove-boucle | 166 | drums | 100.0 % | 0.0 % |
| groove-fill | 65 | drums | 100.0 % | 0.0 % |
| hihat-synth | 100 | drums | 100.0 % | 0.0 % |
| librispeech | 247 | voix | 100.0 % | 100.0 % |
| medley-instrument | 411 | melodie | 92.9 % | 6.6 % |
| medley-voix | 311 | voix | 100.0 % | 100.0 % |
| note-envers | 277 | fx | 93.1 % | 3.2 % |
| nsynth | 1984 | melodie | 85.7 % | 2.0 % |
| pad | 100 | melodie | 100.0 % | 0.0 % |
| pad-note | 30 | melodie | 26.7 % | 3.3 % |
| phrase | 213 | melodie | 95.3 % | 0.9 % |
| pluck | 78 | melodie | 80.8 % | 2.6 % |
| pluck-synth | 50 | melodie | 64.0 % | 2.0 % |
| shaker-synth | 50 | drums | 100.0 % | 0.0 % |
| sub | 100 | basse | 100.0 % | 0.0 % |
| vibrato | 81 | melodie | 66.7 % | 24.7 % |
| vocalset | 367 | voix | 100.0 % | 100.0 % |
| voix-ambiance | 80 | voix | 100.0 % | 100.0 % |
| voix-choeur | 98 | voix | 100.0 % | 100.0 % |
| voix-choeur+reverb | 100 | voix | 100.0 % | 100.0 % |
| voix-chop | 90 | voix | 94.4 % | 94.4 % |
| voix-chop+pitch | 92 | voix | 88.0 % | 88.0 % |
| voix-chop+reverb | 83 | voix | 88.0 % | 88.0 % |
| voix-hachee | 452 | voix | 89.2 % | 89.2 % |
| voix-pitch | 96 | voix | 99.0 % | 99.0 % |
| voix-pitch+reverb | 91 | voix | 97.8 % | 97.8 % |
| voix-reverb | 100 | voix | 100.0 % | 100.0 % |
| voix-reverse | 92 | voix | 100.0 % | 100.0 % |
| voix-reverse+reverb | 89 | voix | 100.0 % | 100.0 % |
| voix-saturate | 99 | voix | 99.0 % | 99.0 % |
| voix-stutter | 86 | voix | 77.9 % | 77.9 % |
| voix-telephone | 86 | voix | 100.0 % | 100.0 % |

## Confusion des familles (lignes : attendu ; colonnes : décidé)

| | voix | melodie | basse | drums | fx |
|---|---|---|---|---|---|
| voix | 2561 | 41 | 10 | 31 | 16 |
| melodie | 92 | 2487 | 124 | 37 | 151 |
| basse | 6 | 20 | 646 | 3 | 2 |
| drums | 4 | 11 | 5 | 975 | 8 |
| fx | 9 | 10 | 0 | 0 | 361 |

## Sorte (sons dont on la connaît : 7350)

- Sorte juste (parmi celles de la famille décidée) : **76.6 %**
- Sorte donnée (nette) : 82.7 % des sons, juste dans **84.0 %** des cas ; sinon le mot général de la famille (ou, pour des drums et des mélodies, la sorte trouvée par l'app sans l'IA)

| Sorte | Sons | Bien nommés | Le plus souvent pris pour |
|---|---|---|---|
| Voix | 419 | 94.5 % | Ambiance |
| Voix lead | 1159 | 79.1 % | Ambiance |
| Chœur | 198 | 93.4 % | Ambiance |
| Adlib | 803 | 69.2 % | Voix lead |
| Ambiance | 80 | 91.2 % | Voix lead |
| Lead | 36 | 0.0 % | Basse |
| Pluck | 128 | 74.2 % | Perc |
| Pad | 130 | 76.9 % | FX |
| Keys | 333 | 22.2 % | Bell |
| Piano | 106 | 90.6 % | FX |
| Arp | 96 | 95.8 % | Fill |
| Chords | 198 | 74.7 % | Basse |
| Guitare | 387 | 44.7 % | Keys |
| Strings | 327 | 85.6 % | FX |
| Bell | 143 | 67.8 % | Basse |
| Flûte | 190 | 67.4 % | Mélodie |
| Brass | 254 | 73.6 % | FX |
| Orgue | 442 | 81.4 % | FX |
| Mélodie | 121 | 78.5 % | Flûte |
| 808 | 100 | 90.0 % | Sub |
| Sub | 100 | 98.0 % | 808 |
| Basse | 477 | 91.2 % | Orgue |
| Kick | 102 | 74.5 % | Tom |
| Snare | 118 | 72.0 % | Rim |
| Clap | 3 | 33.3 % | Rim |
| Rim | 12 | 91.7 % | Adlib |
| Snap | 1 | 0.0 % | Hi-hat |
| Hi-hat | 130 | 76.9 % | Snap |
| Open Hat | 4 | 25.0 % | Hi-hat |
| Perc | 21 | 71.4 % | Rim |
| Tom | 9 | 66.7 % | Kick |
| Shaker | 55 | 96.4 % | Hi-hat |
| Crash | 3 | 0.0 % | Hi-hat |
| Ride | 2 | 50.0 % | Perc |
| Cymbal | 2 | 50.0 % | Riser |
| Drum loop | 216 | 86.1 % | Fill |
| Fill | 65 | 87.7 % | Drum loop |
| Riser | 22 | 100.0 % | — |
| Downlifter | 18 | 100.0 % | — |
| Impact | 17 | 100.0 % | — |
| Sweep | 12 | 100.0 % | — |
| FX | 311 | 93.6 % | Chœur |

## Sorte par source

| Source | Sons | Sorte juste |
|---|---|---|
| 808 | 100 | 90.0 % |
| accord | 175 | 65.7 % |
| accords-synth | 50 | 86.0 % |
| arp | 96 | 95.8 % |
| basse-synth | 100 | 89.0 % |
| batterie | 312 | 68.6 % |
| boucle | 50 | 100.0 % |
| cymbale-envers | 3 | 100.0 % |
| fx | 100 | 100.0 % |
| groove-boucle | 166 | 81.9 % |
| groove-fill | 65 | 87.7 % |
| hihat-synth | 100 | 86.0 % |
| librispeech | 247 | 100.0 % |
| medley-instrument | 411 | 91.2 % |
| medley-voix | 311 | 76.8 % |
| note-envers | 277 | 92.8 % |
| nsynth | 1984 | 63.3 % |
| pad | 100 | 100.0 % |
| pad-note | 30 | 0.0 % |
| phrase | 213 | 70.9 % |
| pluck | 78 | 80.8 % |
| pluck-synth | 50 | 64.0 % |
| shaker-synth | 50 | 100.0 % |
| sub | 100 | 98.0 % |
| vibrato | 81 | 54.3 % |
| vocalset | 367 | 98.1 % |
| voix-ambiance | 80 | 91.2 % |
| voix-choeur | 98 | 94.9 % |
| voix-choeur+reverb | 100 | 92.0 % |
| voix-chop | 90 | 68.9 % |
| voix-chop+pitch | 92 | 66.3 % |
| voix-chop+reverb | 83 | 48.2 % |
| voix-hachee | 452 | 73.0 % |
| voix-pitch | 96 | 90.6 % |
| voix-pitch+reverb | 91 | 51.6 % |
| voix-reverb | 100 | 39.0 % |
| voix-reverse | 92 | 90.2 % |
| voix-reverse+reverb | 89 | 46.1 % |
| voix-saturate | 99 | 88.9 % |
| voix-stutter | 86 | 73.3 % |
| voix-telephone | 86 | 95.3 % |

## Packs de batterie du propriétaire jamais entendus (essai du 24/10, avant l'apprentissage livré)
Le modèle livré a appris tous les packs que le propriétaire a donnés ; pour savoir ce qu'il vaut sur des packs
inconnus, un essai (une seule tête) a d'abord été appris sans deux d'entre eux (un pack de fills et de boucles, un
pack de boucles trap), puis noté sur leurs sons (la moitié B : 25 boucles, 17 fills).

| Sons | Famille (Drums) | Sorte juste | Avant les boucles et fills trap fabriqués |
|---|---|---|---|
| Boucles | 72 % (28 % prises pour des voix) | 48 % | 64 % (36 % voix), sorte 52 % |
| Fills (courts, 1 à 2 s) | 82 % | 35 % | 76 %, sorte 12 % |

Les boucles trap clairsemées (rolls de hats, beaucoup de vide) passent encore souvent pour des voix hachées, et un
fill court ressemble à une boucle d'une mesure : dans l'app, le nom du son (« Fill », « Loop ») et la boucle mesurée
(grave d'un kick + aigus) passent avant l'IA. Exiger deux tranches « voix » au lieu d'une pour un son long a été
essayé : voix 98 % au lieu de 96 %, mais boucles 64 % au lieu de 72 % ; pas retenu.
