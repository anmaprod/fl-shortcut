import XCTest
@testable import FLShortcut

/// FL simulé pour l'Organiser : tout le projet (Channel rack, patterns, Mixer, Playlist), journal des opérations,
/// mémo de l'écoute comme le script, déplacements au clavier (⌥↑ dans le Channel rack, ⌥← dans le Mixer).
final class FakeOrganizerLink: OrganizerLink {
    var window: FLWindow = .channelRack
    var channels: [ChannelInfo] = []
    /// Toutes les pistes du Mixer, Master compris (index = numéro de la piste).
    var mixer: [MixerTrackInfo] = []
    var playlist: [PlaylistTrackInfo] = []
    var patternList: [PatternInfo] = []
    /// Script v12 simulé ; faux : un ancien script, qui refuse les patterns (FL à redémarrer).
    var v12 = true
    /// Faux : FL trop ancien pour jouer toute la chanson (relevé de la Playlist impossible).
    var song = true
    /// Sons qui jouent dans chaque pattern (1 = le premier), pistes et sons qui jouent à chaque position de la
    /// chanson, sons qui jouent quand une piste de la Playlist joue seule (index 0 = piste 1).
    var patternSounds: [Int: Set<Int>] = [:]
    var songAt: (Double) -> (tracks: Set<Int>, channels: Set<Int>) = { _ in ([], []) }
    var trackChannels: [Int: Set<Int>] = [:]
    var routes: [Int: [Int]] = [:]
    var currentPattern = 1
    /// Longueur de la chanson rendue par l'écoute (opérations 11 et 16).
    var bars = 32
    var playing = false
    private(set) var log: [String] = []
    private(set) var solo: Int?
    /// Piste de la Playlist jouée seule, et la position de la chanson (0…1).
    private(set) var track: Int?
    private(set) var position = 0.0
    private var memo = false
    /// Pattern joué par la dernière opération 6 (nil : celui qui est ouvert), position de la chanson jouée en entier.
    private(set) var playedPattern: Int?
    private(set) var songPosition: Double?
    private(set) var selected: Int?
    private(set) var selectedTrack: Int?
    /// Index des couleurs ignorées par ce faux FL (pour tester la vérification), et genre concerné.
    var ignoredColors: Set<Int> = []
    var ignoredKind: ItemKind = .channels

    func page() throws -> FLWindow { window }

    func listChannels() throws -> [ChannelInfo] {
        log.append("list")
        return channels
    }

    func listMixer() throws -> [MixerTrackInfo] {
        log.append("mixer")
        return mixer
    }

    func listPlaylist(limit: Int) throws -> [PlaylistTrackInfo] {
        log.append("playlist")
        return Array(playlist.prefix(limit))
    }

    func listPatterns() throws -> [PatternInfo] {
        guard v12 else { throw OrganizerError.outdatedScript }
        log.append("patterns")
        return patternList
    }

    func routes(from track: Int) throws -> [Int] {
        log.append("routes \(track)")
        return routes[track] ?? []
    }

    func show(_ window: FLWindow) throws {
        log.append("show \(window)")
        self.window = window
    }

    func setColors(_ kind: ItemKind, _ colors: [(index: Int, color: FLShortcut.RGBColor)]) throws {
        guard !colors.isEmpty else { return }
        log.append("colors \(kind) \(colors.count)")
        for (index, color) in colors where !(kind == ignoredKind && ignoredColors.contains(index)) {
            switch kind {
            case .channels:
                if channels.indices.contains(index) { channels[index] = Self.copy(channels[index], index: index, color: color) }
            case .mixer:
                if mixer.indices.contains(index) {
                    mixer[index] = MixerTrackInfo(index: index, color: color, name: mixer[index].name)
                }
            case .playlist:
                if playlist.indices.contains(index) {
                    let t = playlist[index]
                    playlist[index] = PlaylistTrackInfo(index: index, selected: t.selected, color: color, name: t.name)
                }
            case .patterns:
                if patternList.indices.contains(index) {
                    patternList[index] = PatternInfo(index: index, color: color, name: patternList[index].name)
                }
            }
        }
    }

    func setNames(_ kind: ItemKind, _ names: [(index: Int, name: String)]) throws {
        guard !names.isEmpty else { return }
        log.append("names \(kind) \(names.count)")
        for (index, name) in names {
            switch kind {
            case .channels:
                if channels.indices.contains(index) {
                    let c = channels[index]
                    channels[index] = ChannelInfo(index: index, type: c.type, mixerTrack: c.mixerTrack, color: c.color,
                                                  name: name)
                }
            case .mixer:
                if mixer.indices.contains(index) {
                    mixer[index] = MixerTrackInfo(index: index, color: mixer[index].color, name: name)
                }
            case .playlist:
                if playlist.indices.contains(index) {
                    let t = playlist[index]
                    playlist[index] = PlaylistTrackInfo(index: index, selected: t.selected, color: t.color, name: name)
                }
            case .patterns:
                if patternList.indices.contains(index) {
                    patternList[index] = PatternInfo(index: index, color: patternList[index].color, name: name)
                }
            }
        }
    }

    func selectOne(_ kind: ItemKind, _ index: Int) throws {
        log.append("select \(kind) \(index)")
        if kind == .mixer { selectedTrack = index } else { selected = index }
    }

    /// ⌥↑ simulé : le canal sélectionné remonte d'une place par pas, tant que le Channel rack est devant.
    func moveSelectedUp(_ count: Int) -> Int {
        var done = 0
        while done < count, window == .channelRack, let at = selected, at > 0 {
            channels.swapAt(at, at - 1)
            selected = at - 1
            done += 1
        }
        channels = channels.enumerated().map { Self.copy($0.element, index: $0.offset, color: $0.element.color) }
        return done
    }

    /// ⌥← simulé : la piste du Mixer sélectionnée passe à gauche d'une place par pas, tant que le Mixer est devant ;
    /// jamais à la place du Master. Les canaux reliés suivent leur piste, comme dans FL.
    func moveSelectedLeft(_ count: Int) -> Int {
        var done = 0
        while done < count, window == .mixer, let at = selectedTrack, at > 1, at < mixer.count {
            mixer.swapAt(at, at - 1)
            channels = channels.map { c in
                let fx = c.mixerTrack == at ? at - 1 : c.mixerTrack == at - 1 ? at : c.mixerTrack
                return ChannelInfo(index: c.index, type: c.type, mixerTrack: fx, color: c.color, name: c.name)
            }
            selectedTrack = at - 1
            done += 1
        }
        mixer = mixer.enumerated().map { MixerTrackInfo(index: $0.offset, color: $0.element.color, name: $0.element.name) }
        return done
    }

    static func copy(_ c: ChannelInfo, index: Int, color: FLShortcut.RGBColor) -> ChannelInfo {
        ChannelInfo(index: index, type: c.type, mixerTrack: c.mixerTrack, color: color, name: c.name)
    }

    func playSolo(_ channel: Int, pattern: Int?) throws {
        if !memo && playing { throw OrganizerError.refused(4) }
        memo = true
        playing = true
        playedPattern = pattern
        songPosition = nil
        track = nil
        if channel == OrganizerPayload.allChannels {
            solo = nil
            log.append("all \(pattern ?? 0)")
        } else {
            solo = channel
            log.append(pattern.map { "solo \(channel) p\($0)" } ?? "solo \(channel)")
        }
    }

    func patterns() throws -> (count: Int, current: Int) { (patternList.count, currentPattern) }

    func activeChannels() throws -> Set<Int> {
        if let track { return trackChannels[track] ?? [] }
        if let at = songPosition { return songAt(at).channels }
        if solo == nil, let p = playedPattern { return patternSounds[p] ?? [] }
        return []
    }

    func activeTracks() throws -> Set<Int> {
        songPosition.map { songAt($0).tracks } ?? []
    }

    func playSong(at fraction: Double) throws -> Int {
        guard song else { throw OrganizerError.refused(6) }
        if !memo && playing { throw OrganizerError.refused(4) }
        memo = true
        playing = true
        solo = nil
        track = nil
        songPosition = fraction
        log.append("song \(Int((fraction * 1000).rounded()))")
        return bars
    }

    func playTrack(_ index: Int) throws -> Int {
        if !memo && playing { throw OrganizerError.refused(4) }
        memo = true
        playing = true
        songPosition = nil
        track = index
        position = 0
        log.append("track \(index)")
        return bars
    }

    func seek(_ fraction: Double) throws {
        guard memo, track != nil else { throw OrganizerError.refused(5) }
        position = fraction
        log.append("seek \(Int((fraction * 1000).rounded()))")
    }

    /// Comme le script : sans écoute en cours (pas de mémo), rien ne change.
    func stopRestore() {
        log.append("restore")
        if memo { playing = false }
        memo = false
        solo = nil
        track = nil
        playedPattern = nil
        songPosition = nil
    }

    func audition(_ channel: Int, note: UInt8, velocity: UInt8) throws {
        log.append("note \(channel) \(note) \(velocity)")
    }
}

/// Capture simulée : le son de la partie du canal en solo, ou celui de ses notes d'essai ; une piste de la Playlist
/// jouée seule : le son de son clip audio.
final class FakeAudio: AudioSource {
    let rate = 48_000.0
    let link: FakeOrganizerLink
    var parts: [Int: [Float]] = [:]
    var testSounds: [Int: [Float]] = [:]
    /// Son du clip audio de chaque piste de la Playlist (index 0 = piste 1).
    var clips: [Int: [Float]] = [:]
    /// Canal dont la partie ne joue que dans ce pattern (ailleurs : muet, comme dans FL).
    var partPattern: [Int: Int] = [:]
    private(set) var started = 0
    private(set) var stopped = 0
    private var mark = 0

    init(link: FakeOrganizerLink) { self.link = link }

    func start() throws { started += 1 }
    func stop() { stopped += 1 }
    func reset() { mark = link.log.count }

    func take() -> [Float] {
        if let track = link.track { return clips[track] ?? [] }
        guard let channel = link.solo else { return [] }
        let since = link.log[mark...]
        if since.contains(where: { $0.hasPrefix("note \(channel) ") }) { return testSounds[channel] ?? [] }
        if let only = partPattern[channel], (link.playedPattern ?? link.currentPattern) != only { return [] }
        return parts[channel] ?? []
    }
}

final class OrganizerSessionTests: XCTestCase {
    private let red = RGBColor(r: 200, g: 0, b: 0)
    private let timing = OrganizerSession.Timing(listen: 0.2, testNote: 0.1, tail: 0.1, slice: 0.05, probe: 0.1)

    /// Le son d'une famille : sa place dans l'ordre des familles, en amplitude (bien au-dessus de −50 dBFS).
    private func tone(_ family: SoundFamily) -> [Float] {
        [Float](repeating: 0.1 * Float(family.rank + 1), count: 64)
    }

    private let classify: OrganizerSession.Classify = { samples, _ in
        guard let v = samples.first, v > 0.01 else { return (.unsure, 0) }
        return (SoundFamily.order[Int((v / 0.1).rounded()) - 1], 0.9)
    }

    private func channel(_ index: Int, type: Int = 2, fx: Int = 0) -> ChannelInfo {
        ChannelInfo(index: index, type: type, mixerTrack: fx, color: red, name: "Son \(index)")
    }

    private func named(_ index: Int, _ name: String, fx: Int = 0) -> ChannelInfo {
        ChannelInfo(index: index, type: 2, mixerTrack: fx, color: red, name: name)
    }

    private func make(_ link: FakeOrganizerLink, _ audio: FakeAudio, timing: OrganizerSession.Timing? = nil,
                      sleep: @escaping (TimeInterval) -> Void = { _ in },
                      progress: @escaping (Int, Int) -> Void = { _, _ in }) -> OrganizerSession {
        OrganizerSession(link: link, audio: audio, classify: classify, nameDrum: { _, _ in .kick },
                         timing: timing ?? self.timing, sleep: sleep, progress: progress)
    }

    /// Tout le projet : sons d'après leur nom ou écoutés dans leur pattern, sons de chaque pattern, sons de chaque
    /// piste de la Playlist jouée seule (à l'endroit où elle joue avec le moins d'autres), envois du Mixer.
    func testWholeProjectIsRead() throws {
        let link = FakeOrganizerLink()
        link.channels = [named(0, "BEAM KICK", fx: 1), named(1, "Serum 2", fx: 2), named(2, "ZEBRA 808", fx: 3),
                         named(3, "ALTER OPEN HAT", fx: 1)]
        link.patternList = [PatternInfo(index: 0, color: red, name: "Pattern 1"),
                            PatternInfo(index: 1, color: red, name: "kick")]
        link.patternSounds = [1: [0, 3], 2: [1]]
        link.mixer = (0...6).map { MixerTrackInfo(index: $0, color: red, name: $0 == 0 ? "Master" : "Insert \($0)") }
        link.routes = [1: [4], 3: [4]]
        link.bars = 4
        link.songAt = { at in at < 0.5 ? ([0, 1], [0, 1, 3]) : ([1, 2], [1, 2]) }
        link.trackChannels = [0: [0, 3], 1: [1], 2: [2]]
        link.playlist = (0..<5).map { PlaylistTrackInfo(index: $0, selected: false, color: red, name: "Track \($0 + 1)") }
        let audio = FakeAudio(link: link)
        audio.parts = [1: tone(.melody)]
        audio.partPattern = [1: 2]
        var steps: [[Int]] = []
        let session = make(link, audio, progress: { steps.append([$0, $1]) })
        let result = try session.run().get()

        XCTAssertEqual(result.items.map(\.family), [.drums, .melody, .bass, .drums])
        XCTAssertEqual(result.items.map(\.kind), [.kick, nil, .bass808, .openHat])
        XCTAssertEqual(result.items.map(\.byName), [true, false, true, true])
        XCTAssertEqual(result.patternSounds, [0: [0, 3], 1: [1]], "index 0 = pattern 1")
        XCTAssertEqual(result.trackSounds, [0: [0, 3], 1: [1], 2: [2]])
        XCTAssertEqual(result.playlist.count, 3, "lue jusqu'à la dernière piste qui joue")
        XCTAssertEqual(result.routes, [1: [4], 2: [], 3: [4], 4: []], "la piste de groupe est lue aussi")
        XCTAssertEqual(link.log, ["patterns", "list", "mixer", "all 1", "all 2", "solo 1 p2", "song 0", "song 500",
                                  "playlist", "track 0", "track 1", "track 2", "seek 500",
                                  "routes 1", "routes 2", "routes 3", "routes 4", "restore"])
        XCTAssertEqual(steps.last.map { $0[0] == $0[1] }, true, "fini à 100 %")
        XCTAssertEqual([audio.started, audio.stopped], [1, 1])
        let diag = session.diagnostics
        XCTAssertEqual([diag.byName, diag.listened, diag.scanned, diag.withSounds, diag.tracks, diag.tracksSolo],
                       [3, 1, 2, 2, 3, 3])
        XCTAssertFalse(diag.text.contains("KICK"), "jamais un nom dans le diagnostic")
    }

    /// Un ancien script (v11 ou avant) : rien n'est touché, FL doit être redémarré.
    func testOldScriptAsksForARestart() {
        let link = FakeOrganizerLink()
        link.v12 = false
        link.channels = [channel(0)]
        let audio = FakeAudio(link: link)
        XCTAssertEqual(make(link, audio).run(), .failure(.outdatedScript))
        XCTAssertEqual(link.log, [])
        XCTAssertEqual(audio.started, 0)
    }

    /// Capture muette : les sons nommés restent classés, les autres « À vérifier » ; tout muet et rien de nommé :
    /// `noSound`.
    func testNamesSurviveASilentCapture() throws {
        let link = FakeOrganizerLink()
        link.song = false
        link.channels = [named(0, "BEAM KICK"), named(1, "Serum 2")]
        let audio = FakeAudio(link: link)
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.family), [.drums, .unsure])
        link.channels = [named(0, "Serum 2")]
        XCTAssertEqual(make(link, audio).run(), .failure(.noSound))
    }

    /// Plus rapide : un son entendu tout de suite n'est écouté que `afterSound` de plus ; un canal muet passe aux notes
    /// d'essai au bout de `silentGiveUp`.
    func testListeningStopsOnceTheSoundIsHeard() throws {
        let link = FakeOrganizerLink()
        link.song = false
        link.channels = [channel(0), channel(1)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.bass)]
        audio.testSounds = [1: tone(.melody)]
        let fast = OrganizerSession.Timing(listen: 3, testNote: 0.1, tail: 0.1, slice: 0.1, probe: 0.1,
                                           afterSound: 0.5, silentGiveUp: 1)
        var slept = 0.0
        let result = try make(link, audio, timing: fast, sleep: { slept += $0 }).run().get()
        XCTAssertEqual(result.items.map(\.family), [.bass, .melody])
        XCTAssertEqual(result.items.map(\.testNotes), [false, true])
        // Canal 0 : entendu à 0,1 s, puis 0,5 s ; canal 1 : muet 1 s, puis 2 notes de 0,1 s et 0,1 s de queue.
        XCTAssertEqual(slept, 0.6 + 1 + 0.3, accuracy: 1e-6)
    }

    func testSkipsLayerAndAutomation() throws {
        let link = FakeOrganizerLink()
        link.song = false
        link.channels = [channel(0, type: 0), channel(1, type: ChannelInfo.layerType),
                         channel(2, type: ChannelInfo.automationType), channel(3, type: 4)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums), 3: tone(.vocals)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.index), [0, 3])
        XCTAssertEqual(result.items.map(\.family), [.drums, .vocals])
        XCTAssertEqual(result.channels.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(link.log, ["patterns", "list", "mixer", "solo 0", "solo 3", "restore"])
    }

    func testSilentChannelUsesTestNotes() throws {
        let link = FakeOrganizerLink()
        link.song = false
        link.channels = [channel(0), channel(1), channel(2)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.bass)]
        audio.testSounds = [1: tone(.drums)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.family), [.bass, .drums, .unsure])
        XCTAssertEqual(result.items.map(\.testNotes), [false, true, true])
        XCTAssertEqual(result.items[1].confidence, 0.9 * OrganizerSession.testNotesFactor, accuracy: 1e-9)
        XCTAssertEqual(Array(link.log.dropFirst(3)), ["solo 0",
                                                      "solo 1", "note 1 48 100", "note 1 48 0", "note 1 60 100", "note 1 60 0",
                                                      "solo 2", "note 2 48 100", "note 2 48 0", "note 2 60 100", "note 2 60 0",
                                                      "restore"])
        XCTAssertLessThan(OrganizerSession.peakDB([]), FamilyFusion.silenceDB)
        XCTAssertLessThan(OrganizerSession.peakDB([0.001, -0.002]), FamilyFusion.silenceDB)
        XCTAssertEqual(OrganizerSession.peakDB([0.1, -0.5]), 20 * log10(0.5), accuracy: 1e-6)
    }

    func testCancelAlwaysRestores() {
        // Échap pendant l'écoute du 2e canal.
        let link = FakeOrganizerLink()
        link.song = false
        link.channels = [channel(0), channel(1), channel(2)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums), 1: tone(.bass), 2: tone(.fx)]
        var session: OrganizerSession?
        session = make(link, audio, sleep: { _ in if link.log.last == "solo 1" { session?.cancel() } })
        XCTAssertEqual(session!.run(), .failure(.cancelled))
        XCTAssertEqual(link.log, ["patterns", "list", "mixer", "solo 0", "solo 1", "restore"])
        XCTAssertEqual(audio.stopped, 1)
        session = nil

        // Échap pendant une note d'essai : la note est coupée, puis FL remis.
        let quiet = FakeOrganizerLink()
        quiet.channels = [channel(0)]
        let silentAudio = FakeAudio(link: quiet)
        var second: OrganizerSession?
        second = make(quiet, silentAudio, sleep: { _ in if quiet.log.last == "note 0 48 100" { second?.cancel() } })
        XCTAssertEqual(second!.run(), .failure(.cancelled))
        XCTAssertEqual(quiet.log, ["patterns", "list", "mixer", "solo 0", "note 0 48 100", "note 0 48 0", "restore"])
        XCTAssertEqual(silentAudio.stopped, 1)
        second = nil
        XCTAssertEqual(OrganizerError.cancelled.message, "Organiser arrêté : FL est remis comme avant.")
    }

    func testPlayingStopsBeforeListening() {
        let link = FakeOrganizerLink()
        link.channels = [channel(0), channel(1)]
        link.patternList = [PatternInfo(index: 0, color: red, name: "Pattern 1")]
        link.playing = true
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums)]
        XCTAssertEqual(make(link, audio).run(), .failure(.refused(4)))
        XCTAssertEqual(link.log, ["patterns", "list", "mixer", "restore"])
        XCTAssertTrue(link.playing, "la lecture de l'utilisateur n'est pas coupée")
        XCTAssertEqual(audio.stopped, 1)
        XCTAssertTrue(OrganizerError.refused(4).message.contains("Stop"))
    }

    /// Une piste où FL ne dit aucun son (clip audio) est écoutée ; FL muet et rien entendu : les sons qui jouent en
    /// même temps qu'elle.
    func testClipTrackIsHeard() throws {
        let link = FakeOrganizerLink()
        link.channels = [named(0, "BEAM KICK")]
        link.bars = 2
        link.songAt = { _ in ([0, 1], [0]) }
        link.playlist = (0..<2).map { PlaylistTrackInfo(index: $0, selected: false, color: red, name: "Track \($0 + 1)") }
        let audio = FakeAudio(link: link)
        audio.clips = [0: tone(.vocals)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.trackItems.map(\.index), [0])
        XCTAssertEqual(result.trackItems.map(\.family), [.vocals])
        XCTAssertEqual(result.trackSounds, [1: [0]], "repli : ce qui joue avec elle")
    }

    func testPureHelpers() {
        XCTAssertEqual(OrganizerSession.homes([2: [5, 1], 0: [1]]), [1: 1, 5: 3], "le premier pattern où le son joue")
        XCTAssertEqual(OrganizerSession.quietestSample([0, 1, 2], samples: [[0, 1, 2], [0], [0, 3]]), 1)
        XCTAssertEqual(OrganizerSession.quietestSample([0, 2], samples: [[0, 1], [5], [0, 3]]), 0, "égalité : le premier")
        XCTAssertNil(OrganizerSession.quietestSample([], samples: [[0]]))
        // Deux pistes qui jouent toujours ensemble : le son va sur les deux.
        let samples: [(tracks: Set<Int>, channels: Set<Int>)] = [([0, 1], [5]), ([0, 1], [5]), ([2], [6])]
        let sounds = OrganizerSession.trackSounds(samples)
        XCTAssertEqual(sounds[0]?.keys.sorted(), [5])
        XCTAssertEqual(sounds[1]?.keys.sorted(), [5])
        XCTAssertEqual(sounds[2], [6: 1.0])
        XCTAssertEqual(OrganizerSession.songPositions(bars: 16).count, 8)
        XCTAssertEqual(OrganizerSession.songPositions(bars: 0).count, 16)
        XCTAssertEqual(OrganizerSession.songPositions(bars: 500).count, OrganizerSession.maxPositions)
    }

    /// Rangé d'après le mot de son nom qui dit ce qu'il est (vidéo de l'utilisateur : « BEAM KICK » doit être un Kick).
    func testSoundNames() {
        XCTAssertEqual(SoundNames.kind(of: "BEAM KICK"), .kick)
        XCTAssertEqual(SoundNames.kind(of: "ZEBRA 808"), .bass808)
        XCTAssertEqual(SoundNames.kind(of: "ALTER OPEN HAT"), .openHat)
        XCTAssertEqual(SoundNames.kind(of: "@MEH CLAP"), .clap)
        XCTAssertEqual(SoundNames.kind(of: "ANOTHER BASIC HI HAT"), .hiHat)
        XCTAssertEqual(SoundNames.kind(of: "ALSO GOOD..OLD CRASH"), .crash)
        XCTAssertEqual(SoundNames.kind(of: "Trap OH 01"), .openHat)
        XCTAssertEqual(SoundNames.kind(of: "808 Kick"), .kick, "un mot de drums précis l'emporte")
        XCTAssertEqual(SoundNames.kind(of: "Kick01"), .kick)
        XCTAssertEqual(SoundNames.kind(of: "Sub 808"), .bass808, "le premier dans l'ordre de la famille")
        XCTAssertEqual(SoundNames.kind(of: "Synth Bass"), .bass)
        XCTAssertEqual(SoundNames.kind(of: "Vocal Chop"), .vocal)
        XCTAssertEqual(SoundNames.kind(of: "Adlib Vox"), .adlib, "un mot précis passe avant le mot général")
        XCTAssertEqual(SoundNames.kind(of: "Riser FX"), .riser)
        XCTAssertEqual(SoundNames.kind(of: "Synth Lead"), .lead)
        XCTAssertEqual(SoundNames.kind(of: "Drum Loop"), .drums)
        XCTAssertEqual(SoundNames.kind(of: "Mélodie"), .melody)
        XCTAssertEqual(SoundNames.kind(of: "hi hat"), .hiHat, "nom d'un pattern")
        XCTAssertEqual(SoundNames.family(of: "BEAM KICK"), .drums)
        XCTAssertEqual(SoundNames.family(of: "ZEBRA 808"), .bass)
        XCTAssertEqual(SoundNames.family(of: "Piano"), .melody)
        XCTAssertNil(SoundNames.kind(of: "Serum 2"))
        XCTAssertNil(SoundNames.kind(of: "1SHOT - ARPME"))
        XCTAssertNil(SoundNames.kind(of: "Subtle"), "mots entiers seulement")
        XCTAssertNil(SoundNames.kind(of: "Open Sampler"))
        XCTAssertNil(SoundNames.kind(of: "Pattern 3"))
        // Chaque sorte a un nom et sa famille la propose ; un seul mot général par famille, au nom de la famille.
        XCTAssertEqual(SoundKind.kick.name, "Kick")
        XCTAssertEqual(SoundKind.bass808.name, "808")
        XCTAssertEqual(SoundKind.openHat.name, "Open Hat")
        for family in SoundFamily.order where family != .unsure {
            let general = family.kinds.filter(\.isGeneral)
            XCTAssertEqual(general.count, 1, "\(family)")
            XCTAssertEqual(general.first?.name, family.trackName, "\(family)")
        }
        XCTAssertEqual(SoundFamily.unsure.kinds, [])
        XCTAssertEqual(Set(SoundKind.allCases.map(\.name)).count, SoundKind.allCases.count)
        XCTAssertEqual(DrumKind.allCases.map(\.sound.family), Array(repeating: .drums, count: DrumKind.allCases.count))
    }
}
