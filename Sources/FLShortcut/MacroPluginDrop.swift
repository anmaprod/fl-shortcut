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

    /// Pure sur le disque (testée) : le .fst du plugin `name` dans la base `root`, au format préféré ; nil : absent.
    static func presetFile(named name: String, effect: Bool, root: URL) -> URL? {
        let wanted = TextLook.normalized(name)
        guard !wanted.isEmpty else { return nil }
        let prefer = preferredFormats(effect: effect)
        func rank(_ format: String) -> Int { prefer.firstIndex(of: formatKey(format)) ?? prefer.count }
        let plugins = FLPluginDatabase.installed(effect ? .effects : .generators, root: root)
            .filter { TextLook.normalized($0.name) == wanted }
            .sorted { (rank($0.format), $0.format) < (rank($1.format), $1.format) }
        for plugin in plugins {
            if let fst = plugin.files.first(where: { $0.pathExtension.lowercased() == "fst" }) { return fst }
        }
        return nil
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
    static func channelRackPoint(in items: [TextLook.Item], bottom: CGFloat? = nil) -> CGPoint? {
        let titleKey = TextLook.normalized("Channel rack")
        for title in items.filter({ TextLook.normalized($0.text) == titleKey }).sorted(by: { $0.box.minY < $1.box.minY }) {
            let top = title.box.maxY
            let below = items.filter {
                $0.box.minY > top + 2 && $0.box.minY < top + 1500 && $0.box.minX > title.box.minX - 40
                    && $0.box.minX < title.box.minX + 520 && (6...40).contains($0.box.height) && $0.box.width <= 220
                    && usable($0.text)
            }.sorted { $0.box.minX < $1.box.minX }
            // Colonnes : même bord gauche à 8 points près ; une ligne par son (une ligne lue et ses mots : un seul).
            var columns: [[TextLook.Item]] = []
            for item in below {
                if let i = columns.firstIndex(where: { abs($0[0].box.minX - item.box.minX) <= 8 }) {
                    if columns[i].allSatisfy({ abs($0.center.y - item.center.y) > 4 }) { columns[i].append(item) }
                } else {
                    columns.append([item])
                }
            }
            for column in columns.sorted(by: { $0.count > $1.count }) {
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
    /// Le plugin ouvert en déposant son .fst (PluginDrop) ; nil : pas par là (le menu Add, comme avant). Jamais de nom
    /// au journal.
    func dropPlugin(_ name: String, item: String, ctx: Context) -> StepResult? {
        let effect = item == "Effect"
        let roots = Array(Set([FLPluginDatabase.root(), FLPluginDatabase.root(script: nil)].map(\.standardizedFileURL)))
        guard let file = roots.lazy.compactMap({ PluginDrop.presetFile(named: name, effect: effect, root: $0) }).first else {
            return nil
        }
        var target: CGPoint?
        if effect {
            if FLWindows.contains(ctx.track, pid: ctx.pid) { target = ctx.track }
        } else if Self.canRead {
            let windows = WinSnapshot.take(pid: ctx.pid).fl
                .filter { $0.layer == 0 && $0.bounds.width >= 300 && $0.bounds.height >= 200 && $0.number > 0 }
                .sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
            for w in windows {
                if let stop = stopReason() { return .cancel(stop) }
                guard let image = ScreenLook.captureImage(windowNumber: w.number, size: w.bounds.size, scale: 2),
                      let p = PluginDrop.channelRackPoint(in: TextLook.read(image, size: w.bounds.size), bottom: w.bounds.height)
                else { continue }
                target = CGPoint(x: w.bounds.minX + p.x, y: w.bounds.minY + p.y)
                break
            }
        }
        guard let at = target else {
            MacroLog.shared.write("PLUGIN", effect ? "drop: aimed track outside FL, Add menu used" : "drop: Channel rack not read, Add menu used")
            return nil
        }
        switch dropFile(file.path, at: at, ctx: ctx) {
        case .ok:
            MacroLog.shared.write("PLUGIN", effect ? "effect dropped on the aimed track" : "instrument dropped under the last channel")
            return .ok
        case .cancel(let why):
            return .cancel(why)
        default:
            MacroLog.shared.write("PLUGIN", "drop refused, Add menu used")
            return nil
        }
    }
}
