// Essai de bout en bout de la macro « Enregistrement rapide » contre le FL simulé (FakeFL.swift), sur la CI macOS :
//   FLShortcut --fake-fl état.json &            (le faux FL, processus à part comme le vrai)
//   FLShortcut --selftest-macro sortie.txt état.json <pid du faux FL>
// Le pilote joue l'utilisateur (clic sur la piste 3, puis, la première fois, « (none) » et « In 1 » quand la bulle
// le demande), lance la vraie macro (MacroRunner, développée en blocs et jouée par l'interpréteur) et vérifie l'état
// du faux FL après chaque passage :
// preset choisi chargé SUR LA PISTE 3, piste 3 armée, REC allumé, entrée « In 1 », aucune action inattendue.
// Six passages : preset DÉPOSÉ sur la piste (apprentissage de l'entrée, rejeu), puis le chemin d'origine par le menu
// de la piste et la boîte « Open » (« O » qui ouvre, rejeu, « O » qui ne fait que surligner, Entrée apprise).
// Les durées de chaque étape sont affichées : c'est la mesure de vitesse de la macro.
// `--scenario blocs` : une macro CONSTRUITE EN BLOCS par le code (comme dans le créateur, pas le modèle) — clic droit
// sur la piste 5, S (Select), ←, ↓ ×5, Entrée (« Arm selected track(s) »), puis la touche REC — compilée comme une
// macro de la bibliothèque et lancée par le même chemin que « Tester » dans le créateur (MacroRunMonitor) ; on
// vérifie « arm 5 », « rec on », rien d'autre, et le suivi bloc par bloc.
import AppKit
import CoreGraphics
import Foundation

enum MacroSelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest-macro"), args.count > i + 3 else { return }
        freopen(args[i + 1], "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
        let statePath = args[i + 2]
        guard let pid = Int32(args[i + 3]) else { print("FAIL: pid invalide"); exit(1) }
        guard CGPreflightPostEventAccess() else {
            print("SKIP: pas d'autorisation d'envoi d'événements pour ce programme")
            exit(0)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let name = args.firstIndex(of: "--scenario").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil } ?? "modele"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok: Bool
            if name == "blocs" {
                ok = scenarioBlocs(statePath: statePath, pid: pid)
                print(ok ? "PASS: macro construite en blocs sur le FL simulé (piste 5 armée par son menu, REC)" : "FAIL: voir ci-dessus")
            } else if name == "clics" {
                ok = scenarioClics(statePath: statePath, pid: pid)
                print(ok ? "PASS: suite de clics enregistrée puis rejouée (menus de FL et de la barre, fenêtre des réglages)" : "FAIL: voir ci-dessus")
            } else if name == "touches" {
                ok = scenarioTouches(statePath: statePath, pid: pid)
                print(ok ? "PASS: clics et touches enregistrés puis rejoués (↓ et Entrée dans les menus, ⌘S, R)" : "FAIL: voir ci-dessus")
            } else {
                ok = scenario(statePath: statePath, pid: pid)
                print(ok ? "PASS: macro complète sur le FL simulé (6 passages : preset déposé, puis par la boîte « Open »)" : "FAIL: voir ci-dessus")
            }
            fflush(stdout)
            exit(ok ? 0 : 1)
        }
        app.run()
        exit(1)
    }

    // MARK: État du faux FL

    struct FakeState {
        var raw: [String: Any]
        var armed: [Int] { raw["armed"] as? [Int] ?? [] }
        var rec: Bool { raw["rec"] as? Bool ?? false }
        var input: String { raw["input"] as? String ?? "?" }
        var preset: String { raw["preset"] as? String ?? "" }
        var presetTrack: Int { raw["presetTrack"] as? Int ?? 0 }
        var events: [String] { raw["events"] as? [String] ?? [] }
        var menusOpen: Int { raw["menusOpen"] as? Int ?? 0 }
        var settingsOpen: Bool { raw["settingsOpen"] as? Bool ?? false }
        var device: String { raw["device"] as? String ?? "?" }
        var autoClose: Bool { raw["autoClose"] as? Bool ?? false }
        func point(_ key: String) -> CGPoint? {
            guard let g = raw["geometry"] as? [String: [Double]], let v = g[key], v.count == 2 else { return nil }
            return CGPoint(x: v[0], y: v[1])
        }
    }

    static func read(_ path: String) -> FakeState? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return FakeState(raw: obj)
    }

    static func waitState(_ path: String, timeout: TimeInterval, _ ok: (FakeState) -> Bool) -> FakeState? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if let s = read(path), ok(s) { return s }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < end
        return nil
    }

    // MARK: L'utilisateur simulé (événements NON marqués : ce sont « ses » clics)

    static func userClick(_ p: CGPoint) {
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 30_000 : 50_000)
        }
    }

    /// Touche de l'utilisateur (appui puis relâche), ⌘ tenu si `command`.
    static func userKey(_ code: CGKeyCode, command: Bool = false) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            e?.flags = command ? .maskCommand : []            // jamais un ⌘ resté d'une touche précédente
            e?.post(tap: .cghidEventTap)
            usleep(40_000)
        }
    }

    static func frontmost() -> Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    // MARK: Scénario

    static func scenario(statePath: String, pid: Int32) -> Bool {
        guard let first = waitState(statePath, timeout: 15, { $0.point("track3") != nil }),
              let empty = first.point("empty"), let track3 = first.point("track3") else {
            print("FAIL: le FL simulé ne répond pas (\(statePath))")
            return false
        }
        // Au premier plan, comme FL quand l'utilisateur fait son raccourci.
        if frontmost() != pid { userClick(empty) }
        let end = Date().addingTimeInterval(3)
        while frontmost() != pid, Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        print("au premier plan : \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") (\(frontmost() ?? 0)), FL simulé \(pid)")
        guard frontmost() == pid else { print("FAIL: le FL simulé n'est pas au premier plan"); return false }

        // Presets à choisir (le bon au milieu, avec espaces et parenthèses dans le nom).
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fls-presets-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["Autre.fst", "Voix lead (micro 1).fst", "Zz.fst"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("FLS".utf8))
        }
        let wanted = dir.appendingPathComponent("Voix lead (micro 1).fst").resolvingSymlinksInPath().path

        var macro = Macro()
        macro.presetPath = wanted
        macro.recKey = KeyCombo(keyCode: 15)
        let program = MacroProgram.compile(macro, forbidden: .physical)
        guard program.isRunnable else {
            print("FAIL: macro invalide")
            return false
        }
        // La vérification du larsen ouvrirait une fenêtre d'alerte (sans rapport avec FL) : retirée de l'essai.
        let dropBlocks = program.blocks.filter { $0.body != .feedbackCheck }
        let menuBlocks = MacroTemplates.enregistrementRapide(macro, presetLoad: .menu).filter { $0.body != .feedbackCheck }
        print("étapes (preset déposé) : " + dropBlocks.map { BlockRegistry.journal(of: $0.body) }.joined(separator: " > "))
        print("étapes (boîte « Open ») : " + menuBlocks.map { BlockRegistry.journal(of: $0.body) }.joined(separator: " > "))

        MacroSpots.forgetAll()
        MacroRunner.testFLPID = pid
        MacroRunner.testTrackPoint = track3

        // L'utilisateur montre l'entrée quand la macro le demande (premier passage seulement).
        let learning = Locked(false)
        MacroLog.shared.echo = { tag, text, t in
            print(String(format: "    %6.3f s  %@ %@", t, tag, text))
            if tag == "WIN", text.contains("learn macroSpots.v2.input: before"), !learning.value {
                learning.withLock { $0 = true }
                DispatchQueue.global().async {
                    Thread.sleep(forTimeInterval: 0.4)
                    guard let s = read(statePath), let sel = s.point("selector") else { return }
                    print("    (utilisateur) clic sur « (none) »")
                    userClick(sel)
                    guard let open = waitState(statePath, timeout: 2, { $0.point("input:In 1") != nil }),
                          let in1 = open.point("input:In 1") else {
                        print("    (utilisateur) la liste des entrées ne s'est pas ouverte")
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                    print("    (utilisateur) clic sur « In 1 »")
                    userClick(in1)
                }
            }
        }

        var allOK = true
        let runs: [(String, Bool, Bool)] = [
            ("1 · preset déposé, apprentissage de l'entrée", false, true), ("2 · preset déposé, rejeu", false, true),
            ("3 · boîte « Open »", false, false), ("4 · boîte « Open », rejeu", false, false),
            ("5 · boîte « Open », « O » surligne seulement (Entrée)", true, false),
            ("6 · boîte « Open », rejeu avec Entrée apprise", true, false),
        ]
        for (label, highlight, dropped) in runs {
            let blocks = dropped ? dropBlocks : menuBlocks
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("app.flshortcut.fakefl.mode"), object: highlight ? "highlight" : "activate",
                userInfo: nil, deliverImmediately: true)
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("app.flshortcut.fakefl.reset"), object: nil, userInfo: nil, deliverImmediately: true)
            _ = waitState(statePath, timeout: 3) { s in
                s.events.isEmpty && !s.rec && s.armed.isEmpty && (s.raw["oHighlights"] as? Bool) == highlight
            }
            if frontmost() != pid { userClick(empty) }
            // L'utilisateur clique sur sa piste avant le raccourci.
            userClick(track3)
            Thread.sleep(forTimeInterval: 0.3)
            print("\n== Passage \(label) ==")
            let t0 = Date()
            let outcome = MacroRunner.shared.runForTest(blocks, pid: pid)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            Thread.sleep(forTimeInterval: 0.3)
            let s = read(statePath) ?? FakeState(raw: [:])
            let load = dropped ? "drop Voix lead (micro 1).fst on 3" : "open Voix lead (micro 1).fst"
            let expectedEvents = Set(["arm 3", "rec on", "input In 1", load])
            let unexpected = s.events.filter { !expectedEvents.contains($0) }
            var problems: [String] = []
            if s.preset != wanted { problems.append("preset « \(s.preset) » au lieu du bon") }
            if s.presetTrack != 3 { problems.append("preset chargé sur la piste \(s.presetTrack) au lieu de la 3") }
            if !s.events.contains(load) { problems.append("preset pas chargé par « \(load) »") }
            if !s.armed.contains(3) { problems.append("piste 3 non armée (\(s.armed))") }
            if !s.rec { problems.append("REC éteint") }
            if s.input != "In 1" { problems.append("entrée « \(s.input) »") }
            if !unexpected.isEmpty { problems.append("actions inattendues : \(unexpected)") }
            if s.menusOpen != 0 { problems.append("\(s.menusOpen) menu(s) resté(s) ouvert(s)") }
            print("résultat : \(outcome.text) — \(ms) ms au total" + (dropped ? " (preset déposé, sans boîte « Open »)" : " (dont l'attente de la boîte « Open » par macOS)"))
            print("FL simulé : preset=\(URL(fileURLWithPath: s.preset).lastPathComponent) armées=\(s.armed) REC=\(s.rec) entrée=\(s.input) actions=\(s.events)")
            if problems.isEmpty {
                print("OK passage \(label)")
            } else {
                allOK = false
                print("ÉCHEC passage \(label) : " + problems.joined(separator: " ; "))
            }
        }
        MacroLog.shared.echo = nil
        MacroRunner.testFLPID = nil
        MacroRunner.testTrackPoint = nil
        try? FileManager.default.removeItem(at: dir)
        return allOK
    }

    // MARK: Scénario « blocs »

    static func scenarioBlocs(statePath: String, pid: Int32) -> Bool {
        guard let first = waitState(statePath, timeout: 15, { $0.point("track5") != nil }),
              let empty = first.point("empty"), let track5 = first.point("track5") else {
            print("FAIL: le FL simulé ne répond pas (\(statePath))")
            return false
        }
        // FL simulé remis à zéro, lettres des menus qui activent leur élément.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("app.flshortcut.fakefl.mode"), object: "activate", userInfo: nil, deliverImmediately: true)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("app.flshortcut.fakefl.reset"), object: nil, userInfo: nil, deliverImmediately: true)
        _ = waitState(statePath, timeout: 3) { s in
            s.events.isEmpty && !s.rec && s.armed.isEmpty && (s.raw["oHighlights"] as? Bool) == false
        }
        if frontmost() != pid { userClick(empty) }
        let end = Date().addingTimeInterval(3)
        while frontmost() != pid, Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        print("au premier plan : \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") (\(frontmost() ?? 0)), FL simulé \(pid)")
        guard frontmost() == pid else { print("FAIL: le FL simulé n'est pas au premier plan"); return false }

        // Macro construite bloc par bloc (pas le modèle), compilée comme une macro de la bibliothèque.
        let doc = MacroDoc(name: "Armer la piste 5 et lancer le REC (blocs)",
                           blocks: MacroTemplates.armThroughTrackMenu(rec: KeyRef(KeyCombo(keyCode: 15), char: "r")))
        let program = MacroProgram.compile(doc, forbidden: .physical)
        guard program.isRunnable else {
            print("FAIL: macro invalide : \(program.problem ?? "?")")
            return false
        }
        print("blocs : " + doc.blocks.map { BlockRegistry.journal(of: $0.body) }.joined(separator: " > "))

        MacroRunner.testFLPID = pid
        MacroRunner.testTrackPoint = track5
        MacroLog.shared.echo = { tag, text, t in print(String(format: "    %6.3f s  %@ %@", t, tag, text)) }
        defer {
            MacroLog.shared.echo = nil
            MacroRunner.testFLPID = nil
            MacroRunner.testTrackPoint = nil
        }

        // Même chemin que « Tester » dans le créateur : suivi bloc par bloc, démarrage comme un raccourci.
        let monitor = MacroRunMonitor()
        let finished = DispatchSemaphore(value: 0)
        let outcome = Locked<MacroOutcome?>(nil)
        print("\n== Passage blocs : clic droit sur la piste 5, S, ←, ↓ ×5, Entrée, puis R ==")
        let t0 = Date()
        let started: MacroRunner.StartResult = DispatchQueue.main.sync {
            monitor.start(program, pid: pid) { o in
                outcome.withLock { $0 = o }
                finished.signal()
            }
        }
        guard started == .started else {
            print("FAIL: essai refusé (\(started))")
            return false
        }
        guard finished.wait(timeout: .now() + 30) == .success else {
            print("FAIL: la macro ne s'est pas terminée en 30 s")
            return false
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        Thread.sleep(forTimeInterval: 0.3)
        let s = read(statePath) ?? FakeState(raw: [:])
        let report: (statuses: [UUID: MacroRunMonitor.Status], current: UUID?) = DispatchQueue.main.sync {
            (monitor.statuses, monitor.current)
        }
        var problems: [String] = []
        if outcome.value != .done { problems.append("résultat « \(outcome.value?.text ?? "aucun") »") }
        if s.events != ["arm 5", "rec on"] { problems.append("actions \(s.events) au lieu de [arm 5, rec on]") }
        if !s.armed.contains(5) { problems.append("piste 5 non armée (\(s.armed))") }
        if !s.rec { problems.append("REC éteint") }
        if s.menusOpen != 0 { problems.append("\(s.menusOpen) menu(s) resté(s) ouvert(s)") }
        let notDone = doc.blocks.indices.filter { i in
            if case .done? = report.statuses[doc.blocks[i].id] { return false }
            return true
        }
        if !notDone.isEmpty { problems.append("suivi : bloc(s) \(notDone.map { $0 + 1 }) sans « fait »") }
        if report.current != nil { problems.append("un bloc reste marqué « en cours »") }
        print("résultat : \(outcome.value?.text ?? "?") — \(ms) ms au total")
        print("suivi du créateur : \(report.statuses.count) bloc(s) suivis, \(doc.blocks.count - notDone.count)/\(doc.blocks.count) faits")
        print("FL simulé : sélectionnée=\(s.raw["selected"] ?? "?") armées=\(s.armed) REC=\(s.rec) actions=\(s.events)")
        if problems.isEmpty {
            print("OK passage blocs")
        } else {
            print("ÉCHEC passage blocs : " + problems.joined(separator: " ; "))
        }
        return problems.isEmpty
    }

    // MARK: Scénario « clics »

    /// FL simulé remis à zéro (réglages fermés, carte « Built-in »), au premier plan.
    static func resetFake(_ statePath: String, pid: Int32) -> Bool {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("app.flshortcut.fakefl.reset"), object: nil, userInfo: nil, deliverImmediately: true)
        guard let s = waitState(statePath, timeout: 3, { s in
            s.events.isEmpty && !s.settingsOpen && s.device == "Built-in" && !s.autoClose && s.menusOpen == 0
        }), let empty = s.point("empty") else {
            print("FAIL: le FL simulé ne s'est pas remis à zéro")
            return false
        }
        if frontmost() != pid { userClick(empty) }
        let end = Date().addingTimeInterval(3)
        while frontmost() != pid, Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        guard frontmost() == pid else {
            print("FAIL: le FL simulé n'est pas au premier plan")
            return false
        }
        return true
    }

    /// « Enregistrer des clics » de bout en bout : l'utilisateur simulé (événements NON marqués) clique OPTIONS ›
    /// Audio settings dans la fenêtre de FL, la carte son et la case de la fenêtre des réglages (niveau 8 comme les
    /// boîtes de FL), Fermer ; puis Options › Audio settings par la barre des menus de macOS, Fermer. L'enregistreur
    /// en fait des blocs, rejoués ensuite sur le FL simulé remis à zéro : mêmes actions, rien d'autre.
    static func scenarioClics(statePath: String, pid: Int32) -> Bool {
        guard waitState(statePath, timeout: 15, { $0.point("options") != nil }) != nil else {
            print("FAIL: le FL simulé ne répond pas (\(statePath))")
            return false
        }
        guard resetFake(statePath, pid: pid) else { return false }
        MacroRunner.testFLPID = pid
        MacroLog.shared.echo = { tag, text, t in print(String(format: "    %6.3f s  %@ %@", t, tag, text)) }
        defer {
            MacroLog.shared.echo = nil
            MacroRunner.testFLPID = nil
        }

        // 1. Enregistrement : l'utilisateur clique, l'app recopie.
        print("\n== Enregistrement d'une suite de clics ==")
        func click(_ what: String, _ key: String, until: (FakeState) -> Bool) -> Bool {
            clickFake(statePath, what, key, until: until)
        }
        /// Menu de macOS : comme une vraie souris, le pointeur glisse jusqu'à l'élément (le menu le surligne), puis
        /// clique ; un clic sec, sans survol, referme parfois le menu sans rien choisir.
        func barClick(_ what: String, _ titles: [String], until: ((FakeState) -> Bool)? = nil) -> Bool {
            guard let f = MenuBarAX.frame(pid: pid, titles: titles) else {
                print("FAIL: \(what) : introuvable par l'Accessibilité")
                return false
            }
            let p = CGPoint(x: f.midX, y: f.midY)
            for dx in [-12.0, -6, 0] {
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x + dx, y: p.y),
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(40_000)
            }
            userClick(p)
            if let until, waitState(statePath, timeout: 3, until) == nil {
                print("FAIL: \(what) : le FL simulé n'a pas réagi (\(read(statePath)?.events ?? []))")
                return false
            }
            print("  clic : \(what)")
            Thread.sleep(forTimeInterval: 0.4)
            return true
        }
        let recorded = record(pid: pid) {
            var clicked = click("OPTIONS (dans la fenêtre de FL)", "options") { s in s.menusOpen == 1 }
            if clicked {
                clicked = click("Audio settings (menu de FL)", "item:Audio settings") { s in s.settingsOpen && s.menusOpen == 0 }
            }
            if clicked { clicked = click("carte son (fenêtre des réglages)", "settings:device") { s in s.menusOpen == 1 } }
            if clicked {
                clicked = click("Interface USB (liste de la carte son)", "item:Interface USB") { s in
                    s.device == "Interface USB" && s.menusOpen == 0
                }
            }
            if clicked { clicked = click("case Auto close device", "settings:toggle") { s in s.autoClose } }
            if clicked { clicked = click("Fermer les réglages", "settings:close") { s in !s.settingsOpen } }
            if clicked { clicked = barClick("Options (barre des menus de macOS)", ["Options"]) }
            if clicked {
                clicked = barClick("Audio settings (menu de la barre)", ["Options", "Audio settings"]) { s in s.settingsOpen }
            }
            if clicked { clicked = click("Fermer les réglages ouverts par la barre", "settings:close") { s in !s.settingsOpen } }
            return clicked
        }
        guard let result = recorded else { return false }
        let kinds = result.blocks.map(kindOf)
        print("blocs : " + kinds.joined(separator: " > ") + " · clics ignorés : \(result.ignored)")
        let expected = ["fenêtre", "menu", "fenêtre", "menu", "fenêtre", "fenêtre", "barre[Options › Audio settings]", "fenêtre"]
        guard kinds == expected, result.ignored == 0 else {
            print("FAIL: blocs attendus : " + expected.joined(separator: " > "))
            return false
        }

        // 2. Rejeu des blocs obtenus, par le même chemin que « Tester » dans le créateur.
        guard resetFake(statePath, pid: pid) else { return false }
        print("\n== Rejeu des clics enregistrés ==")
        guard let replayed = replay(result.blocks, name: "Réglages audio (clics enregistrés)", pid: pid) else { return false }
        let (outcome, ms) = replayed
        let s = read(statePath) ?? FakeState(raw: [:])
        let wanted = ["settings open", "device Interface USB", "auto close on", "settings close", "settings open", "settings close"]
        var problems: [String] = []
        if outcome != .done { problems.append("résultat « \(outcome?.text ?? "aucun") »") }
        if s.events != wanted { problems.append("actions \(s.events) au lieu de \(wanted)") }
        if s.device != "Interface USB" { problems.append("carte son « \(s.device) »") }
        if !s.autoClose { problems.append("case non cochée") }
        if s.settingsOpen { problems.append("réglages restés ouverts") }
        if s.menusOpen != 0 { problems.append("\(s.menusOpen) menu(s) resté(s) ouvert(s)") }
        print("résultat : \(outcome?.text ?? "?") — \(ms) ms au total")
        print("FL simulé : carte=\(s.device) case=\(s.autoClose) réglages=\(s.settingsOpen) actions=\(s.events)")
        if problems.isEmpty {
            print("OK rejeu des clics")
        } else {
            print("ÉCHEC rejeu des clics : " + problems.joined(separator: " ; "))
        }
        return problems.isEmpty
    }

    // MARK: Enregistrement et rejeu (scénarios « clics » et « touches »)

    /// Clic de l'utilisateur sur un repère du FL simulé, puis sa réaction attendue.
    static func clickFake(_ statePath: String, _ what: String, _ key: String, until: (FakeState) -> Bool) -> Bool {
        guard let p = read(statePath)?.point(key) else {
            print("FAIL: \(what) : position « \(key) » inconnue du FL simulé")
            return false
        }
        userClick(p)
        guard waitState(statePath, timeout: 3, until) != nil else {
            print("FAIL: \(what) : le FL simulé n'a pas réagi (\(read(statePath)?.events ?? []))")
            return false
        }
        print("  clic : \(what)")
        Thread.sleep(forTimeInterval: 0.3)               // rythme humain : les relevés de fenêtres suivent
        return true
    }

    /// Touche de l'utilisateur (`times` fois), puis la réaction attendue du FL simulé.
    static func keyFake(_ statePath: String, _ what: String, _ code: CGKeyCode, command: Bool = false, times: Int = 1,
                        until: (FakeState) -> Bool) -> Bool {
        for _ in 0..<times {
            userKey(code, command: command)
            Thread.sleep(forTimeInterval: 0.15)
        }
        guard waitState(statePath, timeout: 3, until) != nil else {
            print("FAIL: \(what) : le FL simulé n'a pas réagi (\(read(statePath)?.events ?? []))")
            return false
        }
        print("  touche : \(what)")
        Thread.sleep(forTimeInterval: 0.3)
        return true
    }

    /// « Enregistrer clics et touches » : démarre, l'utilisateur fait `actions`, puis « Terminer » ; les blocs obtenus.
    static func record(pid: Int32, _ actions: () -> Bool) -> ClickSequenceCompiler.Result? {
        let recorded = Locked<ClickSequenceCompiler.Result?>(nil)
        let finished = DispatchSemaphore(value: 0)
        let started: Bool = DispatchQueue.main.sync {
            ClickSequenceRecorder.shared.start(pid: pid, returnTo: nil) { result in
                recorded.withLock { $0 = result }
                finished.signal()
            }
        }
        guard started else {
            print("FAIL: l'enregistrement n'a pas démarré")
            return nil
        }
        Thread.sleep(forTimeInterval: 0.4)
        let done = actions()
        DispatchQueue.main.sync { ClickSequenceRecorder.shared.finish() }
        guard done else { return nil }
        guard finished.wait(timeout: .now() + 3) == .success, let result = recorded.value else {
            print("FAIL: « Terminer » n'a rendu aucun bloc")
            return nil
        }
        return result
    }

    /// Rejeu des blocs par le même chemin que « Tester » dans le créateur : le résultat et sa durée.
    static func replay(_ blocks: [BlockBody], name: String, pid: Int32) -> (MacroOutcome?, Int)? {
        let doc = MacroDoc(name: name, blocks: blocks.map { Block($0) })
        let program = MacroProgram.compile(doc, forbidden: .physical)
        guard program.isRunnable else {
            print("FAIL: macro invalide : \(program.problem ?? "?")")
            return nil
        }
        let monitor = MacroRunMonitor()
        let done = DispatchSemaphore(value: 0)
        let outcome = Locked<MacroOutcome?>(nil)
        let t0 = Date()
        let launched: MacroRunner.StartResult = DispatchQueue.main.sync {
            monitor.start(program, pid: pid) { o in
                outcome.withLock { $0 = o }
                done.signal()
            }
        }
        guard launched == .started else {
            print("FAIL: rejeu refusé (\(launched))")
            return nil
        }
        guard done.wait(timeout: .now() + 30) == .success else {
            print("FAIL: le rejeu ne s'est pas terminé en 30 s")
            return nil
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        Thread.sleep(forTimeInterval: 0.3)
        return (outcome.value, ms)
    }

    /// Genre d'un bloc enregistré, lisible (jamais le texte d'un nom de piste) : « fenêtre », « menu down×2 »,
    /// « touche ⌘s×1 »…
    static func kindOf(_ body: BlockBody) -> String {
        switch body {
        case .click(.flWindow, _): return "fenêtre"
        case .click(.openMenu, _): return "menu"
        case .menuBar(let titles): return "barre[\(titles.joined(separator: " › "))]"
        case .menuKey(let key, let times): return "menu \(key.rawValue)×\(times)"
        case .key(let ref, let times):
            return "touche \(ref.combo.command ? "⌘" : "")\(ref.char ?? String(ref.combo.keyCode))×\(times)"
        default: return BlockRegistry.journal(of: body)
        }
    }

    // MARK: Scénario « touches »

    /// « Enregistrer clics et touches » avec le clavier : OPTIONS (clic), ↓ ↓ Entrée dans son menu (Audio settings),
    /// carte son (clic), ↓ ↓ Entrée dans la liste (Interface USB), Fermer (clic), ⌘S (raccourci de FL), R (touche
    /// seule : REC). L'enregistreur en fait des blocs « Dans le menu » et « Touche », rejoués ensuite sur le FL
    /// simulé remis à zéro : mêmes actions, rien d'autre.
    static func scenarioTouches(statePath: String, pid: Int32) -> Bool {
        guard waitState(statePath, timeout: 15, { $0.point("options") != nil }) != nil else {
            print("FAIL: le FL simulé ne répond pas (\(statePath))")
            return false
        }
        guard resetFake(statePath, pid: pid) else { return false }
        MacroRunner.testFLPID = pid
        MacroLog.shared.echo = { tag, text, t in print(String(format: "    %6.3f s  %@ %@", t, tag, text)) }
        defer {
            MacroLog.shared.echo = nil
            MacroRunner.testFLPID = nil
        }

        print("\n== Enregistrement de clics et de touches ==")
        let recorded = record(pid: pid) {
            guard clickFake(statePath, "OPTIONS (dans la fenêtre de FL)", "options", until: { s in s.menusOpen == 1 }),
                  keyFake(statePath, "↓ ↓ (jusqu'à Audio settings)", 125, times: 2, until: { s in s.menusOpen == 1 }),
                  keyFake(statePath, "Entrée (ouvre Audio settings)", 36, until: { s in s.settingsOpen && s.menusOpen == 0 })
            else { return false }
            guard clickFake(statePath, "carte son (fenêtre des réglages)", "settings:device", until: { s in s.menusOpen == 1 }),
                  keyFake(statePath, "↓ ↓ (jusqu'à Interface USB)", 125, times: 2, until: { s in s.menusOpen == 1 }),
                  keyFake(statePath, "Entrée (choisit Interface USB)", 36, until: { s in
                      s.device == "Interface USB" && s.menusOpen == 0
                  }),
                  clickFake(statePath, "Fermer les réglages", "settings:close", until: { s in !s.settingsOpen })
            else { return false }
            return keyFake(statePath, "⌘S (raccourci de FL)", 1, command: true, until: { s in s.events.last == "save project" })
                && keyFake(statePath, "R (touche seule : REC)", 15, until: { s in s.events.last == "rec on" })
        }
        guard let result = recorded else { return false }
        let kinds = result.blocks.map(kindOf)
        print("blocs : " + kinds.joined(separator: " > ") + " · ignorés : \(result.ignored)")
        let expected = ["fenêtre", "menu down×2", "menu enter×1", "fenêtre", "menu down×2", "menu enter×1", "fenêtre",
                        "touche ⌘s×1", "touche r×1"]
        guard kinds == expected, result.ignored == 0 else {
            print("FAIL: blocs attendus : " + expected.joined(separator: " > "))
            return false
        }

        guard resetFake(statePath, pid: pid) else { return false }
        print("\n== Rejeu des clics et des touches enregistrés ==")
        guard let replayed = replay(result.blocks, name: "Réglages audio au clavier (enregistrés)", pid: pid) else { return false }
        let (outcome, ms) = replayed
        let s = read(statePath) ?? FakeState(raw: [:])
        let wanted = ["settings open", "device Interface USB", "settings close", "save project", "rec on"]
        var problems: [String] = []
        if outcome != .done { problems.append("résultat « \(outcome?.text ?? "aucun") »") }
        if s.events != wanted { problems.append("actions \(s.events) au lieu de \(wanted)") }
        if s.settingsOpen { problems.append("réglages restés ouverts") }
        if s.menusOpen != 0 { problems.append("\(s.menusOpen) menu(s) resté(s) ouvert(s)") }
        print("résultat : \(outcome?.text ?? "?") — \(ms) ms au total")
        print("FL simulé : carte=\(s.device) actions=\(s.events)")
        if problems.isEmpty {
            print("OK rejeu des clics et des touches")
        } else {
            print("ÉCHEC rejeu des clics et des touches : " + problems.joined(separator: " ; "))
        }
        return problems.isEmpty
    }
}
