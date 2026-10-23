# Résultats de l'IA intégrée

Sons de validation B : 4115 (jamais entendus à l'apprentissage). Seuil des voix : 0.7.

- Justesse de la famille : **93.1 %**
- Voix reconnues : **94.0 %** (YAMNet seul, ses classes de voix ≥ 0,5 : 66.4 %)
- Autres sons pris pour des voix : **1.7 %** (YAMNet seul : 0.3 %)

## Par source

| Source | Sons | Famille attendue | Bien classés | Pris pour des voix |
|---|---|---|---|---|
| 808 | 100 | basse | 100.0 % | 0.0 % |
| accord | 36 | melodie | 86.1 % | 5.6 % |
| accords-synth | 50 | melodie | 98.0 % | 0.0 % |
| arp | 32 | melodie | 96.9 % | 0.0 % |
| basse-synth | 100 | basse | 99.0 % | 0.0 % |
| batterie | 584 | drums | 96.9 % | 0.2 % |
| boucle | 50 | drums | 100.0 % | 0.0 % |
| cymbale-envers | 7 | fx | 85.7 % | 0.0 % |
| fx | 100 | fx | 100.0 % | 0.0 % |
| hihat-synth | 100 | drums | 100.0 % | 0.0 % |
| librispeech | 244 | voix | 100.0 % | 100.0 % |
| note-envers | 102 | fx | 86.3 % | 5.9 % |
| nsynth | 721 | melodie | 83.4 % | 3.5 % |
| pad | 100 | melodie | 100.0 % | 0.0 % |
| phrase | 44 | melodie | 93.2 % | 4.5 % |
| pluck-synth | 50 | melodie | 84.0 % | 0.0 % |
| shaker-synth | 50 | drums | 100.0 % | 0.0 % |
| sub | 100 | basse | 100.0 % | 0.0 % |
| vibrato | 29 | melodie | 79.3 % | 10.3 % |
| vocalset | 367 | voix | 100.0 % | 100.0 % |
| voix-ambiance | 70 | voix | 100.0 % | 100.0 % |
| voix-choeur | 58 | voix | 98.3 % | 98.3 % |
| voix-choeur+reverb | 64 | voix | 100.0 % | 100.0 % |
| voix-chop | 53 | voix | 88.7 % | 88.7 % |
| voix-chop+pitch | 71 | voix | 78.9 % | 78.9 % |
| voix-chop+reverb | 60 | voix | 90.0 % | 90.0 % |
| voix-hachee | 301 | voix | 80.7 % | 80.7 % |
| voix-pitch | 70 | voix | 100.0 % | 100.0 % |
| voix-pitch+reverb | 56 | voix | 98.2 % | 98.2 % |
| voix-reverb | 65 | voix | 100.0 % | 100.0 % |
| voix-reverse | 54 | voix | 100.0 % | 100.0 % |
| voix-reverse+reverb | 58 | voix | 100.0 % | 100.0 % |
| voix-saturate | 60 | voix | 100.0 % | 100.0 % |
| voix-stutter | 53 | voix | 66.0 % | 66.0 % |
| voix-telephone | 56 | voix | 100.0 % | 100.0 % |

## Confusion des familles (lignes : attendu ; colonnes : décidé)

| | voix | melodie | basse | drums | fx |
|---|---|---|---|---|---|
| voix | 1655 | 42 | 10 | 32 | 21 |
| melodie | 32 | 811 | 20 | 7 | 69 |
| basse | 0 | 16 | 406 | 0 | 1 |
| drums | 1 | 5 | 7 | 766 | 5 |
| fx | 6 | 7 | 1 | 1 | 194 |

## Sorte (sons dont on la connaît : 3871)

- Sorte juste (parmi celles de la famille décidée) : **76.5 %**
- Sorte donnée (nette) : 84.6 % des sons, juste dans **83.5 %** des cas ; sinon le mot général de la famille (ou, pour des drums et des mélodies, la sorte trouvée par l'app sans l'IA)

| Sorte | Sons | Bien nommés | Le plus souvent pris pour |
|---|---|---|---|
| Voix | 402 | 94.8 % | Ambiance |
| Voix lead | 628 | 83.9 % | Ambiance |
| Chœur | 122 | 86.9 % | Ambiance |
| Adlib | 538 | 54.6 % | Voix |
| Ambiance | 70 | 94.3 % | Voix lead |
| Pluck | 50 | 84.0 % | Perc |
| Pad | 100 | 100.0 % | — |
| Keys | 163 | 6.7 % | Guitare |
| Arp | 32 | 96.9 % | Basse |
| Chords | 82 | 85.4 % | Strings |
| Guitare | 84 | 57.1 % | Bell |
| Strings | 123 | 89.4 % | FX |
| Flûte | 63 | 4.8 % | FX |
| Brass | 85 | 57.6 % | FX |
| Orgue | 157 | 81.5 % | Ambiance |
| 808 | 100 | 94.0 % | Sub |
| Sub | 100 | 99.0 % | 808 |
| Basse | 223 | 88.3 % | Brass |
| Kick | 118 | 81.4 % | Tom |
| Snare | 118 | 71.2 % | Kick |
| Clap | 5 | 20.0 % | Rim |
| Rim | 9 | 66.7 % | Hi-hat |
| Snap | 2 | 0.0 % | Snare |
| Hi-hat | 135 | 76.3 % | Snap |
| Perc | 32 | 46.9 % | Rim |
| Tom | 7 | 42.9 % | Kick |
| Shaker | 54 | 96.3 % | Rim |
| Crash | 3 | 0.0 % | Snare |
| Ride | 3 | 33.3 % | Riser |
| Cymbal | 4 | 25.0 % | Clap |
| Drums | 50 | 100.0 % | — |
| Riser | 26 | 96.2 % | Ride |
| Downlifter | 15 | 100.0 % | — |
| Impact | 16 | 100.0 % | — |
| Sweep | 19 | 100.0 % | — |
| FX | 133 | 88.0 % | Orgue |
