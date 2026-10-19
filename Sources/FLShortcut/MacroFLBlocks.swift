// Blocs propres à FL Studio (déplacés tels quels de l'ancien MacroRunner.swift, durées et journal identiques) :
// menu de la piste au clavier (lettres soulignées, Entrée apprise), armement et REC (lien MIDI d'abord, sinon au
// clavier), entrée « (none) » → 1 (apprise une fois), apprentissage des clics.
import AppKit
import CoreGraphics
import Foundation

/// Mémoire « Entrée après la dernière lettre » selon la politique du bloc. Apprise : clé UserDefaults historique
/// (`macroMenuEnterAfterLetter`, liste blanche de MacroValidation), lue et écrite exactement comme avant.
struct EnterMemory {
    let policy: EnterPolicy

    func read() -> Bool? {
        switch policy {
        case .learned(let key): return UserDefaults.standard.object(forKey: key) as? Bool
        case .always: return true
        case .ifNeeded, .never: return nil
        }
    }

    func write(_ value: Bool?) {
        guard case .learned(let key) = policy else { return }
        if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

extension MacroEffectsMac {
    // MARK: Menu de piste (ancré à la fenêtre du menu)

    /// Clic droit sur la piste, puis File › Open mixer track state AU CLAVIER : les éléments des menus de FL ont une
    /// lettre soulignée (« F » de File, « O » de Open…), comme sous Windows. Aucun clic dans le menu, aucune position
    /// à apprendre : FL peut placer son menu où il veut. Chaque touche n'est envoyée que si un menu de FL est ouvert
    /// (sinon une lettre irait à FL : clavier-piano…).
    func trackMenu(letters: [Character], labels: [String], at target: CGPoint, enter memory: EnterMemory,
                   ctx: Context) -> StepResult {
        guard !letters.isEmpty, letters.allSatisfy({ Self.letterKeyCodes[$0] != nil }) else {
            return .fail(String(localized: "menu de piste mal décrit"))
        }
        guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel(String(localized: "relâche les touches du raccourci")) }
        let before = WinSnapshot.take(pid: ctx.pid)
        MacroLog.shared.windows("before right-click", before)
        // Clic droit là où tu as cliqué la piste (comme dans la version validée).
        let r = click(at: target, right: true, ctx: ctx)
        guard case .ok = r else { return r }
        trackTarget = target

        // 1. Le menu de la piste s'ouvre (nouvelle fenêtre de FL).
        var opened: Set<Int> = []
        switch WindowWait.newWindow(pid: ctx.pid, excluding: before.numbers, timeout: 1.5,
                                    accept: { $0.isMenuLike }, stop: stopReason) {
        case .success(let menu):
            opened.insert(menu.number)
            MacroLog.shared.write("MENU", "track menu \(menu)")
            // FL place souvent son menu sous le curseur : son survol ouvrirait un sous-menu tout seul.
            hoverOutside(menu.bounds, pid: ctx.pid)
        case .failure(.stopped(let why)):
            closePopups(base: before.numbers, ctx: ctx)
            return .cancel(why)
        case .failure(.timeout):
            MacroLog.shared.windows("no menu after the right-click", WinSnapshot.take(pid: ctx.pid))
            return .fail(String(localized: "le menu de la piste ne s'est pas ouvert (clique sur le nom de ta piste dans le Mixer)"))
        }

        // 2. Lettres des sous-menus (File) : le sous-menu doit apparaître ; sinon flèche droite.
        for letter in letters.dropLast() {
            guard menusOpen(opened, ctx: ctx) else {
                MacroLog.shared.windows("menu closed before « \(letter) »", WinSnapshot.take(pid: ctx.pid))
                return .fail(String(localized: "le menu de FL s'est fermé tout seul"))
            }
            let known = WinSnapshot.take(pid: ctx.pid).numbers
            postLetter(letter, pid: ctx.pid)
            var sub = WindowWait.newWindow(pid: ctx.pid, excluding: known, timeout: 0.6,
                                           accept: { $0.isMenuLike }, stop: stopReason)
            if case .failure(.timeout) = sub {
                MacroLog.shared.write("KEY", "« \(letter) » : no submenu → right arrow")
                postKey(KeyCombo(keyCode: 124), pid: ctx.pid)
                sub = WindowWait.newWindow(pid: ctx.pid, excluding: known, timeout: 0.6,
                                           accept: { $0.isMenuLike }, stop: stopReason)
            }
            switch sub {
            case .success(let w):
                opened.insert(w.number)
                MacroLog.shared.write("MENU", "« \(letter) » → submenu \(w)")
            case .failure(.stopped(let why)):
                closePopups(base: before.numbers, ctx: ctx)
                return .cancel(why)
            case .failure(.timeout):
                MacroLog.shared.windows("« \(letter) » : still no submenu", WinSnapshot.take(pid: ctx.pid),
                                        mark: WinSnapshot.take(pid: ctx.pid).numbers.subtracting(before.numbers))
                closePopups(base: before.numbers, ctx: ctx)
                return .fail(String(localized: "le sous-menu « \(labels.first ?? "File") » ne s'est pas ouvert"))
            }
        }

        // 3. Dernière lettre (Open mixer track state) : tous les menus se ferment ; sinon Entrée (lettre partagée
        //    par plusieurs éléments : FL la surligne seulement).
        guard let last = letters.last else { return .fail(String(localized: "menu de piste mal décrit")) }
        guard menusOpen(opened, ctx: ctx) else { return .fail(String(localized: "le menu de FL s'est fermé trop tôt")) }
        postLetter(last, pid: ctx.pid)
        // La lettre ouvre l'élément, ou seulement le surligne (plusieurs éléments la partagent) : il faut alors Entrée.
        // Appris au premier passage, puis Entrée part aussitôt (sinon 0,6 s d'attente à chaque fois).
        let needsEnter = memory.read()
        if needsEnter != true {
            switch WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: needsEnter == false ? 0.8 : 0.5,
                                   stop: stopReason) {
            case .success:
                MacroLog.shared.write("MENU", "« \(last) » → menus closed")
                memory.write(false)
                return .ok
            case .failure(.stopped(let why)):
                return .cancel(why)
            case .failure(.timeout):
                MacroLog.shared.write("KEY", "« \(last) » : menus still open → Enter")
            }
        } else {
            // Courte attente quand même : si la lettre a suffi cette fois, Entrée ne doit pas tomber dans la boîte.
            _ = WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: 0.12, stop: stopReason)
            guard menusOpen(opened, ctx: ctx) else {
                // Cette fois la lettre a suffi (menu changé ?) : plus d'Entrée automatique.
                memory.write(false)
                MacroLog.shared.write("MENU", "« \(last) » → menus closed (Enter not needed any more)")
                return .ok
            }
        }
        postKey(KeyCombo(keyCode: 36), pid: ctx.pid)
        switch WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: 0.8, stop: stopReason) {
        case .success:
            MacroLog.shared.write("MENU", "Enter → menus closed")
            memory.write(true)
            return .ok
        case .failure(.stopped(let why)):
            return .cancel(why)
        case .failure(.timeout):
            closePopups(base: before.numbers, ctx: ctx)
            memory.write(nil)
            return .fail(String(localized: "« \(labels.last ?? "Open mixer track state") » n'a pas répondu"))
        }
    }

    /// Lien MIDI d'abord : FL confirme, et rien de déjà allumé n'est éteint. Sans lien, au clavier :
    /// - armement : menu de la piste › « Arm selected track(s) » (n'éteint jamais, Disarm est un autre élément) ;
    /// - REC : la touche REC de FL (R), qui inverse l'état sans le lire ;
    /// - mute / solo : le bouton mute de la piste cliquée (MacroMuteSolo.swift), qui inverse l'état.
    /// Actions consécutives d'une macro : un seul réveil du lien (généralisation de l'ancien armement + REC).
    func flActions(_ group: [FLActionCall], state: inout RunState) -> StepResult {
        let ids = group.compactMap { FLActions.id(forKey: $0.key) }
        guard ids.count == group.count, !ids.isEmpty else { return .fail(String(localized: "action de FL inconnue")) }
        let names = group.map { $0.key == "armon" ? "arm" : $0.key == "recon" ? "REC" : $0.key }
        guard let why = MIDILink.shared.runBriefly(ids) else {
            MacroLog.shared.write("MIDI", "\(names.joined(separator: " + ")) acknowledged")
            return .ok
        }
        MacroLog.shared.write("MIDI", "unavailable (\(why)) → keyboard")
        var warnings: [String] = []
        for call in group {
            switch call.fallback {
            case .trackMenuArm:
                let r = armViaKeyboard(ctx: ctx)
                switch r {
                case .cancel: return r
                case .fail(let w), .warn(let w): warnings.append(String(localized: "armement non fait : \(w)"))
                case .ok: break
                }
            case .key(let ref):
                if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
                let rec = call.key == "recon"
                if EventTap.shared.currentConfig.forbidden.isForbidden(ref.combo) {
                    warnings.append(rec ? String(localized: "REC non lancé (touche interdite)")
                                        : String(localized: "action « \(call.key) » non faite (touche interdite)"))
                } else {
                    Thread.sleep(forTimeInterval: 0.03)
                    postKey(ref.combo, pid: ctx.pid)
                    MacroLog.shared.write("KEY", rec ? "REC key" : "fallback key")
                }
            case .none where MuteSolo.handlesWithoutLink(call.key):
                // Mute / solo de la piste cliquée, sans le script (MacroMuteSolo.swift).
                let r = call.key == "mute" ? muteWithoutLink(ctx: ctx) : soloWithoutLink(ctx: ctx)
                guard case .ok = r else { return r }
            case .none:
                return .fail(String(localized: "ce bloc a besoin du lien avec FL (\(why))"))
            }
        }
        return warnings.isEmpty ? .ok : .warn(warnings.joined(separator: " ; "))
    }

    /// Menu de la piste au clavier : « S » (Select, lettre soulignée) ouvre son sous-menu, ← le referme en laissant
    /// « Select » surligné, puis ↓ ×5 et Entrée. Chaque touche n'est envoyée que si le menu de piste est encore ouvert.
    func armViaKeyboard(ctx: Context) -> StepResult {
        guard waitForKeyboardIdle(timeout: 1.0) else { return .cancel(String(localized: "relâche les touches du raccourci")) }
        let before = WinSnapshot.take(pid: ctx.pid)
        let r = click(at: trackTarget ?? ctx.track, right: true, ctx: ctx)
        guard case .ok = r else { return r }
        let menu: WinInfo
        switch WindowWait.newWindow(pid: ctx.pid, excluding: before.numbers, timeout: 1.5,
                                    accept: { $0.isMenuLike }, stop: stopReason) {
        case .success(let w): menu = w
        case .failure(.stopped(let why)):
            closePopups(base: before.numbers, ctx: ctx)
            return .cancel(why)
        case .failure(.timeout):
            return .fail(String(localized: "le menu de la piste ne s'est pas ouvert"))
        }
        MacroLog.shared.write("ARM", "track menu \(menu)")
        hoverOutside(menu.bounds, pid: ctx.pid)

        let known = WinSnapshot.take(pid: ctx.pid).numbers
        postLetter("s", pid: ctx.pid)
        guard case .success(let sub) = WindowWait.newWindow(pid: ctx.pid, excluding: known, timeout: 0.45,
                                                            accept: { $0.isMenuLike }, stop: stopReason) else {
            closePopups(base: before.numbers, ctx: ctx)
            return .fail(String(localized: "sous-menu « Select » non ouvert"))
        }
        MacroLog.shared.write("ARM", "« s » → submenu \(sub)")
        postKey(KeyCombo(keyCode: 123), pid: ctx.pid)                       // ←
        guard case .success = WindowWait.gone(pid: ctx.pid, numbers: [sub.number], timeout: 0.4, stop: stopReason),
              menusOpen([menu.number], ctx: ctx) else {
            closePopups(base: before.numbers, ctx: ctx)
            return .fail(String(localized: "le menu de FL n'a pas suivi les flèches"))
        }
        for _ in 0..<Self.armDownCount {
            postKey(KeyCombo(keyCode: 125), pid: ctx.pid)                   // ↓
            Thread.sleep(forTimeInterval: 0.015)
        }
        guard menusOpen([menu.number], ctx: ctx) else { return .fail(String(localized: "le menu de FL s'est fermé")) }
        postKey(KeyCombo(keyCode: 36), pid: ctx.pid)                        // Entrée
        switch WindowWait.gone(pid: ctx.pid, numbers: [menu.number], timeout: 0.8, stop: stopReason) {
        case .success:
            MacroLog.shared.write("ARM", "Enter → menu closed")
            restoreCursor()
            return .ok
        case .failure(.stopped(let why)):
            return .cancel(why)
        case .failure(.timeout):
            closePopups(base: before.numbers, ctx: ctx)
            return .fail(String(localized: "« Arm selected track(s) » n'a pas répondu"))
        }
    }

    /// Un menu de la taille apprise apparaît (FL peut le décaler n'importe où : seul son coin haut-gauche compte).
    /// Tout ce qui s'est ouvert d'autre est fermé (Échap, vérifié) et l'étape échoue : jamais de clic à l'aveugle.
    func awaitPopup(fitting hop: MacroSpots.PopupHop, excluding base: Set<Int>, timeout: TimeInterval,
                            ctx: Context) -> Result<WinInfo, MenuStop> {
        let began = Date()
        switch WindowWait.newWindow(pid: ctx.pid, excluding: base, timeout: timeout,
                                    accept: { $0.isMenuLike && hop.fits($0.bounds) },
                                    stop: stopReason) {
        case .success(let w):
            // Pas de question à l'Accessibilité ici : FL, dans sa boucle de menu, peut tarder à répondre.
            popupAX = false
            MacroLog.shared.write("MENU", "popup \(w) after \(Int(Date().timeIntervalSince(began) * 1000)) ms "
                + "(learned \(Int(hop.size.width))x\(Int(hop.size.height)))")
            return .success(w)
        case .failure(.stopped(let why)):
            closePopups(base: base, ctx: ctx)
            return .failure(.cancel(why))
        case .failure(.timeout):
            let snap = WinSnapshot.take(pid: ctx.pid)
            MacroLog.shared.windows("no popup of the learned size after \(Int(timeout * 1000)) ms", snap,
                                    mark: snap.numbers.subtracting(base))
            let other = snap.fl.first { !base.contains($0.number) && $0.isMenuLike }
            closePopups(base: base, ctx: ctx)
            if let other {
                return .failure(.fail(String(localized: "FL a ouvert un autre menu (\(Int(other.bounds.width))x\(Int(other.bounds.height))) : clique sur le nom de ta piste dans le Mixer, ou réapprends les clics")))
            }
            return .failure(.fail(String(localized: "le menu de FL ne s'est pas ouvert")))
        }
    }

    /// Clique chaque saut dans son propre menu ; entre deux sauts, attend le menu suivant (sous-menu) ; après le dernier,
    /// attend que tous les menus se ferment (preuve que l'élément a été pris).
    func runHops(_ hops: [MacroSpots.PopupHop], titles: [[String]], firstPopup: WinInfo,
                         base: Set<Int>, ctx: Context) -> StepResult {
        var popup = firstPopup
        var opened: Set<Int> = [firstPopup.number]
        for (i, hop) in hops.enumerated() {
            let byTitle = popupAX && i < titles.count ? AXProbe.itemCenter(in: popup, titles: titles[i]) : nil
            let p = byTitle ?? hop.point(in: popup.bounds)
            MacroLog.shared.write("HOP", "\(i + 1)/\(hops.count) in \(popup) → \(p.logText) "
                + (byTitle != nil ? "by AX title" : "by learned offset (\(Int(hop.offset.dx)),\(Int(hop.offset.dy)))"))
            let known = WinSnapshot.take(pid: ctx.pid).numbers
            let r = clickInside(p, popup: popup, ctx: ctx)
            guard case .ok = r else {
                closePopups(base: base, ctx: ctx)
                return r
            }
            if i + 1 < hops.count {
                switch awaitPopup(fitting: hops[i + 1], excluding: known.union(opened), timeout: 1.2, ctx: ctx) {
                case .success(let next):
                    popup = next
                    opened.insert(next.number)
                case .failure(let stop):
                    closePopups(base: base, ctx: ctx)
                    return result(stop)
                }
            } else {
                switch WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: 1.0, stop: stopReason) {
                case .success:
                    MacroLog.shared.write("MENU", "all popups closed after the last click")
                case .failure(.stopped(let why)):
                    return .cancel(why)
                case .failure(.timeout):
                    closePopups(base: base, ctx: ctx)
                    return .fail(String(localized: "le menu de FL est resté ouvert après le clic (élément manqué : réapprends les clics)"))
                }
            }
        }
        restoreCursor()
        return .ok
    }

    /// Ancien format, décalages enchaînés (menus dans la fenêtre de FL seulement). Invérifiable : gardé pour le rejeu exact.
    func replayChain(_ offsets: [CGVector], from anchor: CGPoint, ctx: Context) -> StepResult {
        for p in MacroSpots.Learned(anchorSize: .zero, offsets: offsets).points(from: anchor) {
            if case .cancel(let why) = pause(220, pid: ctx.pid) { return .cancel(why) }
            let r = click(at: p, right: false, ctx: ctx)
            guard case .ok = r else { return r }
        }
        if case .cancel(let why) = pause(150, pid: ctx.pid) { return .cancel(why) }
        restoreCursor()
        return .ok
    }

    // MARK: Apprentissage (retient la fenêtre où est tombé chaque clic de l'utilisateur)

    /// La bulle s'affiche AVANT le clic droit (aucune fenêtre ne passe devant quand le menu de FL est ouvert), sur
    /// l'autre moitié de l'écran. Les fenêtres de FL sont relevées toutes les 15 ms ; chaque clic de l'utilisateur est
    /// attribué à la fenêtre tout devant sous lui dans le dernier relevé pris avant l'instant du clic.
    func learnPath(_ kind: MacroSpots.PathKind, clicks n: Int, hint: String, hintAt: CGPoint,
                           rightClick: Bool, ctx: Context) -> StepResult {
        guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel(String(localized: "relâche les touches du raccourci")) }
        DispatchQueue.main.sync {
            ClickRecorder.shared.start()
            HintPanel.shared.show(hint, near: hintAt)
        }
        defer { DispatchQueue.main.async { ClickRecorder.shared.stop(); HintPanel.shared.hide() } }
        let before = WinSnapshot.take(pid: ctx.pid)
        MacroLog.shared.windows("learn \(kind.rawValue): before", before)
        var row: MacroSpots.TrackRow?
        if rightClick {
            if let w = before.fl.first(where: { $0.layer == 0 && $0.bounds.contains(ctx.track) }) {
                row = MacroSpots.TrackRow(yFromWindowTop: ctx.track.y - w.bounds.minY, windowSize: w.bounds.size)
            }
            let r = click(at: ctx.track, right: true, ctx: ctx)
            guard case .ok = r else { return r }
            restoreCursor()                                          // l'utilisateur prend la main ici
        }
        var history: [WinSnapshot] = []
        var samples: [ClickSample] = []
        let deadline = Date().addingTimeInterval(60)
        while samples.count < n {
            if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
            guard Date() < deadline else { return .fail(String(localized: "clics non montrés (60 s)")) }
            let snap = WinSnapshot.take(pid: ctx.pid)
            if let last = history.last, last.numbers != snap.numbers {
                MacroLog.shared.windows("learn: windows changed", snap, mark: snap.numbers.subtracting(before.numbers))
            }
            history.append(snap)
            if history.count > 200 { history.removeFirst(history.count - 200) }
            samples = ClickRecorder.shared.capturedSamples
            Thread.sleep(forTimeInterval: 0.015)
        }
        let used = Array(samples.prefix(n))
        var path = MacroSpots.resolve(used, history: history, base: before.numbers,
                                      anchor: ctx.track, firstInWindow: !rightClick)
        path.row = row
        for (i, s) in used.enumerated() {
            let hitWindow = (history.last(where: { $0.time <= s.time }) ?? history.first)?.hit(s.point)
            MacroLog.shared.write("LEARN", "click \(i + 1) at \(s.point.logText) in \(hitWindow?.description ?? "no FL window")")
        }
        MacroLog.shared.write("LEARN", "\(kind.rawValue) = \(MacroSpots.describe(path))")
        guard path.isValid else { return .fail(String(localized: "clics non reconnus : refais le raccourci pour recommencer")) }
        MacroSpots.savePath(path, kind)
        return .ok
    }

    // MARK: Entrée « (none) » → 1

    func selectInput(ctx: Context) -> StepResult {
        let snap = WinSnapshot.take(pid: ctx.pid)
        if let path = MacroSpots.loadPath(.input), let start = path.start,
           let window = Self.inputWindow(in: snap, size: start.windowSize, track: ctx.track) {
            guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel(String(localized: "relâche les touches du raccourci")) }
            let p0 = CGPoint(x: window.bounds.maxX + start.fromTopRight.dx, y: window.bounds.minY + start.fromTopRight.dy)
            MacroLog.shared.write("INPUT", "selector \(p0.logText) in \(window)")
            let r = click(at: p0, right: false, ctx: ctx)
            guard case .ok = r else { return r }
            if let first = path.hops.first {
                switch awaitPopup(fitting: first, excluding: snap.numbers, timeout: 1.2, ctx: ctx) {
                case .success(let list): return runHops(path.hops, titles: [], firstPopup: list, base: snap.numbers, ctx: ctx)
                case .failure(let stop): return result(stop)
                }
            }
            if let inline = path.inline { return replayChain(inline.offsets, from: p0, ctx: ctx) }
            return .fail(String(localized: "entrée à réapprendre (fiche du raccourci)"))
        }
        // Pas appris, ou la fenêtre de FL a changé de taille : l'utilisateur le montre (une fois).
        guard let main = snap.fl.filter({ $0.layer == 0 })
                .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else {
            return .fail(String(localized: "fenêtre de FL introuvable"))
        }
        return learnPath(.input, clicks: 2,
                         hint: String(localized: "Une seule fois : clique sur « (none) » de la piste, puis sur l'entrée « 1 »."),
                         hintAt: CGPoint(x: main.bounds.maxX - 160, y: main.bounds.minY + 90), rightClick: false, ctx: ctx)
    }

    /// Fenêtre de FL de la taille apprise : d'abord celle qui contient la piste (Mixer détaché), sinon n'importe laquelle.
    static func inputWindow(in snap: WinSnapshot, size: CGSize, track: CGPoint) -> WinInfo? {
        let fits = snap.fl.filter { $0.layer == 0 && MacroSpots.sameSize($0.bounds.size, size) }
        return fits.first { $0.bounds.contains(track) } ?? fits.first
    }
}

extension MacroEffectsMac {
    // MARK: « Cliquer sur… » : canal par son numéro, nom de la piste (jamais la souris)

    /// Mute ou solo du canal `number` : le script de FL le bascule lui-même (opération 13, ni touche ni clic) ; sans
    /// le lien, jusqu'au canal 10, la touche 1 à 0 de FL (⌘ pour le solo), le Channel rack devant.
    func toggleChannel(_ number: Int, solo: Bool, layout: KeyboardLayout, ctx: Context) -> StepResult {
        let what = solo ? "solo" : "mute"
        let key = PageOptions.channelKey(number, solo: solo, layout: layout)
        if key == nil || MIDILink.shared.core.snapshot.hasKey {
            switch MIDILink.shared.runMacroRequest(OrganizerPayload.toggleChannel(number - 1, solo: solo)) {
            case .answered:
                MacroLog.shared.write("FL", "channel \(what) by link")
                return .ok
            case .refused(5) where key == nil:
                // Aussi la réponse d'un script d'avant la v7 (opération inconnue).
                return .fail(String(localized: "canal \(number) absent du Channel rack (ou script de FL pas à jour : redémarre FL)"))
            case .refused(let reason) where key == nil:
                return .fail(String(localized: "FL a refusé le \(what) du canal (raison \(reason))"))
            case .failed(let why) where key == nil:
                return .fail(why + String(localized: " (au-delà du canal 10, seul le lien avec FL le fait)"))
            default:
                MacroLog.shared.write("FL", "channel \(what): link unavailable, FL key")
            }
        }
        guard let key else { return .fail(String(localized: "canal \(number) : lien avec FL nécessaire")) }
        if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
        postKey(key, pid: ctx.pid)
        MacroLog.shared.write("FL", "channel \(what) by key")
        return .ok
    }

    /// Nouveau nom de la piste sélectionnée : le script de FL le pose (opération 1, rien n'est tapé) ; sans le lien,
    /// la fenêtre F2 de FL, le nom tapé par-dessus l'ancien, puis Entrée. Le nom n'est jamais journalisé.
    func renameTrack(_ name: String, ctx: Context) -> StepResult {
        let payload = NameColorPayload(name: name, color: nil)
        guard let clean = payload.name else { return .fail(String(localized: "nouveau nom de la piste à écrire dans « Cliquer sur… »")) }
        switch MIDILink.shared.runMacroData(payload.units) {
        case .done:
            MacroLog.shared.write("FL", "track renamed by link")
            return .ok
        case .refused(let reason):
            return .fail(NameColorPayload.message(forReason: reason))
        case .failed:
            MacroLog.shared.write("FL", "rename: link unavailable, F2 window")
        }
        guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel(String(localized: "relâche les touches du raccourci")) }
        let before = WinSnapshot.take(pid: ctx.pid)
        postKey(KeyCombo(keyCode: 120), pid: ctx.pid)                                    // F2
        let box: WinInfo
        switch WindowWait.newWindow(pid: ctx.pid, excluding: before.numbers, timeout: 1.5, accept: { _ in true },
                                    stop: stopReason) {
        case .success(let w): box = w
        case .failure(.stopped(let why)): return .cancel(why)
        case .failure(.timeout):
            return .fail(String(localized: "la fenêtre « Renommer » de FL ne s'est pas ouverte (sélectionne ta piste dans le Mixer)"))
        }
        let layout = SystemKeyboardLayout()
        postKey(KeyCombo(keyCode: KeyNames.commandKeyCode(for: "a", layout: layout) ?? 0, command: true), pid: ctx.pid)
        usleep(30_000)
        guard PresetChooser.type(clean, pid: ctx.pid, stop: stopReason) else {
            return .cancel(stopReason() ?? String(localized: "FL n'est plus au premier plan"))
        }
        usleep(30_000)
        postKey(KeyCombo(keyCode: 36), pid: ctx.pid)                                     // Entrée
        switch WindowWait.gone(pid: ctx.pid, numbers: [box.number], timeout: 1.5, stop: stopReason) {
        case .success:
            MacroLog.shared.write("FL", "track renamed by F2 window")
            return .ok
        case .failure(.stopped(let why)): return .cancel(why)
        case .failure(.timeout): return .fail(String(localized: "la fenêtre « Renommer » de FL est restée ouverte"))
        }
    }
}
