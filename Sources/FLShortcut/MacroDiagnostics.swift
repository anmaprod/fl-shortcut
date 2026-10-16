// Diagnostic des macros en ligne de commande. Déplacé tel quel de MacroRunner.swift.
import AppKit
import ApplicationServices
import Foundation

// MARK: - Diagnostic : `FLShortcut --diag-macro`

/// Affiche ce que voit l'app dans FL (fenêtres, arbre d'accessibilité) pour régler les macros.
/// Mode d'emploi : lancer la commande app quittée, ouvrir dans FL le menu ou la boîte à étudier pendant le compte à rebours.
enum MacroDiagnostics {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--diag-macro") else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        print("Accessibilité autorisée pour ce programme : \(AXIsProcessTrusted() ? "oui" : "NON (à activer pour le Terminal)")")
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.image-line.flstudio").first else {
            print("FL Studio ne tourne pas.")
            exit(1)
        }
        let pid = app.processIdentifier
        if let i = CommandLine.arguments.firstIndex(of: "--watch") {
            let seconds = min(max(Double(CommandLine.arguments.dropFirst(i + 1).first ?? "") ?? 20, 1), 120)
            print("Observation des fenêtres de FL pendant \(Int(seconds)) s. Dans FL : clic droit sur une piste du Mixer, survole File, ouvre le sous-menu, Échap.")
            MacroLog.shared.beginRun("sonde --watch", flPID: pid)
            MacroProbe.watch(pid: pid, seconds: seconds) { line in
                print(line)
                MacroLog.shared.write("PROBE", line)
            }
            MacroLog.shared.endRun("sonde terminée")
            MacroLog.shared.flush()
            exit(0)
        }
        print("FL Studio : pid \(pid). Ouvre maintenant le menu / la boîte à étudier dans FL : mesure dans 6 s…")
        Thread.sleep(forTimeInterval: 6)
        let windows = FLWindows.list(pid: pid)
        print("\nFenêtres de FL (avant → arrière) : \(windows.count), dont \(FLWindows.dialogCount(pid: pid)) de niveau 0 à 8")
        for w in windows {
            print("  niveau \(w.layer) · \(Int(w.bounds.width))×\(Int(w.bounds.height)) en (\(Int(w.bounds.minX)), \(Int(w.bounds.minY)))")
        }
        print("\nArbre d'accessibilité :")
        for line in AXMenus.dump(pid: pid) { print(line) }
        exit(0)
    }

    /// `FLShortcut --diag-icon 7-4 [--relearn]` : pose l'icône (colonne-rangée de la grille de FL) sur l'élément
    /// sélectionné du vrai FL, par le même chemin que le bloc « Nom et couleur » (F2, bouton de l'icône, case,
    /// Entrée), et affiche chaque étape (fenêtres vues, points cliqués). FL est mis au premier plan d'abord ;
    /// sélectionne une seule piste ou un seul canal dans FL avant de lancer la commande. `--relearn` : le bouton de
    /// l'icône est à montrer de nouveau (bulle).
    static func runIconIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--diag-icon") else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let code = args.dropFirst(i + 1).first, let icon = FLIcon(code: code) else {
            print("Usage : FLShortcut --diag-icon <colonne-rangée> [--relearn]   (exemple : --diag-icon 7-4, Microphone)")
            exit(2)
        }
        guard CGPreflightPostEventAccess() else {
            print("FAIL: ce programme (le Terminal) n'a pas l'autorisation Accessibilité")
            exit(1)
        }
        guard let fl = NSRunningApplication.runningApplications(withBundleIdentifier: "com.image-line.flstudio").first else {
            print("FAIL: FL Studio ne tourne pas")
            exit(1)
        }
        let pid = fl.processIdentifier
        if args.contains("--relearn") { IconPlacement.forgetSpot() }
        print("Icône \(icon.code) : \(FLIconGrid.cell(icon)?.name ?? "case vide ou colonne Channel")")
        print("Bouton de l'icône : " + (IconPlacement.loadSpot().map {
            "appris (\(Int($0.fromTopRight.dx)), \(Int($0.fromTopRight.dy))) depuis le coin haut-droit d'une fenêtre de "
                + "\(Int($0.windowSize.width)) × \(Int($0.windowSize.height))"
        } ?? "à montrer : une bulle le demandera"))
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        MacroRunner.testFLPID = pid
        MacroLog.shared.echo = { tag, text, t in print(String(format: "  %6.3f s  %@ %@", t, tag, text)) }
        DispatchQueue.global(qos: .userInitiated).async {
            func frontmost() -> Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
            if frontmost() != pid, let url = fl.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            let deadline = Date().addingTimeInterval(8)
            var asked = false
            while frontmost() != pid, Date() < deadline {
                if !asked, Date().addingTimeInterval(6) > deadline {
                    print("FL n'est pas encore devant : clique dans FL (sans changer la sélection).")
                    asked = true
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard frontmost() == pid else {
                print("FAIL: FL Studio n'est pas passé au premier plan")
                exit(1)
            }
            Thread.sleep(forTimeInterval: 0.4)
            MacroLog.shared.beginRun("diag-icon \(icon.code)", flPID: pid)
            MacroLog.shared.windows("before", WinSnapshot.take(pid: pid))
            let result = MacroEffectsMac(pid: pid).placeIcon(icon, alsoColored: false)
            MacroLog.shared.windows("after", WinSnapshot.take(pid: pid))
            MacroLog.shared.endRun("\(result)")
            MacroLog.shared.flush()
            switch result {
            case .ok: print("PASS: icône \(icon.code) posée (vérifie-la dans FL)")
            case .warn(let why), .fail(let why), .cancel(let why): print("FAIL: \(why)")
            }
            exit(result == .ok ? 0 : 1)
        }
        app.run()
        exit(1)
    }
}
