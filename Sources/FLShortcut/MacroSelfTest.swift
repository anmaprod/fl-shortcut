// Essai de bout en bout de la macro « Enregistrement rapide » contre le FL simulé (FakeFL.swift), sur la CI macOS :
//   FLShortcut --fake-fl état.json &            (le faux FL, processus à part comme le vrai)
//   FLShortcut --selftest-macro sortie.txt état.json <pid du faux FL>
// Le pilote joue l'utilisateur (clic sur la piste 3, puis, la première fois, « (none) » et « In 1 » quand la bulle
// le demande), lance la vraie macro (MacroRunner, développée en blocs et jouée par l'interpréteur) et vérifie l'état
// du faux FL après chaque passage :
// preset choisi chargé, piste 3 armée, REC allumé, entrée « In 1 », aucune action inattendue (Delete, Solo…).
// Quatre passages : apprentissage, rejeu, puis « O » qui ne fait que surligner (Entrée apprise), rejeu.
// Les durées de chaque étape sont affichées : c'est la mesure de vitesse de la macro.
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
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = scenario(statePath: statePath, pid: pid)
            print(ok ? "PASS: macro complète sur le FL simulé (4 passages)" : "FAIL: voir ci-dessus")
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
        var events: [String] { raw["events"] as? [String] ?? [] }
        var menusOpen: Int { raw["menusOpen"] as? Int ?? 0 }
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
        let blocks = program.blocks.filter { $0.body != .feedbackCheck }
        print("étapes : " + blocks.map { BlockRegistry.journal(of: $0.body) }.joined(separator: " > "))

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
        let runs: [(String, Bool)] = [("1 · apprentissage de l'entrée", false), ("2 · rejeu", false),
                                      ("3 · « O » surligne seulement (Entrée)", true), ("4 · rejeu avec Entrée apprise", true)]
        for (label, highlight) in runs {
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
            let expectedEvents = Set(["arm 3", "rec on", "input In 1", "open Voix lead (micro 1).fst"])
            let unexpected = s.events.filter { !expectedEvents.contains($0) }
            var problems: [String] = []
            if s.preset != wanted { problems.append("preset « \(s.preset) » au lieu du bon") }
            if !s.armed.contains(3) { problems.append("piste 3 non armée (\(s.armed))") }
            if !s.rec { problems.append("REC éteint") }
            if s.input != "In 1" { problems.append("entrée « \(s.input) »") }
            if !unexpected.isEmpty { problems.append("actions inattendues : \(unexpected)") }
            if s.menusOpen != 0 { problems.append("\(s.menusOpen) menu(s) resté(s) ouvert(s)") }
            print("résultat : \(outcome.text) — \(ms) ms au total (dont l'attente de la boîte « Open » par macOS)")
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
}
