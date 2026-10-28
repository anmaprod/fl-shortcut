// Modèles développés en blocs, et reprise des anciennes macros.
// - « Enregistrement rapide » (`autoRecord`) : mêmes étapes, mêmes paramètres et même ordre que l'ancien
//   `MacroLibrary.autoRecordSteps` (test « golden » des 8 combinaisons d'options), sauf le preset fixe, désormais
//   déposé sur la piste (bloc `dropFile`) ; l'ancien chemin par le menu reste disponible (`PresetLoad.menu`).
//   Ids DÉTERMINISTES, propres à chaque rôle : stables d'un lancement à l'autre (surlignage, rapport par bloc).
// - Anciennes macros (`custom`, `quickRecord`) : chaque étape devient le bloc qui l'exécute exactement de la même
//   façon, au moment de l'exécution (le profil n'est pas modifié).
import Foundation

enum MacroTemplates {
    /// Rôle d'un bloc du modèle « Enregistrement rapide ».
    enum Role: Int, CaseIterable {
        case trackMenu = 1, waitOpen, chooseFile, waitClose, delay, arm, rec, input, feedback, dropPreset
    }

    /// Chargement d'un preset fixe. `.drop` : glissé sur la piste, comme depuis le Finder (essai de l'utilisateur sur
    /// son FL : rapide, sans boîte « Open » ; le double-clic dans le Finder, lui, charge sur le Master).
    /// `.menu` : menu de la piste puis boîte « Open » (chemin d'origine, toujours essayé sur la CI).
    enum PresetLoad { case drop, menu }

    /// Id stable d'un rôle du modèle : F15C0000-0000-4000-8000-00000000000N.
    static func id(_ role: Role) -> UUID { fixedID(0, role.rawValue) }

    /// Id stable de la N-ième étape d'une ancienne macro.
    static func legacyID(_ index: Int) -> UUID { fixedID(1, index + 1) }

    private static func fixedID(_ group: Int, _ n: Int) -> UUID {
        UUID(uuidString: String(format: "F15C%04d-0000-4000-8000-%012d", group, n)) ?? UUID()
    }

    /// Clic droit sur la dernière piste cliquée › File › Open mixer track state (lettres soulignées), Entrée apprise.
    static var openStateMenu: BlockBody {
        let titles = [Macro.fileMenuTitles[0], Macro.openStateTitles[0]]
        return .trackMenu(letters: titles.compactMap { $0.first.map { Character($0.lowercased()) } }, labels: titles,
                          target: .lastClicked, finalEnter: .learned(legacyKey: MacroRunner.enterAfterLetterKey))
    }

    /// Éléments du menu de la piste qu'on choisit dans une liste (bloc « Menu de la piste ») : lettres soulignées du
    /// menu de FL 2026, relevées sur les vidéos de l'utilisateur (les mêmes que le FL simulé). « Autre » garde les
    /// lettres tapées à la main.
    static let trackMenuChoices: [TrackMenuChoice] = [
        TrackMenuChoice(id: "openState", name: String(localized: "Ouvrir un état de piste (preset de piste)"),
                        labels: [Macro.fileMenuTitles[0], Macro.openStateTitles[0]], letters: ["f", "o"],
                        enter: .learned(legacyKey: MacroRunner.enterAfterLetterKey)),
        TrackMenuChoice(id: "saveState", name: String(localized: "Enregistrer l'état de la piste"),
                        labels: [Macro.fileMenuTitles[0], "Save mixer track state as"], letters: ["f", "s"], enter: .ifNeeded),
        TrackMenuChoice(id: "rename", name: String(localized: "Renommer, couleur et icône"),
                        labels: ["Rename, color and icon"], letters: ["r"], enter: .ifNeeded),
        TrackMenuChoice(id: "assignAudio", name: String(localized: "Créer sa piste audio (Playlist)"),
                        labels: ["Assign to new Audio track(s)"], letters: ["a"], enter: .ifNeeded),
    ]

    static func trackMenuChoice(_ letters: [Character]) -> TrackMenuChoice? {
        trackMenuChoices.first { $0.letters == letters }
    }

    /// « (none) » → entrée 1, appris une fois (clé historique : rien à réapprendre).
    static var inputOne: BlockBody { .selectInput(.legacy(key: MacroSpots.PathKind.input.rawValue)) }

    /// Enregistrement rapide sans réglage. Ordre : menu de la piste, preset, armement, REC, entrée 1, puis le
    /// larsen en dernier (tout est déjà en place : il ne reste qu'à changer d'entrée ou de sortie).
    static func enregistrementRapide(_ macro: Macro, presetLoad: PresetLoad = .drop) -> [Block] {
        var out: [Block] = []
        func add(_ role: Role, _ body: BlockBody) { out.append(Block(id: id(role), body)) }
        if let path = macro.presetPath, !path.isEmpty {
            switch presetLoad {
            case .drop:
                add(.dropPreset, .dropFile(path: path))
            case .menu:
                add(.trackMenu, openStateMenu)
                add(.waitOpen, .waitWindow(.dialog, timeoutMs: 4_000))
                add(.chooseFile, .chooseFile(path: path))
                add(.waitClose, .waitWindowClose(.dialog, timeoutMs: 8_000))
            }
        } else {
            // Preset choisi à chaque fois : menu de la piste puis boîte « Open », chemin validé, inchangé.
            add(.trackMenu, openStateMenu)
            add(.waitOpen, .waitWindow(.dialog, timeoutMs: 4_000))
            add(.waitClose, .waitWindowClose(.dialog, timeoutMs: MacroLibrary.maxWaitMs))
        }
        if macro.armAndInput || macro.startRecording { add(.delay, .delay(ms: 100)) }
        // Armement puis REC : deux actions consécutives, un seul réveil du lien avec FL (MacroInterpreter).
        if macro.armAndInput { add(.arm, .flAction(key: "armon", fallback: .trackMenuArm)) }
        if macro.startRecording {
            // Touche REC de FL : utilisée seulement sans lien MIDI (le lien, lui, n'allume que si c'est éteint).
            let rec = macro.recKey ?? KeyCombo(keyCode: MacroLibrary.fallbackRecKeyCode)
            add(.rec, .flAction(key: "recon", fallback: .key(KeyRef(rec))))
        }
        if macro.armAndInput { add(.input, inputOne) }
        if macro.armAndInput || macro.startRecording { add(.feedback, .feedbackCheck) }
        return out
    }

    /// Ancien format → blocs, étape par étape (même exécution : mêmes repères de clic, mêmes délais).
    static func blocks(fromLegacy steps: [MacroStep]) -> [Block] {
        steps.enumerated().map { i, step in Block(id: legacyID(i), body(of: step)) }
    }

    static func body(of step: MacroStep) -> BlockBody {
        switch step.kind {
        case .key:
            return .key(KeyRef(step.combo ?? KeyCombo(keyCode: 0)), times: 1)
        case .delay:
            return .delay(ms: step.ms)
        case .click:
            let target = step.spot.map(ClickTarget.init) ?? .startCursor(dx: .nan, dy: .nan)
            return .click(target, button: step.button == .right ? .right : .left)
        case .menu:
            return .menuAX(titles: step.titles, fallback: step.fallback.map(ClickTarget.init))
        case .waitDialog:
            return .waitWindow(.dialog, timeoutMs: step.ms)
        case .waitDialogClose:
            return .waitWindowClose(.dialog, timeoutMs: step.ms)
        case .chooseFile:
            return .chooseFile(path: step.path ?? "")
        case .trackMenu:
            // Chaque titre peut porter des variantes séparées par « | » : la lettre est la première du premier.
            let first = step.titles.map { $0.split(separator: "|").first.map(String.init) ?? "" }
            return .trackMenu(letters: first.compactMap { $0.first.map { Character($0.lowercased()) } }, labels: first,
                              target: .lastClicked, finalEnter: .learned(legacyKey: MacroRunner.enterAfterLetterKey))
        case .armTrack:
            return .flAction(key: "armon", fallback: .trackMenuArm)
        case .recordOn:
            return .flAction(key: "recon", fallback: .key(KeyRef(step.combo ?? KeyCombo(keyCode: MacroLibrary.fallbackRecKeyCode))))
        case .selectInput:
            return inputOne
        case .feedbackCheck:
            return .feedbackCheck
        }
    }
}

extension MacroLibrary {
    /// Blocs à exécuter pour la macro d'un raccourci, ou ce qui manque. Pure : aucun accès au système de fichiers
    /// ni à l'écran. Les anciennes macros gardent d'abord leurs propres bornes (40 étapes, 180 s).
    static func blocks(for macro: Macro, forbidden: ForbiddenTargets) -> Result<[Block], BuildError> {
        switch macro.template {
        case .autoRecord:
            return .success(MacroTemplates.enregistrementRapide(macro))
        case .quickRecord, .custom:
            return legacySteps(for: macro, forbidden: forbidden).map(MacroTemplates.blocks(fromLegacy:))
        }
    }

    /// Raison pour laquelle la macro ne peut pas tourner, ou `nil` si elle est prête (programme en cache).
    static func problem(in macro: Macro, forbidden: ForbiddenTargets) -> String? {
        MacroProgram.compile(macro, forbidden: forbidden).problem
    }
}

// MARK: - Galerie de modèles du créateur de macros

/// Un modèle de la galerie : une macro en blocs prête à modifier (ids neufs à chaque copie).
/// Un élément du menu de la piste : nom affiché dans la liste, titres de FL (ligne du bloc), lettres soulignées.
struct TrackMenuChoice: Identifiable {
    let id: String
    let name: String
    let labels: [String]
    let letters: [Character]
    let enter: EnterPolicy
}

struct MacroTemplate: Identifiable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
    let make: (KeyboardLayout) -> MacroDoc
}

extension MacroTemplates {
    /// Modèle livré « Enregistrement rapide » (galerie et origine de sa copie personnalisée).
    static let autoRecordID = "autoRecord"
    /// Modèle « Organiser » : l'utilisateur ne choisit que le raccourci.
    static let organizeID = "organize"

    /// « Personnaliser » : copie en blocs du modèle, compilée avant de remplacer le raccourci. Problème : le
    /// raccourci n'est pas touché.
    static func customizedCopy(of macro: Macro, name: String,
                               forbidden: ForbiddenTargets) -> (doc: MacroDoc, problem: String?) {
        let doc = MacroDoc(name: name, blocks: freshIDs(enregistrementRapide(macro)), origin: .template(autoRecordID))
        return (doc, MacroProgram.compile(doc, forbidden: forbidden).problem)
    }

    /// Modèle de la galerie « Enregistrement rapide » : les blocs du modèle livré jusqu'à l'armement de la piste
    /// (la suite sera refaite, plus rapide).
    static func untilArm(_ macro: Macro) -> [Block] {
        let all = enregistrementRapide(macro)
        guard let arm = all.firstIndex(where: { $0.id == id(.arm) }) else { return all }
        return Array(all[...arm])
    }

    /// Les mêmes blocs sans aucune note, imbrications comprises (notes retirées à la demande de l'utilisateur).
    static func withoutNotes(_ blocks: [Block]) -> [Block] {
        blocks.map { b in
            var copy = b
            copy.note = nil
            copy.body = b.body.replacingChildren(b.body.children.map(withoutNotes))
            return copy
        }
    }

    /// Copie avec des ids neufs, imbrication comprise (deux copies d'un modèle ne partagent jamais un id).
    static func freshIDs(_ blocks: [Block]) -> [Block] {
        blocks.map { b in
            var copy = b
            copy.id = UUID()
            copy.body = b.body.replacingChildren(b.body.children.map(freshIDs))
            return copy
        }
    }

    /// Modèles construits seulement avec des blocs que l'interpréteur sait déjà jouer. Les quatre premiers sont les
    /// macros faites par le propriétaire (25/10, « tu as juste à les mettre ») ; retirés à sa demande : l'ancien
    /// « Enregistrement rapide », « Organiser » et « Enregistrer puis exporter en WAV » (toujours compris dans les
    /// macros déjà faites). Certains blocs se règlent sur chaque Mac : le preset à choisir, les clics à montrer.
    static func gallery(layout: KeyboardLayout) -> [MacroTemplate] {
        [
            MacroTemplate(id: "threeFour", title: String(localized: "3/4"),
                          summary: String(localized: "Règle la mesure du projet en 3/4."),
                          symbol: "metronome") { _ in
                MacroDoc(name: String(localized: "3/4"), blocks: [
                    Block(.menuBar(titles: ["Options", "Project general settings"])),
                    Block(.click(.toLearn, button: .left)),
                    Block(.click(.toLearn, button: .left)),
                ], origin: .template("threeFour"))
            },
            MacroTemplate(id: "quickDrop", title: String(localized: "Enregistrement Rapide"),
                          summary: String(localized: "Ouvre ton preset dans le Mixer."),
                          symbol: "record.circle") { _ in
                MacroDoc(name: String(localized: "Enregistrement Rapide"), blocks: [Block(.dropFile(path: ""))],
                         origin: .template("quickDrop"))
            },
            MacroTemplate(id: "exportStems", title: String(localized: "Export Stems"),
                          summary: String(localized: "Exporte une piste audio par piste de la Playlist."),
                          symbol: "square.stack.3d.down.right") { _ in
                MacroDoc(name: String(localized: "Export Stems"), blocks: [
                    Block(.menuBar(titles: ["File", "Export", "All playlist tracks", "Time selection..."])),
                ], origin: .template("exportStems"))
            },
            MacroTemplate(id: "openVST", title: String(localized: "Ouvre un VST"),
                          summary: String(localized: "Ajoute un instrument dans le Channel rack."),
                          symbol: "pianokeys") { _ in
                MacroDoc(name: String(localized: "Ouvre un VST"), blocks: [
                    Block(.openPage(.channelRack)),
                    Block(.pageOption(id: "channelRack.addInstrument", name: "")),
                ], origin: .template("openVST"))
            },
            MacroTemplate(id: "purgeAudio", title: String(localized: "Supprimer les clips audio inutilisés"),
                          summary: String(localized: "Retire du projet les clips audio inutilisés."),
                          symbol: "trash") { _ in
                MacroDoc(name: "Supprimer les clips audio inutilisés",
                         // Dans la barre des menus de macOS, FL met ses macros à plat dans Tools (vidéo de
                         // l'utilisateur) : pas de sous-menu « Macros » comme dans son menu TOOLS.
                         blocks: [Block(.menuBar(titles: ["Tools", "Purge unused audio clips"]))],
                         origin: .template("purgeAudio"))
            },
        ]
    }
}

extension MacroTemplates {
    /// Armer la piste visée par son menu, construit à la main avec des blocs simples (essai « blocs » de la CI,
    /// exemple du créateur) : clic droit sur la piste, S (Select), ←, ↓ ×5, Entrée = « Arm selected track(s) »,
    /// puis la touche REC de FL.
    static func armThroughTrackMenu(rec: KeyRef) -> [Block] {
        [
            Block(.click(.track(dx: 0, dy: 0), button: .right)),                // menu de la piste
            Block(.waitWindow(.menu, timeoutMs: 1_500)),
            Block(.menuLetters(["s"], finalEnter: .never)),                      // Select
            Block(.delay(ms: 200)),
            Block(.menuKey(.left, times: 1)),
            Block(.menuKey(.down, times: 5)),                                    // jusqu'à « Arm selected track(s) »
            Block(.menuKey(.enter, times: 1)),
            Block(.waitWindowClose(.menu, timeoutMs: 1_000)),
            Block(.key(rec, times: 1)),                                          // touche REC de FL
        ]
    }

    /// Macro d'exemple de la mesure de l'interface (jamais enregistrée) : les blocs de l'essai « blocs », dans une
    /// macro qui montre aussi un commentaire, une boucle et des badges.
    static func sampleForCapture(layout: KeyboardLayout) -> MacroDoc {
        let rec = AppMode.nativeEquivalent(of: 3, layout: layout) ?? KeyCombo(keyCode: MacroLibrary.fallbackRecKeyCode)
        let mixer = AppMode.nativeEquivalent(of: 33, layout: layout) ?? KeyCombo(keyCode: 101)
        var blocks = [Block(.comment("Clique d'abord sur ta piste dans le Mixer, puis lance le raccourci"))]
        blocks += armThroughTrackMenu(rec: KeyRef(rec))
        blocks += [
            Block(.selectInput(.legacy(key: MacroSpots.PathKind.input.rawValue))),
            Block(.repeatCount(2, [Block(.flAction(key: "mx", fallback: .key(KeyRef(mixer))))])),
            Block(.feedbackCheck),
        ]
        return MacroDoc(name: "Armer la piste et lancer le REC (exemple)", blocks: blocks, origin: .template("exemple"))
    }
}

extension BlockBody {
    /// Même bloc avec d'autres listes imbriquées (dans l'ordre de `children` : alors puis sinon, ou corps).
    func replacingChildren(_ lists: [[Block]]) -> BlockBody {
        switch self {
        case .ifElse(let c, let then, let otherwise):
            return .ifElse(c, then: lists.first ?? then, otherwise: lists.count > 1 ? lists[1] : otherwise)
        case .repeatCount(let n, let body):
            return .repeatCount(n, lists.first ?? body)
        case .repeatWhile(let c, let max, let body):
            return .repeatWhile(c, maxIterations: max, lists.first ?? body)
        default:
            return self
        }
    }
}
