# FL Remap 🎹

Personnalise les raccourcis clavier de **FL Studio sur Mac**.
FL Remap vit dans la barre des menus, intercepte tes touches quand FL Studio est au premier plan, et :

- **envoie un autre raccourci** à FL (ex. `Q` → `⌥M`),
- ou **déclenche directement une action FL** via un petit script MIDI (afficher le Mixer, mute la piste sélectionnée, rétablir, métronome…), même si elle n'a pas de raccourci d'origine.

> Outil indépendant, non affilié à Image-Line.

---

## Pour les utilisateurs

1. Ouvre `FLRemap.dmg` et glisse **FL Remap** dans **Applications**.
2. Premier lancement : clic droit sur l'app › **Ouvrir** (l'app n'est pas notarisée par Apple, macOS demande une confirmation une seule fois).
3. Autorise FL Remap dans **Réglages Système › Confidentialité et sécurité › Accessibilité**.
4. Clique sur **Installer le script FL Studio** (proposé au premier lancement, ou depuis le menu ⌨︎).
5. Dans FL Studio : **Options › MIDI Settings** → dans *Input*, sélectionne **FL Remap**, clique sur **Enable**, puis choisis **FL Remap** dans *Controller type*.
6. Menu ⌨︎ › **Modifier les raccourcis…** pour créer tes raccourcis.

`⌃⌥⌘F` active ou désactive tous les raccourcis, par exemple pour renommer une piste sans déclencher un remap.

### Raccourcis par défaut (style Ableton)

| Raccourci | Action |
|---|---|
| `⌘⇧Z` | Rétablir |
| `Tab` | Basculer Playlist ↔ Mixer |
| `0` | Mute de la piste du Mixer / du canal sélectionné |
| `⌃1` … `⌃5` | Playlist, Channel Rack, Piano Roll, Mixer, Browser |
| `⌃M` | Métronome |
| `⌃L` | Mode Pattern ↔ Song |
| `⌃←` / `⌃→` | Pattern précédent / suivant |

### Limites connues

- Mute / Solo ne marchent que dans le Mixer et le Channel Rack (l'API de FL ne donne pas accès aux clips sélectionnés de la Playlist).
- Les remaps s'appliquent aussi dans les fenêtres de plugins de FL. En cas de conflit, utilise `⌃⌥⌘F`.
- Les touches sont enregistrées par position physique : un profil créé sur un clavier AZERTY peut afficher d'autres lettres sur un clavier QWERTY.

---

## Pour construire l'app

**Option A : sur un Mac avec Xcode**

```bash
./build.sh
```

Le script produit `dist/FL Remap.app` et `dist/FLRemap.dmg` (app universelle Apple Silicon + Intel).

**Option B : sans Xcode, via GitHub**

1. Crée un dépôt GitHub et pousse ce dossier.
2. L'onglet **Actions** construit le `.dmg` à chaque push (téléchargeable dans l'artefact *FLRemap-dmg*).
3. Pousse un tag (`git tag v0.1.0 && git push --tags`) pour publier le `.dmg` dans une **Release**, avec un lien à partager.

### Distribuer sans avertissement Gatekeeper

Il faut un compte Apple Developer (99 $/an) :

```bash
SIGN_IDENTITY="Developer ID Application: Ton Nom (TEAMID)" ./build.sh
xcrun notarytool submit dist/FLRemap.dmg --apple-id … --team-id … --wait
xcrun stapler staple dist/FLRemap.dmg
```

Pour la signature, ajoute aussi `--options runtime` à la commande `codesign` dans `build.sh`.

---

## Structure

```
Sources/FLRemap/
  FLRemapApp.swift        app barre des menus, premier lancement, permissions
  EditorView.swift        éditeur de raccourcis (enregistrement des touches)
  EventTap.swift          interception clavier (CGEventTap)
  MIDIOut.swift           port MIDI virtuel « FL Remap »
  Model.swift             raccourcis, actions FL, sauvegarde du profil
  KeyNames.swift          noms des touches selon la disposition (AZERTY…)
  FLScriptInstaller.swift installe le script dans FL Studio
Resources/
  device_FLRemap.py       script MIDI côté FL Studio
  Info.plist
build.sh                  construit l'app et le .dmg
```

**Ajouter une action FL :** ajoute un `case` dans `FLAction` (`Model.swift`) avec un nouveau numéro de CC, puis la même entrée dans `ACTIONS` (`device_FLRemap.py`). La [documentation de l'API Python de FL Studio](https://il-group.github.io/FL-Studio-API-Stubs/) liste ce qui est possible.

Le profil de chaque utilisateur est sauvegardé dans `~/Library/Application Support/FL Remap/profile.json`.
