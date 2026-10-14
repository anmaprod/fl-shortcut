// Exécution des macros : point d'entrée (démarrage, verrou, notification, essais). Sans script ni réseau ; le lien
// MIDI n'est réveillé que brièvement par les blocs « Action de FL ».
// Garde-fous (même esprit que EventTap.post) :
//  - la macro ne démarre que si FL est au premier plan, et s'arrête dès qu'il ne l'est plus ;
//  - tout est envoyé au seul PID de FL (postToPid) ; les clics doivent tomber dans une fenêtre de FL ;
//  - les touches sont revérifiées contre la liste noire (⌘Q, ⌘W…) avant l'envoi ;
//  - Échap interrompt la macro à tout moment ; une seule macro à la fois ;
//  - tout tourne sur une file dédiée : jamais d'attente dans le thread du tap clavier (REL-03), et plus aucune
//    validation non plus (programme compilé et validé sur le thread principal : MacroValidation.swift) ;
//  - aucune frappe n'est lue ni journalisée : seules des durées / étapes sont retenues pour le diagnostic.
// Découpage : programme (MacroValidation.swift), interpréteur (MacroInterpreter.swift), effets macOS
// (MacroEffectsMac.swift, MacroFLBlocks.swift).
import AppKit
import Foundation

extension Notification.Name {
    /// userInfo : "ok" (Bool), "text" (String).
    static let macroFinished = Notification.Name("FLShortcutMacroFinished")
}

final class MacroRunner {
    static let shared = MacroRunner()

    enum StartResult: Equatable {
        case started
        /// Une macro tourne déjà : le raccourci est avalé sans rien faire (jamais envoyé à FL tel quel).
        case busy
        /// FL pas au premier plan, macro invalide : le raccourci passe à FL.
        case refused
    }

    /// Le curseur réel est déplacé pendant les clics (certaines interfaces lisent la position réelle de la souris)
    /// puis remis à sa place. À mettre à `false` pour tester l'envoi pur d'événements.
    static var warpCursor = true

    /// Clics envoyés comme de vrais clics (flux du système) : beaucoup d'apps ignorent la souris envoyée à leur
    /// seul PID. Garde-fou : la fenêtre visible tout devant au point visé doit appartenir à FL.
    /// `defaults write app.flshortcut.FLShortcut macroClicksToPid -bool YES` : envoi au seul PID (essai).
    static var clicksToPid: Bool { UserDefaults.standard.bool(forKey: "macroClicksToPid") }

    private let queue = DispatchQueue(label: "fr.flshortcut.macro", qos: .userInitiated)
    private let busy = Locked(false)

    private init() {}

    /// Essai de bout en bout (`--selftest-macro`, FL simulé) : FL reconnu par son PID et le premier plan de
    /// NSWorkspace (pas de tap clavier dans l'essai), piste visée donnée directement. Jamais utilisé dans l'app.
    static var testFLPID: Int32?
    static var testTrackPoint: CGPoint?

    /// FL au premier plan : état tenu à jour par l'app (immédiat) ; dans l'essai, NSWorkspace (≈ 20 ms par appel
    /// hors du thread principal, mesuré sur la CI : jamais dans une boucle serrée de l'app).
    static func isFrontmost(_ pid: Int32) -> Bool {
        if testFLPID != nil { return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
        return EventTap.shared.currentConfig.frontmostPID == pid
    }

    /// Essai : exécute les blocs sur la file appelante (jamais le thread principal) et rend le résultat.
    func runForTest(_ blocks: [Block], pid: Int32) -> MacroOutcome {
        busy.withLock { $0 = true }
        defer { busy.withLock { $0 = false } }
        let program = MacroProgram(blocks: blocks, name: "essai", source: .blocks(id: UUID(), revision: 0),
                                   context: ValidationContext(forbidden: .physical))
        return execute(program, pid: pid)
    }

    /// Une macro est en cours (ses propres clics ne doivent pas compter comme « dernière piste cliquée »).
    var isRunning: Bool { busy.value }

    /// Appelé depuis le thread du tap : ne bloque jamais, la macro tourne sur sa propre file. Le programme a été
    /// compilé et validé sur le thread principal (index du tap) : ici, une lecture et une mise en file.
    func start(_ program: MacroProgram, flPID pid: Int32) -> StartResult {
        let cfg = EventTap.shared.currentConfig
        guard pid != 0, cfg.flPIDs.contains(pid), cfg.frontmostPID == pid, program.isRunnable else { return .refused }
        let acquired = busy.withLock { b -> Bool in
            if b { return false }
            b = true
            return true
        }
        guard acquired else { return .busy }
        queue.async { [self] in
            let outcome = execute(program, pid: pid)
            busy.withLock { $0 = false }
            DispatchQueue.main.async {
                var ok = false
                switch outcome {
                case .done, .stopped: ok = true
                case .doneWithWarning: break                       // la fenêtre du larsen suffit
                default: NSSound.beep()
                }
                NotificationCenter.default.post(name: .macroFinished, object: nil,
                                                userInfo: ["ok": ok, "text": outcome.text])
            }
        }
        return .started
    }

    /// « Tester » dans la fiche du raccourci (thread principal) : programme compilé (en cache) avec la liste noire
    /// active, puis même démarrage que le raccourci.
    func start(_ macro: Macro, flPID pid: Int32) -> StartResult {
        start(MacroProgram.compile(macro, forbidden: EventTap.shared.currentConfig.forbidden), flPID: pid)
    }

    private func execute(_ program: MacroProgram, pid: Int32) -> MacroOutcome {
        MacroLog.shared.beginRun(program.title, flPID: pid)
        // Effets neufs à chaque passage : rien de l'état d'un passage ne survit au suivant.
        let outcome = MacroInterpreter(effects: MacroEffectsMac(pid: pid)).run(program)
        MacroLog.shared.endRun(outcome.text)
        return outcome
    }

    // MARK: Constantes partagées (clés UserDefaults et actions du script : inchangées)

    /// Actions du script FL (PROTOCOL.md §6) qui n'éteignent jamais ce qui est déjà allumé.
    static let armOnAction = 39
    static let recOnAction = 40

    /// Entrée nécessaire après la dernière lettre du menu de piste (appris au premier passage).
    static let enterAfterLetterKey = "macroMenuEnterAfterLetter"

    /// Ancienne mémoire de la rangée du Mixer (retirée) : effacée avec le reste.
    static let trackMenuMemoKey = "macroTrackMenuMemo"

    static func forgetTrackMenuMemo(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: trackMenuMemoKey)
        defaults.removeObject(forKey: enterAfterLetterKey)
    }

    /// Éléments entre « Select » et « Arm selected track(s) » dans le menu de piste de FL 2026 : Reset selected
    /// track(s) routing, Unroute tracks…, Solo selected track(s), Alt solo selected track(s), Arm selected track(s).
    static let armDownCount = 5
}
