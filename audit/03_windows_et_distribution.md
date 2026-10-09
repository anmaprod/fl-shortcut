# Audit 03 — Modèle de menaces Windows et chaîne de distribution (Mac + Windows)

Audit offensif mandaté par le propriétaire du logiciel, daté du 8 octobre 2026.
Cibles :
- **Version Windows à venir.** Elle n'est pas encore codée. Le document en fixe donc les exigences de conception.
- **Chaîne de distribution existante :** `.github/workflows/build.yml`, `build.sh`, le README (instructions de distribution) et le script `Resources/device_FLShortcut.py`, commun aux deux plateformes.
- **Mises à jour automatiques à venir :** Sparkle sur Mac, et sur Windows MSIX/App Installer, Microsoft Store, WinGet ou Velopack.

Ce document complète `01_securite_mac.md`, dont les identifiants SEC-xx sont repris quand une faille Mac a son équivalent Windows.

---

## 1. Résumé

FL Shortcut est un **keylogger légitime** : il voit toutes les frappes du système, peut en avaler et en injecter, démarre avec la session et se met à jour seul. Pour un attaquant, c'est une cible à forte valeur, pour trois raisons :

- **Hôte de confiance.** Un binaire signé, mis en liste blanche par l'antivirus et autorisé à poser un hook clavier, est idéal pour cacher un vrai keylogger, par injection de DLL ou par une mise à jour piégée.
- **Canal d'injection vers FL Studio.** Le port MIDI virtuel et le script Python chargé par FL ne sont pas authentifiés.
- **Chaîne d'approvisionnement fragile.** La seule voie de distribution actuelle est un `.dmg` non signé, produit par une CI non durcie.

### Constats majeurs

| # | Constat | IDs |
|---|---|---|
| 1 | **Chaîne de build actuelle non durcie.** Actions épinglées par tag mutable, dont une action tierce (`softprops/action-gh-release@v2`) qui tourne avec `contents: write`. Jeton en écriture pour *tous* les déclenchements, identifiants git persistés, aucune protection des tags. Aucune signature (Developer ID ad hoc), aucune notarisation, aucune empreinte, aucune provenance. Le README apprend aux utilisateurs à contourner Gatekeeper. Un faux `FLShortcut.dmg` est donc indiscernable du vrai. | SUP-01 à SUP-08 |
| 2 | **Mises à jour automatiques = exécution de code à distance par conception.** Sans signature indépendante du transport (EdDSA Sparkle + flux signé ; signature MSIX/Authenticode avec éditeur épinglé), sans protection contre la rétrogradation et avec un compte GitHub non verrouillé, une compromission du dépôt ou du serveur suffit à pousser un keylogger signé à toute la base installée. | SUP-11, SUP-12, WIN-18 |
| 3 | **Windows : le hook doit être cantonné par construction.** Il faut l'installer seulement quand FL Studio est au premier plan, identifier FL par chemin et signature (pas par nom), ne jamais conserver de frappes, et refuser toute élévation (pas d'`uiAccess`, pas de service, pas de tâche « privilèges les plus élevés »). Sinon le produit sera à la fois classé keylogger par les EDR et réellement exploitable comme tel. | WIN-01 à WIN-05, WIN-12 |
| 4 | **Le port MIDI est pire sous Windows que sous Mac.** Avec loopMIDI (port loopback), *n'importe quel* processus local, y compris un navigateur via Web MIDI, peut écrire dans le port « FL Shortcut » et piloter FL. Un « virtual device » de Windows MIDI Services isole mieux : seule l'appli propriétaire du device émet vers les clients. | WIN-13, WIN-14 |
| 5 | **Le script FL est du code exécuté dans FL depuis un dossier inscriptible.** `Documents\…\Hardware\FL Shortcut\` est souvent synchronisé par OneDrive. Un `midi.py` déposé à côté du script peut en masquer les modules. L'appli doit vérifier l'intégrité du dossier (empreinte plus liste des fichiers), pas seulement celle du fichier. | WIN-10, WIN-11 |

### Recommandations structurantes pour la v1 Windows

1. **Empaquetage MSIX**, distribué en priorité par le **Microsoft Store**. L'inscription est gratuite pour les développeurs individuels depuis septembre 2025, et le Store re-signe les paquets MSIX : pas de certificat à acheter, pas d'alerte SmartScreen. Pour le sideload, utiliser un `.appinstaller` sur HTTPS signé via Azure Artifact Signing (si éligible) ou un certificat OV sur HSM. MSIX apporte gratuitement un répertoire d'installation protégé en écriture (`WindowsApps`), la vérification d'intégrité par block map, le refus des rétrogradations et une désinstallation propre.
2. **Hook à la demande :** `SetWindowsHookEx(WH_KEYBOARD_LL)` seulement tant que FL est au premier plan, puis `UnhookWindowsHookEx` dès qu'il ne l'est plus.
3. **Windows MIDI Services** (virtual device) comme transport par défaut, loopMIDI en repli documenté. Côté script, ajouter une liste blanche d'actions inoffensives et une limitation de débit.
4. **CI :** épinglage par SHA (avec la politique d'organisation qui l'impose), `permissions: {}` par défaut, jobs de signature dans un *environment* protégé, provenance attestée, releases immuables. Les corrections prêtes à appliquer sont en section 7.

---

## 2. Périmètre, actifs et modèle d'attaquant

### Actifs à protéger

| Actif | Pourquoi il compte |
|---|---|
| Frappes clavier de l'utilisateur | Mots de passe, messages. Le hook les voit *toutes*, pas seulement dans FL. |
| Intégrité des projets FL | Undo en boucle, enregistrement par-dessus, mute/solo, et sous Windows `FPT_Save` (sauvegarde) atteignable par le script. |
| Matériel MIDI connecté | Le script FL peut envoyer du SysEx vers les sorties MIDI (`device.midiOutSysex`), et du SysEx peut écraser des presets ou des firmwares de synthés. |
| Identité de signature (Developer ID, Authenticode, clé EdDSA) | La voler, c'est pouvoir livrer un malware « officiel ». |
| Canal de mise à jour | Exécution de code sur toute la base installée. |
| Réputation (SmartScreen, Defender, Smart App Control) | Un seul faux positif massif ou une seule compromission la détruit. |

### Attaquants considérés

| Code | Attaquant | Capacités | Dans le périmètre ? |
|---|---|---|---|
| A1 | Réseau (Wi-Fi public, proxy, FAI) | MITM HTTP, DNS | Oui (mises à jour, téléchargement de dépendances) |
| A2 | Site web visité | Web MIDI (avec permission), liens `ms-appinstaller:`/`flshortcut:`, faux sites de téléchargement | Oui |
| A3 | Processus local **même utilisateur, intégrité moyenne** (malware déjà présent) | Écrit dans `%APPDATA%`, `Documents`, `%LOCALAPPDATA%` ; peut poser son propre hook et appeler `SendInput` | **Partiellement.** On ne peut pas l'empêcher d'agir, mais FL Shortcut ne doit **pas l'amplifier** : pas d'hôte signé à détourner, pas de chemin d'élévation, pas de pont vers l'admin. |
| A4 | Processus local **à intégrité inférieure** (onglet de navigateur sandboxé, AppContainer) | Ne peut ni écrire dans les dossiers utilisateur ni faire de `SendInput` vers medium | Oui. FL Shortcut ne doit pas être un pont, via son port MIDI, une IPC ou un localhost. |
| A5 | Contenu partagé (profil JSON, script « amélioré » téléchargé sur un forum) | Ingénierie sociale | Oui |
| A6 | Chaîne d'approvisionnement (action GitHub compromise, dépendance NuGet ou SwiftPM, compte mainteneur) | Exécution dans la CI, accès aux secrets, publication | Oui |
| A7 | Administrateur local / noyau | Tout | Non (hors périmètre) |

**Principe directeur :** FL Shortcut ne doit jamais posséder un privilège que l'utilisateur n'a pas déjà, ni l'offrir à un tiers moins privilégié. Tout le reste en découle : pas d'élévation, pas d'`uiAccess`, pas de service, pas d'IPC ouverte, pas de port MIDI inscriptible par tous.

### Architecture Windows cible (frontières de confiance)

```
           ┌──────────────── Session utilisateur (intégrité moyenne) ────────────────┐
 Clavier ─▶│ [Hook LL] ──▶ FLShortcut.exe (WinUI 3, MSIX, WindowsApps en lecture seule)│
           │     │  identifie FL : HWND → PID → chemin image + signataire Image-Line │
           │     ├─▶ SendInput (combinaison de remplacement) ──▶ FL64.exe            │
           │     └─▶ MIDI CC ch.16 ─▶ [Windows MIDI Services virtual device       ]│
           │                          [ ou loopMIDI : port loopback ouvert à tous ]│──▶ FL64.exe
           │ Profils : %APPDATA% (virtualisé MSIX)    Script : Documents\Image-Line\…│      └─ device_FLShortcut.py
           │                                           (inscriptible, souvent OneDrive)
           └──────────────────────────────────────────────────────────────────────────┘
 Internet ─▶ mises à jour (Store / .appinstaller HTTPS / WinGet)   ◀── CI GitHub (signature)
```

---

## 3. Tableau des menaces

Gravité = impact × vraisemblance, en supposant la contre-mesure absente.

### 3.1 Windows (WIN-xx)

| ID | Gravité | Scénario d'attaque | Impact | Contre-mesure concrète |
|---|---|---|---|---|
| **WIN-01** | **Critique** | Le hook `WH_KEYBOARD_LL` reçoit **toutes** les frappes de la session. Trois façons d'en abuser : une DLL injectée dans FLShortcut.exe (WIN-06/07), une mise à jour piégée (WIN-18), ou une dérive du code (journal de débogage oublié, télémétrie « d'usage des raccourcis »). Il suffit alors de lire `KBDLLHOOKSTRUCT.vkCode` hors de FL pour avoir un keylogger signé. | Vol de mots de passe et de messages sur toute la base installée | Hook installé **seulement** quand FL est au premier plan (`SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` → `SetWindowsHookEx`/`UnhookWindowsHookEx`). Rappel sans allocation, sans E/S, sans file : il consulte un `HashSet<(vk, mods)>` immuable puis rend la main. Interdiction outillée (analyseur Roslyn ou test) de toute écriture, de tout log et de toute capture de `vkCode` dans l'assembly du hook. Aucune API d'enregistrement de séquence. L'éditeur de raccourcis capture les touches via la fenêtre de l'appli (`KeyDown` WinUI), pas via le hook. |
| **WIN-02** | Haute | Profil comportemental « keylogger » : `SetWindowsHookEx` LL, `SendInput`, démarrage automatique, icône de notification, accès réseau, binaire peu répandu. Les EDR et Defender (ML + cloud), SmartScreen et **Smart App Control** (Windows 11) bloquent ou mettent en quarantaine. Un attaquant peut aussi publier un clone malveillant nommé « FL Shortcut » pour faire mal réputer le vrai. | Produit inutilisable ; signalements ; perte de réputation | Signer **tous** les PE (exe, dll natives, assemblies) avec une identité stable et horodater. Pas de packer, d'obfuscation ni de bundle auto-extractible. Pas de `GetAsyncKeyState` en boucle, pas d'accès au presse-papiers. Hook à la demande (WIN-01). Avant chaque release : passage VirusTotal et, en cas de détection, soumission à Microsoft (portail WDSI, « software developer »). Publication du code source et d'une page « Pourquoi FL Shortcut utilise un hook clavier ». Distribution Store ou MSIX signé pour profiter de la réputation. Garder le même éditeur d'une release à l'autre : la réputation SmartScreen s'accumule par éditeur ; l'EV ne donne plus d'avantage depuis 2024. |
| **WIN-03** | Haute | **Course au premier plan.** Le hook décide « FL est devant », puis `SendInput` part un peu plus tard. Entre les deux, une autre fenêtre prend le focus : notification de messagerie, fenêtre de connexion, ou fenêtre malveillante qui se place exprès au premier plan. La combinaison injectée (Ctrl+S, Alt+F4, Ctrl+W, Suppr…) arrive dans la mauvaise application. Équivalent de SEC-03 sur Mac. | Action destructrice hors de FL ; fermeture de documents, envoi de messages | 1) Capturer le `HWND`/PID de FL au moment de la décision, revérifier `GetForegroundWindow()` **immédiatement** avant `SendInput`, abandonner en cas d'écart. 2) Un seul `SendInput` atomique par combinaison (les événements d'un même appel ne sont pas entrelacés avec d'autres entrées, selon la doc Microsoft). 3) **Liste noire de cibles** non contournable par profil : Alt+F4, Win+*, Ctrl+Alt+*, Ctrl+Échap, Alt+Tab, Ctrl+Maj+Échap. 4) Privilégier le chemin MIDI, qui ne se trompe jamais de fenêtre, pour toute action disponible dans le script. 5) Piste à tester : `PostMessage(WM_KEYDOWN)` ciblé sur la fenêtre FL, sans erreur de destinataire, mais avec un risque sur les modificateurs (`GetKeyState`). |
| **WIN-04** | Moyenne | Détection de FL par nom d'exécutable (`FL64.exe`) ou par titre de fenêtre (« FL Studio »). Un programme quelconque nommé `FL64.exe`, ou une fenêtre intitulée « FL Studio – … », reçoit les remaps et les injections. Équivalent de SEC-04. | Injection dans un processus non prévu ; contournement de WIN-03 | `GetWindowThreadProcessId` → `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageNameW`. Puis vérification Authenticode (`WinVerifyTrust`) et du nom du signataire (Image-Line), avec un cache par (PID, heure de création du processus). Vérification complémentaire de la classe de fenêtre principale. Les fenêtres de plugins pontés (processus de pont d'Image-Line) se valident de la même façon, par signataire. |
| **WIN-05** | Haute (si mal traité) | **FL lancé en administrateur.** Certains utilisateurs le font pour « réparer » des plugins. UIPI bloque alors `SendInput` vers FL *silencieusement* (la doc indique que ni la valeur de retour ni `GetLastError` ne signalent un blocage UIPI). D'après la FAQ UAC d'AutoHotkey, les hooks d'un processus non élevé ne voient pas non plus les frappes destination élevée. **Contre-mesure :** ne jamais s'élever (`asInvoker`, pas d'`uiAccess`) ; détecter un FL élevé (`OpenProcess` refusé ou jeton `TokenElevation`) et l'afficher clairement (« Relance FL Studio normalement »), sans installer le hook. **Statut : corrigé** (`FlPresence.Identify`, `AppController.UpdateStatus`, `app.manifest`). |

> **Note de reprise (9 octobre 2026).** L'agent auteur a été interrompu au milieu de WIN-05. La suite du rapport a été complétée par la session principale, à partir des constats déjà listés au §1 et du code écrit depuis (`windows/`, `PROTOCOL.md`). Chaque ligne indique le **statut** dans le code actuel.

| ID | Gravité | Menace | Contre-mesure | Statut |
|---|---|---|---|---|
| **WIN-06** | Critique | Injection de DLL dans FLShortcut.exe (processus qui détient un hook clavier) pour en faire un keylogger. | Signature Authenticode de tous les binaires ; installation dans un dossier protégé en écriture (MSIX → `WindowsApps`) ; aucun chargement de plugin ou de DLL depuis un dossier inscriptible ; `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32)` au démarrage. | **À faire** : `SetDefaultDllDirectories` dans `App()` et empaquetage MSIX. |
| **WIN-07** | Haute | Détournement de l'ordre de recherche des DLL (DLL plantée à côté de l'exe dans `Téléchargements`). | Distribution MSIX ou installeur vers `%ProgramFiles%` ; binaire auto-contenu (`WindowsAppSDKSelfContained`) ; pas de `.zip` exécuté depuis Téléchargements dans la doc utilisateur. | **Partiel** : auto-contenu fait ; MSIX à faire. |
| **WIN-08** | Moyenne | Liens symboliques / jonctions dans les dossiers de profil, de clé ou du script (écriture redirigée). | Refus des liens sur le fichier et ses 3 dossiers parents ; fichier temporaire dans le même dossier puis remplacement atomique. | **Corrigé** (`SafeFile`). |
| **WIN-09** | Moyenne | Démarrage automatique détourné (clé `Run` modifiée par un tiers pour lancer un autre exe). | Démarrage via la tâche de démarrage MSIX (`StartupTask`) ou clé `HKCU\…\Run` pointant vers le chemin protégé, vérifiée au lancement. Jamais de service ni de tâche « privilèges les plus élevés ». | **À faire** (pas encore de démarrage automatique). |
| **WIN-10** | Haute | Script FL modifié par un autre logiciel pour exécuter du Python dans FL. | Empreinte SHA-256 du script vérifiée ; réinstallation proposée. | **Corrigé** (`ScriptInstaller.IsIntact`, Mac : `ScriptIntegrity`). |
| **WIN-11** | Haute | Fichier Python déposé à côté du script (`transport.py`, `midi.py`) qui masque un module de FL. | Le dossier `Hardware\FL Shortcut\` ne doit contenir que notre script : tout autre fichier ou dossier rend l'état « modifié ». | **Corrigé** (Windows et Mac). |
| **WIN-12** | Haute | Élévation demandée « pour que ça marche avec FL en admin », ou `uiAccess`, ou service système. | Jamais : `asInvoker`, avertissement à la place (WIN-05). | **Corrigé** (`app.manifest`). |
| **WIN-13** | Critique | Port de bouclage loopMIDI accessible à tout processus local, y compris un navigateur (Web MIDI) : injection de commandes dans FL. | Trames signées HMAC-SHA256 avec nonce de session et anti-rejeu, liste blanche d'actions, limitation de débit côté script (PROTOCOL.md). Un processus sans la clé ne peut rien déclencher. | **Corrigé** (script FL + `MidiLink`). |
| **WIN-14** | Moyenne | Faux statut « Relié » (HELLO forgé sur le port retour) ; déni de service par flot MIDI. | Le statut ne donne aucun droit : les actions restent signées. File de réception bornée (4 096 messages), rappel WinMM sans verrou, PING limité. | **Corrigé** (`MidiLink`). |
| **WIN-15** | Moyenne | Vol de la clé du lien. | Clé chiffrée par DPAPI (utilisateur courant), dans `%LOCALAPPDATA%` (non itinérant), régénérée à chaque réinstallation. | **Corrigé** (`SecretStore`). |
| **WIN-16** | Haute | Profil importé malveillant (cibles Alt+F4, Win+R…). | Liste noire non contournable appliquée à l'import, au chargement et juste avant chaque injection ; récapitulatif et confirmation avant import. | **Corrigé** (`ProfileImporter`, `ForbiddenTargets`, `KeyboardHook.DoInject`). |
| **WIN-17** | Moyenne | Vie privée : journalisation accidentelle de frappes, télémétrie. | Aucun journal ni télémétrie ; le rappel du hook ne copie que le code de touche et les modificateurs. Toute télémétrie future : désactivée par défaut, consentement explicite, sans frappes. | **Corrigé** (aucun journal dans le code). |
| **WIN-18** | Critique | Mise à jour automatique piégée (serveur ou dépôt compromis). | MSIX + App Installer ou Store (signature de l'éditeur épinglée, refus des rétrogradations) ; pas de mécanisme maison. | **À faire** à la publication. |

### 3.2 Chaîne d'approvisionnement (SUP-xx)

| ID | Gravité | Menace | Contre-mesure | Statut |
|---|---|---|---|---|
| **SUP-01** | Haute | Actions GitHub épinglées par tag mutable. | Épinglage par SHA de commit + Dependabot. | **Corrigé** (`build.yml`, `dependabot.yml`). |
| **SUP-02** | Haute | Action tierce de publication avec `contents: write`. | Remplacée par `gh release create` (outil officiel). | **Corrigé**. |
| **SUP-03** | Haute | Jeton en écriture pour tous les déclenchements. | `permissions: contents: read` par défaut ; écriture limitée au job `release` (tags `v*`). | **Corrigé**. |
| **SUP-04** | Moyenne | Identifiants git conservés dans les jobs. | `persist-credentials: false` partout. | **Corrigé**. |
| **SUP-05** | Critique | Binaires non signés (Mac ad hoc, Windows rien). | Mac : Developer ID + Hardened Runtime + notarisation (`build.sh`) ; Windows : Authenticode (Azure Artifact Signing si éligible, sinon certificat OV) ou Store. | **Partiel** : Mac prêt (secrets à fournir) ; Windows à faire. |
| **SUP-06** | Moyenne | Aucune empreinte publiée. | `.sha256` publié avec chaque release, vérifié avant publication. | **Corrigé**. |
| **SUP-07** | Moyenne | Aucune provenance. | `actions/attest-build-provenance` sur le `.dmg`. | **Corrigé** (Mac) ; à ajouter pour les `.zip` Windows. |
| **SUP-08** | Moyenne | Le README apprend à contourner Gatekeeper. | Retirer cette consigne dès que l'app est notarisée. | **À faire** à la première release signée. |
| **SUP-09** | Moyenne | Tags et branche principale non protégés. | Règles de protection : `main` (revue obligatoire), tags `v*` réservés aux mainteneurs, releases immuables. | **À faire** dans les réglages GitHub. |
| **SUP-10** | Moyenne | Secrets de signature exposés à tous les jobs. | Secrets dans un *environment* GitHub protégé (validation manuelle) utilisé par le seul job de signature. | **À faire** au moment d'ajouter les secrets. |
| **SUP-11** | Critique | Sparkle (Mac) sans signature EdDSA ni flux signé. | Si Sparkle est ajouté : clé EdDSA, `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`, flux HTTPS. | **À faire** (pas de mise à jour automatique pour l'instant). |
| **SUP-12** | Haute | Compte GitHub du mainteneur compromis. | Double authentification par clé de sécurité, jetons à portée minimale, alertes de connexion. | **À faire** (compte du propriétaire). |

## 4. Check-list v1 Windows

- [x] Hook installé seulement quand FL (identifié par chemin + signature) est au premier plan ; aucune frappe conservée.
- [x] Injection : FL revérifié juste avant `SendInput`, un seul appel atomique, marque `dwExtraInfo`, liste noire.
- [x] Trames MIDI signées (HMAC, nonce, anti-rejeu) ; statut « Relié » sans aucun droit associé.
- [x] Clé DPAPI ; écritures atomiques ; liens et jonctions refusés ; dossier du script vérifié (WIN-11).
- [x] `asInvoker`, FL administrateur signalé ; instance unique.
- [x] CI : SHA épinglés, permissions minimales, empreintes ; tests du cœur sous Linux, compilation x64 et ARM64.
- [ ] `SetDefaultDllDirectories` au démarrage (WIN-06).
- [ ] Empaquetage MSIX et distribution Store ou App Installer signé (WIN-06/07/18, SUP-05).
- [ ] Création des ports par Windows MIDI Services (au lieu de loopMIDI) — à tester sur Windows 11 24H2+.
- [ ] Réglages GitHub : protections, environment de signature, double authentification (SUP-09/10/12).

## 5. Corrections déjà appliquées à `build.yml` et `build.sh`

Voir le dépôt : `build.sh` (Hardened Runtime, notarisation, empreinte, pas de `--deep`) et `.github/workflows/build.yml` (jobs `script-fl`, `windows-core`, `windows`, `mac`, `release`). Les SHA des actions ont été relevés le 8 octobre 2026 par l'agent auteur avant son interruption.
