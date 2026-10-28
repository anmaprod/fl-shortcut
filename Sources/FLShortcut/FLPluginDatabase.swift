// « Cliquer sur… › Ajouter un instrument / un effet » : tous les plugins installés, pas seulement les favoris du menu
// Add de FL. FL les connaît dans sa « Plugin database » (dossier de données de FL › Presets › Plugin database ›
// Installed › Generators ou Effects) : un fichier par plugin (.fst, .nfo), rangés par format (VST, VST3, AU…). Rien
// n'est lu d'autre, et seulement quand la liste est demandée. Rien n'y est JAMAIS écrit (demande du propriétaire,
// 28/10, captures) : un plugin hors des favoris est pris par la macro dans « More plugins… » du menu Add de FL
// (`morePlugins`), sans rien cocher. Les favoris qu'ajoutaient d'anciennes versions (dossier « FL Shortcuts » dans
// Generators ou Effects : une catégorie « FL Shortcuts » dans les menus Add) partent à la Corbeille au lancement (FL le
// voit à son prochain démarrage) : seulement un dossier « FL Shortcuts » qui ne contient que des fichiers de plugins.
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

    /// Élément du menu Add de FL qui ouvre la liste de tous ses plugins (fenêtre « Select plugin ») ; aussi le premier
    /// élément du nom d'un plugin choisi hors des favoris (« More plugins... › Serum 2 »).
    static let morePlugins = "More plugins..."

    /// Pure (testée) : nom du plugin à prendre dans « More plugins… », nil pour un favori du menu Add.
    static func fromPluginList(_ path: [String]) -> String? {
        path.count == 2 && path[0] == morePlugins && !path[1].isEmpty ? path[1] : nil
    }

    /// Dossier des favoris ajoutés par les anciennes versions (dans Generators et Effects).
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

    /// Dossiers ajoutés par FL Shortcuts dans la base de FL : seulement s'ils ne contiennent que des fichiers de
    /// plugins (.fst, .nfo).
    static func favoriteFolders(root: URL, fileManager: FileManager = .default) -> [URL] {
        ["Generators", "Effects"].compactMap { kind in
            let folder = root.appendingPathComponent("\(kind)/\(folderName)", isDirectory: true)
            guard SecureFile.kind(at: folder.path) == .directory,
                  let entries = try? fileManager.contentsOfDirectory(atPath: folder.path),
                  entries.allSatisfy({ $0 == ".DS_Store" || $0.hasPrefix("._")
                      || ["fst", "nfo"].contains(($0 as NSString).pathExtension.lowercased()) }) else { return nil }
            return folder
        }
    }

    /// Ces dossiers mis à la Corbeille (jamais effacés pour de bon) ; renvoie combien. Bases : celle du script
    /// installé et l'emplacement par défaut.
    @discardableResult
    static func removeAddedFavorites(roots: [URL]? = nil, fileManager: FileManager = .default) -> Int {
        let bases = roots ?? Array(Set([root(), root(script: nil)].map(\.standardizedFileURL)))
        var removed = 0
        for folder in bases.flatMap({ favoriteFolders(root: $0, fileManager: fileManager) })
        where (try? fileManager.trashItem(at: folder, resultingItemURL: nil)) != nil {
            removed += 1
        }
        return removed
    }

    /// Pure (testée) : chemin d'un plugin choisi par une ancienne version (« FL Shortcuts › Serum 2 ») : le plugin seul,
    /// tel qu'il est dans les favoris de l'utilisateur.
    static func withoutAddedFolder(_ path: [String]) -> [String] {
        path.count > 1 && path[0] == folderName ? Array(path.dropFirst()) : path
    }
}
