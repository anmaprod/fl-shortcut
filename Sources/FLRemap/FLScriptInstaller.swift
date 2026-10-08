import AppKit

/// Copie le script Python dans le dossier "Hardware" de FL Studio.
enum FLScriptInstaller {
    static let fileName = "device_FLRemap.py"

    private static var defaultHardwareFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Image-Line/FL Studio/Settings/Hardware", isDirectory: true)
    }

    static func installWithAlert() {
        NSApp.activate(ignoringOtherApps: true)
        guard let script = Bundle.main.url(forResource: "device_FLRemap", withExtension: "py") else {
            alert("Script introuvable", "Le fichier \(fileName) manque dans l'application.", style: .critical)
            return
        }

        var hardware = defaultHardwareFolder
        if !FileManager.default.fileExists(atPath: hardware.deletingLastPathComponent().path) {
            // Dossier utilisateur FL personnalisé : on demande où il se trouve
            let panel = NSOpenPanel()
            panel.message = "Choisis le dossier « Settings/Hardware » de FL Studio (dans ton dossier Image-Line)."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            hardware = url
        }

        do {
            let folder = hardware.appendingPathComponent("FL Remap", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: script, to: dest)
            alert("Script installé ✅", """
            Dernière étape dans FL Studio :
            1. Ouvre Options › MIDI Settings.
            2. Dans « Input », sélectionne « FL Remap » et clique sur Enable.
            3. Dans « Controller type », choisis « FL Remap ».

            Si FL Studio était ouvert, redémarre-le pour qu'il voie le script.
            """)
        } catch {
            alert("Installation impossible", error.localizedDescription, style: .critical)
        }
    }

    private static func alert(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = style
        a.runModal()
    }
}
