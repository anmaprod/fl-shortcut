// Projet de FL lu dans son fichier (.flp) : ce que joue chaque pattern, où est chaque clip, et la copie rangée (retour
// du propriétaire, vidéo du 21/10 : des mélodies classées « FX », des patterns oubliés, des clips mal posés ; « je veux
// quelque chose de solide »). Les fichiers sont fabriqués ici, comme FL les écrit (même forme que son projet de test).
import XCTest
@testable import FLShortcut

final class FLPProjectTests: XCTestCase {
    // MARK: - Lecture

    func testFileIsRewrittenByteForByte() throws {
        var file = FLPSample.sample()
        file.events.append(FLPEvent(id: 212, bytes: [UInt8](repeating: 7, count: 300)))   // longueur sur 2 octets
        let bytes = file.encoded()
        let read = try FLPFile(bytes: bytes)
        XCTAssertEqual(read, file)
        XCTAssertEqual(read.encoded(), bytes)
    }

    func testDamagedFilesAreRefused() {
        let bytes = FLPSample.sample().encoded()
        XCTAssertThrowsError(try FLPFile(bytes: Array("RIFF".utf8) + bytes.dropFirst(4))) { error in
            XCTAssertEqual(error as? FLPError, .notProject)
        }
        XCTAssertThrowsError(try FLPFile(bytes: Array(bytes.prefix(bytes.count - 10)))) { error in
            XCTAssertEqual(error as? FLPError, .damaged, "fichier coupé")
        }
        XCTAssertThrowsError(try FLPFile(bytes: [])) { XCTAssertEqual($0 as? FLPError, .notProject) }
        var endless = Array(bytes.prefix(18))   // en-tête et « FLdt »
        endless += FLPBytes.le(6, size: 4) + [240, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
        XCTAssertThrowsError(try FLPFile(bytes: endless)) { XCTAssertEqual($0 as? FLPError, .damaged) }
    }

    func testChannelsPatternsAndClipsAreRead() throws {
        let project = try FLPProject(FLPSample.sample())
        XCTAssertEqual(project.channels.map(\.name), ["Pad", "Kick", "ZENOLOGY", "Snare", "808"],
                       "le 64 des réglages MIDI n'est pas un canal ; le nom d'un effet du Mixer non plus")
        XCTAssertEqual(project.channels.map(\.type), [0, 0, 2, 0, 0])
        XCTAssertEqual(project.sounds(of: 1), [2])
        XCTAssertEqual(project.sounds(of: 2), [3, 4])
        XCTAssertEqual(project.sounds(of: 4), [], "pattern vide : aucune note")
        XCTAssertEqual(project.notes[1], [2: 3])
        XCTAssertEqual(project.patternNames, [1: "Mélodie", 2: "Drums", 4: "Vide"])
        XCTAssertEqual(project.trackCount, 12)
        XCTAssertEqual(project.itemSize, 88)
        XCTAssertEqual(project.clips.map(\.source), [.pattern(1), .pattern(2), .pattern(1), .pattern(2), .pattern(4),
                                                     .channel(1)])
        XCTAssertEqual(project.clips.map(\.track), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(project.clips[2].position, 4 * 384)
        XCTAssertEqual(project.clips[2].length, 4 * 384)
    }

    func testOlderClipSizeIsRecognized() throws {
        var file = FLPSample.sample()
        let index = file.events.firstIndex { $0.id == 233 }!
        file.events[index] = FLPSample.playlist([FLPSample.ClipSpec(pattern: 2, track: 3, bar: 2)], size: 60, tracks: 12)
        let project = try FLPProject(file)
        XCTAssertEqual(project.itemSize, 60)
        XCTAssertEqual(project.clips.first?.track, 3)
        XCTAssertEqual(project.clips.first?.position, 384)
    }

    /// Ce qui n'a pas exactement la forme attendue arrête tout : rien n'est deviné.
    func testUnexpectedShapesStopEverything() {
        var two = FLPSample.sample()
        two.events += [FLPSample.ev(99, 1), FLPSample.playlist([FLPSample.ClipSpec(pattern: 1, track: 0, bar: 1)], tracks: 12)]
        XCTAssertThrowsError(try FLPProject(two)) {
            XCTAssertEqual($0 as? FLPError, .unsupported("arrangements"), "deux arrangements avec des clips")
        }
        var odd = FLPSample.sample()
        let index = odd.events.firstIndex { $0.id == 233 }!
        odd.events[index].bytes.removeLast()
        XCTAssertThrowsError(try FLPProject(odd)) { XCTAssertEqual($0 as? FLPError, .unsupported("clips")) }
        var hole = FLPSample.sample()
        let second = hole.events.indices.filter { hole.events[$0].id == 238 }[1]
        hole.events[second] = FLPSample.track(7)
        XCTAssertThrowsError(try FLPProject(hole)) { XCTAssertEqual($0 as? FLPError, .unsupported("pistes")) }
        var stray = FLPSample.sample()
        let notesAt = stray.events.firstIndex { $0.id == 224 }!
        stray.events[notesAt] = FLPSample.notes([(9, 60)])
        XCTAssertThrowsError(try FLPProject(stray)) {
            XCTAssertEqual($0 as? FLPError, .unsupported("notes"), "note d'un canal qui n'existe pas")
        }
    }

    /// Plusieurs arrangements (retour du propriétaire : « si j'en ai deux il bloque ») : celui qui est ouvert dans FL
    /// est rangé, l'autre ne bouge pas ; sans savoir lequel est ouvert, rien n'est deviné.
    func testOpenArrangementIsTheOneOrganized() throws {
        let second = [FLPSample.ClipSpec(pattern: 2, track: 0, bar: 1)]
        let file = FLPSample.sample(second: second, current: 1)
        let open = try FLPProject(file)
        XCTAssertEqual(open.clips.map(\.source), [.pattern(2)])
        XCTAssertEqual(open.trackCount, 12)
        XCTAssertEqual(try FLPProject(FLPSample.sample(second: second, current: 0)).clips.count, 6)
        XCTAssertThrowsError(try FLPProject(FLPSample.sample(second: second))) {
            XCTAssertEqual($0 as? FLPError, .unsupported("arrangements"))
        }
        XCTAssertEqual(try FLPProject(FLPSample.sample(second: [])).clips.count, 6, "un seul a des clips")
        let copy = try open.rearranged(file, tracks: [0: 3])
        XCTAssertEqual(try FLPProject(copy).clips.map(\.track), [3])
        let playlists: (FLPFile) -> [FLPEvent] = { $0.events.filter { $0.id == 233 } }
        XCTAssertEqual(playlists(copy).first, playlists(file).first, "l'autre arrangement ne bouge pas")
        let first: (FLPFile) -> [FLPEvent] = { f in
            let at = f.events.firstIndex { $0.id == 99 && $0.value == 1 }!
            return Array(f.events[..<at].filter { $0.id == 238 || $0.id == 239 })
        }
        XCTAssertEqual(first(copy), first(file), "ni ses pistes")
    }

    /// Channel rack sur un groupe (« Unsorted »…) : la copie le montre sur « All », rien d'autre ne change.
    func testCopyShowsAllChannels() throws {
        let file = FLPSample.sample(group: 2)
        let project = try FLPProject(file)
        XCTAssertTrue(project.showsGroup)
        let all = project.showingAll(file)
        XCTAssertFalse(try FLPProject(all).showsGroup)
        XCTAssertEqual(all.events.filter { $0.id == 146 }.map(\.bytes), [[0xFF, 0xFF, 0xFF, 0xFF]])
        XCTAssertEqual(all.events.filter { $0.id != 146 }, file.events.filter { $0.id != 146 })
        let copy = try project.rearranged(file, tracks: [:])
        XCTAssertEqual(copy.events.filter { $0.id == 146 }.map(\.bytes), [[0xFF, 0xFF, 0xFF, 0xFF]])
        XCTAssertFalse(try FLPProject(FLPSample.sample(group: -1)).showsGroup)
        XCTAssertEqual(FLPSample.sample().events.filter { $0.id == 146 }, [], "pas écrit : rien à changer")
        XCTAssertEqual(try FLPProject(FLPSample.sample()).showingAll(FLPSample.sample()), FLPSample.sample())
    }

    func testLayerPlaysItsChildren() throws {
        var file = FLPSample.sample()
        let pad = file.events.firstIndex { $0.id == 203 && $0.text == "Pad" }!
        file.events[pad - 2] = FLPSample.ev(21, 3)
        file.events.insert(contentsOf: [FLPSample.ev(94, 3), FLPSample.ev(94, 4)], at: pad + 1)
        let project = try FLPProject(file)
        XCTAssertEqual(project.channels[0].type, 3)
        XCTAssertEqual(project.channels[0].children, [3, 4])
        XCTAssertEqual(project.played([0, 2]), [2, 3, 4])
    }

    // MARK: - Rangement

    private func group(_ project: FLPProject) -> (FLPProject.Clip) -> PlaylistLayout.Group {
        { clip in
            switch clip.source {
            case .pattern(let n):
                let sounds = project.sounds(of: n)
                return sounds.isEmpty ? .silent(n) : .sounds(sounds)
            case .channel(let c): return .sounds([c])
            }
        }
    }

    /// La vidéo : les mêmes patterns posés deux fois, sur deux pistes ; chaque pattern finit seul sur sa piste avec
    /// toutes ses répétitions, mélodies d'abord, puis drums, puis le pattern vide.
    func testSameSoundsShareOneTrack() throws {
        let project = try FLPProject(FLPSample.sample())
        let melody: Set<Int> = [2]
        let layout = try XCTUnwrap(PlaylistLayout.make(project.clips, group: group(project),
                                                       key: { ($0.isSubset(of: melody) ? 0 : 1, 0, $0.min()!) },
                                                       trackCount: project.trackCount))
        XCTAssertEqual(layout.tracks, [0: 0, 2: 0, 1: 2, 3: 2, 5: 1, 4: 3])
        XCTAssertEqual(layout.sounds, [0: [2], 1: [1], 2: [3, 4]])
        XCTAssertEqual(layout.count, 4)
    }

    func testOverlappingClipsOfOneSoundGetAnotherTrack() throws {
        let clips = [FLPSample.ClipSpec(pattern: 1, track: 0, bar: 1, bars: 8), FLPSample.ClipSpec(pattern: 1, track: 3, bar: 5),
                     FLPSample.ClipSpec(pattern: 1, track: 2, bar: 9), FLPSample.ClipSpec(pattern: 3, track: 1, bar: 1)]
        let project = try FLPProject(FLPSample.sample(clips: clips))
        let layout = try XCTUnwrap(PlaylistLayout.make(project.clips, group: group(project), key: { (0, 0, $0.min()!) },
                                                       trackCount: project.trackCount))
        XCTAssertEqual(layout.tracks, [3: 0, 0: 1, 2: 1, 1: 2], "le clip qui chevauche passe juste dessous")
        XCTAssertEqual(layout.sounds, [0: [1], 1: [2], 2: [2]])
        XCTAssertNil(PlaylistLayout.make(project.clips, group: group(project), key: { (0, 0, $0.min()!) },
                                         trackCount: 2), "plus de pistes que FL n'en a : rien")
    }

    /// La copie : seuls les clips changent de piste ; les pistes où il y avait ou où il y a des clips perdent leur
    /// ancien nom et leur couleur (rien d'autre ne bouge, octet pour octet).
    func testCopyMovesOnlyTheClips() throws {
        var file = FLPSample.sample(trackNames: [1: "Intro", 9: "Voix plus tard"])
        let colored = file.events.indices.filter { file.events[$0].id == 238 }[3]
        file.events[colored] = FLPSample.track(4, color: 0x00FF00)
        let project = try FLPProject(file)
        let moves = [0: 0, 2: 0, 1: 2, 3: 2, 5: 1, 4: 3]
        let copy = try project.rearranged(file, tracks: moves)
        let again = try FLPProject(FLPFile(bytes: copy.encoded()))
        XCTAssertEqual(again.clips.map(\.track), [0, 2, 0, 2, 3, 1])
        XCTAssertEqual(again.clips.map(\.source), project.clips.map(\.source))
        XCTAssertEqual(again.clips.map(\.position), project.clips.map(\.position))
        XCTAssertEqual(again.clips.map(\.length), project.clips.map(\.length))
        XCTAssertEqual(copy.events.filter { $0.id == 239 }.map(\.text), ["Voix plus tard"],
                       "nom d'une piste jamais touchée : gardé")
        let colors = copy.events.filter { $0.id == 238 }.map { FLPBytes.uint($0.bytes, at: 4, size: 4) }
        XCTAssertEqual(Set(colors), [0x404040], "couleur des pistes jamais touchées")
        let others: (FLPFile) -> [FLPEvent] = { $0.events.filter { ![233, 238, 239].contains($0.id) } }
        XCTAssertEqual(others(copy), others(file), "tout le reste, tel quel")
        let playlist = file.events.firstIndex { $0.id == 233 }!
        let same = try project.rearranged(file, tracks: Dictionary(uniqueKeysWithValues: project.clips.map {
            ($0.item, $0.track)
        }))
        XCTAssertEqual(same.events[playlist], file.events[playlist], "sans changement de piste : à l'identique")
        XCTAssertThrowsError(try project.rearranged(file, tracks: [0: 12])) {
            XCTAssertEqual($0 as? FLPError, .unsupported("clips"))
        }
    }

    /// Une piste coupée (mute) : un clip qui en part se mettrait à jouer dans la copie, donc rien n'est fait ; une
    /// piste coupée sans clip reste coupée, les pistes touchées jouent.
    func testMutedTrackStopsTheCopy() throws {
        var file = FLPSample.sample()
        let tracks = file.events.indices.filter { file.events[$0].id == 238 }
        file.events[tracks[3]] = FLPSample.track(4, muted: true)
        let project = try FLPProject(file)
        XCTAssertEqual(project.mutedTracks, [3])
        XCTAssertThrowsError(try project.rearranged(file, tracks: [3: 2])) {
            XCTAssertEqual($0 as? FLPError, .unsupported("piste coupée"))
        }
        var quiet = FLPSample.sample()
        quiet.events[tracks[9]] = FLPSample.track(10, muted: true)
        let copy = try FLPProject(quiet).rearranged(quiet, tracks: [0: 9, 5: 0])
        XCTAssertEqual(try FLPProject(copy).mutedTracks, [], "la piste qui reçoit un clip joue")
        XCTAssertEqual(try FLPProject(FLPProject(quiet).rearranged(quiet, tracks: [:])).mutedTracks, [9],
                       "une piste coupée jamais touchée le reste")
    }

    /// FL 2025 (projet de test du propriétaire, vidéo du 22/10) : l'événement 172 a un octet de forme, puis 2 ou 4
    /// octets. Lu comme les autres, il décalait la lecture et les notes du pattern 1 (ZENOLOGY) disparaissaient : la
    /// mélodie finissait en bas, comme un pattern vide.
    func testFL2025EventKeepsTheReadingAligned() throws {
        var file = FLPSample.sample()
        file.events.insert(contentsOf: [FLPEvent(id: 172, bytes: [1, 1, 0]), FLPSample.text(192, "FL Studio 26.1"),
                                        FLPEvent(id: 172, bytes: [0, 1, 0, 0, 0]), FLPSample.ev(37, 2)], at: 1)
        let read = try FLPFile(bytes: file.encoded())
        XCTAssertEqual(read, file)
        XCTAssertEqual(read.encoded(), file.encoded())
        XCTAssertEqual(try FLPProject(read).sounds(of: 1), [2], "les notes du pattern 1 sont lues")
        var odd = FLPSample.sample()
        odd.events.insert(FLPEvent(id: 172, bytes: [2, 0, 0, 0]), at: 1)
        XCTAssertThrowsError(try FLPFile(bytes: odd.encoded())) {
            XCTAssertEqual($0 as? FLPError, .unsupported("événement 172"), "forme inconnue : rien n'est deviné")
        }
    }

    /// Des notes de pattern ailleurs qu'au début d'un événement (avant les canaux) : la lecture s'est décalée sur un
    /// événement inconnu, des notes manqueraient. Tout s'arrête.
    func testHiddenNotesStopEverything() {
        var file = FLPSample.sample()
        let notes = FLPSample.notes([(2, 60)])
        let hidden = [UInt8(65), 1, 0, 224, UInt8(notes.bytes.count)] + notes.bytes
        file.events.insert(FLPEvent(id: 212, bytes: [9, 9] + hidden), at: 1)
        XCTAssertThrowsError(try FLPFile(bytes: file.encoded())) {
            XCTAssertEqual($0 as? FLPError, .unsupported("lecture"))
        }
        let fewer = FLPFile(channelCount: 9, ppq: 96, events: FLPSample.sample().events)
        XCTAssertThrowsError(try FLPProject(fewer)) {
            XCTAssertEqual($0 as? FLPError, .unsupported("canaux"), "l'en-tête dit 9 canaux, la lecture en trouve 5")
        }
    }
}
