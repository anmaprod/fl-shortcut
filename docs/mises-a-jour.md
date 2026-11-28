# Mises à jour toutes seules

Depuis le 19/11, FL Shortcuts se corrige tout seul chez les gens, sur Mac et sur Windows, sans réinstaller.

## Ce que fait l'app

- Au lancement, puis toutes les 6 heures, elle regarde la dernière version publiée sur GitHub
  (`releases/latest/download/mise-a-jour.json`).
- Si elle est plus récente, elle la télécharge en fond et la vérifie : signature du fichier (clé de FL Shortcuts),
  empreinte SHA-256 du téléchargement, et sur Mac le même certificat que l'app.
- Elle l'installe **seulement quand FL Studio est fermé et qu'aucune fenêtre de FL Shortcuts n'est ouverte**, puis se
  relance d'elle-même dans la barre des menus (Mac) ou près de l'horloge (Windows).
- Seules les versions publiées le font. Une version d'essai (téléchargée depuis une vérification de la branche) ne se
  remplace jamais toute seule.

## À faire une fois : trois secrets dans GitHub

GitHub › le dépôt › Settings › Secrets and variables › Actions › **New repository secret**, trois fois :

| Nom | Contenu |
| --- | --- |
| `UPDATE_SIGNING_KEY` | la clé qui signe les mises à jour (bloc « BEGIN EC PRIVATE KEY ») |
| `MAC_SELF_CERT_P12` | le certificat de FL Shortcuts pour le Mac (une longue ligne) |
| `MAC_SELF_CERT_PASSWORD` | son mot de passe |

Les valeurs sont dans le fichier que Claude t'a donné. Colle-les, puis supprime ce fichier. Elles ne vont jamais
dans le dépôt.

- Sans `UPDATE_SIGNING_KEY`, une publication s'arrête avec une erreur (les apps ne verraient pas la version).
- Avec `MAC_SELF_CERT_P12`, toutes les versions Mac ont la même signature : macOS garde les autorisations
  (Accessibilité, Enregistrement de l'écran) d'une mise à jour à l'autre, et d'une version d'essai à l'autre.

## Publier une version

Dis à Claude « publie ». Il pose un tag `vX.Y.Z` (version suivante) sur la branche et l'envoie. La vérification GitHub
fabrique tout, puis crée la release avec :

- `FLShortcuts.pkg` et `FLShortcuts-Windows-Setup.exe` (première installation),
- `FLShortcuts-mac.zip` (l'app Mac pour les mises à jour),
- `mise-a-jour.json` et `mise-a-jour.json.sig` (ce que lisent les apps).

## La toute première fois

Les versions installées avant le 19/11 n'ont pas ce système : il faut installer **une fois** à la main la première
version publiée (le .pkg ou le .exe). Ensuite, plus jamais. Sur Mac, cette première version demande de redonner les
autorisations une dernière fois (elle a la nouvelle signature).

## Où c'est dans le code

- Mac : `Sources/FLShortcut/AutoUpdate.swift` (`UpdateRules` pur, testé dans `AutoUpdateTests.swift`) ; `build.sh`
  (`FLSUpdates`, signature par le certificat stable, `FLShortcuts-mac.zip`).
- Windows : `windows/FLShortcut.Core/AutoUpdate.cs` (testé dans `AutoUpdateTests.cs`) et
  `windows/FLShortcut.App/Services/AutoUpdateWin.cs` ; installeur `FLShortcut.iss` (`/UPDATE=1` relance l'appli).
- CI : `.github/workflows/build.yml` (job Mac : `MAC_SELF_CERT_*` ; job « Publication » : fichier signé).
- Journal : lignes `UPDATE` (versions seulement).
