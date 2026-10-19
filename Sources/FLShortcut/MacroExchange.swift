// Échange d'une macro seule : fichier `.flsmacro` (JSON lisible), exactement une entrée de la bibliothèque.
//   { "format": "flsmacro", "version": 1, "exportedBy": "FL Shortcuts 1.2 (macOS)",
//     "macro": { "name": "…", "blocks": [ … ] } }
// Export : les positions apprises (clics montrés dans FL) sont retirées, à montrer de nouveau sur l'autre machine ;
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

    /// Copie à partager : positions apprises retirées, chemins relatifs au dossier personnel.
    static func sharable(_ blocks: [Block], home: String) -> [Block] {
        blocks.map { b in
            var copy = b
            switch b.body {
            case .click(let target, let button) where target.isLearnedPosition:
                copy.body = .click(.toLearn, button: button)
            case .drag(let from, let to) where from.isLearnedPosition || to.isLearnedPosition:
                copy.body = .drag(from: .toLearn, to: .toLearn)
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

    static func export(_ doc: MacroDoc, appVersion: String, home: String = NSHomeDirectory()) throws -> Data {
        var macro: [String: JSONValue] = [
            "name": .string(doc.name),
            "blocks": .array(sharable(doc.blocks, home: home).map(\.json)),
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
    }

    static func prepareImport(_ data: Data, home: String = NSHomeDirectory(), layout: KeyboardLayout) throws -> Preview {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              json["format"]?.string == format, let macro = json["macro"], case .object = macro else {
            throw Failure.notAMacro
        }
        guard (json["version"]?.int ?? 1) <= version else { throw Failure.newerVersion }
        guard let list = macro["blocks"]?.array else { throw Failure.notAMacro }
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
        describe(blocks, prefix: "", offset: 0, depth: 0, layout: layout, lines: &lines, warnings: &warnings,
                 sensitive: &sensitive)
        return Preview(doc: doc, lines: lines, warnings: Array(Set(warnings)).sorted(), sensitiveCount: sensitive)
    }

    /// Chemins « ~/… » rendus absolus dans le dossier personnel de cette machine ; chaque clic, quel que soit son
    /// repère (piste, dernier clic, curseur…), est à montrer de nouveau : aucun décalage n'est repris d'un fichier.
    private static func localized(_ blocks: [Block], home: String) -> [Block] {
        blocks.map { b in
            var copy = b
            switch b.body {
            case .chooseFile(let path):
                copy.body = .chooseFile(path: absolute(path, home: home))
            case .dropFile(let path):
                copy.body = .dropFile(path: absolute(path, home: home))
            case .click(_, let button):
                copy.body = .click(.toLearn, button: button)
            case .drag:
                copy.body = .drag(from: .toLearn, to: .toLearn)
            default:
                copy.body = b.body.replacingChildren(b.body.children.map { localized($0, home: home) })
            }
            return copy
        }
    }

    private static func describe(_ blocks: [Block], prefix: String, offset: Int, depth: Int, layout: KeyboardLayout,
                                 lines: inout [String], warnings: inout [String], sensitive: inout Int) {
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
                } else if case .click = b.body {
                    marks.append(String(localized: "clic dans FL"))
                }
                if case .drag(.toLearn, _) = b.body {
                    marks.append(String(localized: "glisser : endroits à montrer dans FL"))
                    warnings.append(String(localized: "Montre de nouveau chaque glisser-déposer dans FL (positions propres à chaque Mac)."))
                } else if case .drag = b.body {
                    marks.append(String(localized: "glisser dans FL"))
                }
                if b.body.type == .chooseFile || b.body.type == .dropFile {
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
                         warnings: &warnings, sensitive: &sensitive)
            }
        }
    }
}
