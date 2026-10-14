# Correctifs du créateur de macros (après revue de l'incrément 2) — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre le créateur de macros livrable : mémoire tenue (fenêtre vraiment libérée, pages paresseuses), aucune perte silencieuse, « Personnaliser » sûr, import durci, éditeur fluide, tests manquants.

**Architecture:** Corrections ciblées sur l'incrément 2 (bibliothèque + créateur) sans toucher au chemin validé « Enregistrement rapide ». Les deux problèmes de mémoire passent d'abord par une tâche de PREUVE (mesure sur la CI) : les corrections 2 et 3 n'appliquent que ce que la preuve confirme.

**Tech Stack:** Swift 5.9 (mode Swift 5), SwiftUI + AppKit, macOS 13 minimum, XCTest, CI GitHub Actions macos-26 / Xcode 26 (seule compilation possible : ce dépôt est édité sous Linux).

**Spec:** revue `04-revue-increment2.md` (I1–I7 + mineurs), architecture `03-architecture-code.md` §2.3, §2.4, §2.11, §4 — dossier `/tmp/claude-0/-home-user-fl-shortcut/9fb9ab9c-db79-5c5e-bdbb-2e5a1c4d9b5b/scratchpad/macrocreator/`.

## Global Constraints

- Interface et commentaires en français, concis, comme le reste du code.
- macOS 13 minimum ; outils Swift 5.9 ; pas de `@Observable` ; toute API plus récente sous `if #available`.
- Rien ne tourne au repos : aucune minuterie, aucun observateur permanent, aucun trafic MIDI quand aucune macro ne tourne et que le créateur est fermé.
- Le chemin validé « Enregistrement rapide » ne change pas (menu de piste F puis O avec Entrée apprise, choix du preset, armement/REC, entrée 1, larsen à la fin).
- Essais de bout en bout inchangés et verts : `selftest-macro.txt` = 4 « OK passage » + `PASS` ; `selftest-macro-blocs.txt` = `PASS` ; `selftest-preset.txt` = `PASS`.
- Garde-fous de sécurité dans la couche d'effets uniquement (FL au premier plan, liste noire, Échap, clics dans FL).
- Objectifs mémoire (table « | verre | » de `scripts/mesure-interface.sh`) : créateur ouvert ≤ fenêtre + 15 Mo ; créateur refermé ≤ fenêtre + 2 Mo ; recherche « e » ≤ 100 Mo.
- Vérification = CI : `git push -u origin claude/relaxed-mayer-ndguzv`, puis job « App Mac (compilation + tests) » vert, 0 `error:`, tous les tests passent, artefacts `FLShortcut-mac-mesure` lus (`gh run download <run> --repo anmaprod/fl-shortcut -n FLShortcut-mac-mesure -D <dossier>`). Les tests ne tournent que sur la CI : écrire le test et le code dans le même commit est admis.
- Commits en français terminés exactement par les deux lignes `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` et `Claude-Session: https://claude.ai/code/session_015cWn3nRUmsQoCfPZgGBtCt`. Aucun identifiant de modèle ailleurs. Pas de pull request. Un seul agent écrit dans le dépôt à la fois.

## Review Focus

- Fermer le créateur pendant « Tester » ou « Montrer dans FL… » : tout s'arrête, plus rien n'écrit dans la bibliothèque ensuite (Task 2, test `testCloseCancelsTeachingAndKeepsDraft`).
- Ouvrir/fermer le créateur dix fois : la mémoire ne grimpe pas à chaque fois (Task 1 mesure 3 cycles ; Task 2 test `testControllerReleasesModelOnClose`).
- Bibliothèque illisible ou non inscriptible : un message visible dans le menu ET dans le créateur, jamais de macro perdue sans prévenir (Task 4).
- Preset sur un disque externe puis « Personnaliser » : le raccourci continue de marcher (Task 5).
- Fichier `.flsmacro` fabriqué à la main avec des clics déjà visés ou un bloc caché `menuAX` : arrive désactivé, sans raccourci, clics « à apprendre », tout listé à la relecture (Task 7).

---

### Task 1: Preuves mémoire (aucun changement visible)

**Files:**
- Modify: `Sources/FLShortcut/MacroEditorModel.swift` (compteur d'instances vivantes)
- Modify: `Sources/FLShortcut/EditorView.swift` (conteneur de page commutable, désactivé par défaut)
- Modify: `Sources/FLShortcut/DebugSnapshot.swift` (notification de rapport)
- Modify: `scripts/mesure-interface.sh`

**Interfaces:**
- Produces: `MacroEditorModel.liveCount: Int` (statique, `Locked<Int>` incrémenté dans `init`, décrémenté dans `deinit`) ; clé UserDefaults de mesure `debugPagesAsList` (Bool, défaut faux) ; notification `app.flshortcut.debug.report` qui écrit `editorModels=<n> windows=<n>` dans `~/Library/Caches/app.flshortcut.FLShortcut/report.txt`.

- [ ] **Step 1:** `struct PageContainer<Content: View>: View` dans EditorView.swift : `Form { content }.formStyle(.grouped)` normalement, `List { content }.listStyle(.inset)` si `UserDefaults.standard.bool(forKey: "debugPagesAsList")` ; remplacer les `Form {` de `sectionList`, `searchResults`, `customList` par `PageContainer {` (le `cardList()` reste appliqué).
- [ ] **Step 2:** compteur `liveCount` + rapport `debug.report` (actif seulement avec `debugSnapshots`, comme les autres notifications).
- [ ] **Step 3:** `scripts/mesure-interface.sh` : après la mesure actuelle du créateur, refaire 2 cycles ouvrir → mesurer → fermer → attendre 3 s → mesurer, et écrire le rapport après chaque fermeture ; puis relancer l'app avec `debugPagesAsList YES`, recherche « e », mesurer ; remettre la clé. Colonnes ajoutées : « créateur cycle 2/3 ouvert/fermé », « modèles vivants après fermeture », « recherche « e » en List ».
- [ ] **Step 4:** pousser, attendre la CI verte, relever la table. **Sortie de la tâche (à recopier dans le rapport) :** les chiffres, et les deux verdicts : H1 « la mémoire de la recherche vient du Form groupé » = vraie si recherche List ≤ 100 Mo ; H2 « le créateur reste vivant après fermeture » = vraie si `editorModels` reste ≥ 1 après fermeture.
- [ ] **Step 5:** commit « Mesure : preuves mémoire du créateur et des pages ».

### Task 2: Fenêtre du créateur possédée par AppKit, vraiment libérée (si H2 vraie)

**Files:**
- Create: `Sources/FLShortcut/MacroCreatorWindow.swift`
- Modify: `Sources/FLShortcut/FLShortcutApp.swift:58-65` (retirer la scène `Window` du créateur), `MacroEditorView.swift` (`MacroCreatorLink`, `MacroCreatorView`, `WindowFinder`), `MacroEditorModel.swift` (`close()`), `EditorView.swift` et `DebugSnapshot.swift` (remplacer `openWindow(id: MacroCreatorLink.windowID)`), `MACROS.md`
- Test: `Tests/FLShortcutTests/MacroCreatorWindowTests.swift`

**Interfaces:**
- Consumes: `MacroCreatorLink.open(_:)`, `openSample()`, `requestClose()` (inchangés pour les appelants).
- Produces: `final class MacroCreatorWindowController: NSObject, NSWindowDelegate` avec `static let shared`, `func show()` (crée à la demande `NSWindow` 1100×700 min 900×600 + `NSHostingController(rootView: MacroCreatorView().environmentObject(Store.shared))`, `isRestorable = false`, `isReleasedWhenClosed = false`), `func windowWillClose(_:)` (appelle `model.close()`, `contentViewController = nil`, lâche la fenêtre), `var isOpen: Bool`. `MacroEditorModel.close()` devient idempotent et appelle `ClickTeacher.shared.cancel(nil)` ; les ports MIDI ne sont plus annoncés à l'ouverture mais au début de « Tester » (`setEditorNeeds` dans le chemin de test, remis à `[]` à la fin du test et à `close()`).

- [ ] **Step 1:** tests : `testControllerReleasesModelOnClose` (show → close → `MacroEditorModel.liveCount == 0`) ; `testCloseIsIdempotent` (deux `close()` → un seul enregistrement, besoins vides) ; `testCloseCancelsTeachingAndKeepsDraft` (`ClickTeacher` actif → `close()` → plus actif, brouillon intact dans la bibliothèque) ; `testEditorNeedsEmptyUntilTest`.
- [ ] **Step 2:** implémentation ci-dessus ; `openWindow(id:)` remplacé par `MacroCreatorWindowController.shared.show()` partout ; corriger le commentaire « libérée à sa fermeture » et MACROS.md.
- [ ] **Step 3:** CI verte + table : « créateur refermé » ≤ fenêtre + 2 Mo, cycles 2/3 sans hausse, `editorModels=0` après fermeture ; essais FakeFL verts.
- [ ] **Step 4:** commit.

### Task 3: Pages paresseuses à l'aspect « cartes » (si H1 vraie)

**Files:**
- Modify: `Sources/FLShortcut/EditorView.swift` (`PageContainer`, `cardList()`), `Sources/FLShortcut/GlassStyle.swift` (fond de ligne)
- Test: `Tests/FLShortcutTests/AppearanceTests.swift` (position de ligne)

**Interfaces:**
- Produces: `PageContainer` toujours `List` (`.listStyle(.inset)` sans fond alterné), sections rendues en cartes par `enum CardRowPosition { case single, first, middle, last }` + `struct CardRowBackground: View` (rectangle arrondi seulement en haut pour `.first`, en bas pour `.last`, les deux pour `.single`) appliqué par `.listRowBackground(…)` avec séparateurs internes ; `static func position(index: Int, count: Int) -> CardRowPosition`. La clé `debugPagesAsList` est retirée.

- [ ] **Step 1:** test `testCardRowPositions` : `(0,1)→.single`, `(0,3)→.first`, `(1,3)→.middle`, `(2,3)→.last`.
- [ ] **Step 2:** implémentation ; verre coupé et Réduire la transparence : fond opaque comme aujourd'hui.
- [ ] **Step 3:** CI verte + table : recherche « e » ≤ 100 Mo, page Mixer ≤ fenêtre + 10 Mo ; capture `verre.png` : les pages gardent l'aspect cartes (sections arrondies, en-tête de page).
- [ ] **Step 4:** commit.

### Task 4: Erreurs de la bibliothèque visibles, jamais de perte silencieuse

**Files:**
- Modify: `Sources/FLShortcut/MacroLibraryStore.swift:150-190, 297`, `MacroLibraryView.swift:22-51`, `FLShortcutApp.swift:463-464` (`MenuContent.alerts`), `MacroEditorView.swift` (bandeau)
- Test: `Tests/FLShortcutTests/MacroLibraryStoreTests.swift`

**Interfaces:**
- Produces: `MacroLibraryStore.problem: String?` (calculé : `saveError ?? loadWarning ?? (writesDisabled ? message : nil)`) lu par le menu, la page Macros (y compris vide) et un bandeau du créateur. Échec d'une copie de secours avant écriture ⇒ `writesDisabled = true` et message, au lieu d'écraser.

- [ ] **Step 1:** tests `testBackupFailureDisablesWrites`, `testProblemMessageWhenWritesDisabled`, `testProblemVisibleWhenLibraryEmpty` (avec `MemoryMacroLibraryStorage` capable de simuler l'échec de copie).
- [ ] **Step 2:** implémentation (textes : « Tes macros ne peuvent pas être enregistrées : … » ; « Le fichier des macros était illisible : une copie datée a été gardée dans … »).
- [ ] **Step 3:** CI verte ; commit.

### Task 5: « Personnaliser » ne casse jamais un raccourci qui marche

**Files:**
- Modify: `Sources/FLShortcut/EditorView.swift:1054-1075` (`customizeTemplate`), `MacroRegistry.swift:468-474` ou `MacroValidation.swift` (contexte de validation)
- Test: `Tests/FLShortcutTests/MacroTemplateTests.swift`

**Interfaces:**
- Produces: validation selon l'origine : un `MacroDoc` d'origine `.template("autoRecord")` accepte le preset hors du dossier personnel (même règle que le modèle en ligne), extension `.fst` toujours exigée ; `customizeTemplate` compile le `MacroDoc` avant de basculer et, si `problem != nil`, ne touche pas au raccourci et affiche le problème.

- [ ] **Step 1:** tests `testCustomizedTemplateWithExternalPresetStaysValid` (preset `/Volumes/Studio/Voix.fst`) et `testCustomizeRefusedWhenCopyInvalid`.
- [ ] **Step 2:** implémentation ; CI verte ; commit.

### Task 6: Fluidité de l'éditeur

**Files:**
- Modify: `Sources/FLShortcut/MacroEditorView.swift:47-80, 282-300` (`MacroCreatorView`, `AddBlockMenu`), `MacroPalette.swift:21` (`MacroPaletteView`), `MacroHeader`

**Interfaces:**
- Produces: `MacroPaletteView(items: [PaletteItem], insert: (PaletteItem) -> Void)` et `AddBlockMenu(items: [PaletteItem], insert: …)` sans objet observé ; `PaletteCatalog.items(layout: store.layout)` calculé une seule fois (`paletteItems`) ; `MacroCreatorView` sans `@EnvironmentObject Store` s'il n'en a pas besoin.

- [ ] **Step 1:** implémentation (aucun changement de comportement) ; la capture `verre-createur.png` reste identique.
- [ ] **Step 2:** CI verte (tests + essais) ; commit.

### Task 7: Import durci et relecture complète

**Files:**
- Modify: `Sources/FLShortcut/MacroExchange.swift:36-52, 103-150`, `MacroLibraryView.swift:300-345`, `MacroRegistry.swift:67, 113` (`PolitiqueImport` réellement utilisée)
- Test: `Tests/FLShortcutTests/MacroExchangeTests.swift`

**Interfaces:**
- Produces: `prepareImport` applique `sharable()` (toutes les cibles de clic → `.toLearn`), met « à relire » ou refuse le bloc caché `menuAX` selon `BlockRegistry.spec(...).import_`, compte les blocs sensibles de TOUT l'arbre (`Preview.sensitiveCount: Int`) ; la relecture affiche toute la liste dans une vue défilante (plus de limite à 30 lignes) avec le décompte en tête.

- [ ] **Step 1:** tests `testImportForcesClicksToLearn`, `testImportFlagsHiddenMenuAX`, `testImportCountsSensitiveBlocksInWholeTree` (sensible au-delà de la 30ᵉ ligne).
- [ ] **Step 2:** implémentation ; CI verte ; commit.

### Task 8: Tests de l'éditeur et finitions

**Files:**
- Modify: `Sources/FLShortcut/MacroEditorModel.swift:188-191` (nom vide), `MacroRunMonitor.swift:96` (`refuse`), `MacroEditorView.swift:82` (`handle` idempotent par `serial`), `Catalog.swift:511` (`remapTitle` pour `macroRef`), `MacroValidation.swift:284` (retirer `docCache`, garder `programCache`), `MACROS.md` (bornes 200 blocs / 300 s, liste des fichiers)
- Test: `Tests/FLShortcutTests/MacroEditorModelTests.swift`

**Interfaces:**
- Produces: nom vide ⇒ « Macro sans nom » enregistré ; `refuse` ⇒ résultat « non lancé » (pas « arrêté ») ; `remapTitle` d'un `macroRef` = nom de la macro.

- [ ] **Step 1:** tests `testEmptyNameSavedAsUntitled`, `testUndoGroupsTyping`, `testSelectionAfterDelete`, `testRunMonitorCapsAt200`, `testRemapTitleForMacroRef`, `testHandleRequestIsIdempotent`.
- [ ] **Step 2:** implémentation ; CI verte ; commit.

### Fin : revue de toute la branche

- [ ] Relecture complète 4d48844..HEAD par un relecteur Swift indépendant (ecc:swift-reviewer) ; corriger tout « Critical » et « Important ».
- [ ] CI finale verte, table mémoire dans les objectifs, essais FakeFL verts, captures du créateur et des pages relues.
