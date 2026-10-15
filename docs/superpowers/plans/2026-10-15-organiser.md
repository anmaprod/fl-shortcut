# Organiser, dégradé et icônes — plan d'implémentation

> **Pour les agents :** sous-compétence requise : superpowers:executing-plans (exécution native dans cette session,
> demandée par l'utilisateur : « vas-y fonce »). Étapes en cases à cocher (`- [ ]`).

**But :** organiser la page ouverte de FL (Channel rack, Mixer) en écoutant les sons, avec une couleur ou un dégradé
et une icône par famille ; dégradé et icône aussi dans le bloc « Nom et couleur ».

**Architecture :** le script FL passe en v5 (opérations 2 à 8, réponses signées FL → appli). L'appli ajoute une
façade `OrganizerLink` sur le lien, un classement pur (mesures Accelerate + SoundAnalysis), une capture du seul
processus de FL (Core Audio, macOS 14.2+), une session qui enchaîne écoute → classement → aperçu → application, et
une fenêtre Liquid Glass. Les icônes passent par la fenêtre de FL (F2, clic appris, case de la grille).

**Technologies :** Swift 5.9, SwiftUI/AppKit, CoreMIDI, CryptoKit, Accelerate, SoundAnalysis, Core Audio
(`CATapDescription`), Python 3 (script FL, tests `unittest`).

**Conception :** `docs/superpowers/specs/2026-10-15-nom-couleur-organiser-design.md` (§1 ajouts, §4, §5, §6, §6 bis).

## Contraintes globales

- Jamais l'écran (ni capture ni lecture) ; liste des fenêtres, Accessibilité et événements seulement.
- MIDI seulement pendant une action ; rien ne tourne au repos ; capture, modèle et fenêtres libérés à la fin.
- Textes, commentaires et réponses en français ; Swift 5.9, macOS 13 minimum (Organiser : macOS 14.2, sinon
  message), pas de `@Observable`.
- Ne pas toucher aux étapes validées (minutages du menu de piste, `runBriefly` de l'armement et du REC).
- Le nom tapé et les noms des sons n'apparaissent jamais dans les journaux ni dans les messages de FL.
- Protocole : constantes identiques entre `Resources/device_FLShortcut.py` et `FLProtocol.swift`.
- Chaque étape : CI verte (tests, 4 essais, tableau mémoire) avant tout pkg ; push sur `claude/relaxed-mayer-ndguzv`.

## Points à surveiller (non couverts par les tests de tâche → tests ajoutés aux tâches indiquées)

1. **FL qui joue au lancement** : l'Organiser doit s'arrêter avec « Appuie sur Stop » sans rien couper (T1 :
   `test_play_solo_refuses_when_playing` ; T6 : `testPlayingStopsBeforeListening`).
2. **Écoute interrompue** (Échap, lien perdu, erreur de capture) : sourdines, mode et position toujours remis
   (T1 : `test_sleep_restores_memo` ; T6 : `testCancelAlwaysRestores`).
3. **Groupe filtré dans le Channel rack** : les ⌥↑ suivraient le groupe → refus clair (T6 : `testFilteredGroupRefused`).
4. **Canaux qui ne bougent pas comme prévu** (FL refuse un ⌥↑) : la vérification par `list` le voit et propose
   « Revenir comme avant » (T7 : `testApplyDetectsMismatch`).
5. **Projet de plus de 16 canaux** (pages de `list`) et noms non ASCII coupés au milieu d'un caractère
   (T1 : `test_list_pages_and_utf8_cut` ; T2 : `testChannelListPagesDecode`).

---

### Tâche 1 : script FL v5 — réponses signées, opérations 2 à 8

**Fichiers :** modifier `Resources/device_FLShortcut.py`, `Tests/python/fl_mocks.py`,
`Tests/python/test_device_flshortcut.py`, `PROTOCOL.md` (§8).

**Interfaces produites (script) :** constantes `CC_RESP_START=112`, `CC_RESP_UNIT=113`, `CC_RESP_END=114`,
`CC_RESP_MAC=115`, `OP_LIST=2`, `OP_AUDITION=3`, `OP_SET_COLORS=4`, `OP_SELECT_ONE=5`, `OP_PLAY_SOLO=6`,
`OP_STOP_RESTORE=7`, `OP_GRADIENT=8`, `REASON_PLAYING=4`, `REASON_FEW=7`, `EXT_ACTION_ID=42`, `LIST_PAGE=16`,
`LIST_NAME_BYTES=24`, `MAX_COLORS=64`, `SCRIPT_VERSION=5`. `pack7(bytes)`, `_respond(op, data, seq3)`,
`_run_data(units, seq3)`.

- Réponse : CC 112 = op, CC 113 × unités (`pack7(data)`, 600 au plus), CC 114 = 0, puis 4 × CC 115 =
  `mac28(HMAC(clé, nonce ‖ seq3 ‖ [op] ‖ unités))`, envoyée avant l'accusé 41.
- `list` `[2, genre, début_hi, début_lo]` → `[genre, total_hi, total_lo, début_hi, début_lo, n, filtré]` +
  entrées. Canaux : `[type, fx_hi, fx_lo, R, G, B, len, nom]` ; Mixer : `[R, G, B, len, nom]` ; nom UTF-8 coupé
  à 24 octets sur une frontière de caractère ; couleurs par `utils.ColorToRGB`. `filtré = channelCount() !=
  channelCount(True)`.
- `playSolo` `[6, hi, lo]` : FL qui joue sans mémo → raison 4. 1er appel : mémo = sourdines de tous les canaux,
  `getLoopMode()`, `getSongPos()`. Puis arrêt si lecture, sourdine de chaque canal ≠ index (bascule seulement là où
  l'état diffère, `muteChannel(i)`), mode pattern (`setLoopMode()` si `getLoopMode() != 0`), `setSongPos(0.0)`,
  `start()`.
- `stopRestore` `[7]` : `stop()`, remet sourdines / mode / position du mémo, vide le mémo ; 0 même sans mémo.
  `_sleep()` appelle aussi la remise (sécurité si l'appli disparaît).
- `audition` `[3, hi, lo, note, vel]` : `channels.midiNoteOn(getChannelIndex(i), note, vel)`.
- `setColors` `[4, genre, n, (hi, lo, R, G, B) × n]`, n ≤ 64, index < nombre.
- `selectOne` `[5, genre, hi, lo]` : canaux `selectOneChannel` (API 8) ; Mixer `setActiveTrack` (API 27), sinon
  `deselectAll` + `selectTrack`.
- `gradientSelected` `[8, R1, G1, B1, R2, G2, B2]` : page de `_NAME_COLOR_PAGES`, tous les sélectionnés ; 0 →
  raison 2, 1 → raison 7 ; couleur k = `int(a + (b − a) × k / (n − 1) + 0,5)` par composante (même arrondi que `RGBColor.lerp`).
- Capacité 42 annoncée quand `_data_available()` et `utils.ColorToRGB` existent. Fonction absente pour une
  opération → raison 6.

- [ ] Tests d'abord (`TestDataV5`) : `test_response_mac_vector` (vecteur commun avec Swift, voir T2),
  `test_list_channels_page`, `test_list_pages_and_utf8_cut`, `test_list_mixer`, `test_set_colors`,
  `test_set_colors_bad_index`, `test_select_one_channel_and_mixer`, `test_play_solo_mutes_others_and_plays`,
  `test_play_solo_refuses_when_playing`, `test_stop_restore_puts_back`, `test_stop_restore_without_memo`,
  `test_sleep_restores_memo`, `test_audition_note_on_off`, `test_gradient_three_tracks` (E0453A → 3FA7E0 sur 3 :
  milieu = 90768D), `test_gradient_needs_two` (1 → 7, 0 → 2), `test_caps_bit_42`, `test_name_never_in_hints`.
- [ ] `python3 -m unittest discover -s Tests/python` : échec attendu, puis implémentation, puis tout passe.
- [ ] PROTOCOL.md §8 ; commit « Lien v5 : réponses signées et opérations de l'Organiser (script) ».

### Tâche 2 : appli — réponses signées et façade `OrganizerLink`

**Fichiers :** modifier `FLProtocol.swift`, `MIDILink.swift` ; créer `OrganizerLink.swift` ;
tests `ProtocolTests.swift` (`ResponseTests`), `OrganizerLinkTests.swift`.

**Interfaces produites :**
- `FLProtocol.ccRespStart/Unit/End/Mac = 112…115`, `FLProtocol.extActionID = 42`.
- `IncomingEvent.response(op: Int, units: [UInt8], mac: [UInt8])` (décodeur : 112 début, 113 unités ≤ 600,
  114 fin, 4 × 115 ; toute séquence cassée est jetée).
- `LinkCore.runRequest(_ bytes: [UInt8], brief: Bool, timeout: TimeInterval = 4) -> RequestReply` avec
  `enum RequestReply: Equatable { case answered([UInt8]), refused(Int), failed(String) }` (réponse vérifiée avec le
  seq de la commande ; accusé 41 sans réponse → `.answered([])`). `MIDILink.runRequest(_:)`.
- `enum ItemKind: UInt8 { case channels = 1, mixer = 2 }` ; `struct ChannelInfo { index, type, mixerTrack: Int;
  color: RGBColor; name: String }` ; `struct MixerTrackInfo { index: Int; color: RGBColor; name: String }`.
- `enum OrganizerPayload` (pur) : `list(kind:start:)`, `setColors(kind:_:)` (paquets de 64), `selectOne`,
  `playSolo`, `stopRestore`, `audition`, `gradient(first:last:)`, `decodeChannels(_:) -> (total, start,
  [ChannelInfo], filtered)?`, `decodeMixer(_:)`.
- `protocol OrganizerLink: AnyObject` : `listChannels() throws -> (channels: [ChannelInfo], filtered: Bool)`,
  `listMixer() throws -> [MixerTrackInfo]`, `setColors(_ kind: ItemKind, _ colors: [(Int, RGBColor)]) throws`,
  `selectOne(_ kind: ItemKind, _ index: Int) throws`, `playSolo(_ channel: Int) throws`, `stopRestore()`,
  `audition(_ channel: Int, note: UInt8, velocity: UInt8) throws`, `var window: FLWindow { get }`.
  `enum OrganizerError: Error, Equatable { case refused(Int), failed(String) }` + `message`.
  `final class LiveOrganizerLink: OrganizerLink` (sur `MIDILink`).

- [ ] Tests : `testResponseDecodeAndMac` (même vecteur que T1), `testResponseWrongMacIgnored`,
  `testResponseBoundToSeq`, `testBrokenResponseDropped`, `testChannelListPagesDecode`, `testPayloadSizes` (64
  couleurs ≤ 600 unités), `testFakeTransportRequestRoundTrip` (FakeTransport.onSend répond comme le script).
- [ ] Implémentation, CI, commit « Lien v5 : réponses signées et façade de l'Organiser (appli) ».

### Tâche 3 : dégradé dans le bloc « Nom et couleur »

**Fichiers :** `MacroModel.swift`, `MacroRegistry.swift`, `MacroEditing.swift`, `MacroEffectsMac.swift`,
`MacroInspector.swift`, `NameColor.swift`, `FLColorSelector.swift` (+ `FLGradientField`) ; tests
`MacroModelTests`, `MacroValidationTests`.

**Interfaces :** `struct NameColorSettings: Equatable { var name: String?; var color: RGBColor?; var fade:
RGBColor?; var icon: FLIcon? }` ; `BlockBody.nameColor(NameColorSettings)` ; JSON `name`, `color`, `fade`,
`icon` (`"c-r"`) ; `struct FLIcon: Equatable { column, row: Int; code: String; init?(code:) }` ;
`RGBColor.lerp(_ b: RGBColor, _ t: Double) -> RGBColor` (arrondi au plus proche, comme le script) ;
`NameColorPayload.gradientBytes(first:last:)` ; message raison 7 « Sélectionne au moins 2 pistes pour un
dégradé ».

- Validation : au moins un de nom / couleur / icône ; `fade` demande `color` et refuse `name`.
- Réglages : sélecteur « Ne pas changer | Une couleur | Dégradé » ; Dégradé = `FLGradientField` (cases First et
  Last qui ouvrent `FLColorSelector`, aperçu, ▶ ◀▶ ◀) ; nom grisé en Dégradé.
- [ ] Tests : `testNameColorFadeJSONRoundTrip`, `testFadeNeedsColorAndNoName`, `testLerpMatchesScript`
  (E0453A → 3FA7E0, t = 0,5 → 90768D), `testIconCodeRoundTrip`, `testGradientReasonMessage`.
- [ ] Implémentation, CI, commit.

### Tâche 4 : classement pur (mesures + IA de macOS)

**Fichiers :** créer `SoundFeatures.swift`, `SoundFamilies.swift`, `SoundClassifier.swift` ; tests
`SoundClassificationTests.swift` (+ générateur de sons de synthèse dans les tests).

**Interfaces :** `enum SoundFamily: String, CaseIterable { case drums, bass, melody, vocals, fx, unsure }` (+
`label` français, ordre d'affichage) ; `struct SoundFeatures { peakDB, noteLength (s), pitchedFraction,
medianF0 (Hz), lowRatio, flatness, onsetsPerSecond }` ; `SoundFeatures.measure(_ samples: [Float], rate: Double)
-> SoundFeatures` ; `struct AILabels { top: [(String, Double)] }` ; `SoundClassifier.labels(_ samples:, rate:)
-> AILabels` (SoundAnalysis `.version1`, sur le Mac) ; `FamilyFusion.decide(_ f: SoundFeatures, _ ai: AILabels)
-> (SoundFamily, confidence: Double)` (règles de la conception §6, dans l'ordre) ; `FamilyFusion.labelTable:
[String: SoundFamily]`.

- [ ] Tests : `testLabelTableIsKnown` (⊂ `knownClassifications`, affiche les absentes),
  `testFeaturesOfSine` (f0 ± 2 %), `testFeaturesOfNoise` (flatness haute, pitchedFraction basse),
  `testFusionRules` (une mesure par règle), `testSynthSoundsClassified` (kick, caisse claire, charleston, 808,
  basse, lead, nappe, montée de bruit, voix de synthèse : au moins 8 sur 9, tableau affiché).
- [ ] Implémentation, CI (le tableau des 9 sons part dans le résumé de la CI), commit.

### Tâche 5 : capture du seul processus de FL

**Fichiers :** créer `FLAudioTap.swift` (`@available(macOS 14.2, *)`), `CaptureBuffer.swift` ; modifier
`Resources/Info.plist` (`NSAudioCaptureUsageDescription` : « FL Shortcut écoute FL Studio, et seulement lui,
pendant « Organiser », pour reconnaître les sons. Rien n'est enregistré. ») ; tests `CaptureBufferTests.swift`.

**Interfaces :** `final class CaptureBuffer` (mono, capacité en secondes, `append(_:frames:channels:)`,
`take() -> [Float]`, `reset()`, thread-safe) ; `protocol AudioSource { func start() throws; func
take() -> [Float]; func reset(); func stop(); var rate: Double { get } }` ; `final class FLAudioTap: AudioSource`
(`init(pid:)` : pid → objet audio, `CATapDescription(stereoMixdownOfProcesses:)`, `muteBehavior =
.mutedWhenTapped`, `isPrivate = true`, agrégat privé, IOProc ; tout détruit par `stop()` et `deinit`).

- [ ] Tests : `testBufferMixesStereoToMono`, `testBufferKeepsLastSeconds`, `testBufferResetAndTake`.
- [ ] Implémentation, CI, commit.

### Tâche 6 : session d'écoute

**Fichiers :** créer `OrganizerSession.swift` ; tests `OrganizerSessionTests.swift` (faux `OrganizerLink`, faux
`AudioSource` qui renvoie un son choisi par canal).

**Interfaces :** `struct OrganizerItem { index: Int; name: String; family: SoundFamily; confidence: Double;
testNotes: Bool; mixerTrack: Int; color: RGBColor }` ; `enum OrganizerPage { case channelRack, mixer }` ;
`struct OrganizerResult { page; items: [OrganizerItem]; mixer: [MixerTrackInfo] }` ;
`final class OrganizerSession` : `init(link:, audio:, classify: (([Float], Double) -> (SoundFamily, Double)),
progress: (Int, Int) -> Void)`, `func run() -> Result<OrganizerResult, OrganizerError>`, `func cancel()`.
Canaux sautés : types 3 (layer) et 5 (automation). Écoute : `playSolo`, 3 s, `take()` ; silence (< −50 dBFS) →
notes d'essai 48 puis 60 (300 ms chacune, coupées par vélocité 0), 0,6 s de queue ; `stopRestore` en `defer`.
Mixer : famille majoritaire des canaux reliés ; aucune → `.unsure`.

- [ ] Tests : `testChannelRackFlow`, `testSkipsLayerAndAutomation`, `testSilentChannelUsesTestNotes`,
  `testCancelAlwaysRestores`, `testPlayingStopsBeforeListening`, `testFilteredGroupRefused`,
  `testMixerMajority`, `testOtherPageRefused`.
- [ ] Implémentation, CI, commit.

### Tâche 7 : plan, application, « Revenir comme avant »

**Fichiers :** créer `OrganizerApply.swift` ; tests `OrganizerApplyTests.swift`.

**Interfaces :** `struct FamilyStyle: Codable, Equatable { color: RGBColor; fade: RGBColor?; icon: FLIcon? }` ;
`enum FamilyStyles` (préférence `organize.families`, valeurs de départ de la conception §6) ;
`struct Move: Equatable { from: Int; up: Int }` ; `RegroupPlan.make(order: [SoundFamily]) -> (moves: [Move],
final: [Int])` (tri stable ; `final[p]` = index d'origine à la place p) ; `RegroupPlan.back(final: [Int]) ->
[Move]` ; `FamilyStyle.colors(count:) -> [RGBColor]` (lerp) ; `final class OrganizerApplier` : `apply(result:,
styles:, keys: (Int) -> Bool) -> Result<Snapshot, OrganizerError>` (déplacements : `selectOne` puis ⌥↑ × up, 15 ms
entre deux touches, Channel rack devant à chaque pas ; couleurs par paquets ; vérification par `listChannels`),
`undo(_ snapshot:)`.

- [ ] Tests : `testPlanStableAndBounded` (n ≤ 40 : pas ≤ n(n−1)/2), `testPlanBackRestoresOrder` (simulation),
  `testFadeColorsPerFamily`, `testApplyColorsInChunks`, `testApplyDetectsMismatch`, `testUndoRestoresColorsAndOrder`,
  `testStopsWhenPageChanges`.
- [ ] Implémentation, CI, commit.

### Tâche 8 : fenêtre, lancement, mémoire

**Fichiers :** créer `OrganizerWindow.swift` (contrôleur + vues SwiftUI) ; modifier `MacroModel.swift`,
`MacroRegistry.swift` (`BlockType.organize`, besoin `.lienMIDI`), `MacroEditing.swift`, `MacroEffectsMac.swift`,
`MacroTemplates.swift` (modèle « Organiser la page ouverte »), `FLShortcutApp.swift` (menu de la barre des menus) ;
tests `OrganizerWindowTests.swift`.

- Fenêtre (panneau flottant, style de `GlassStyle.swift`) : « Écoute n / N » + Arrêter (Échap) ; aperçu par
  famille (pastille cliquable pour changer de famille), réglage de chaque famille (Une couleur / Dégradé, icône) ;
  Appliquer / Annuler ; après : Revenir comme avant / Fermer. macOS < 14.2 → message.
- Tout libéré à la fermeture : `OrganizerController.current` nil, capture arrêtée.
- [ ] Tests : `testControllerReleasedOnClose` (référence faible nil), `testOrganizeBlockJSON`,
  `testTemplateHasOrganize`.
- [ ] Implémentation, CI (tableau mémoire inchangé au repos), commit.

### Tâche 9 : icônes

**Fichiers :** créer `FLIcons.swift` (grille : titres de colonnes, cases, symbole SF et nom anglais de FL) et
`FLIconPicker.swift` ; modifier `MacroInspector.swift`, `OrganizerWindow.swift`, `MacroFLBlocks.swift`
(`placeIcon`), `MacroSpots.swift` (chemin appris `iconButton`) ; tests `FLIconTests.swift`.

**Interfaces :** `enum FLIconGrid { static let columns = 14; static let rows = 15; static let titles:
[(column: Int, title: String)]; static func cell(_ icon: FLIcon) -> (symbol: String, name: String)?; static func
center(of icon: FLIcon, in window: CGRect) -> CGPoint }` (colonne 13 « Channel » non proposée : ses titres Quad /
5.1 / 7.1 décalent les cases) ; `func placeIcon(_ icon: FLIcon, ctx:) -> StepResult` (F2 → fenêtre du nom → clic
appris → grille → case → Entrée).

- [ ] Tests : `testCellCenters` (fenêtre 617 × 677 : case (1, 0) à x = 66,1, y = 38,0 depuis le coin),
  `testAllSymbolsExist`, `testPickerSkipsChannelColumn`, `testIconStepOrder` (faux FL : touches et clics dans
  l'ordre).
- [ ] Implémentation, CI, commit.

### Tâche 10 : docs, relecture, pkg

- [ ] MACROS.md, README.md, PROTOCOL.md à jour ; relecture de toute la branche par un relecteur neuf.
- [ ] CI verte (tests, 4 essais, mémoire), pkg envoyé avec son sha256.
