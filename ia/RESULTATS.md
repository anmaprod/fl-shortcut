# Résultats de l'IA intégrée

Sons de validation B : 6837 (jamais entendus à l'apprentissage). Seuil des voix : 0.34.

- Justesse de la famille : **91.8 %**
- Voix reconnues : **97.6 %** (YAMNet seul, ses classes de voix ≥ 0,5 : 61.5 %)
- Autres sons pris pour des voix : **2.2 %** (YAMNet seul : 0.2 %)

## Par famille (objectif : 99 %)

| Famille | Sons | Bien classés |
|---|---|---|
| voix | 2360 | 97.6 % |
| melodie | 2640 | 84.4 % |
| basse | 693 | 93.5 % |
| drums | 784 | 96.6 % |
| fx | 360 | 94.2 % |

## Par source

| Source | Sons | Famille attendue | Bien classés | Pris pour des voix |
|---|---|---|---|---|
| 808 | 100 | basse | 100.0 % | 0.0 % |
| accord | 175 | melodie | 93.1 % | 1.1 % |
| accords-synth | 50 | melodie | 88.0 % | 0.0 % |
| arp | 116 | melodie | 96.6 % | 0.0 % |
| basse-synth | 100 | basse | 99.0 % | 0.0 % |
| batterie | 584 | drums | 95.5 % | 0.9 % |
| boucle | 50 | drums | 98.0 % | 2.0 % |
| cymbale-envers | 7 | fx | 57.1 % | 28.6 % |
| fx | 100 | fx | 100.0 % | 0.0 % |
| hihat-synth | 100 | drums | 100.0 % | 0.0 % |
| librispeech | 244 | voix | 100.0 % | 100.0 % |
| medley-instrument | 78 | melodie | 82.1 % | 17.9 % |
| medley-voix | 218 | voix | 100.0 % | 100.0 % |
| note-envers | 253 | fx | 92.9 % | 3.6 % |
| nsynth | 2087 | melodie | 83.3 % | 2.3 % |
| pad | 100 | melodie | 100.0 % | 0.0 % |
| pad-note | 22 | melodie | 36.4 % | 0.0 % |
| phrase | 213 | melodie | 93.0 % | 1.4 % |
| pluck | 58 | melodie | 75.9 % | 3.4 % |
| pluck-synth | 50 | melodie | 86.0 % | 0.0 % |
| shaker-synth | 50 | drums | 100.0 % | 0.0 % |
| sub | 100 | basse | 100.0 % | 0.0 % |
| vibrato | 84 | melodie | 75.0 % | 15.5 % |
| vocalset | 367 | voix | 100.0 % | 100.0 % |
| voix-ambiance | 86 | voix | 100.0 % | 100.0 % |
| voix-choeur | 77 | voix | 100.0 % | 100.0 % |
| voix-choeur+reverb | 84 | voix | 98.8 % | 98.8 % |
| voix-chop | 74 | voix | 95.9 % | 95.9 % |
| voix-chop+pitch | 80 | voix | 92.5 % | 92.5 % |
| voix-chop+reverb | 77 | voix | 93.5 % | 93.5 % |
| voix-hachee | 414 | voix | 92.8 % | 92.8 % |
| voix-pitch | 93 | voix | 100.0 % | 100.0 % |
| voix-pitch+reverb | 70 | voix | 98.6 % | 98.6 % |
| voix-reverb | 80 | voix | 100.0 % | 100.0 % |
| voix-reverse | 76 | voix | 100.0 % | 100.0 % |
| voix-reverse+reverb | 82 | voix | 100.0 % | 100.0 % |
| voix-saturate | 79 | voix | 100.0 % | 100.0 % |
| voix-stutter | 81 | voix | 86.4 % | 86.4 % |
| voix-telephone | 78 | voix | 100.0 % | 100.0 % |

## Confusion des familles (lignes : attendu ; colonnes : décidé)

| | voix | melodie | basse | drums | fx |
|---|---|---|---|---|---|
| voix | 2303 | 23 | 13 | 17 | 4 |
| melodie | 74 | 2228 | 191 | 20 | 127 |
| basse | 8 | 37 | 648 | 0 | 0 |
| drums | 6 | 6 | 8 | 757 | 7 |
| fx | 11 | 7 | 1 | 2 | 339 |

## Sorte (sons dont on la connaît : 6593)

- Sorte juste (parmi celles de la famille décidée) : **77.2 %**
- Sorte donnée (nette) : 83.0 % des sons, juste dans **84.3 %** des cas ; sinon le mot général de la famille (ou, pour des drums et des mélodies, la sorte trouvée par l'app sans l'IA)

| Sorte | Sons | Bien nommés | Le plus souvent pris pour |
|---|---|---|---|
| Voix | 402 | 95.8 % | Ambiance |
| Voix lead | 985 | 86.5 % | Ambiance |
| Chœur | 161 | 91.9 % | Ambiance |
| Adlib | 726 | 71.2 % | Voix lead |
| Ambiance | 86 | 94.2 % | Voix lead |
| Lead | 41 | 2.4 % | Basse |
| Pluck | 108 | 76.9 % | Perc |
| Pad | 122 | 84.4 % | FX |
| Keys | 342 | 15.8 % | Piano |
| Piano | 81 | 93.8 % | FX |
| Arp | 116 | 95.7 % | Basse |
| Chords | 198 | 75.8 % | Bell |
| Guitare | 301 | 38.2 % | Basse |
| Strings | 259 | 85.7 % | FX |
| Bell | 147 | 65.3 % | Basse |
| Flûte | 175 | 68.0 % | Mélodie |
| Brass | 185 | 65.9 % | FX |
| Orgue | 469 | 81.9 % | FX |
| Mélodie | 96 | 75.0 % | Flûte |
| 808 | 100 | 94.0 % | Sub |
| Sub | 100 | 100.0 % | — |
| Basse | 493 | 89.0 % | Lead |
| Kick | 118 | 79.7 % | Tom |
| Snare | 118 | 72.9 % | Rim |
| Clap | 5 | 40.0 % | Rim |
| Rim | 9 | 55.6 % | Hi-hat |
| Snap | 2 | 0.0 % | Snare |
| Hi-hat | 135 | 83.0 % | Snap |
| Perc | 32 | 65.6 % | Rim |
| Tom | 7 | 57.1 % | Kick |
| Shaker | 54 | 96.3 % | Hi-hat |
| Crash | 3 | 0.0 % | Hi-hat |
| Ride | 3 | 0.0 % | Riser |
| Cymbal | 4 | 75.0 % | Hi-hat |
| Drums | 50 | 98.0 % | Adlib |
| Riser | 26 | 88.5 % | Adlib |
| Downlifter | 15 | 100.0 % | — |
| Impact | 16 | 100.0 % | — |
| Sweep | 19 | 100.0 % | — |
| FX | 284 | 93.0 % | Flûte |
