// Audit : REL-03 (tap sur un thread dédié avec sa propre boucle d'exécution ; configuration immuable sous
//         verrou), REL-04 / SEC-11 (purge sur coupure du tap, veille, changement de session, arrêt/démarrage),
//         REL-05 (tap annoté : PID destinataire réel, repli sur le PID au premier plan), REL-08 (start/stop/
//         restart, état interrogeable par le superviseur), SEC-10 (réactivations limitées à 5/min puis
//         redémarrage demandé au superviseur), SEC-03 (re-vérification de FL juste avant l'injection +
//         CGEvent.postToPid : la frappe ne peut pas fuir vers une autre appli), SEC-05 (liste noire revérifiée
//         avant chaque injection), REL-13 (flagsChanged encadrants, source d'événements privée),
//         SEC-07 (aucune frappe stockée, journalisée ni transmise : seuls keyCode et modificateurs sont lus
//         pour la décision, jamais conservés hors de l'état « appui en cours »).
import AppKit
import CoreGraphics

final class EventTap {
    static let shared = EventTap()
    /// Marque nos propres événements (« FLSH ») pour ne jamais les retraiter (anti-boucle).
    static let mark: Int64 = 0x464C_5348

    private struct Handles {
        let tap: CFMachPort
        let source: CFRunLoopSource
        let runLoop: CFRunLoop
    }

    private let config = Locked(TapConfig())
    private let router = Locked(KeyRouter())
    private let handles = Locked<Handles?>(nil)
    private let reenableTimes = Locked<[Date]>([])
    private let restartFlag = Locked(false)
    /// Le tap n'est actif que lorsque FL Studio est au premier plan. Le reste du temps il est coupé :
    /// aucune frappe ne transite par FL Shortcut, ni dans FL, ni ailleurs.
    private let wantsActive = Locked(false)
    /// Source privée : l'état des modificateurs postés ne se mélange pas au clavier physique (REL-13).
    private let postSource = CGEventSource(stateID: .privateState)

    private init() {}

    // MARK: Configuration (thread principal)

    func updateConfig(_ body: (inout TapConfig) -> Void) {
        config.withLock { body(&$0) }
    }

    var currentConfig: TapConfig { config.value }

    func purge() { router.withLock { $0.purge() } }

    // MARK: Cycle de vie

    var isRunning: Bool { handles.value != nil }

    var isEnabled: Bool {
        guard let h = handles.value else { return false }
        return CGEvent.tapIsEnabled(tap: h.tap)
    }

    /// Vrai si le tap est dans l'état voulu (actif quand FL est devant, coupé sinon).
    var isHealthy: Bool {
        guard let h = handles.value else { return false }
        return !wantsActive.value || CGEvent.tapIsEnabled(tap: h.tap)
    }

    /// Active le tap quand FL passe au premier plan, le coupe dès qu'il le quitte (thread principal).
    func setActive(_ active: Bool) {
        let changed = wantsActive.withLock { w -> Bool in
            defer { w = active }
            return w != active
        }
        guard changed else { return }
        if let h = handles.value { CGEvent.tapEnable(tap: h.tap, enable: active) }
        purge()
        // Tant que FL est devant, chaque frappe vers FL passe par notre callback : macOS ne doit pas mettre
        // l'app en sieste (App Nap), sinon la frappe attendrait que notre thread soit réveillé.
        if active, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Raccourcis clavier de FL Studio")
        } else if !active, let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    /// Activité « latence critique » tenue seulement pendant que FL est au premier plan (thread principal).
    private var activity: NSObjectProtocol?
    /// Une seule installation de tap à la fois (une installation lente ne doit jamais en laisser deux).
    private let installing = Locked(false)

    /// Vrai (une fois) si le tap a été coupé trop souvent et doit être recréé.
    func consumeRestartRequest() -> Bool {
        restartFlag.withLock { flag in
            defer { flag = false }
            return flag
        }
    }

    /// Crée le tap sur un thread dédié. Bloque au plus 2 s en attendant le résultat.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let claimed = installing.withLock { busy -> Bool in
            defer { busy = true }
            return !busy
        }
        guard claimed else { return false }
        let ready = DispatchSemaphore(value: 0)
        let result = Locked(false)
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            let ok = self.installTap()
            self.installing.withLock { $0 = false }
            result.withLock { $0 = ok }
            ready.signal()
            if ok { CFRunLoopRun() }          // rend la main quand la source est retirée ou la boucle arrêtée
        }
        thread.name = "FLShortcut.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        return result.value
    }

    func stop() {
        let old = handles.withLock { h -> Handles? in
            let o = h
            h = nil
            return o
        }
        purge()
        guard let old else { return }
        CGEvent.tapEnable(tap: old.tap, enable: false)
        CFRunLoopRemoveSource(old.runLoop, old.source, .commonModes)
        CFMachPortInvalidate(old.tap)
        CFRunLoopStop(old.runLoop)
    }

    @discardableResult
    func restart() -> Bool {
        stop()
        reenableTimes.withLock { $0.removeAll() }
        return start()
    }

    private func installTap() -> Bool {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: eventTapCallback,
                                          userInfo: nil) else { return false }
        let maybeSource: CFRunLoopSource? = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source = maybeSource else {
            CFMachPortInvalidate(tap)
            return false
        }
        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: wantsActive.value)
        handles.withLock { $0 = Handles(tap: tap, source: source, runLoop: runLoop) }
        purge()
        return true
    }

    // MARK: Thread du tap

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            purge()                           // des keyUp ont pu être perdus pendant la coupure
            reenableAfterDisable()
            return pass
        case .keyDown, .keyUp:
            break
        default:
            return pass
        }

        let isOwn = event.getIntegerValueField(.eventSourceUserData) == Self.mark
        if isOwn { return pass }

        let cfg = config.value
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let target = Int32(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        let destination = target != 0 ? target : cfg.frontmostPID
        var input = RouterInput(kind: type == .keyDown ? .down : .up,
                                combo: KeyCombo(keyCode: code, flags: event.flags),
                                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                isOwn: false,
                                targetIsFL: destination != 0 && cfg.flPIDs.contains(destination))
        // Touche seule qui lance un raccourci : FL s'en sert-il en ce moment (saisie, menu, clavier-piano) ? Lu
        // seulement dans ce cas, jamais pour les autres frappes ni au repos.
        if input.kind == .down, !input.isRepeat, input.targetIsFL, cfg.enabled, !cfg.recording,
           input.combo.isTypingKey, cfg.index.hasTrigger(input.combo) {
            input.typingInFL = TypingGuard.shared.reason(pid: destination) != nil
        }
        // Le routeur ne consulte le lien que pour une frappe destinée à FL (REL-28, SEC-07 : hors FL,
        // rien d'autre que keyCode / modificateurs n'est lu).
        let link = input.targetIsFL ? MIDILink.shared.core.routingView() : .offline
        let decision = router.withLock { $0.route(input, config: cfg, link: link) }

        var swallow = decision.swallow
        for effect in decision.effects {
            switch effect {
            case .sendAction(let id):
                // REL-06 : le lien a pu tomber entre la décision et l'envoi (ou CoreMIDI échouer) :
                // si aucune trame n'est partie, la touche va à FL telle quelle.
                if case .sent = MIDILink.shared.core.sendAction(id) { break }
                router.withLock { $0.release(code) }
                swallow = false
            case .post(let combo):
                if post(combo, to: destination, physical: event.flags) { break }
                // Injection refusée au dernier moment (FL plus au premier plan, cible interdite) :
                // appui initial rendu ; une répétition reste avalée (pas de répétition orpheline).
                if !input.isRepeat {
                    router.withLock { $0.release(code) }
                    swallow = false
                }
            case .runMacro(let macro):
                // La macro tourne sur sa propre file : jamais d'attente dans le thread du tap (REL-03).
                // Déjà en cours : le raccourci est avalé sans rien faire. Refusée : la touche va à FL telle quelle.
                switch MacroRunner.shared.start(macro, flPID: destination) {
                case .started, .busy:
                    break
                case .refused:
                    if !input.isRepeat {
                        router.withLock { $0.release(code) }
                        swallow = false
                    }
                }
            case .toggleEnabled:
                DispatchQueue.main.async { Store.shared.enabled.toggle() }
            }
        }
        return swallow ? nil : pass
    }

    /// Au plus 5 réactivations par minute ; au-delà, le superviseur recrée le tap et prévient l'utilisateur.
    private func reenableAfterDisable() {
        guard wantsActive.value else { return }   // coupé volontairement (FL n'est pas devant)
        let now = Date()
        let allowed = reenableTimes.withLock { times -> Bool in
            times.removeAll { now.timeIntervalSince($0) > 60 }
            guard times.count < 5 else { return false }
            times.append(now)
            return true
        }
        if allowed, let h = handles.value {
            CGEvent.tapEnable(tap: h.tap, enable: true)
        } else {
            restartFlag.withLock { $0 = true }
        }
    }

    /// Injection confinée à FL : PID revérifié avec la configuration la plus récente, liste noire revérifiée,
    /// puis postToPid (jamais post(tap:)), encadré de flagsChanged pour que FL voie les bons modificateurs.
    /// Renvoie faux si l'injection a été refusée (rien n'a été posté).
    private func post(_ target: KeyCombo, to pid: Int32, physical: CGEventFlags) -> Bool {
        let cfg = config.value
        guard pid != 0, cfg.flPIDs.contains(pid), cfg.frontmostPID == pid,
              !cfg.forbidden.isForbidden(target) else { return false }
        let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

        func postFlags(_ flags: CGEventFlags) {
            guard let e = CGEvent(source: postSource) else { return }
            e.type = .flagsChanged
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            e.postToPid(pid)
        }

        postFlags(target.cgFlags)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: postSource, virtualKey: target.keyCode, keyDown: down) else { continue }
            e.flags = target.cgFlags
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            e.postToPid(pid)
        }
        postFlags(physical.intersection(modifierMask))
        return true
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    EventTap.shared.handle(type: type, event: event)
}
