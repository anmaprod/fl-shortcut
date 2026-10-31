// Organiser : une piste de la Playlist remontée comme le ferait l'utilisateur, FL ne permettant pas de la déplacer
// depuis un script : clic droit sur son nom (menu de la piste), puis « Move up » (retour de l'utilisateur : la Playlist
// doit être rangée comme le Channel rack et le Mixer). Le nom de la piste est retrouvé dans la fenêtre de FL au moment
// du clic, comme un bouton retrouvé à son nom (lecture de cette fenêtre seule, autorisation « Enregistrement de
// l'écran ») ; « Move up » aussi, dans le menu ouvert. Chaque pas est vérifié par le script (la piste est bien montée
// d'une place) ; au premier doute, tout s'arrête et le menu est refermé. Aucun nom n'est journalisé.
import AppKit

enum PlaylistMover {
    /// Remonte la piste à `place` (0 = la piste 1 de FL) de `count` places ; renvoie le nombre de places faites.
    /// Hors du fil principal ; la Playlist doit être devant.
    static func moveUp(_ place: Int, _ count: Int, link: OrganizerLink, pid: Int32) -> Int {
        guard count > 0, place >= count, ScreenLook.allowed else { return 0 }
        let effects = MacroEffectsMac(pid: pid)
        defer { effects.restoreCursor() }
        guard var tracks = try? link.listPlaylist(limit: place + 1), tracks.count == place + 1,
              let spot = headerRows(names: tracks.map(\.name), pid: pid) else {
            MacroLog.shared.write("PLAYLIST", "track names not found in FL's window")
            return 0
        }
        var at = place
        var done = 0
        while done < count {
            guard let point = spot.rows[at] else { break }
            // « Move up » remonte la piste sélectionnée : elle seule, choisie par le script avant le clic.
            guard (try? link.selectOne(.playlist, at)) != nil else { break }
            let screen = CGPoint(x: spot.window.minX + point.x, y: spot.window.minY + point.y)
            guard menuMoveUp(at: screen, effects: effects, pid: pid) else { break }
            // Vérifié par le script : la piste est montée d'une place, celle d'au-dessus est descendue.
            guard let now = try? link.listPlaylist(limit: at + 1), now.count == at + 1,
                  Self.same(now[at - 1], tracks[at]), Self.same(now[at], tracks[at - 1]) else {
                MacroLog.shared.write("PLAYLIST", "move up not confirmed by FL (step \(done + 1))")
                break
            }
            tracks = now
            at -= 1
            done += 1
        }
        MacroLog.shared.write("PLAYLIST", "track moved up \(done)/\(count)")
        return done
    }

    /// Même piste : même nom et même couleur (un nom de FL, « Track 4 », suit la place : la couleur décide).
    private static func same(_ a: PlaylistTrackInfo, _ b: PlaylistTrackInfo) -> Bool {
        let defaultNames = a.hasDefaultName && b.hasDefaultName
        return (defaultNames || a.name == b.name) && a.color == b.color
    }

    /// Clic droit sur le nom de la piste, puis « Move up » dans le menu de FL ; vrai si le menu s'est refermé sur ce
    /// choix. Menu sans « Move up » : refermé (Échap), faux.
    private static func menuMoveUp(at p: CGPoint, effects: MacroEffectsMac, pid: Int32) -> Bool {
        let before = WinSnapshot.take(pid: pid).numbers
        guard case .ok = effects.click(at: p, right: true, ctx: effects.ctx) else { return false }
        guard case .success(let menu) = WindowWait.newWindow(pid: pid, excluding: before, timeout: 1.5,
                                                              stop: { nil }) else { return false }
        let wanted = TextLook.normalized("Move up")
        guard let image = ScreenLook.captureImage(windowNumber: menu.number, size: menu.bounds.size, scale: 2),
              let item = TextLook.read(image, size: menu.bounds.size)
                .first(where: { TextLook.normalized($0.text) == wanted }) else {
            close(menu, effects: effects, pid: pid)
            return false
        }
        let target = CGPoint(x: menu.bounds.minX + item.center.x, y: menu.bounds.minY + item.center.y)
        guard case .ok = effects.click(at: target, right: false, ctx: effects.ctx) else {
            close(menu, effects: effects, pid: pid)
            return false
        }
        guard case .success = WindowWait.gone(pid: pid, numbers: [menu.number], timeout: 1, stop: { nil }) else {
            close(menu, effects: effects, pid: pid)
            return false
        }
        Thread.sleep(forTimeInterval: 0.08)
        return true
    }

    private static func close(_ menu: WinInfo, effects: MacroEffectsMac, pid: Int32) {
        effects.postKey(KeyCombo(keyCode: 53), pid: pid)
        _ = WindowWait.gone(pid: pid, numbers: [menu.number], timeout: 0.5, stop: { nil })
    }

    /// Fenêtre de FL où sont les noms des pistes (la Playlist peut être détachée) et la place de chaque nom dans
    /// cette fenêtre ; nil si les noms n'y sont pas.
    private static func headerRows(names: [String], pid: Int32) -> (window: CGRect, rows: [Int: CGPoint])? {
        let windows = WinSnapshot.take(pid: pid).fl.filter { $0.layer == 0 && $0.bounds.width >= 300 && $0.bounds.height >= 200 }
        for window in windows.sorted(by: { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }) {
            guard let image = ScreenLook.captureImage(windowNumber: window.number, size: window.bounds.size, scale: 2)
            else { continue }
            if let rows = rows(names: names, items: TextLook.read(image, size: window.bounds.size)) {
                return (window.bounds, rows)
            }
        }
        return nil
    }

    /// Pur (testé) : point à viser pour chaque piste (0…), dans la colonne des noms de la Playlist d'après les textes
    /// lus : la colonne (même bord gauche, à 10 points près) où le plus de noms attendus se suivent de haut en bas ;
    /// à égalité, la plus à gauche (les clips de la Playlist portent souvent les mêmes noms, plus à droite). Une piste
    /// dont le nom n'est pas lu prend sa place d'après le pas entre les rangées. nil si moins de 2 noms sont trouvés.
    static func rows(names: [String], items: [TextLook.Item]) -> [Int: CGPoint]? {
        let wanted = names.map(TextLook.normalized)
        let matching = items.filter { wanted.contains(TextLook.normalized($0.text)) }
        var columns: [[TextLook.Item]] = []
        for item in matching.sorted(by: { $0.box.minX < $1.box.minX }) {
            if let i = columns.firstIndex(where: { abs($0[0].box.minX - item.box.minX) <= 10 }) {
                columns[i].append(item)
            } else {
                columns.append([item])
            }
        }
        var best: (found: [Int: TextLook.Item], left: CGFloat)?
        for column in columns {
            var found: [Int: TextLook.Item] = [:]
            var last = -1
            for item in column.sorted(by: { $0.box.midY < $1.box.midY }) {
                let text = TextLook.normalized(item.text)
                guard let slot = wanted.indices.first(where: { $0 > last && wanted[$0] == text }) else { continue }
                found[slot] = item
                last = slot
            }
            let left = column.map(\.box.minX).min() ?? 0
            if found.count > best?.found.count ?? 1 || (found.count == best?.found.count && left < best?.left ?? 0) {
                best = (found, left)
            }
        }
        guard let found = best?.found, let left = best?.left, found.count >= 2 else { return nil }
        let slots = found.keys.sorted()
        var steps: [CGFloat] = []
        for (a, b) in zip(slots, slots.dropFirst()) {
            steps.append((found[b]!.box.midY - found[a]!.box.midY) / CGFloat(b - a))
        }
        let pitch = steps.sorted()[steps.count / 2]
        guard pitch >= 8 else { return nil }
        var out: [Int: CGPoint] = [:]
        for slot in names.indices {
            let nearest = slots.min { abs($0 - slot) < abs($1 - slot) }!
            let y = found[nearest]!.box.midY + CGFloat(slot - nearest) * pitch
            out[slot] = CGPoint(x: left + 8, y: y)
        }
        return out
    }
}
