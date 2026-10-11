# FL Shortcut

Tes propres raccourcis clavier pour **FL Studio**, sur **Mac** et **Windows**.

FL Studio n'a pas d'éditeur de raccourcis. FL Shortcut en ajoute un : quand FL Studio est au premier plan, il reconnaît tes raccourcis et envoie à FL **ses propres touches** (Mixer, Playlist, REC, métronome, pattern suivant…). **Rien à installer dans FL** : pas de script, pas de MIDI, pas de loopMIDI.

- **Macros** (Mac, version de test) : *Enregistrement rapide* charge un état de piste du Mixer, arme la piste, choisit l'entrée et lance le REC, d'un seul raccourci. Voir [MACROS.md](MACROS.md).
- **Mode MIDI** (facultatif, pour les utilisateurs avancés) : 38 actions via un script authentifié (mute / solo de piste, volume…). Désactivé par défaut.

> Outil indépendant, non affilié à Image-Line. « FL Studio » est une marque d'Image-Line.

| | Mac | Windows |
|---|---|---|
| Système | macOS 13 ou plus récent (Liquid Glass sur macOS 26) | Windows 10 (1809+) ou 11, x64 ou ARM64 |
| FL Studio | 20.7 → 2025 et suivants (actions grisées si ta version est trop ancienne) | idem |
| Où vit l'appli | barre des menus | zone de notification |
| Pause | `⌃⌥⌘F` | `Ctrl+Alt+Maj+F` |

---

## Installation

**Télécharge la dernière version** sur la [page des versions](../../releases/latest) (ou la page de téléchargement du projet, qui choisit le bon fichier toute seule).

### Mac : `FLShortcut.dmg`

1. Ouvre `FLShortcut.dmg` et glisse **FL Shortcut** dans **Applications**, puis lance-le. Il s'installe dans la barre des menus.
2. **Autoriser le clavier** : clique sur *Autoriser…* ; l'appli ouvre *Réglages Système › Confidentialité et sécurité › Accessibilité*. Active FL Shortcut.

C'est tout. Si macOS dit qu'il ne peut pas vérifier l'appli (version non notarisée) : *Réglages Système › Confidentialité et sécurité*, tout en bas, **Ouvrir quand même**. Fais-le seulement pour un fichier venu de la page officielle des versions, dont l'empreinte SHA-256 correspond.

Pour désinstaller : *Désinstaller FL Shortcut* dans le menu de l'appli, ou l'appli du même nom dans le `.dmg`.

### Windows : `FLShortcut-Windows-Setup.exe`

1. Double-clique sur l'installeur, puis **Installer**. Aucun droit administrateur demandé, x64 et ARM dans le même fichier.
2. FL Shortcut se lance et se range dans la zone de notification. Il démarre avec Windows (décochable dans l'installeur).

C'est tout. Si Windows affiche « Windows a protégé votre ordinateur » (installeur non signé) : **Informations complémentaires › Exécuter quand même**. Désinstallation : *Paramètres › Applications*. Une version portable (`.zip`) existe aussi. Ne lance pas FL Studio en administrateur.

---

## Profils fournis

Le profil **Recommandé** n'écrase aucun raccourci de FL. Tu peux changer de profil à tout moment (c'est annulable), en importer un ou exporter le tien.

| Action | Mac | Windows |
|---|---|---|
| Playlist, Channel Rack, Piano Roll, Mixer, Browser | `⌃1` … `⌃5` | `Ctrl+Maj+1` … `5` |
| Pattern précédent / suivant | `⌃D` / `⌃F` | `Ctrl+Maj+D` / `F` |
| Mute / Solo de la piste du Mixer (mode MIDI seulement) | `⌃T` / `⌃S` | `Ctrl+Maj+T` / `G` |
| Métronome | `⌃M` | `Ctrl+Maj+K` |
| Rétablir (mode MIDI seulement) | `⇧⌘Z` | `Ctrl+Y` |

- **Style Ableton** ajoute `Tab` (Playlist ↔ Mixer), `0` (mute) et pattern précédent / suivant (`⌃⌥←/→` sur Mac, `Ctrl+Maj+←/→` sur Windows). Ce profil contient des touches seules.
- **Vide** part de zéro.

Sur Windows, on évite `Ctrl+Alt` : c'est AltGr sur les claviers AZERTY (`@`, `€`, `{`…). L'appli prévient quand un raccourci :
- entre en conflit avec FL ;
- est déjà pris ;
- est une touche seule ;
- demande une version de FL plus récente.

### Limites connues

- Mute et Solo agissent sur la piste du Mixer sélectionnée. L'API de FL ne donne pas accès aux clips sélectionnés de la Playlist.
- Les raccourcis s'appliquent aussi dans les fenêtres de plugins de FL. En cas de conflit, mets FL Shortcut en pause.
- Une touche seule (sans modificateur) ne peut plus servir à taper du texte dans FL. L'appli demande confirmation.

---

## Macros (sans MIDI)

Une **macro** enchaîne des clics et des touches dans FL, avec le même principe sûr que le mode léger : aucun script, aucun port MIDI, rien d'écrit dans FL. Les événements ne vont qu'au processus FL, et seulement quand il est au premier plan. Échap interrompt la macro.

Modèle livré, **Enregistrement rapide** (fiche d'un raccourci › Type › Macro) :

1. clic droit sur la piste du Mixer sous la souris, puis *File › Open mixer track state* ;
2. preset : la liste de FL s'ouvre et la macro attend ton choix, ou un preset (.fst) est choisi une fois dans FL Shortcut et chargé directement ;
3. armement de la piste et première entrée (positions apprises une fois, en cliquant dans FL) ;
4. REC allumé à la fin (facultatif).

Détails, limites et mode d'emploi du diagnostic (`FLShortcut --diag-macro`) : [MACROS.md](MACROS.md).

---

## Sécurité et vie privée

- Le clavier n'est observé **que quand FL Studio est au premier plan**. Aucune frappe n'est enregistrée, journalisée ni envoyée. L'appli n'utilise pas le réseau.
- Les actions passent par des **trames MIDI signées** (HMAC-SHA256, nonce, anti-rejeu, limite de débit, liste blanche des 38 actions). Un autre logiciel qui écrit sur le port ne peut rien déclencher. Le protocole est décrit dans [PROTOCOL.md](PROTOCOL.md).
- La clé est rangée dans le **Trousseau** (Mac) ou protégée par **DPAPI** (Windows).
- Les écritures de fichiers sont atomiques, et les liens symboliques sont refusés. L'empreinte du script installé est vérifiée, et un script modifié est signalé.
- Les touches dangereuses (`⌘Q`, `Alt+F4`, `Win+…`…) sont refusées comme cibles, y compris dans un profil importé.
- Les audits complets sont dans [audit/](audit/) : sécurité, fiabilité, compatibilité des versions, ergonomie et relectures.

---

## Compiler

| | Commande | Où |
|---|---|---|
| Script FL (tests) | `python3 -m unittest discover -s Tests/python` | partout (Python 3.6+) |
| Cœur Windows (tests) | `dotnet test windows/FLShortcut.Core.Tests` | partout (.NET 8) |
| App Mac | `./build.sh` | Mac avec Xcode 16+ (Xcode 26 pour le Liquid Glass natif) |
| App Windows | `dotnet publish windows/FLShortcut.App -c Release -r win-x64 -p:Platform=x64` | Windows avec .NET 8 |
| Installeur Windows | `iscc /DAppVersion=1.0.0 /DDistDir=…\dist windows\installer\FLShortcut.iss` | Windows avec Inno Setup 6 |

**Sans Mac ni PC de développement :** pousse le dépôt sur GitHub. Le workflow [build.yml](.github/workflows/build.yml) :
- lance tous les tests ;
- compile le `.dmg` universel, l'installeur Windows (`FLShortcut-Windows-Setup.exe`, x64 + ARM64) et les `.zip` portables, avec leurs empreintes SHA-256 et une attestation de provenance ;
- publie une *Release* à chaque tag `v*` (`git tag v1.0.0 && git push --tags`) ; les liens « latest » de la page de téléchargement suivent tout seuls.

**Page de téléchargement :** `site/index.html`, publiée par [pages.yml](.github/workflows/pages.yml) (à activer une fois : *Settings › Pages › Source : GitHub Actions*). Elle propose le bon fichier selon l'ordinateur du visiteur.

**Distribution sans avertissement :**
- **Mac** : il faut un compte Apple Developer. Ensuite, `SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=… ./build.sh` signe, notarise et agrafe le ticket.
- **Windows** : il faut un certificat de signature de code (Authenticode), ou une publication via le Microsoft Store.

---

## Structure

```
Resources/device_FLShortcut.py   script MIDI côté FL Studio (Python 3.6+, FL 20.7 → 2025+)
PROTOCOL.md                      contrat commun : trames, HMAC, table des 38 actions
Sources/FLShortcut/              app Mac (SwiftUI) : interception (EventTap), routeur, MIDI (CoreMIDI),
                                 Trousseau, interface Liquid Glass (GlassStyle, EditorView, OnboardingView)
Tests/FLShortcutTests/           tests XCTest
windows/FLShortcut.Core/         cœur Windows portable (protocole, modèle, profils, routeur)
windows/FLShortcut.Core.Tests/   tests xUnit
windows/FLShortcut.App/          app WinUI 3 (Mica, Fluent 2) : hook clavier, injection, MIDI WinMM, DPAPI
Tests/python/                    tests du script FL (simulateur de l'API FL)
audit/                           rapports d'audit et de relecture
build.sh                         compilation, signature et notarisation Mac
```

**Ajouter une action FL :** donne-lui l'id suivant dans [PROTOCOL.md](PROTOCOL.md) §6, puis ajoute-la à ces trois endroits :
- `ACTIONS` dans `device_FLShortcut.py` ;
- `Actions.swift` ;
- `windows/FLShortcut.Core/Actions.cs`.

Les tests vérifient que les trois listes concordent. Les fonctions disponibles sont dans la [documentation de l'API Python de FL Studio](https://il-group.github.io/FL-Studio-API-Stubs/).
