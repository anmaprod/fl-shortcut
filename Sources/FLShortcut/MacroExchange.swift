// Échange d'une macro seule : fichier `.flsmacro` (JSON lisible), exactement une entrée de la bibliothèque.
//   { "format": "flsmacro", "version": 1, "exportedBy": "FL Shortcuts 1.2 (macOS)",
//     "macro": { "name": "…", "blocks": [ … ] } }
// Export : chaque clic est gardé sous une forme qui se retrouve dans le FL d'un autre ordinateur (bouton par son nom
// ou son image, point d'une fenêtre de plugin en proportion : ClickTarget.portable), le reste est à montrer une fois ;
// le chemin d'un preset est écrit relatif au dossier personnel (« ~/… »), jamais le nom du compte.
// Import (relu avant d'être accepté) : 256 Ko au plus, nombre de blocs et imbrication bornés, ids régénérés, la
// macro arrive SANS raccourci (donc inactive) ; chaque bloc est décrit en français, les blocs sensibles marqués.
// Données pures, testables.
import Foundation

enum MacroExchange {
    static let format = "flsmacro"
    static let version = 1
    static let fileExtension = "flsmacro"
    static let maxBytes = 256 * 1024

    enum Failure: Error, LocalizedError, Equatable {
        case tooLarge
        case notAMacro
        case newerVersion
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .tooLarge: return String(localized: "Fichier trop volumineux pour une macro (256 Ko au plus).")
            case .notAMacro: return String(localized: "Ce fichier n'est pas une macro de FL Shortcuts (.flsmacro).")
            case .newerVersion:
                return String(localized: "Macro d'une version plus récente de FL Shortcuts : mets l'app à jour pour l'importer.")
            case .invalid(let why): return why
            }
        }
    }

    // MARK: Export

    /// Copie à partager : chaque clic gardé sous une forme retrouvable dans le FL d'un autre ordinateur
    /// (ClickTarget.portable), le reste à montrer une fois ; chemins relatifs au dossier personnel.
    static func sharable(_ blocks: [Block], home: String) -> [Block] {
        blocks.map { b in
            var copy = b
            switch b.body {
            case .click(let target, let button):
                copy.body = .click(target.portable, button: button)
            case .drag(let from, let to):
                copy.body = .drag(from: from.portable, to: to.portable)
            case .menuAX(let titles, _):
                copy.body = .menuAX(titles: titles, fallback: [])
            case .chooseFile(let path):
                copy.body = .chooseFile(path: relative(path, home: home))
            case .dropFile(let path):
                copy.body = .dropFile(path: relative(path, home: home))
            default:
                copy.body = b.body.replacingChildren(b.body.children.map { sharable($0, home: home) })
            }
            return copy
        }
    }

    // MARK: Presets joints (19/11 : « le preset part avec la macro ») — miroir de MacroExchange.cs (Windows)

    /// Un preset joint : 150 Ko au plus chacun, 180 Ko en tout (le fichier partagé fait 256 Ko au plus).
    static let maxAttachedBytes = 150 * 1024
    static let maxAttachedTotal = 180 * 1024

    /// Preset d'une macro importée à écrire sur ce Mac (Documents › FL Shortcuts › Presets) quand on l'ajoute.
    struct AttachedFile: Equatable {
        let path: String
        let data: Data
    }

    /// Nom de fichier sûr : le dernier élément du chemin, sans caractère de contrôle ni séparateur, 80 caractères au
    /// plus, toujours en .fst ; nil sinon (jamais d'autre sorte de fichier).
    static func safePresetName(_ name: String?) -> String? {
        guard let name else { return nil }
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var scalars = String.UnicodeScalarView()
        for u in last.unicodeScalars where !CharacterSet.controlCharacters.contains(u) && !":*?\"<>|".unicodeScalars.contains(u) {
            scalars.append(u)
        }
        let clean = String(scalars).trimmingCharacters(in: .whitespaces)
        guard clean.count >= 5, !clean.hasPrefix("."), clean.lowercased().hasSuffix(".fst") else { return nil }
        return clean.count <= 80 ? clean : String(clean.prefix(76)) + ".fst"
    }

    /// Lecture sûre d'un preset à joindre : fichier .fst ordinaire (pas un lien), 150 Ko au plus ; nil sinon.
    static func readPreset(_ path: String) -> Data? {
        guard (path as NSString).pathExtension.lowercased() == "fst",
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let size = attrs[.size] as? Int, size <= maxAttachedBytes else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    private static func isFileBlock(_ o: [String: JSONValue]) -> Bool {
        o["type"]?.string == "chooseFile" || o["type"]?.string == "dropFile"
    }

    /// Chaque preset (Ouvrir un preset, preset glissé) part avec la macro, tant qu'il est lisible et que le total tient.
    private static func attach(_ v: JSONValue, home: String, read: (String) -> Data?, total: inout Int) -> JSONValue {
        switch v {
        case .object(var o):
            if isFileBlock(o), let path = o["path"]?.string, let name = safePresetName(path),
               let bytes = read(absolute(path, home: home)), bytes.count <= maxAttachedBytes,
               total + bytes.count <= maxAttachedTotal {
                o["attached"] = .object(["name": .string(name), "data": .string(bytes.base64EncodedString())])
                total += bytes.count
            }
            for (k, child) in o where k != "attached" { o[k] = attach(child, home: home, read: read, total: &total) }
            return .object(o)
        case .array(let a):
            var out: [JSONValue] = []
            for child in a { out.append(attach(child, home: home, read: read, total: &total)) }
            return .array(out)
        default:
            return v
        }
    }

    /// Presets joints d'un fichier importé : le même fichier déjà là (chemin d'origine ou dossier des presets) est repris
    /// tel quel ; sinon écrit dans `presets` sous un nom libre (« Bass 2.fst »), jamais par-dessus un autre fichier. Le
    /// chemin du bloc devient celui de ce Mac ; la clé « attached » est retirée.
    private static func unpack(_ v: JSONValue, home: String, presets: String, existing: (String) -> Data?,
                               files: inout [AttachedFile]) -> JSONValue {
        switch v {
        case .object(var o):
            if isFileBlock(o), let att = o["attached"] {
                o["attached"] = nil
                if let encoded = att["data"]?.string, encoded.count <= maxAttachedBytes * 4 / 3 + 8,
                   let bytes = Data(base64Encoded: encoded), !bytes.isEmpty, bytes.count <= maxAttachedBytes,
                   let name = safePresetName(att["name"]?.string) {
                    let original = o["path"]?.string.map { absolute($0, home: home) }
                    if let original, let there = existing(original), there == bytes {
                        o["path"] = .string(original)
                    } else {
                        let folder = presets.hasSuffix("/") ? String(presets.dropLast()) : presets
                        let stem = String(name.dropLast(4))
                        for n in 1...50 {
                            let dest = folder + "/" + (n == 1 ? name : "\(stem) \(n).fst")
                            let onDisk = files.first(where: { $0.path == dest })?.data ?? existing(dest)
                            if let onDisk, onDisk != bytes { continue }
                            o["path"] = .string(dest)
                            if onDisk == nil { files.append(AttachedFile(path: dest, data: bytes)) }
                            break
                        }
                    }
                }
            }
            for (k, child) in o {
                o[k] = unpack(child, home: home, presets: presets, existing: existing, files: &files)
            }
            return .object(o)
        case .array(let a):
            var out: [JSONValue] = []
            for child in a { out.append(unpack(child, home: home, presets: presets, existing: existing, files: &files)) }
            return .array(out)
        default:
            return v
        }
    }

    /// Dossier des presets joints : Documents › FL Shortcuts › Presets.
    static func presetsFolder(home: String) -> String {
        (home.hasSuffix("/") ? home : home + "/") + "Documents/FL Shortcuts/Presets"
    }

    /// Écrit les presets joints d'une macro qu'on ajoute (Documents › FL Shortcuts › Presets, fichiers 0600) ; un
    /// fichier déjà là n'est jamais remplacé. La raison si l'un n'a pas pu être écrit, sinon nil.
    static func writeAttached(_ files: [AttachedFile]) -> String? {
        let fm = FileManager.default
        for f in files {
            guard safePresetName(f.path) != nil, f.data.count <= maxAttachedBytes else { continue }
            let url = URL(fileURLWithPath: f.path)
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: f.path) { continue }
                try f.data.write(to: url, options: .withoutOverwriting)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
            } catch {
                if fm.fileExists(atPath: f.path) { continue }
                return String(localized: "un preset joint n'a pas pu être enregistré dans Documents › FL Shortcuts › Presets")
            }
        }
        return nil
    }

    static func export(_ doc: MacroDoc, appVersion: String, home: String = NSHomeDirectory(),
                       read: (String) -> Data? = readPreset) throws -> Data {
        var total = 0
        let blocks = attach(.array(sharable(doc.blocks, home: home).map(\.json)), home: home, read: read, total: &total)
        var macro: [String: JSONValue] = [
            "name": .string(doc.name),
            "blocks": blocks,
        ]
        if !doc.variables.isEmpty {
            macro["variables"] = .array(doc.variables.map {
                .object(["name": .string($0.name), "initial": .num($0.initial)])
            })
        }
        let file: JSONValue = .object([
            "format": .string(format),
            "version": .num(version),
            "exportedBy": .string("FL Shortcuts \(appVersion) (macOS)"),
            "macro": .object(macro),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Nom de fichier proposé (sans caractères gênants).
    static func suggestedFileName(_ name: String) -> String {
        let cleaned = name.displaySafe(max: 60).map { "/:\\".contains($0) ? "-" : $0 }
        let base = String(cleaned).trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "Macro" : base) + "." + fileExtension
    }

    static func relative(_ path: String, home: String) -> String {
        let prefix = home.hasSuffix("/") ? home : home + "/"
        return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
    }

    static func absolute(_ path: String, home: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        let prefix = home.hasSuffix("/") ? home : home + "/"
        return prefix + path.dropFirst(2)
    }

    // MARK: Import

    struct Preview {
        /// Macro prête à entrer dans la bibliothèque (ids neufs, origine « importée »).
        var doc: MacroDoc
        /// Une ligne par bloc, en français, dans l'ordre de la liste (retrait selon l'imbrication).
        var lines: [String]
        /// Ce qu'il faudra faire avant de s'en servir (positions à montrer, fichiers à rechoisir…).
        var warnings: [String]
        /// Blocs à relire, dans tout l'arbre (touches, clics, fichiers, lien avec FL, blocs cachés de l'ancien format).
        var sensitiveCount: Int
        /// Presets joints à écrire quand on ajoute la macro (writeAttached).
        var files: [AttachedFile] = []
    }

    /// `presets` : dossier des presets joints (Documents › FL Shortcuts › Presets) ; `existing` : contenu d'un fichier déjà
    /// sur ce Mac (nil : absent).
    static func prepareImport(_ data: Data, home: String = NSHomeDirectory(), layout: KeyboardLayout,
                              presets: String? = nil, existing: (String) -> Data? = readPreset) throws -> Preview {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              json["format"]?.string == format, let macro = json["macro"], case .object = macro else {
            throw Failure.notAMacro
        }
        guard (json["version"]?.int ?? 1) <= version else { throw Failure.newerVersion }
        guard let raw = macro["blocks"]?.array else { throw Failure.notAMacro }
        var files: [AttachedFile] = []
        let presetFolder = presets ?? presetsFolder(home: home)
        var list: [JSONValue] = []
        for v in raw { list.append(unpack(v, home: home, presets: presetFolder, existing: existing, files: &files)) }
        let parsed = list.map { Block(json: $0) }
        guard MacroValidation.count(parsed) <= MacroValidation.maxBlocks else {
            throw Failure.invalid(String(localized: "Macro trop longue (\(MacroValidation.maxBlocks) blocs au plus)."))
        }
        guard MacroValidation.depth(parsed) <= MacroValidation.maxDepth else {
            throw Failure.invalid(String(localized: "Blocs trop imbriqués (\(MacroValidation.maxDepth) niveaux au plus)."))
        }
        var variables: [VariableDecl] = []
        for v in macro["variables"]?.array ?? [] {
            guard let name = v["name"]?.string else { continue }
            variables.append(VariableDecl(name: name, initial: v["initial"]?.int ?? 0))
        }
        // Nom nettoyé (relecture 11 : ni contrôle ni bidi), coupé sans points de suspension.
        let cleaned = (macro["name"]?.string ?? "").displaySafe(max: 4_096)
        let trimmed = String(cleaned.prefix(MacroValidation.maxNameLength)).trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? String(localized: "Macro importée") : trimmed
        // Positions jamais reprises d'un fichier, même fabriqué à la main : chaque clic est à montrer sur ce Mac.
        let blocks = localized(sharable(MacroTemplates.freshIDs(parsed), home: home), home: home)
        let doc = MacroDoc(name: name, blocks: blocks, variables: Array(variables.prefix(MacroValidation.maxVariables)),
                           origin: .imported)
        var lines: [String] = []
        var warnings: [String] = []
        var sensitive = 0
        let joined = Set(filePaths(blocks).filter { $0.hasPrefix(presetFolder) })
        describe(blocks, prefix: "", offset: 0, depth: 0, layout: layout, lines: &lines, warnings: &warnings,
                 sensitive: &sensitive, joined: joined)
        return Preview(doc: doc, lines: lines, warnings: Array(Set(warnings)).sorted(), sensitiveCount: sensitive,
                       files: files)
    }

    /// Chemins « ~/… » rendus absolus dans le dossier personnel de cette machine ; chaque clic reste retrouvable ici
    /// (ClickTarget.portable, même pour un fichier fait à la main), sinon à montrer de nouveau : aucun décalage depuis la
    /// piste, le dernier clic ou le curseur n'est repris d'un fichier.
    private static func localized(_ blocks: [Block], home: String) -> [Block] {
        blocks.map { b in
            var copy = b
            switch b.body {
            case .chooseFile(let path):
                copy.body = .chooseFile(path: absolute(path, home: home))
            case .dropFile(let path):
                copy.body = .dropFile(path: absolute(path, home: home))
            case .click(let target, let button):
                copy.body = .click(target.portable, button: button)
            case .drag(let from, let to):
                copy.body = .drag(from: from.portable, to: to.portable)
            default:
                copy.body = b.body.replacingChildren(b.body.children.map { localized($0, home: home) })
            }
            return copy
        }
    }

    /// Chemins des presets de toute la macro (Ouvrir un preset, preset glissé).
    private static func filePaths(_ blocks: [Block]) -> [String] {
        blocks.flatMap { b -> [String] in
            var own: [String] = []
            switch b.body {
            case .chooseFile(let path), .dropFile(let path): own = [path]
            default: break
            }
            return own + b.body.children.flatMap { filePaths($0) }
        }
    }

    private static func describe(_ blocks: [Block], prefix: String, offset: Int, depth: Int, layout: KeyboardLayout,
                                 lines: inout [String], warnings: inout [String], sensitive: inout Int,
                                 joined: Set<String>) {
        for (i, b) in blocks.enumerated() {
            let path = MacroValidation.path(prefix, offset + i + 1)
            let indent = String(repeating: "    ", count: depth)
            var text: String
            if let type = b.body.type {
                let spec = BlockRegistry.spec(type)
                let value = spec.resume(b.body, layout)
                text = value.isEmpty ? spec.label : String(localized: "\(spec.label) : \(value)")
                var marks: [String] = []
                if case .key(let k, _) = b.body, k.combo.command { marks.append(String(localized: "touche avec ⌘")) }
                if case .click(.toLearn, _) = b.body {
                    marks.append(String(localized: "clic : position à montrer dans FL"))
                    warnings.append(String(localized: "Montre de nouveau chaque clic dans FL (positions propres à chaque Mac)."))
                } else if case .click(.named, _) = b.body {
                    marks.append(String(localized: "clic : bouton retrouvé par son nom"))
                } else if case .click(.button, _) = b.body {
                    marks.append(String(localized: "clic : bouton retrouvé à son image"))
                } else if case .click(.flWindow, _) = b.body {
                    marks.append(String(localized: "clic : même endroit de la fenêtre du plugin"))
                } else if case .click = b.body {
                    marks.append(String(localized: "clic dans FL"))
                }
                if case .drag(.toLearn, _) = b.body {
                    marks.append(String(localized: "glisser : endroits à montrer dans FL"))
                    warnings.append(String(localized: "Montre de nouveau chaque glisser-déposer dans FL (positions propres à chaque Mac)."))
                } else if case .drag = b.body {
                    marks.append(String(localized: "glisser dans FL"))
                }
                if case .chooseFile(let path) = b.body, joined.contains(path) {
                    marks.append(String(localized: "preset joint"))
                } else if case .dropFile(let path) = b.body, joined.contains(path) {
                    marks.append(String(localized: "preset joint"))
                } else if b.body.type == .chooseFile || b.body.type == .dropFile {
                    marks.append(String(localized: "fichier"))
                    warnings.append(String(localized: "Rechoisis le preset : le fichier doit exister sur ce Mac."))
                }
                if BlockRegistry.needs(of: b.body).contains(.lienMIDI) { marks.append(String(localized: "lien avec FL")) }
                if !spec.dansLaPalette, b.body.type != .menuBar {     // « Menu de FL » : créé par l'enregistreur
                    marks.append(String(localized: "bloc caché (ancien format)"))
                    warnings.append(String(localized: "Un bloc caché de l'ancien format est inclus : relis-le dans le créateur avant de t'en servir."))
                }
                if spec.import_ != .ok || !spec.dansLaPalette { sensitive += 1 }
                if !marks.isEmpty { text += " — " + marks.joined(separator: ", ") }
            } else {
                sensitive += 1
                text = String(localized: "Bloc inconnu (version plus récente) : la macro restera bloquée")
                warnings.append(String(localized: "Un bloc vient d'une version plus récente de FL Shortcuts : la macro ne tournera pas."))
            }
            if !b.enabled { text += String(localized: " (désactivé)") }
            lines.append("\(indent)\(path). \(text)")
            for (start, child) in MacroValidation.childLists(b.body) {
                describe(child, prefix: path, offset: start, depth: depth + 1, layout: layout, lines: &lines,
                         warnings: &warnings, sensitive: &sensitive, joined: joined)
            }
        }
    }
}
