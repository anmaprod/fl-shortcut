// Projets de FL fabriqués pour les tests, comme FL les écrit (même forme que le projet de test du propriétaire) :
// réglages MIDI, canaux, notes de chaque pattern, Playlist, pistes, Mixer.
import Foundation
@testable import FLShortcut

enum FLPSample {
    static func ev(_ id: UInt8, _ value: Int) -> FLPEvent {
        FLPEvent(id: id, bytes: FLPBytes.le(value, size: FLPEvent.fixedSize(id)!))
    }

    static func text(_ id: UInt8, _ s: String) -> FLPEvent {
        FLPEvent(id: id, bytes: s.utf16.flatMap { FLPBytes.le(Int($0), size: 2) } + [0, 0])
    }

    static func notes(_ list: [(channel: Int, key: Int)]) -> FLPEvent {
        var bytes: [UInt8] = []
        for (n, note) in list.enumerated() {
            bytes += FLPBytes.le(n * 96, size: 4) + FLPBytes.le(0x4000, size: 2) + FLPBytes.le(note.channel, size: 2)
            bytes += FLPBytes.le(96, size: 4) + FLPBytes.le(note.key, size: 2) + [0, 0, 120, 0, 100, 0, 64, 100, 128, 128]
        }
        return FLPEvent(id: 224, bytes: bytes)
    }

    struct ClipSpec {
        var pattern: Int? = nil
        var channel: Int? = nil
        var track: Int
        var bar: Int
        var bars = 4
    }

    static func playlist(_ clips: [ClipSpec], size: Int = 88, tracks: Int) -> FLPEvent {
        var bytes: [UInt8] = []
        for c in clips {
            var item = [UInt8](repeating: 0, count: size)
            FLPBytes.put(UInt32((c.bar - 1) * 384), into: &item, at: 0, size: 4)
            FLPBytes.put(0x5000, into: &item, at: 4, size: 2)
            FLPBytes.put(UInt32(c.pattern.map { 0x5000 + $0 } ?? c.channel!), into: &item, at: 6, size: 2)
            FLPBytes.put(UInt32(c.bars * 384), into: &item, at: 8, size: 4)
            FLPBytes.put(UInt32(tracks - 1 - c.track), into: &item, at: 12, size: 2)
            FLPBytes.put(0x7F7F7F7F, into: &item, at: 20, size: 4)
            bytes += item
        }
        return FLPEvent(id: 233, bytes: bytes)
    }

    static func track(_ number: Int, color: Int = 0x404040, muted: Bool = false) -> FLPEvent {
        var data = [UInt8](repeating: 0, count: 70)
        FLPBytes.put(UInt32(number), into: &data, at: 0, size: 4)
        FLPBytes.put(UInt32(color), into: &data, at: 4, size: 4)
        data[FLPProject.trackEnabled] = muted ? 0 : 1
        return FLPEvent(id: 238, bytes: data)
    }

    /// Le projet de test du propriétaire, en petit : réglages MIDI (où 64 sert à autre chose), canal 0 qui contient
    /// les noms des patterns, notes, Playlist (deux fois les mêmes patterns sur deux pistes), pistes, Mixer.
    /// `group` : groupe affiché par le Channel rack (-1 : « All ») ; `second` : un deuxième arrangement et ses clips ;
    /// `current` : l'arrangement ouvert (0 = le premier) ; `names` : noms des canaux ; `samples` : chemin du fichier
    /// de son de ces canaux ; `types` : type de ces canaux (4 : clip audio).
    static func sample(clips: [ClipSpec]? = nil, trackNames: [Int: String] = [:], trackCount: Int = 12,
                       group: Int? = nil, second: [ClipSpec]? = nil, current: Int? = nil,
                       names: [String] = ["Pad", "Kick", "ZENOLOGY", "Snare", "808"],
                       samples: [Int: String] = [:], types: [Int: Int] = [:]) -> FLPFile {
        var events: [FLPEvent] = [text(199, "26.1"), ev(0, 64), ev(100, 32896), ev(64, 2), ev(96, 0), ev(0, 71)]
        if let group { events.append(ev(146, group)) }
        events += [ev(65, 1), notes([(2, 60), (2, 64), (2, 67)]), ev(65, 2), notes([(3, 48), (4, 36)]),
                   ev(65, 3), notes([(1, 60)])]
        for (i, name) in names.enumerated() {
            events += [ev(64, i), ev(21, types[i] ?? (i == 2 ? 2 : 0)), text(201, i == 2 ? "Fruity Wrapper" : ""),
                       text(203, name)]
            if let path = samples[i] { events.append(text(196, path)) }
            if i == 0 {
                events += [ev(65, 1), text(193, "Mélodie"), ev(150, 0x404040), ev(65, 2), text(193, "Drums"),
                           ev(65, 4), text(193, "Vide")]
            }
            events.append(ev(128, 0x404040))
        }
        let spec = clips ?? [ClipSpec(pattern: 1, track: 0, bar: 1), ClipSpec(pattern: 2, track: 1, bar: 1),
                             ClipSpec(pattern: 1, track: 2, bar: 5), ClipSpec(pattern: 2, track: 3, bar: 5),
                             ClipSpec(pattern: 4, track: 4, bar: 1), ClipSpec(channel: 1, track: 5, bar: 9)]
        for (n, clips) in [spec, second].enumerated() {
            guard let clips else { continue }
            events += [ev(99, n), text(241, "Arrangement"), playlist(clips, tracks: trackCount)]
            for t in 0..<trackCount {
                events.append(track(t + 1))
                if let name = trackNames[t] { events.append(text(239, name)) }
                events.append(ev(43, 0))
            }
        }
        if let current { events.append(ev(100, current)) }
        events += [text(204, "Insert 1"), text(201, "Fruity Wrapper"), text(203, "Reverb"), text(236, "")]
        return FLPFile(channelCount: UInt16(names.count), ppq: 96, events: events)
    }
}
