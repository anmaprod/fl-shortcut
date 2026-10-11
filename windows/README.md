# FL Shortcut pour Windows

Même fonctionnement que la version Mac : FL Shortcut vit dans la zone de notification, et quand FL Studio est au premier plan il transforme tes raccourcis en **actions dans FL** (via un script MIDI authentifié) ou en **touches de FL**.

## Installation (utilisateurs)

1. Télécharge **`FLShortcut-Windows-Setup.exe`** (page des versions du projet) et double-clique dessus. Aucun droit administrateur, x64 et ARM dans le même fichier.
2. FL Shortcut se lance et se range dans la zone de notification. Il démarre avec Windows (décochable).
3. **Ne lance pas FL Studio en administrateur** : Windows empêcherait FL Shortcut d'agir (l'appli te prévient).

Rien à faire dans FL Studio : en **mode léger** (par défaut), FL Shortcut n'envoie que les touches d'origine de FL. Les actions sans touche dans FL (mute / solo de piste, volume, rétablir…) sont grisées.

`Ctrl+Alt+Maj+F` (dans FL Studio) ou le menu de l'icône met FL Shortcut en pause.

### Mode MIDI (facultatif)

Pour les 40 actions, mets `"MidiActions": true` dans `%LOCALAPPDATA%\FL Shortcut\settings.json`, relance l'appli, puis :
1. installe [loopMIDI](https://www.tobias-erichsen.de/software/loopmidi.html) et crée deux ports nommés exactement `FL Shortcut` et `FL Shortcut Retour` ;
2. clique sur « Installer le lien » ; dans FL Studio, *Options › MIDI Settings* : *Input* `FL Shortcut` → **Enable**, *Controller type* **FL Shortcut** ; *Output* `FL Shortcut Retour` → même numéro de port.

### Profil recommandé (rien n'écrase FL)

| Raccourci | Action |
|---|---|
| `Ctrl+Maj+1` … `5` | Playlist, Channel Rack, Piano Roll, Mixer, Browser |
| `Ctrl+Maj+D` / `F` | Pattern précédent / suivant |
| `Ctrl+Maj+T` / `G` | Mute / Solo de la piste du Mixer |
| `Ctrl+Maj+K` | Métronome |
| `Ctrl+Y` | Rétablir |

Jamais de `Ctrl+Alt` (c'est AltGr : `@`, `€`, `{`…), ni de `Win+…`, ni de `Alt+lettre`.

## Structure

```
windows/
  FLShortcut.Core/         cœur portable (aucune dépendance Windows) : protocole HMAC, modèle, profils,
                           routeur de touches, liste noire, conflits — miroir de la version Mac
  FLShortcut.Core.Tests/   tests xUnit (vecteur de PROTOCOL.md, profils, routeur…) — tournent sous Linux/macOS
  FLShortcut.App/          appli WinUI 3 (Mica, Fluent) : hook clavier, injection, MIDI (WinMM), installeur
```

## Compiler

- Tests du cœur (n'importe quel système avec .NET 8) : `dotnet test windows/FLShortcut.Core.Tests`
- Appli (Windows 10/11 avec .NET 8) : `dotnet publish windows/FLShortcut.App -c Release -r win-x64 -p:Platform=x64`

- Installeur (Windows avec Inno Setup 6) : `iscc windows\installer\FLShortcut.iss`

Le workflow GitHub (`.github/workflows/build.yml`) fait tout et publie l'installeur et les `.zip` x64 / ARM64 avec leurs empreintes SHA-256.

## Sécurité (audit 03 et 01)

- Hook clavier installé **seulement** quand FL Studio est au premier plan ; aucune frappe n'est conservée ni journalisée.
- FL Studio identifié par le chemin de l'exécutable **et** la signature Authenticode d'Image-Line (WinVerifyTrust).
- Avant chaque injection, FL est revérifié au premier plan ; Alt+F4, Alt+Tab, Win+…, Ctrl+Alt+… sont interdits comme cibles, y compris dans un profil importé.
- Les actions passent par des trames MIDI signées (HMAC-SHA256, nonce, anti-rejeu) : un autre logiciel qui écrit sur le port ne peut rien déclencher.
- Clé protégée par DPAPI (utilisateur courant), écritures atomiques, liens symboliques et jonctions refusés, empreinte du script installé vérifiée.
- L'appli ne s'élève jamais (`asInvoker`).

## À vérifier sur un vrai PC

- Création automatique des ports via Windows MIDI Services (Windows 11 24H2+) au lieu de loopMIDI.
- Signature Authenticode de FL64.exe : texte exact du sujet du certificat (« Image-Line »).
- Comportement du hook avec les claviers AZERTY (AltGr) et les touches Fn des portables.
