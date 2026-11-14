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

    /// `FLShortcut --diag-icon 7-4 [--relearn]` : pose l'icône (colonne-rangée de la grille de FL) sur l'élément du
    /// vrai FL sous la souris, par le même chemin que le bloc « Nom et couleur » (clic droit, « Change icon… », case),
    /// et affiche chaque étape (fenêtres vues, points cliqués). FL est mis au premier plan d'abord ; mets la souris sur
    /// le nom d'un son ou d'une piste dans FL avant de lancer la commande. `--relearn` : les places retenues de
    /// « Change icon… » sont oubliées.
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
        let spots = IconPlacement.loadSpots()
        print("« Change icon… » : lu dans le menu" + (ScreenLook.allowed ? "" : " (impossible : pas d'Enregistrement de l'écran)")
              + (spots.isEmpty ? "" : " ; places retenues : " + spots.map {
                  "(\(Int($0.fromTopLeft.dx)), \(Int($0.fromTopLeft.dy))) dans un menu de \(Int($0.menuSize.width)) × \(Int($0.menuSize.height))"
              }.joined(separator: ", ")))
        print("Clic droit sous la souris : mets-la sur le nom d'un son (Channel rack) ou d'une piste (Mixer, Playlist) dans FL.")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        MacroRunner.testFLPID = pid
        // Vidé à chaque ligne : une autre session (ou `tail -f`) suit le journal pendant que la pose attend un clic.
        MacroLog.shared.echo = { tag, text, t in
            print(String(format: "  %6.3f s  %@ %@", t, tag, text))
            fflush(stdout)
        }
        fflush(stdout)
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
                    fflush(stdout)
                    asked = true
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard frontmost() == pid else {
                print("FAIL: FL Studio n'est pas passé au premier plan")
                exit(1)
            }
            Thread.sleep(forTimeInterval: 0.4)
            let target = FLWindows.cursor()
            MacroLog.shared.beginRun("diag-icon \(icon.code)", flPID: pid)
            MacroLog.shared.windows("before", WinSnapshot.take(pid: pid))
            let result = MacroEffectsMac(pid: pid).placeIcon(icon, at: target, alsoColored: false)
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
