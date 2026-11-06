// « Ajouter un instrument / un effet » en déposant le fichier du plugin pris dans la Plugin database de FL (demande et
// essais du propriétaire, 04/11 : « trop lent… faire comme le drag and drop ») : Installed › Generators › VST3 ›
// <nom>.fst déposé juste sous le dernier son du Channel rack ouvre l'instrument ; Installed › Effects › AudioUnit ›
// <nom>.fst déposé sur la piste du Mixer visée ouvre l'effet (même non sélectionnée, c'est la piste sous la souris qui le
// reçoit). Seulement les .fst (les .nfo ne marchent pas, capture du 04/11). Déposé SUR un son, il le REMPLACE ; ailleurs
// dans FL, rien. Rien n'est jamais écrit dans la base de FL (règle du propriétaire) : on y lit le nom des fichiers. Le
// Channel rack est lu dans la seule fenêtre de FL, au moment du dépôt (« Enregistrement de l'écran »). En cas de doute
// (pas de fichier, Channel rack mal lu, piste hors de FL) : le menu Add, comme avant. Miroir de PluginDrop.cs (Windows).
import AppKit

enum PluginDrop {
    /// Pure (testée) : format d'un dossier de la base (« AudioUnit » → « au », « VST2 » → « vst »).
    static func formatKey(_ folder: String) -> String {
        let f = folder.lowercased().replacingOccurrences(of: " ", with: "")
        switch f {
        case "audiounit", "audiounits", "au", "component", "components": return "au"
        case "vst", "vst2": return "vst"
        case "vst3": return "vst3"
        case "clap": return "clap"
        case "fruity", "native", "fl": return "fl"
        default: return f
        }
    }

    /// Ordre des formats (03/11) : un instrument en VST3 puis VST ; un effet en AU d'abord.
    static func preferredFormats(effect: Bool) -> [String] {
        effect ? ["au", "vst3", "vst", "clap", "fl"] : ["vst3", "vst", "au", "clap", "fl"]
    }

    /// Pure sur le disque (testée) : le .fst du plugin `name` dans la base `root` ; nil : absent.
    /// 06/11 (« il n'y a que pour Analog Lab que ça fonctionne… mets ça pour tout ») : cherché dans TOUTE la base,
    /// sous-dossiers compris : d'abord Installed › Generators ou Effects (format préféré), puis les catégories de
    /// favoris de FL (Generators › Synth classic › …). Le nom : identique, sinon sans la marque ni le format
    /// (« FabFilter Pro-Q 3 », « Analog Lab V (VST3) »), jamais un autre numéro (« Serum » n'ouvre pas « Serum 2 »).
    /// Seulement des .fst (les .nfo ne marchent pas) ; jamais un lien ; rien n'est écrit dans la base.
    static func presetFile(named name: String, effect: Bool, root: URL) -> URL? {
        let wanted = TextLook.normalized(name)
        let wantedKey = looseKey(name)
        guard !wanted.isEmpty, !wantedKey.isEmpty else { return nil }
        let prefer = preferredFormats(effect: effect)
        let kind = effect ? FLPluginDatabase.Kind.effects : .generators
        var best: (rank: [Int], path: String, url: URL)?
        for (source, base) in [root.appendingPathComponent("Installed/\(kind.rawValue)", isDirectory: true),
                               root.appendingPathComponent(kind.rawValue, isDirectory: true)].enumerated() {
            for file in fstFiles(under: base, skipping: source == 1 ? FLPluginDatabase.folderName : nil) {
                let stem = file.url.deletingPathExtension().lastPathComponent
                guard let level = matchLevel(stem, wanted: wanted, wantedKey: wantedKey) else { continue }
                let format = source == 0 ? (prefer.firstIndex(of: formatKey(file.top)) ?? prefer.count) : prefer.count
                let rank = [level, source, format, abs(looseKey(stem).count - wantedKey.count)]
                if best == nil || rank.lexicographicallyPrecedes(best!.rank)
                    || (rank == best!.rank && file.url.path < best!.path) {
                    best = (rank, file.url.path, file.url)
                }
            }
        }
        return best?.url
    }

    /// Pure (testée) : 0 nom identique, 1 identique sans la marque ni le format, 2 contenu l'un dans l'autre sans autre
    /// chiffre (« FabFilter Pro-Q 3 » pour « Pro-Q 3 ») ; nil : un autre plugin.
    static func matchLevel(_ stem: String, wanted: String, wantedKey: String) -> Int? {
        if TextLook.normalized(stem) == wanted { return 0 }
        let key = looseKey(stem)
        if key == wantedKey { return 1 }
        guard wantedKey.count >= 4, key.count >= 4 else { return nil }
        let (long, short) = key.count > wantedKey.count ? (key, wantedKey) : (wantedKey, key)
        guard let range = long.range(of: short) else { return nil }
        let rest = long.replacingCharacters(in: range, with: "")
        return rest.contains(where: \.isNumber) ? nil : 2
    }

    /// Pure (testée) : le nom en lettres et chiffres seuls, minuscules, sans les mots de format (« vst3 », « au »,
    /// « x64 »…).
    static func looseKey(_ name: String) -> String {
        let formats: Set<String> = ["vst", "vst2", "vst3", "au", "aax", "clap", "x64", "x86", "64bit", "32bit", "aufx", "aumu"]
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !formats.contains($0) }
            .joined()
    }

    /// Les .fst sous `base` (sous-dossiers compris, ni lien ni fichier caché), avec leur premier dossier (le format
    /// sous Installed) ; `skipping` : un dossier du premier niveau laissé de côté. 50 000 entrées au plus.
    private static func fstFiles(under base: URL, skipping: String?) -> [(url: URL, top: String)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard SecureFile.kind(at: base.path) == .directory,
              let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        // Chemins comparés liens résolus (/var et /private/var sur macOS).
        let basePath = base.resolvingSymlinksInPath().path
        var out: [(URL, String)] = []
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > 50_000 { break }
            let full = url.path.hasPrefix(basePath) ? url.path : url.resolvingSymlinksInPath().path
            let relative = full.dropFirst(basePath.count).split(separator: "/").map(String.init)
            if let skipping, relative.first == skipping {
                walker.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "fst",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            out.append((url, relative.count > 1 ? relative[0] : ""))
        }
        return out
    }

    /// Pure (testée) : la première case d'effet vide de la piste choisie du Mixer (06/11, « ça vise la piste qui est
    /// sélectionnée ») : dans le Mixer de FL, les cases libres de la piste choisie s'appellent « Slot 1 »…« Slot 10 » ;
    /// on dépose sur la plus petite. Lecture tolérante (« Slot l », « slot 1 »). nil : aucune case libre lue.
    static func mixerSlotPoint(in items: [TextLook.Item]) -> CGPoint? {
        var best: (number: Int, point: CGPoint)?
        for item in items {
            let words = item.text.lowercased().split(whereSeparator: { $0 == " " })
            guard words.count == 2, words[0] == "slot" else { continue }
            let digits = String(words[1]).map { c -> Character in c == "l" || c == "i" || c == "|" ? "1" : c == "o" ? "0" : c }
            guard let number = Int(String(digits)), (1...10).contains(number) else { continue }
            if best == nil || number < best!.number { best = (number, item.center) }
        }
        return best?.point
    }

    /// Un nom de son qu'on peut lire : 2 à 40 caractères, au moins une lettre.
    private static func usable(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return (2...40).contains(t.count) && t.contains(where: \.isLetter) && !t.contains(":")
    }

    /// Pure (testée) : point où déposer dans le Channel rack, toujours dans l'espace entre deux lignes (jamais SUR un son :
    /// il le remplacerait) : juste sous le dernier son ; Channel rack coupé (dernier nom lu à moitié, ou dernier son au
    /// ras de `bottom`, le bas de la fenêtre) : juste au-dessus du premier (vidéo du 04/11 : « ça fonctionne tout
    /// autant »). D'après les textes lus dans la fenêtre de FL : la colonne des noms sous le titre « Channel rack », à pas
    /// réguliers (un nom illisible laisse un trou d'une ligne). nil : titre absent, moins de deux noms, pas réguliers.
    /// Vidéo du 05/11 : dans le Channel rack de FL 2025, le titre est à droite des noms (centrés dans leur bouton, à
    /// ~100 points à gauche du titre) : les noms sont cherchés jusqu'à 240 points à gauche du titre, une colonne est
    /// faite des noms de même bord gauche OU de même centre, et la colonne la plus proche du titre l'emporte.
    static func channelRackPoint(in items: [TextLook.Item], bottom: CGFloat? = nil) -> CGPoint? {
        let titleKey = TextLook.normalized("Channel rack")
        for title in items.filter({ TextLook.normalized($0.text) == titleKey }).sorted(by: { $0.box.minY < $1.box.minY }) {
            let top = title.box.maxY
            let below = items.filter {
                $0.box.minY > top + 2 && $0.box.minY < top + 1500 && $0.box.minX > title.box.minX - 240
                    && $0.box.minX < title.box.minX + 520 && (6...40).contains($0.box.height) && $0.box.width <= 220
                    && usable($0.text)
            }.sorted { $0.box.minX < $1.box.minX }
            // Colonnes : même bord gauche ou même centre à 8 points près ; une ligne par son (une ligne lue et ses
            // mots : un seul).
            var columns: [[TextLook.Item]] = []
            for item in below {
                if let i = columns.firstIndex(where: {
                    abs($0[0].box.minX - item.box.minX) <= 8 || abs($0[0].center.x - item.center.x) <= 8
                }) {
                    if columns[i].allSatisfy({ abs($0.center.y - item.center.y) > 4 }) { columns[i].append(item) }
                } else {
                    columns.append([item])
                }
            }
            func distance(_ column: [TextLook.Item]) -> CGFloat { abs(column[0].center.x - title.center.x) }
            for column in columns.sorted(by: { ($0.count, -distance($0)) > ($1.count, -distance($1)) }) {
                guard column.count >= 2 else { break }
                // Dernier nom lu à moitié (coupé par le bas du Channel rack) : pas compté dans les lignes.
                let heights = column.map(\.box.height).sorted()
                let lastRead = column.max { $0.center.y < $1.center.y }!
                let halfRead = lastRead.box.height < heights[heights.count / 2] * 0.75
                let rows = halfRead ? column.filter { $0 != lastRead } : column
                guard rows.count >= 2 else { continue }
                let ys = rows.map(\.center.y).sorted()
                if ys[0] - top > 110 { continue }                        // les sons commencent juste sous le titre
                let diffs = zip(ys, ys.dropFirst()).map { $1 - $0 }
                guard let step = diffs.min(), (12...60).contains(step) else { continue }
                let regular = diffs.allSatisfy { d in
                    let k = d / step
                    return abs(k - k.rounded()) <= 0.25 && k <= 6.5
                }
                guard regular else { continue }
                let xs = rows.map(\.center.x).sorted()
                let cut = halfRead || (bottom.map { ys[ys.count - 1] + step > $0 - 8 } ?? false)
                return CGPoint(x: xs[xs.count / 2], y: cut ? ys[0] - step / 2 : ys[ys.count - 1] + step / 2)
            }
        }
        return nil
    }
}

extension MacroEffectsMac {
    /// Point de dépôt lu dans la plus grande fenêtre de FL qui le montre : sous le dernier son du Channel rack, ou la
    /// première case libre de la piste choisie du Mixer ; nil : la page n'est pas à l'écran.
    private func readDropPoint(effect: Bool, ctx: Context) -> CGPoint? {
        let windows = WinSnapshot.take(pid: ctx.pid).fl
            .filter { $0.layer == 0 && $0.bounds.width >= 300 && $0.bounds.height >= 200 && $0.number > 0 }
            .sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
        for w in windows {
            guard let image = ScreenLook.captureImage(windowNumber: w.number, size: w.bounds.size, scale: 2) else { continue }
            let items = TextLook.read(image, size: w.bounds.size)
            let p = effect ? PluginDrop.mixerSlotPoint(in: items)
                           : PluginDrop.channelRackPoint(in: items, bottom: w.bounds.height)
            if let p { return CGPoint(x: w.bounds.minX + p.x, y: w.bounds.minY + p.y) }
        }
        return nil
    }

    /// Le plugin ouvert en déposant son .fst (PluginDrop) ; nil : pas par là (le menu Add, comme avant). Jamais de nom
    /// au journal.
    func dropPlugin(_ name: String, item: String, ctx: Context) -> StepResult? {
        let effect = item == "Effect"
        let roots = Array(Set([FLPluginDatabase.root(), FLPluginDatabase.root(script: nil)].map(\.standardizedFileURL)))
        guard let file = roots.lazy.compactMap({ PluginDrop.presetFile(named: name, effect: effect, root: $0) }).first else {
            MacroLog.shared.write("PLUGIN", "drop: no .fst in the Plugin database (\(roots.count) bases), Add menu used")
            return nil
        }
        // 06/11 (« si la souris n'est pas sur la page Channel rack, ça ne fonctionne pas… que la souris y aille
        // automatiquement, sélectionne la page ») : la page est lue ; pas trouvée, elle est ouverte (sa touche de FL)
        // puis relue, avant de déposer. Instrument : sous le dernier son (au-dessus du premier si le Channel rack est
        // coupé) ; effet : la première case libre de la piste choisie du Mixer.
        var target: CGPoint?
        if Self.canRead {
            for attempt in 0..<3 {
                if let stop = stopReason() { return .cancel(stop) }
                target = readDropPoint(effect: effect, ctx: ctx)
                if target != nil { break }
                if attempt == 0 {
                    let page: FLPage = effect ? .mixer : .channelRack
                    guard let key = page.nativeKey(layout: SystemKeyboardLayout()) else { break }
                    postKey(key, pid: ctx.pid)
                    MacroLog.shared.write("PLUGIN", "drop: page \(page.rawValue) not read, opened")
                }
                usleep(450_000)
            }
        } else if !effect {
            // Sans « Enregistrement de l'écran », le Channel rack ne peut pas être lu : dit (jamais la fenêtre de macOS
            // au milieu d'une macro, elle passait derrière FL).
            MacroLog.shared.write("PLUGIN", "drop: screen recording not allowed, Add menu used")
            DispatchQueue.main.async {
                HintPanel.shared.flash(String(localized: "Autorise « Enregistrement de l'écran » : les plugins s'ouvriront plus vite."),
                                       seconds: 3)
            }
            return nil
        }
        // Effet sans case lue : la piste du dernier clic dans FL, comme avant.
        if target == nil, effect, FLWindows.contains(ctx.track, pid: ctx.pid) { target = ctx.track }
        guard let at = target else {
            MacroLog.shared.write("PLUGIN", effect ? "drop: no free slot read and aimed track outside FL, Add menu used" : "drop: Channel rack not read, Add menu used")
            return nil
        }
        switch dropFile(file.path, at: at, ctx: ctx) {
        case .ok:
            MacroLog.shared.write("PLUGIN", effect ? "effect dropped on the selected track" : "instrument dropped under the last channel")
            return .ok
        case .cancel(let why):
            return .cancel(why)
        default:
            MacroLog.shared.write("PLUGIN", "drop refused, Add menu used")
            return nil
        }
    }
}
