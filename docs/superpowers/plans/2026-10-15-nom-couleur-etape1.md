# Étape 1 : lien avec données + bloc « Nom et couleur » — plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** une macro peut nommer et colorer l'élément sélectionné de la page de FL qui est devant (Mixer, Channel rack,
Playlist), par le lien avec FL.

**Architecture :** la trame authentifiée existante (CC 104–111) porte l'action 41 ; elle est précédée de données
(CC 96 début, CC 97 unités de 7 bits) que son MAC couvre. Le script décode l'opération 1, vérifie la page et la
sélection, applique, et explique un refus par le CC 116 avant l'accusé 0. Côté Mac, un nouveau bloc envoie ces données
et traduit la réponse en message.

**Tech Stack :** Swift 5.9 (SwiftUI, CryptoKit, CoreMIDI), script Python de FL, XCTest, unittest.

**Spec :** `docs/superpowers/specs/2026-10-15-nom-couleur-organiser-design.md` (§4, §5 ; étape 1 de §9).

## Global Constraints

- Français partout (interface, commentaires, messages, commits) ; identifiants JSON en ASCII, stables.
- Swift 5.9, macOS 13 minimum, pas de `@Observable` ; aucun travail au repos ; jamais l'écran.
- Le nom tapé n'apparaît jamais dans un journal (`MacroLog`, hints de FL) : journal = `nameColor`.
- Actions 1 à 40 et leurs tests inchangés ; la table §6 de PROTOCOL.md reste identique (le test Python la relit).
- Script : `SCRIPT_VERSION = 4`, `PROTOCOL_VERSION` reste 2 (une appli ancienne garde le lien).
- Commits : message en français, terminé par
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` et
  `Claude-Session: https://claude.ai/code/session_015cWn3nRUmsQoCfPZgGBtCt` ; push sur `claude/relaxed-mayer-ndguzv`.
- Pas de compilateur Swift en local : la CI (macOS) compile et teste ; les tests Python tournent en local.

## Review Focus

1. Nom avec accents et emoji (« Café 🎹 ») : octets UTF-8 sur plusieurs unités, relus à l'identique par le script
   (test Task 1 `test_name_utf8_roundtrip`).
2. Nom fait seulement d'espaces : bloc invalide, rien n'est envoyé (test Task 3 `testNameColorValidation`).
3. Données à moitié envoyées (CC 96 sans trame), puis une action normale : l'action normale marche, le tampon est
   vidé (test Task 1 `test_leftover_data_does_not_leak`).
4. Trame 41 sans données, ou données de plus de 600 unités : refus, raison 5, rien d'appliqué (test Task 1
   `test_data_frame_without_or_oversized_data`).
5. Playlist devant avec une API < 12 (pas de `playlist.isTrackSelected`) : raison 1, aucune exception (test Task 1
   `test_playlist_needs_api12`).

---

### Task 1 : script FL — données, action 41, opération 1

**Files :**
- Modify : `Resources/device_FLShortcut.py` (constantes en tête, `_State`, `_midi_msg`, `_on_frame_cc`,
  `_process_frame`, `capability_mask`, `_PROTOCOL_CCS`/`_COMMAND_CCS`)
- Modify : `Tests/python/fl_mocks.py` (fonctions de nom, couleur, sélection ; `utils.RGBToColor` ; `mac_for` et
  `frame` acceptent des unités)
- Modify : `Tests/python/test_device_flshortcut.py` (nouvelle classe `TestData` ; attentes du masque)
- Modify : `PROTOCOL.md` (nouveau §7)

**Interfaces :**
- Produces (contrat lu par Task 2) : CC 96 = début des données (valeur ignorée, vide le tampon) ; CC 97 = une unité ;
  action `DATA_ACTION_ID = 41` ; MAC = `HMAC(clé, nonce ‖ seq(3) ‖ 41 ‖ unités)` ; `MAX_DATA_UNITS = 600` ;
  CC 116 = raison (1 page, 2 rien de sélectionné, 3 plusieurs, 4 FL joue, 5 données invalides) envoyée juste avant
  `CC_ACK 0` ; bit 41 du masque = données disponibles.
- Empaquetage 7 bits : par groupe de 7 octets, une unité d'en-tête (bit j = bit 7 de l'octet j), puis les 7 bits bas
  de chaque octet. Opération 1 : `[1, drapeaux (bit0 nom, bit1 couleur), R, G, B, n, nom UTF-8 (n octets)]`.

- [ ] **Step 1 : tests qui échouent** — dans `TestData(Base)` :
  - `test_vector` : `pack7([1,3,0xE0,0x45,0x3A,4] + list(b"Kick")) == [4,1,3,96,69,58,4,75,0,105,99,107]` et
    `M.mac_for([17,42,99,5], 300, 41, units=…) == [116,112,71,62]`.
  - `test_name_and_color_on_selected_mixer_track` : `focused={0}`, une seule piste sélectionnée (3) ; données
    nom « Kick » + couleur E0453A ; accusé 41 ; `mixer.setTrackName` appelé avec `(3, "Kick")`,
    `mixer.setTrackColor` avec `(3, utils.RGBToColor(0xE0,0x45,0x3A))`.
  - `test_channel_rack_and_playlist` : même chose sur le canal sélectionné (`focused={1}`) et la piste de Playlist
    sélectionnée (`focused={2}`, index de 1 à `trackCount()`).
  - `test_color_only_and_name_only` : drapeaux 2 → seule la couleur ; drapeaux 1 → seul le nom.
  - `test_refusals` : rien sélectionné → CC 116 = 2 puis accusé 0 ; deux sélectionnés → 3 ; Piano roll devant
    (`focused={3}`) → 1 ; aucune fonction `set*` appelée.
  - `test_name_utf8_roundtrip` (Review Focus 1), `test_leftover_data_does_not_leak` (3),
    `test_data_frame_without_or_oversized_data` (4 : sans CC 96 → 5 ; 601 unités → 5), `test_playlist_needs_api12` (5).
  - `test_bad_mac_over_data` : unités modifiées après signature → refus (`mac`), rien appliqué.
  - `test_data_ignored_while_asleep` : endormi, les CC 96/97 ne remplissent aucun tampon.
  - Masque : dans `TestCapabilities`, `test_api45_all_actions` attend `set(ALL_IDS) | {41}` ; les tests par API
    attendent 41 seulement si `ui.getFocused` et les fonctions de nom/couleur du Mixer existent.
- [ ] **Step 2 :** `python3 -m unittest discover -s Tests/python -v` → les nouveaux tests échouent.
- [ ] **Step 3 : implémenter.** Tampon `_st.data` (liste ou `None`) : CC 96 le crée vide, CC 97 ajoute (au-delà de
  600 : tampon marqué invalide), tout CC 104 de début de trame ne le touche pas, il est vidé (`None`) après chaque
  trame complète, au sommeil et à chaque PING. Dans `_process_frame`, si `aid == 41` (pas dans `ACTION_BY_ID`) :
  MAC sur `nonce ‖ f[0:4] ‖ unités`, puis `_run_data(bytes)` ; sinon chemin actuel inchangé. `_run_data` :
  `unpack7`, opération 1, page par `focused_window_code()` (0, 1 ou 2, sinon raison 1), comptage des sélectionnés
  (Mixer `0..trackCount-1`, canaux `0..channelCount-1`, Playlist `1..trackCount`), application par
  `setTrackName/setChannelName/…` et `utils.RGBToColor` (sinon `(B << 16) | (G << 8) | R`). Nom : UTF-8 décodé,
  64 caractères au plus, sans caractère < 0x20, sinon raison 5. Aucun nom dans `_hint`/`_log`.
  `capability_mask()` met le bit 41 si `_data_available()`. CC 96, 97 dans `_COMMAND_CCS`, 116 dans `_PROTOCOL_CCS`.
  `SCRIPT_VERSION = 4`.
- [ ] **Step 4 :** relancer les tests Python → tous passent (anciens compris).
- [ ] **Step 5 : PROTOCOL.md §7** « Commande avec données (script v4) » : CC 96/97, empaquetage, MAC, opération 1,
  CC 116, vecteur de test ci-dessus. Lignes de tableau commençant par `| op 1 |` (jamais `| 1 | mot |` : le test
  relit les lignes `| id | clé |` du §6).
- [ ] **Step 6 : commit** « Lien avec FL : commande avec données (action 41) et opération Nom et couleur dans le
  script (v4) ».

### Task 2 : appli — envoi des données et lecture de la raison

**Files :**
- Modify : `Sources/FLShortcut/FLProtocol.swift` (constantes, `Pack7`, `FrameSigner`, `FrameEncoder`,
  `IncomingDecoder`, `IncomingEvent`)
- Modify : `Sources/FLShortcut/MIDILink.swift` (`LinkCore`, `MIDILink`)
- Create : `Sources/FLShortcut/NameColor.swift` (`RGBColor`, `NameColorPayload`)
- Test : `Tests/FLShortcutTests/ProtocolTests.swift`

**Interfaces :**
- Consumes : contrat de Task 1.
- Produces :
  - `FLProtocol.ccDataStart: UInt8 = 96`, `ccDataUnit: UInt8 = 97`, `ccReason: UInt8 = 116`,
    `dataActionID = 41`, `maxDataUnits = 600`.
  - `enum Pack7 { static func pack(_ bytes: [UInt8]) -> [UInt8]; static func unpack(_ units: [UInt8]) -> [UInt8]? }`
  - `FrameSigner.mac(nonce: [UInt8], seq: UInt32, action: UInt8, data: [UInt8]) -> [UInt8]`
  - `FrameEncoder.dataFrame(seq: UInt32, units: [UInt8], nonce: [UInt8], signer: FrameSigner) -> [CCMessage]?`
    (CC 96, puis un CC 97 par unité, puis les 8 CC de la trame avec l'action 41 ; `nil` si plus de 600 unités).
  - `IncomingEvent.reason(Int)`.
  - `enum DataReply: Equatable { case done; case refused(Int); case failed(String) }`
  - `LinkCore.runData(_ units: [UInt8], brief: Bool, timeout: TimeInterval) -> DataReply` et
    `MIDILink.runData(_ units: [UInt8]) -> DataReply` (même réveil que `runBriefly`, bit 41 exigé sinon
    `.failed("mets à jour le lien avec FL : redémarre FL")`, attend l'accusé 41 ou la raison + accusé 0, 1,5 s).
  - `struct RGBColor: Equatable, Hashable { let r, g, b: UInt8; init?(hex: String); var hex: String }`
    (`hex` = 6 chiffres majuscules, sans « # » ; `init?` accepte « #e0453a » et « E0453A »).
  - `struct NameColorPayload { let name: String?; let color: RGBColor?; var bytes: [UInt8]; var units: [UInt8] }`

- [ ] **Step 1 : tests qui échouent** (`ProtocolTests`) :
  `testPack7Vector` (mêmes valeurs que Task 1), `testPack7RoundTrip` (0 à 20 octets, toutes valeurs),
  `testDataFrameVector` (`dataFrame(seq: 300, …)` : CC 96, 12 × CC 97, puis CC 104–111 avec action 41 et MAC
  `[116,112,71,62]` pour la clé `000102…0f` et le nonce `[17,42,99,5]`), `testDataFrameTooLong` (601 unités → nil),
  `testReasonDecoded` (CC 116 = 3 → `.reason(3)`), `testRunDataDoneAndRefused` (faux transport : accusé 41 →
  `.done` ; raison 2 puis accusé 0 → `.refused(2)` ; capacité 41 absente → `.failed`),
  `testNameColorPayloadBytes` (« Kick » + E0453A → `[1,3,0xE0,0x45,0x3A,4,75,105,99,107]` ; couleur seule →
  `[1,2,R,G,B,0]`), `testRGBColorHex`.
- [ ] **Step 2 :** pousser, la CI échoue sur ces tests (pas de compilateur local).
- [ ] **Step 3 : implémenter.** `sendData` envoie toute la suite sous le verrou de `LinkCore` (jamais mélangée avec une
  autre trame), séquence suivante comme `sendAction`. La raison reçue est gardée dans l'état et remise à `nil` avant
  chaque envoi.
- [ ] **Step 4 :** CI verte sur `ProtocolTests` et les anciens tests.
- [ ] **Step 5 : commit** « Lien avec FL côté Mac : envoi de données signées (action 41) et raison des refus ».

### Task 3 : bloc « Nom et couleur »

**Files :**
- Modify : `Sources/FLShortcut/MacroRegistry.swift` (`BlockType.nameColor`, `Specs.nameColor`, switch du registre)
- Modify : `Sources/FLShortcut/MacroModel.swift` (`BlockBody.nameColor(name: String?, color: RGBColor?)`, type,
  params JSON `name`/`color`, lecture)
- Modify : `Sources/FLShortcut/MacroEditing.swift` (palette : `item("nameColor", .nameColor)` après `flAction` ;
  ligne de liste)
- Modify : `Sources/FLShortcut/MacroEffectsMac.swift` (`perform` : `.nameColor`)
- Modify : `Sources/FLShortcut/NameColor.swift` (`NameColorPayload.message(forReason:) -> String`)
- Test : `Tests/FLShortcutTests/MacroValidationTests.swift`, `MacroModelTests.swift`, `MacroEditingTests.swift`

**Interfaces :**
- Consumes : `RGBColor`, `NameColorPayload`, `MIDILink.runData` (Task 2).
- Produces : `BlockBody.nameColor(name: String?, color: RGBColor?)` ; `Specs.nameColor` (label « Nom et couleur »,
  catégorie `.fl`, symbole `paintpalette`, `dansLaPalette: true`, `needs` = `base ∪ .lienMIDI`,
  `parDefaut` = `.nameColor(name: nil, color: nil)`, `journal` = `"nameColor"`, `estimationMs` = 300,
  `import_` = `.aRelire("renomme et colore dans FL")`, `plateformes` = `.mac`).

- [ ] **Step 1 : tests qui échouent :**
  - `testNameColorValidation` : nom et couleur absents → « Étape 1 : donne un nom ou une couleur. » ; nom « Kick »
    → valide ; couleur seule → valide ; nom de 65 caractères → invalide ; nom « \u{7}x » → invalide ; nom « ␣␣ »
    (espaces) → invalide (Review Focus 2) ; nom « Café 🎹 » → valide.
  - `testNameColorJSONRoundTrip` : `{"name":"Kick","color":"E0453A"}` ; sans `name` ; sans `color` ; couleur
    « ZZZ » → bloc illisible (`nil`).
  - `testPaletteHasNameColor` : la palette contient « nameColor » ; la recherche « couleur » le trouve.
  - `testNameColorReasonMessages` : 1 → « Ouvre le Mixer, le Channel rack ou la Playlist. » ; 2 → « Sélectionne une
    piste ou un canal. » ; 3 → « Sélectionne une seule piste ou un seul canal. » ; 4 → « Arrête la lecture d'abord. » ;
    5 → « FL a refusé le nom ou la couleur. ».
- [ ] **Step 2 :** pousser, la CI échoue.
- [ ] **Step 3 : implémenter.** Nom : espaces de début et de fin retirés à l'envoi ; vide après coup → absent.
  `perform` : `MIDILink.shared.runData(NameColorPayload(…).units)` ; `.done` → `.ok` ; `.refused(r)` →
  `.fail(message(forReason: r))` ; `.failed(t)` → `.fail(t)`. Ligne de la liste : « Kick » suivi d'une pastille de la
  couleur, ou « couleur #E0453A », ou « nom et couleur à choisir ».
- [ ] **Step 4 :** CI verte.
- [ ] **Step 5 : commit** « Macros : bloc Nom et couleur (renomme et colore la piste ou le canal sélectionné par le
  lien avec FL) ».

### Task 4 : réglages du bloc (palette provisoire) et documentation

**Files :**
- Modify : `Sources/FLShortcut/MacroInspector.swift` (cases `(.nameColor, "name")` et `(.nameColor, "color")`)
- Modify : `Sources/FLShortcut/NameColor.swift` (`RecentColors`)
- Modify : `MACROS.md`, `README.md`
- Test : `Tests/FLShortcutTests/MacroEditingTests.swift`

**Interfaces :**
- Produces : `enum RecentColors { static let key = "nameColor.recentColors"; static func list(defaults:) -> [RGBColor];
  static func remember(_ c: RGBColor, defaults:) }` (10 au plus, la plus récente d'abord, sans doublon).

- [ ] **Step 1 : test qui échoue** `testRecentColors` : 12 couleurs mémorisées → 10 gardées, la dernière en tête ;
  une couleur déjà présente remonte en tête sans doublon ; valeur illisible dans les préférences → ignorée.
- [ ] **Step 2 :** pousser, la CI échoue.
- [ ] **Step 3 : implémenter.** Inspecteur : champ « Nom » (64 caractères, invite « Kick ») ; « Couleur » : bascule
  « Changer la couleur », champ « # » (6 chiffres hex, pastille d'aperçu, couleur invalide signalée en rouge sous le
  champ), rangée « Récentes » (pastilles cliquables) ; une couleur valide choisie est mémorisée par
  `RecentColors.remember`. MACROS.md : ligne du bloc dans le tableau des blocs et § technique (`nameColor`) ;
  README : une ligne.
- [ ] **Step 4 :** CI verte.
- [ ] **Step 5 : commit** « Nom et couleur : réglages (nom, couleur en #, couleurs récentes) et documentation ».

### Task 5 : vérification et pkg

- [ ] **Step 1 :** CI complète verte : tests Swift, tests Python, les 4 essais sur le FL simulé, tableau mémoire au
  niveau d'avant (repos ≈ 14 Mo, fenêtre ≈ 55 Mo, créateur ≈ 83 Mo, 0 modèle vivant).
- [ ] **Step 2 :** relecture de tout le diff de l'étape par un relecteur indépendant ; corriger ce qu'il trouve.
- [ ] **Step 3 :** envoyer le pkg (sha) avec ce qu'il faut faire chez soi : redémarrer FL pour charger le script v4,
  puis essayer le bloc sur une piste du Mixer, un canal et une piste de Playlist.
