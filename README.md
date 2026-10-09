# FL Shortcut

Tes propres raccourcis clavier pour **FL Studio**, sur **Mac** et **Windows**.

FL Studio n'a pas d'éditeur de raccourcis. FL Shortcut en ajoute un : quand FL Studio est au premier plan, il reconnaît tes raccourcis et :

- **déclenche une action dans FL** grâce à un petit script MIDI authentifié : ouvrir le Mixer, mute ou solo de la piste, pattern suivant, métronome, rétablir… (38 actions) ;
- ou **envoie une touche de FL** : il déplace un raccourci existant sur une touche plus pratique.

> Outil indépendant, non affilié à Image-Line. « FL Studio » est une marque d'Image-Line.

| | Mac | Windows |
|---|---|---|
| Système | macOS 13 ou plus récent (Liquid Glass sur macOS 26) | Windows 10 (1809+) ou 11, x64 ou ARM64 |
| FL Studio | 20.7 → 2025 et suivants (actions grisées si ta version est trop ancienne) | idem |
| Où vit l'appli | barre des menus | zone de notification |
| Pause | `⌃⌥⌘F` | `Ctrl+Alt+Maj+F` |

---

## Installation

### Mac

1. Ouvre `FLShortcut.dmg` et glisse **FL Shortcut** dans **Applications**, puis lance-le.
   La version publiée est signée et notarisée par Apple : aucune manipulation de sécurité n'est nécessaire. **Si macOS affiche un avertissement, ne le contourne pas** : télécharge l'appli depuis la page officielle des versions et compare l'empreinte SHA-256 fournie.
2. **Autoriser le clavier** : l'accueil ouvre *Réglages Système › Confidentialité et sécurité › Accessibilité*. Active FL Shortcut.
3. **Relier FL Studio** : clique sur *Installer le lien*, redémarre FL, puis dans *Options › MIDI Settings* :
   - *Input* « FL Shortcut » : **Enable**, *Controller type* « FL Shortcut » ;
   - *Output* « FL Shortcut » : même numéro de port.

   Le statut passe à « FL Studio est relié ». *Tester* ouvre le Mixer.

### Windows

Le détail est dans [windows/README.md](windows/README.md). En bref :

1. Installe [loopMIDI](https://www.tobias-erichsen.de/software/loopmidi.html) (gratuit) et crée deux ports nommés exactement `FL Shortcut` et `FL Shortcut Retour`. L'accueil les détecte tout seul.
2. Clique sur *Installer le lien*. Dans FL Studio, *Options › MIDI Settings*, configure :
   - *Input* « FL Shortcut » : **Enable**, *Controller type* « FL Shortcut » ;
   - *Output* « FL Shortcut Retour » : même numéro de port.
3. Ne lance pas FL Studio en administrateur.

---

## Profils fournis

Le profil **Recommandé** n'écrase aucun raccourci de FL. Tu peux changer de profil à tout moment (c'est annulable), en importer un ou exporter le tien.

| Action | Mac | Windows |
|---|---|---|
| Playlist, Channel Rack, Piano Roll, Mixer, Browser | `⌃1` … `⌃5` | `Ctrl+Maj+1` … `5` |
| Pattern précédent / suivant | `⌃D` / `⌃F` | `Ctrl+Maj+D` / `F` |
| Mute / Solo de la piste du Mixer | `⌃T` / `⌃S` | `Ctrl+Maj+T` / `G` |
| Métronome | `⌃M` | `Ctrl+Maj+K` |
| Rétablir | `⇧⌘Z` | `Ctrl+Y` |

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
| Script FL (tests) | `python3 -m unittest discover -s tests/python` | partout (Python 3.6+) |
| Cœur Windows (tests) | `dotnet test windows/FLShortcut.Core.Tests` | partout (.NET 8) |
| App Mac | `./build.sh` | Mac avec Xcode 16+ (Xcode 26 pour le Liquid Glass natif) |
| App Windows | `dotnet publish windows/FLShortcut.App -c Release -r win-x64 -p:Platform=x64` | Windows avec .NET 8 |

**Sans Mac ni PC de développement :** pousse le dépôt sur GitHub. Le workflow [build.yml](.github/workflows/build.yml) :
- lance tous les tests ;
- compile le `.dmg` universel et les `.zip` Windows x64 / ARM64, avec leurs empreintes SHA-256 et une attestation de provenance ;
- publie une *Release* à chaque tag `v*`.

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
tests/python/                    tests du script FL (simulateur de l'API FL)
audit/                           rapports d'audit et de relecture
build.sh                         compilation, signature et notarisation Mac
```

**Ajouter une action FL :** donne-lui l'id suivant dans [PROTOCOL.md](PROTOCOL.md) §6, puis ajoute-la à ces trois endroits :
- `ACTIONS` dans `device_FLShortcut.py` ;
- `Actions.swift` ;
- `windows/FLShortcut.Core/Actions.cs`.

Les tests vérifient que les trois listes concordent. Les fonctions disponibles sont dans la [documentation de l'API Python de FL Studio](https://il-group.github.io/FL-Studio-API-Stubs/).
