// Modèles développés en blocs, et reprise des anciennes macros.
// - « Enregistrement rapide » (`autoRecord`) : mêmes étapes, mêmes paramètres et même ordre que l'ancien
//   `MacroLibrary.autoRecordSteps` (test « golden » des 8 combinaisons d'options). Ids DÉTERMINISTES, propres à
//   chaque rôle : stables d'un lancement à l'autre (surlignage, rapport par bloc, positions apprises).
// - Anciennes macros (`custom`, `quickRecord`) : chaque étape devient le bloc qui l'exécute exactement de la même
//   façon, au moment de l'exécution (le profil n'est pas modifié).
import Foundation

enum MacroTemplates {
    /// Rôle d'un bloc du modèle « Enregistrement rapide ».
    enum Role: Int, CaseIterable {
        case trackMenu = 1, waitOpen, chooseFile, waitClose, delay, arm, rec, input, feedback
    }

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

    /// « (none) » → entrée 1, appris une fois (clé historique : rien à réapprendre).
    static var inputOne: BlockBody { .selectInput(.legacy(key: MacroSpots.PathKind.input.rawValue)) }

    /// Enregistrement rapide sans réglage. Ordre : menu de la piste, preset, armement, REC, entrée 1, puis le
    /// larsen en dernier (tout est déjà en place : il ne reste qu'à changer d'entrée ou de sortie).
    static func enregistrementRapide(_ macro: Macro) -> [Block] {
        var out: [Block] = []
        func add(_ role: Role, _ body: BlockBody) { out.append(Block(id: id(role), body)) }
        add(.trackMenu, openStateMenu)
        add(.waitOpen, .waitWindow(.dialog, timeoutMs: 4_000))
        if let path = macro.presetPath, !path.isEmpty {
            add(.chooseFile, .chooseFile(path: path))
            add(.waitClose, .waitWindowClose(.dialog, timeoutMs: 8_000))
        } else {
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
