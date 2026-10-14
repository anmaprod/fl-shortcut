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
}
