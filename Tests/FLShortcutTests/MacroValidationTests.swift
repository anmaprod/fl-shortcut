import XCTest
@testable import FLShortcut

/// Règles de validation des macros en blocs (SEC-05) : bornes, touches interdites même imbriquées, conditions,
/// variables, clés apprises en liste blanche, fichiers, pire durée.
final class MacroValidationTests: XCTestCase {
    private let ctx = ValidationContext(forbidden: .physical)
    private let quit = KeyCombo(keyCode: 12, command: true)        // ⌘Q

    private func problem(_ blocks: [Block], variables: [VariableDecl] = [], strict: Bool = false) -> String? {
        MacroValidation.problem(in: blocks, variables: variables,
                                context: ValidationContext(forbidden: .physical, strictFiles: strict))
    }

    private func b(_ body: BlockBody) -> Block { Block(body) }

    func testEmptyMacro() {
        XCTAssertEqual(problem([]), "La macro est vide.")
    }

    /// Messages au format historique (« Étape N : … ») : identiques pour les blocs qui remplacent une ancienne étape.
    func testForbiddenKeysAreRefusedWithTheOldMessages() {
        XCTAssertEqual(problem([b(.key(KeyRef(quit), times: 1))]),
                       "Étape 1 : touche interdite (⌘Q quitte l'application (⌃⌘Q verrouille la session)).")
        XCTAssertEqual(problem([b(.delay(ms: 1)), b(.flAction(key: "recon", fallback: .key(KeyRef(quit))))]),
                       "Étape 2 : touche REC interdite (⌘Q quitte l'application (⌃⌘Q verrouille la session)).")
        XCTAssertEqual(problem([b(.key(KeyRef(KeyCombo(keyCode: 56)), times: 1))]), "Étape 1 : touche non prise en charge.")
        XCTAssertEqual(problem([b(.delay(ms: 5_001))]), "Étape 1 : pause hors limites.")
        XCTAssertEqual(problem([b(.waitWindow(.dialog, timeoutMs: 99))]), "Étape 1 : attente hors limites.")
        XCTAssertEqual(problem([b(.chooseFile(path: "/tmp/a\nb.fst"))]), "Étape 1 : chemin de fichier invalide.")
        XCTAssertEqual(problem([b(.click(.startCursor(dx: .infinity, dy: 0), button: .left))]), "Étape 1 : position invalide.")
    }

    /// Une touche interdite au fond d'un « si » est trouvée ; le sinon continue la numérotation du alors.
    func testForbiddenKeyDeepInsideIsFound() {
        let inner = Block(.ifElse(.windowOpen(.dialog), then: [b(.delay(ms: 1)), b(.delay(ms: 1))],
                                  otherwise: [b(.repeatCount(2, [b(.key(KeyRef(quit), times: 1))]))]))
        XCTAssertEqual(problem([b(.delay(ms: 1)), inner])?.hasPrefix("Étape 2.3.1 : touche interdite"), true)
    }

    func testTreeLimits() {
        XCTAssertNil(problem(Array(repeating: b(.delay(ms: 1)), count: MacroValidation.maxBlocks)))
        XCTAssertEqual(problem(Array(repeating: b(.delay(ms: 1)), count: MacroValidation.maxBlocks + 1)),
                       "Macro trop longue (200 blocs au plus).")
        var nested = [b(.delay(ms: 1))]
        for _ in 0..<MacroValidation.maxDepth { nested = [b(.repeatCount(1, nested))] }
        XCTAssertNil(problem(nested))
        XCTAssertEqual(problem([b(.repeatCount(1, nested))]), "Blocs trop imbriqués (4 niveaux au plus).")
        XCTAssertEqual(problem([b(.repeatCount(51, []))]), "Étape 1 : nombre de répétitions hors limites.")
        XCTAssertEqual(problem([b(.repeatWhile(.windowOpen(.menu), maxIterations: 101, []))]), "Étape 1 : nombre de tours hors limites.")
        XCTAssertEqual(problem([b(.waitUntil(.windowOpen(.menu), timeoutMs: 120_001))]), "Étape 1 : attente hors limites.")
    }

    /// Pire durée : corps × nombre de tours, délais d'attente ; 300 s au plus.
    func testWorstCaseDuration() {
        XCTAssertNil(problem([b(.repeatCount(50, [b(.delay(ms: 5_000))]))]))                       // 250 s
        XCTAssertEqual(problem([b(.repeatCount(50, [b(.delay(ms: 5_000)), b(.delay(ms: 2_000))]))]),
                       "Macro trop longue (durée totale).")                                    // 350 s
        XCTAssertEqual(MacroValidation.estimateMs([b(.ifElse(.lastBlockFailed, then: [b(.delay(ms: 300))],
                                                                otherwise: [b(.delay(ms: 900))]))]), 950)
        XCTAssertEqual(MacroValidation.estimateMs([Block(.delay(ms: 900), enabled: false)]), 0)
        XCTAssertLessThanOrEqual(MacroValidation.estimateMs(MacroTemplates.enregistrementRapide(Macro())), 300_000)
    }

    func testConditionsAreBounded() {
        let leaf = Condition.windowOpen(.dialog)
        XCTAssertNil(problem([b(.waitUntil(.all(Array(repeating: leaf, count: 6)), timeoutMs: 1_000))]))
        XCTAssertNotNil(problem([b(.waitUntil(.all(Array(repeating: leaf, count: 7)), timeoutMs: 1_000))]))
        XCTAssertNil(problem([b(.waitUntil(.not(.not(leaf)), timeoutMs: 1_000))]))
        XCTAssertNotNil(problem([b(.waitUntil(.not(.not(.not(leaf))), timeoutMs: 1_000))]))
        XCTAssertNotNil(problem([b(.waitUntil(.flState(query: "nope", .eq, 1), timeoutMs: 1_000))]))
        XCTAssertNil(problem([b(.waitUntil(.flState(query: "isrec", .eq, 1), timeoutMs: 1_000))]))
    }

    func testVariablesMustBeDeclared() {
        let set = b(.setVariable("n", .constant(1)))
        XCTAssertEqual(problem([set]), "Étape 1 : variable inconnue.")
        XCTAssertNil(problem([set], variables: [VariableDecl(name: "n")]))
        XCTAssertNotNil(problem([b(.ifElse(.variable("m", .eq, 1), then: [], otherwise: []))], variables: [VariableDecl(name: "n")]))
        XCTAssertNotNil(problem([set], variables: [VariableDecl(name: "N")]))
        XCTAssertNotNil(problem([set], variables: [VariableDecl(name: "n"), VariableDecl(name: "n")]))
        XCTAssertNotNil(problem([set], variables: (0...8).map { VariableDecl(name: "v\($0)") }))
    }

    /// Un fichier importé ne peut jamais faire lire ou écrire une clé UserDefaults quelconque.
    func testLearnedKeysAreWhitelisted() {
        let menu = BlockBody.trackMenu(letters: ["f", "o"], labels: [], target: .lastClicked, finalEnter: .learned(legacyKey: "enabled"))
        XCTAssertEqual(problem([b(menu)]), "Étape 1 : mémoire de l'Entrée inconnue.")
        XCTAssertNotNil(problem([b(.menuLetters(["f"], finalEnter: .learned(legacyKey: "midiActions")))]))
        XCTAssertEqual(problem([b(.selectInput(.legacy(key: "enabled")))]), "Étape 1 : positions apprises inconnues.")
        XCTAssertNil(problem([b(MacroTemplates.openStateMenu), b(MacroTemplates.inputOne)]))
    }

    /// Liste du « Menu de la piste » : chaque élément est valable, lettres distinctes, et « Ouvrir un état de piste »
    /// est exactement le bloc du modèle (mêmes lettres, titres et Entrée apprise : rien à réapprendre).
    func testTrackMenuChoices() {
        let choices = MacroTemplates.trackMenuChoices
        XCTAssertEqual(Set(choices.map { String($0.letters) }).count, choices.count)
        for c in choices {
            let body = BlockBody.trackMenu(letters: c.letters, labels: c.labels, target: .lastClicked, finalEnter: c.enter)
            XCTAssertNil(problem([b(body)]), c.id)
            XCTAssertEqual(MacroTemplates.trackMenuChoice(c.letters)?.id, c.id)
        }
        guard case .trackMenu(let l, let labels, _, let e) = MacroTemplates.openStateMenu,
              let open = MacroTemplates.trackMenuChoice(l) else { return XCTFail("modèle introuvable dans la liste") }
        XCTAssertEqual(open.id, "openState")
        XCTAssertEqual(open.labels, labels)
        XCTAssertEqual(open.enter, e)
        XCTAssertNil(MacroTemplates.trackMenuChoice(["x", "y"]))
    }

    func testMenuBlocks() {
        XCTAssertNil(problem([b(.menuLetters(["s", "a"], finalEnter: .never))]))
        XCTAssertNotNil(problem([b(.menuLetters(["f", "1"], finalEnter: .never))]))
        XCTAssertNotNil(problem([b(.menuLetters([], finalEnter: .never))]))
        XCTAssertNotNil(problem([b(.trackMenu(letters: ["f", "o"], labels: [], target: .lastClicked, finalEnter: .never))]))
        XCTAssertNil(problem([b(.trackMenu(letters: ["r"], labels: [], target: .lastClicked, finalEnter: .ifNeeded))]))
        XCTAssertNotNil(problem([b(.trackMenu(letters: [], labels: [], target: .lastClicked, finalEnter: .ifNeeded))]))
        XCTAssertNotNil(problem([b(.trackMenu(letters: ["f", "o", "x", "y"], labels: [], target: .lastClicked, finalEnter: .ifNeeded))]))
        XCTAssertNotNil(problem([b(.menuKey(.down, times: 21))]))
        let hop = MacroSpots.PopupHop(offset: CGVector(dx: 10, dy: 10), size: CGSize(width: 200, height: 100))
        XCTAssertNil(problem([b(.click(.openMenu(hop), button: .left))]))
        XCTAssertNotNil(problem([b(.click(.openMenu(hop), button: .right))]))
        XCTAssertNotNil(problem([b(.flAction(key: "recon", fallback: .trackMenuArm))]))
        XCTAssertNotNil(problem([b(.flAction(key: "teleport", fallback: .none))]))
    }

    /// Bibliothèque et imports : preset .fst du dossier personnel seulement ; modèle et anciennes macros : comme avant.
    func testStrictFiles() {
        let home = NSHomeDirectory()
        XCTAssertNil(problem([b(.chooseFile(path: "/Volumes/Disque/Voix.fst"))]))
        XCTAssertNotNil(problem([b(.chooseFile(path: "/Volumes/Disque/Voix.fst"))], strict: true))
        XCTAssertNil(problem([b(.chooseFile(path: home + "/Documents/Voix.fst"))], strict: true))
        XCTAssertNotNil(problem([b(.chooseFile(path: home + "/Documents/Voix.txt"))], strict: true))
        XCTAssertNotNil(problem([b(.chooseFile(path: home + "/../x/Voix.fst"))], strict: true))
    }

    func testMacroDocNameAndFormat() {
        let blocks = [b(.delay(ms: 1))]
        XCTAssertNil(MacroValidation.problem(in: MacroDoc(name: "Ma macro", blocks: blocks), context: ctx))
        XCTAssertNotNil(MacroValidation.problem(in: MacroDoc(name: String(repeating: "x", count: 61), blocks: blocks), context: ctx))
        var newer = MacroDoc(name: "Plus récente", blocks: blocks)
        newer.format = 3
        XCTAssertNotNil(MacroValidation.problem(in: newer, context: ctx))
        XCTAssertFalse(MacroProgram.compile(newer, forbidden: .physical).isRunnable)
        // Cache de la bibliothèque : même (id, révision) → même programme ; nouvelle révision → recompilé.
        var doc = MacroDoc(name: "Ma macro", blocks: blocks)
        let first = MacroProgram.compile(doc, forbidden: .physical)
        XCTAssertTrue(first === MacroProgram.compile(doc, forbidden: .physical))
        doc.blocks = [b(.delay(ms: 2))]
        doc.revision += 1
        XCTAssertEqual(MacroProgram.compile(doc, forbidden: .physical).blocks, doc.blocks)
    }

    func testNotesAndTextsAreBounded() {
        XCTAssertNotNil(problem([Block(.delay(ms: 1), note: String(repeating: "n", count: 121))]))
        XCTAssertNotNil(problem([b(.stop(message: String(repeating: "m", count: 121)))]))
        XCTAssertNotNil(problem([b(.comment(String(repeating: "c", count: 201)))]))
    }

    func testBlockPaths() {
        let tree = [b(.delay(ms: 1)),
                    b(.ifElse(.lastBlockFailed, then: [b(.delay(ms: 2))], otherwise: [b(.delay(ms: 3)), b(.delay(ms: 4))]))]
        XCTAssertEqual(MacroValidation.block(at: "2.3", in: tree)?.body, .delay(ms: 4))
        XCTAssertEqual(MacroValidation.block(at: "2.1", in: tree)?.body, .delay(ms: 2))
        XCTAssertNil(MacroValidation.block(at: "3", in: tree))
        XCTAssertEqual(MacroValidation.count(tree), 5)
        XCTAssertEqual(MacroValidation.depth(tree), 1)
    }
}
