// Organiser : chaque son sur sa piste de la Playlist, et tous ses clips réunis sur cette piste (retour du
// propriétaire : « ranger chaque son différent dans une piste individuelle » ; « si il reconnaît des sons à
// l'identique, qu'il les mette dans la même piste »). Un même son : les patterns qui jouent exactement les mêmes sons.
// FL ne dit pas à un script où sont les clips et n'a aucune commande pour sélectionner ceux d'une seule piste : au
// moment de ranger, les noms écrits sur les clips (ceux de leurs patterns) sont lus dans la fenêtre de FL, pour savoir
// lesquels déplacer et les retrouver (lecture de cette fenêtre seule, autorisation « Enregistrement de l'écran »,
// partie visible de la Playlist). Chaque clip est sélectionné seul (⌘D, puis ⌘ + clic, la sélection de FL), puis monté
// ou descendu de piste en piste (⇧↑, ⇧↓) et vérifié en relisant la fenêtre : ce clip seul a changé de piste ; sinon il
// revient. Un clip n'est jamais posé sur un autre au même moment. Aucun nom n'est journalisé ni gardé.
import AppKit

/// Un clip de pattern lu dans la Playlist.
struct ClipSpot: Equatable {
    /// Le pattern (index 0 = pattern 1 de FL) et la piste (index 0 = piste 1).
    let pattern: Int
    var track: Int
    /// Bord gauche de son nom dans la fenêtre (points) : il ne change pas quand le clip change de piste.
    let x: CGFloat
    /// Où le cliquer pour le sélectionner, dans la fenêtre (points).
    var point: CGPoint
}

/// Un clip à déplacer, de sa piste vers celle de son son.
struct ClipMove: Equatable {
    let pattern: Int
    let from: Int
    let to: Int
    let x: CGFloat

    var reversed: ClipMove { ClipMove(pattern: pattern, from: to, to: from, x: x) }
}

/// La Playlist telle que la fenêtre de FL la montre : les clips de patterns lus, et les pistes visibles.
struct PlaylistView: Equatable {
    var clips: [ClipSpot]
    var visible: [Int]
}

enum ClipMoveResult: Equatable {
    case done
    /// Rien n'a bougé (clip pas retrouvé, ou revenu à sa place).
    case notDone
    /// Le clip n'a pas pu être remis à sa place.
    case stuck
}

enum ClipLayout {
    /// Écart toléré (points) entre deux lectures du même clip.
    static let tolerance: CGFloat = 6

    /// Pur (testé) : le pattern dont un texte lu est le nom : le nom entier, le nom sans le premier signe (l'icône du
    /// clip lue comme une lettre), ou le nom abrégé par FL dans un clip court (« M..3 » pour « Mélodie 3 »). nil si
    /// aucun ou plusieurs patterns conviennent.
    static func pattern(for text: String, names: [Int: String]) -> Int? {
        let wanted = names.mapValues(TextLook.normalized)
        let read = TextLook.normalized(text)
        var candidates = [read]
        if let space = read.firstIndex(of: " ") { candidates.append(String(read[read.index(after: space)...])) }
        for candidate in candidates {
            let exact = wanted.filter { $0.value == candidate }.map { $0.key }
            if exact.count == 1 { return exact[0] }
        }
        for candidate in candidates {
            let dots = candidate.replacingOccurrences(of: "…", with: "..")
            guard let range = dots.range(of: "..") else { continue }
            let prefix = String(dots[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let suffix = String(dots[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            guard prefix.count + suffix.count >= 2 else { continue }
            let found = wanted.filter { $0.value.hasPrefix(prefix) && $0.value.hasSuffix(suffix) }.map { $0.key }
            if found.count == 1 { return found[0] }
        }
        return nil
    }

    /// Pur (testé) : les clips lus. `names` : le nom de chaque pattern ; `rows` : le point visé sur le nom de chaque
    /// piste (PlaylistMover.rows), `pitch` : la hauteur d'une piste. Un clip est un texte à droite de la colonne des
    /// noms de pistes qui est le nom d'un pattern ; sa piste est la plus proche en hauteur (à une demi-piste près). Les
    /// lignes lues passent avant leurs mots : « Mélodie » dans « Mélodie 3 » n'est pas un autre clip.
    static func clips(items: [TextLook.Item], names: [Int: String], rows: [Int: CGPoint],
                      pitch: CGFloat) -> [ClipSpot] {
        guard pitch > 0, let left = rows.values.map(\.x).min() else { return [] }
        var out: [ClipSpot] = []
        var taken: [CGRect] = []
        for item in items.sorted(by: { $0.box.width > $1.box.width }) where item.box.minX > left + 40 {
            if taken.contains(where: { $0.insetBy(dx: -tolerance, dy: -tolerance).contains(item.box) }) { continue }
            guard let pattern = pattern(for: item.text, names: names),
                  let row = rows.min(by: { abs($0.value.y - item.box.midY) < abs($1.value.y - item.box.midY) }),
                  abs(row.value.y - item.box.midY) <= pitch / 2 else { continue }
            taken.append(item.box)
            // Dans le clip, sous son nom : jamais sur l'icône du clip (son menu), à gauche du nom.
            let point = CGPoint(x: item.box.minX + min(8, item.box.width / 2), y: item.box.midY + pitch * 0.3)
            let spot = ClipSpot(pattern: pattern, track: row.key, x: item.box.minX, point: point)
            // Une ligne et ses mots peuvent être lus tous les deux : un seul clip.
            if !out.contains(where: { $0.pattern == pattern && $0.track == spot.track && abs($0.x - spot.x) <= tolerance }) {
                out.append(spot)
            }
        }
        return out.sorted { ($0.track, $0.x) < ($1.track, $1.x) }
    }

    /// Pur (testé) : les déplacements pour qu'une piste ne porte qu'un son et que chaque son n'ait qu'une piste. Le
    /// son d'un pattern : ses sons (`sounds`), le même pour les patterns qui jouent exactement les mêmes ; inconnus,
    /// le pattern lui-même. Chaque piste appartient au son qui y a le plus de clips (égalité : celui qui y commence le
    /// plus tôt) ; un son
    /// va sur celle de ses pistes où il en a le plus (égalité : la plus haute) ; un son qui n'en a aucune, sur une
    /// piste vide de `free`, dans l'ordre. Ses autres clips l'y rejoignent, sauf sur un clip déjà là au même moment
    /// (FL l'écraserait).
    static func moves(_ clips: [ClipSpot], sounds: [Int: Set<Int>], free: [Int]) -> [ClipMove] {
        func group(_ pattern: Int) -> String {
            if let s = sounds[pattern], !s.isEmpty { return "s" + s.sorted().map(String.init).joined(separator: ",") }
            return "p\(pattern)"
        }
        let ordered = clips.sorted { ($0.track, $0.x) < ($1.track, $1.x) }
        var count: [Int: [String: Int]] = [:]
        var firstX: [Int: [String: CGFloat]] = [:]
        var firstSeen: [String: Int] = [:]
        for (i, clip) in ordered.enumerated() {
            let g = group(clip.pattern)
            count[clip.track, default: [:]][g, default: 0] += 1
            firstX[clip.track, default: [:]][g] = min(firstX[clip.track]?[g] ?? .greatestFiniteMagnitude, clip.x)
            if firstSeen[g] == nil { firstSeen[g] = i }
        }
        var home: [String: Int] = [:]
        for track in count.keys.sorted() {
            let starts = firstX[track] ?? [:]
            guard let owner = count[track]?.max(by: { a, b in
                a.value != b.value ? a.value < b.value : starts[a.key, default: 0] > starts[b.key, default: 0]
            })?.key else { continue }
            let here = count[track]?[owner] ?? 0
            if let current = home[owner], (count[current]?[owner] ?? 0) >= here { continue }
            home[owner] = track
        }
        var spare = free.filter { count[$0] == nil }.makeIterator()
        for g in firstSeen.keys.sorted(by: { firstSeen[$0, default: 0] < firstSeen[$1, default: 0] }) where home[g] == nil {
            home[g] = spare.next()
        }
        var placed: [Int: [CGFloat]] = [:]
        for clip in ordered { placed[clip.track, default: []].append(clip.x) }
        var out: [ClipMove] = []
        for clip in ordered {
            guard let to = home[group(clip.pattern)], to != clip.track,
                  !(placed[to] ?? []).contains(where: { abs($0 - clip.x) <= tolerance }) else { continue }
            // Parti de sa piste : la place qu'il y avait est libre.
            if let i = placed[clip.track]?.firstIndex(where: { abs($0 - clip.x) <= tolerance }) {
                placed[clip.track]?.remove(at: i)
            }
            placed[to, default: []].append(clip.x)
            out.append(ClipMove(pattern: clip.pattern, from: clip.track, to: to, x: clip.x))
        }
        return out
    }

    /// Pur (testé) : les clips une fois ces déplacements faits.
    static func applying(_ moves: [ClipMove], to clips: [ClipSpot]) -> [ClipSpot] {
        var out = clips
        for move in moves {
            if let i = out.firstIndex(where: { $0.pattern == move.pattern && $0.track == move.from
                                                && abs($0.x - move.x) <= tolerance }) {
                out[i].track = move.to
            }
        }
        return out
    }

    /// Pur (testé) : les sons de chaque piste une fois les clips à leur place : ceux de l'analyse (clips hors de la
    /// fenêtre, clips audio, noms illisibles compris), moins ceux des patterns partis de la piste, plus ceux des patterns
    /// qui y sont.
    static func trackSounds(_ original: [Int: Set<Int>], before: [ClipSpot], after: [ClipSpot],
                            sounds: [Int: Set<Int>]) -> [Int: Set<Int>] {
        var out = original
        for track in Set(before.map(\.track)).union(after.map(\.track)) {
            let was = Set(before.filter { $0.track == track }.map(\.pattern))
            let now = Set(after.filter { $0.track == track }.map(\.pattern))
            var here = original[track] ?? []
            for pattern in was.subtracting(now) { here.subtract(sounds[pattern] ?? []) }
            for pattern in now { here.formUnion(sounds[pattern] ?? []) }
            out[track] = here
        }
        return out.filter { !$0.value.isEmpty }
    }

    /// Pur (testé) : le déplacement est fait si ce clip est relu sur sa nouvelle piste et plus sur l'ancienne, et
    /// qu'aucun autre clip relu n'a changé de piste (FL sans sélection aurait déplacé tous les clips).
    static func confirms(_ move: ClipMove, before: [ClipSpot], after: [ClipSpot]) -> Bool {
        func near(_ a: ClipSpot, _ x: CGFloat) -> Bool { abs(a.x - x) <= tolerance }
        guard after.contains(where: { $0.pattern == move.pattern && $0.track == move.to && near($0, move.x) }),
              !after.contains(where: { $0.pattern == move.pattern && $0.track == move.from && near($0, move.x) })
        else { return false }
        for clip in before where !(clip.pattern == move.pattern && clip.track == move.from && near(clip, move.x)) {
            let again = after.filter { $0.pattern == clip.pattern && near($0, clip.x) }
            if !again.isEmpty && !again.contains(where: { $0.track == clip.track }) { return false }
        }
        return true
    }
}

/// Lecture de la Playlist dans la fenêtre de FL et déplacement d'un clip, comme le ferait l'utilisateur.
enum ClipMover {
    /// La Playlist lue maintenant ; nil si FL ne la montre pas (ou sans l'autorisation de lire sa fenêtre).
    static func read(link: OrganizerLink, pid: Int32) -> (window: CGRect, view: PlaylistView)? {
        guard ScreenLook.allowed, let patterns = try? link.listPatterns(),
              let tracks = try? link.listPlaylist(limit: OrganizerSession.maxTracks + 16), tracks.count >= 2 else {
            return nil
        }
        var names: [Int: String] = [:]
        for pattern in patterns where !pattern.name.isEmpty { names[pattern.index] = pattern.name }
        let windows = WinSnapshot.take(pid: pid).fl.filter { $0.layer == 0 && $0.bounds.width >= 300 && $0.bounds.height >= 200 }
        for window in windows.sorted(by: { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }) {
            guard let image = ScreenLook.captureImage(windowNumber: window.number, size: window.bounds.size, scale: 2)
            else { continue }
            let items = TextLook.read(image, size: window.bounds.size)
            guard let rows = PlaylistMover.rows(names: tracks.map(\.name), items: items), rows.count >= 2,
                  let a = rows[0], let b = rows[1] else { continue }
            let pitch = b.y - a.y
            // Pistes visibles : leur rangée tient dans la fenêtre (le nom et le clip sous lui).
            let visible = rows.filter { $0.value.y > 0 && $0.value.y + pitch * 0.5 < window.bounds.height }
                .map { $0.key }.sorted()
            let clips = ClipLayout.clips(items: items, names: names, rows: rows, pitch: pitch)
                .filter { visible.contains($0.track) }
            return (window.bounds, PlaylistView(clips: clips, visible: visible))
        }
        return nil
    }

    /// Le clip sélectionné seul (⌘D, puis ⌘ + clic) puis monté ou descendu jusqu'à sa piste (⇧↑, ⇧↓), vérifié en
    /// relisant la fenêtre ; pas confirmé : il revient d'autant. Hors du fil principal ; FL et sa Playlist devant.
    static func move(_ move: ClipMove, link: OrganizerLink, pid: Int32) -> ClipMoveResult {
        let rows = move.to - move.from
        guard rows != 0, let before = read(link: link, pid: pid),
              let clip = before.view.clips.first(where: {
                  $0.pattern == move.pattern && $0.track == move.from && abs($0.x - move.x) <= ClipLayout.tolerance
              }) else { return .notDone }
        let effects = MacroEffectsMac(pid: pid)
        defer { effects.restoreCursor() }
        let layout = SystemKeyboardLayout()
        let d = KeyNames.commandKeyCode(for: "d", layout: layout) ?? 2
        effects.postKey(KeyCombo(keyCode: d, command: true), pid: pid)            // rien de sélectionné
        Thread.sleep(forTimeInterval: 0.08)
        let target = CGPoint(x: before.window.minX + clip.point.x, y: before.window.minY + clip.point.y)
        guard case .ok = effects.click(at: target, right: false, ctx: effects.ctx, flags: .maskCommand) else {
            return .notDone
        }
        Thread.sleep(forTimeInterval: 0.12)
        let sent = arrows(rows, effects: effects, pid: pid)
        Thread.sleep(forTimeInterval: 0.15)
        for attempt in 0..<2 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.25) }      // une lecture peut manquer un nom
            if let after = read(link: link, pid: pid),
               ClipLayout.confirms(move, before: before.view.clips, after: after.view.clips) {
                return .done
            }
        }
        MacroLog.shared.write("PLAYLIST", "clip move not confirmed (\(abs(sent))/\(abs(rows)) steps)")
        // La même sélection revient d'autant ; relu : le clip est de nouveau sur sa piste.
        _ = arrows(-sent, effects: effects, pid: pid)
        Thread.sleep(forTimeInterval: 0.15)
        for attempt in 0..<2 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.25) }
            if let back = read(link: link, pid: pid), back.view.clips.contains(where: {
                $0.pattern == move.pattern && $0.track == move.from && abs($0.x - move.x) <= ClipLayout.tolerance
            }) { return .notDone }
        }
        return .stuck
    }

    /// ⇧↓ (positif) ou ⇧↑, envoyés à FL seul tant qu'il est devant ; le nombre envoyé, avec le signe du sens.
    private static func arrows(_ rows: Int, effects: MacroEffectsMac, pid: Int32) -> Int {
        let arrow = KeyCombo(keyCode: rows > 0 ? 125 : 126, shift: true)
        var done = 0
        while done < abs(rows) {
            guard EventTap.shared.currentConfig.frontmostPID == pid else { break }
            effects.postKey(arrow, pid: pid)
            done += 1
            Thread.sleep(forTimeInterval: 0.03)
        }
        return rows > 0 ? done : -done
    }
}
