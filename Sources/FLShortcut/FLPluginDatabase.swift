// « Cliquer sur… › Ajouter un instrument / un effet » : tous les plugins installés, pas seulement les favoris du menu
// Add de FL (signalé : ceux de « More plugins… » manquaient). FL les connaît dans sa « Plugin database » (dossier de
// données de FL › Presets › Plugin database › Installed › Generators ou Effects) : un fichier par plugin (.fst, .nfo),
// rangés par format (VST, VST3, AU, Fruity…). Rien n'est lu d'autre, et seulement quand la liste est demandée.
// - Le menu Add de FL ne montre que les favoris (Plugin database › Generators ou Effects). Un plugin choisi hors des
//   favoris y est ajouté, dans le dossier « FL Shortcuts » (copie de ses fichiers) : la macro le choisit alors par le
//   menu, sans souris (Add › Channel › FL Shortcuts › Serum). FL relit sa base en démarrant. La désinstallation retire
//   ce dossier.
import Foundation

enum FLPluginDatabase {
    enum Kind: String {
        case generators = "Generators"
        case effects = "Effects"

        /// Élément du menu Add de FL qui montre ces favoris.
        var addMenuItem: String { self == .generators ? "Channel" : "Effect" }
    }

    /// Un plugin installé : son format (dossier : VST, VST3, AU…), son nom, ses fichiers dans la base de FL.
    struct Plugin: Equatable {
        let format: String
        let name: String
        let files: [URL]
    }

    /// Dossier des favoris ajoutés par FL Shortcuts (dans Generators et Effects).
    static let folderName = "FL Shortcuts"

    /// « Plugin database » de FL : à côté du script installé (dossier de données choisi dans FL), sinon l'emplacement
    /// par défaut.
    static func root(script: URL? = FLScriptInstaller.installedScript()?.url,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        // …/FL Studio/Settings/Hardware/FL Shortcuts/device_FLShortcut.py → …/FL Studio
        if let script {
            let flStudio = script.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            return flStudio.appendingPathComponent("Presets/Plugin database", isDirectory: true)
        }
        return home.appendingPathComponent("Documents/Image-Line/FL Studio/Presets/Plugin database", isDirectory: true)
    }

    /// Pure sur le disque (testée) : plugins installés de cette sorte, un par nom et par format, triés par format
    /// puis par nom. Vide si la base n'existe pas.
    static func installed(_ kind: Kind, root: URL, fileManager: FileManager = .default) -> [Plugin] {
        let base = root.appendingPathComponent("Installed/\(kind.rawValue)", isDirectory: true)
        guard let formats = try? fileManager.contentsOfDirectory(atPath: base.path) else { return [] }
        var out: [Plugin] = []
        for format in formats.sorted() where !format.hasPrefix(".") {
            let folder = base.appendingPathComponent(format, isDirectory: true)
            guard SecureFile.kind(at: folder.path) == .directory,
                  let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { continue }
            var files: [String: [URL]] = [:]
            for file in names where !file.hasPrefix(".") {
                let url = folder.appendingPathComponent(file)
                guard ["fst", "nfo"].contains(url.pathExtension.lowercased()),
                      SecureFile.kind(at: url.path) == .regular else { continue }
                files[url.deletingPathExtension().lastPathComponent, default: []].append(url)
            }
            for name in files.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending })
            where !name.contains("›") {
                out.append(Plugin(format: format, name: name, files: files[name]!.sorted { $0.path < $1.path }))
            }
        }
        return out
    }

    /// Ajoute le plugin aux favoris de FL (dossier « FL Shortcuts » de Generators ou Effects) s'il n'y est pas déjà ;
    /// renvoie son chemin dans le menu Add › Channel ou Effect (« FL Shortcuts › Serum »), ou nil si la copie échoue.
    static func addFavorite(_ plugin: Plugin, kind: Kind, root: URL, fileManager: FileManager = .default) -> String? {
        let folder = root.appendingPathComponent("\(kind.rawValue)/\(folderName)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in plugin.files {
                let dest = folder.appendingPathComponent(file.lastPathComponent)
                if SecureFile.kind(at: dest.path) == .regular { continue }
                try fileManager.copyItem(at: file, to: dest)
            }
        } catch {
            return nil
        }
        return folderName + PageOptions.pathSeparator + plugin.name
    }

    /// Dossiers ajoutés par FL Shortcuts dans la base de FL (désinstallation) : seulement s'ils ne contiennent que des
    /// fichiers de plugins (.fst, .nfo).
    static func favoriteFolders(root: URL, fileManager: FileManager = .default) -> [URL] {
        [Kind.generators, .effects].compactMap { kind in
            let folder = root.appendingPathComponent("\(kind.rawValue)/\(folderName)", isDirectory: true)
            guard SecureFile.kind(at: folder.path) == .directory,
                  let entries = try? fileManager.contentsOfDirectory(atPath: folder.path),
                  entries.allSatisfy({ $0 == ".DS_Store" || $0.hasPrefix("._")
                      || ["fst", "nfo"].contains(($0 as NSString).pathExtension.lowercased()) }) else { return nil }
            return folder
        }
    }
}
