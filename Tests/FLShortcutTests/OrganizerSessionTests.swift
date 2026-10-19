import XCTest
@testable import FLShortcut

/// FL simulé pour l'Organiser : journal des opérations, mémo de l'écoute comme le script.
final class FakeOrganizerLink: OrganizerLink {
    var window: FLWindow = .channelRack
    var channels: [ChannelInfo] = []
    var mixer: [MixerTrackInfo] = []
    var playlist: [PlaylistTrackInfo] = []
    /// Longueur de la chanson rendue par l'écoute d'une piste (opération 11).
    var bars = 32
    var playing = false
    private(set) var log: [String] = []
    private(set) var solo: Int?
    /// Piste de la Playlist écoutée seule, et la position de la chanson (0…1).
    private(set) var track: Int?
    private(set) var position = 0.0
    private var memo = false

    func page() throws -> FLWindow { window }

    func listPlaylist(limit: Int) throws -> [PlaylistTrackInfo] {
        log.append("playlist")
        return Array(playlist.prefix(limit))
    }

    func setNames(_ kind: ItemKind, _ names: [(index: Int, name: String)]) throws {
        log.append("names \(names.count)")
        for (index, name) in names where playlist.indices.contains(index) {
            let t = playlist[index]
            playlist[index] = PlaylistTrackInfo(index: index, selected: t.selected, color: t.color, name: name)
        }
    }

    func playTrack(_ index: Int) throws -> Int {
        if !memo && playing { throw OrganizerError.refused(4) }
        memo = true
        playing = true
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

    func listChannels() throws -> [ChannelInfo] {
        log.append("list")
        return channels
    }

    func listMixer() throws -> [MixerTrackInfo] {
        log.append("mixer")
        return mixer
    }

    private(set) var selected: Int?
    /// Index des couleurs ignorées par ce faux FL (pour tester la vérification).
    var ignoredColors: Set<Int> = []

    func setColors(_ kind: ItemKind, _ colors: [(index: Int, color: FLShortcut.RGBColor)]) throws {
        log.append("colors \(colors.count)")
        for (index, color) in colors where !ignoredColors.contains(index) {
            switch kind {
            case .channels:
                if channels.indices.contains(index) { channels[index] = Self.copy(channels[index], index: index, color: color) }
            case .mixer:
                if let at = mixer.firstIndex(where: { $0.index == index }) {
                    mixer[at] = MixerTrackInfo(index: index, color: color, name: mixer[at].name)
                }
            case .playlist:
                if playlist.indices.contains(index) {
                    let t = playlist[index]
                    playlist[index] = PlaylistTrackInfo(index: index, selected: t.selected, color: color, name: t.name)
                }
            }
        }
    }

    func selectOne(_ kind: ItemKind, _ index: Int) throws {
        log.append("select \(index)")
        selected = index
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

    static func copy(_ c: ChannelInfo, index: Int, color: FLShortcut.RGBColor) -> ChannelInfo {
        ChannelInfo(index: index, type: c.type, mixerTrack: c.mixerTrack, color: color, name: c.name)
    }

    func playSolo(_ channel: Int) throws {
        if !memo && playing { throw OrganizerError.refused(4) }
        memo = true
        playing = true
        solo = channel
        log.append("solo \(channel)")
    }

    /// Comme le script : sans écoute en cours (pas de mémo), rien ne change.
    func stopRestore() {
        log.append("restore")
        if memo { playing = false }
        memo = false
        solo = nil
        track = nil
    }

    func audition(_ channel: Int, note: UInt8, velocity: UInt8) throws {
        log.append("note \(channel) \(note) \(velocity)")
    }
}

/// Capture simulée : le son de la partie du canal en solo, ou celui de ses notes d'essai ; Playlist : le son de la
/// piste écoutée seule, à partir de la position où ses clips commencent.
final class FakeAudio: AudioSource {
    let rate = 48_000.0
    let link: FakeOrganizerLink
    var parts: [Int: [Float]] = [:]
    var testSounds: [Int: [Float]] = [:]
    var tracks: [Int: (from: Double, samples: [Float])] = [:]
    private(set) var started = 0
    private(set) var stopped = 0
    private var mark = 0

    init(link: FakeOrganizerLink) { self.link = link }

    func start() throws { started += 1 }
    func stop() { stopped += 1 }
    func reset() { mark = link.log.count }

    func take() -> [Float] {
        if let track = link.track {
            guard let sound = tracks[track], link.position >= sound.from else { return [] }
            return sound.samples
        }
        guard let channel = link.solo else { return [] }
        let since = link.log[mark...]
        if since.contains(where: { $0.hasPrefix("note \(channel) ") }) { return testSounds[channel] ?? [] }
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

    private func make(_ link: FakeOrganizerLink, _ audio: FakeAudio,
                      sleep: @escaping (TimeInterval) -> Void = { _ in },
                      progress: @escaping (Int, Int) -> Void = { _, _ in }) -> OrganizerSession {
        OrganizerSession(link: link, audio: audio, classify: classify, nameDrum: { _, _ in .kick }, timing: timing,
                         sleep: sleep, progress: progress)
    }

    func testChannelRackFlow() throws {
        let link = FakeOrganizerLink()
        link.channels = [channel(0), channel(1), channel(2)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums), 1: tone(.bass), 2: tone(.melody)]
        var steps: [[Int]] = []
        var slept = 0.0
        let result = try make(link, audio, sleep: { slept += $0 }, progress: { steps.append([$0, $1]) }).run().get()
        XCTAssertEqual(result.page, .channelRack)
        XCTAssertEqual(result.items.map(\.family), [.drums, .bass, .melody])
        XCTAssertEqual(result.items.map(\.testNotes), [false, false, false])
        XCTAssertEqual(result.items[1].confidence, 0.9, accuracy: 1e-9)
        XCTAssertEqual(result.items[2].name, "Son 2")
        XCTAssertEqual(result.channels.count, 3)
        XCTAssertEqual(result.mixer, [])
        XCTAssertEqual(result.mixerFamilies, [:])
        XCTAssertEqual(link.log, ["list", "solo 0", "solo 1", "solo 2", "restore"])
        XCTAssertEqual(steps, [[0, 3], [1, 3], [2, 3], [3, 3]])
        XCTAssertEqual(audio.started, 1)
        XCTAssertEqual(audio.stopped, 1)
        XCTAssertEqual(slept, 0.6, accuracy: 1e-9, "3 canaux × 0,2 s d'écoute")
    }

    /// Plus rapide : un son entendu tout de suite n'est écouté que `afterSound` de plus ; un canal muet passe aux notes
    /// d'essai au bout de `silentGiveUp` (avant : `listen` entier dans les deux cas).
    func testListeningStopsOnceTheSoundIsHeard() throws {
        let link = FakeOrganizerLink()
        link.channels = [channel(0), channel(1)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.bass)]
        audio.testSounds = [1: tone(.melody)]
        let fast = OrganizerSession.Timing(listen: 3, testNote: 0.1, tail: 0.1, slice: 0.1, probe: 0.1,
                                           afterSound: 0.5, silentGiveUp: 1)
        var slept = 0.0
        let result = try OrganizerSession(link: link, audio: audio, classify: classify, nameDrum: { _, _ in .kick },
                                          timing: fast, sleep: { slept += $0 }, progress: { _, _ in }).run().get()
        XCTAssertEqual(result.items.map(\.family), [.bass, .melody])
        XCTAssertEqual(result.items.map(\.testNotes), [false, true])
        // Canal 0 : entendu à 0,1 s, puis 0,5 s ; canal 1 : muet 1 s, puis 2 notes de 0,1 s et 0,1 s de queue.
        XCTAssertEqual(slept, 0.6 + 1 + 0.3, accuracy: 1e-6)
    }

    func testSkipsLayerAndAutomation() throws {
        let link = FakeOrganizerLink()
        link.channels = [channel(0, type: 0), channel(1, type: ChannelInfo.layerType),
                         channel(2, type: ChannelInfo.automationType), channel(3, type: 4)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums), 3: tone(.vocals)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.index), [0, 3])
        XCTAssertEqual(result.items.map(\.family), [.drums, .vocals])
        XCTAssertEqual(result.channels.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(link.log, ["list", "solo 0", "solo 3", "restore"])
    }

    func testSilentChannelUsesTestNotes() throws {
        let link = FakeOrganizerLink()
        link.channels = [channel(0), channel(1), channel(2)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.bass)]
        audio.testSounds = [1: tone(.drums)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.family), [.bass, .drums, .unsure])
        XCTAssertEqual(result.items.map(\.testNotes), [false, true, true])
        XCTAssertEqual(result.items[1].confidence, 0.9 * OrganizerSession.testNotesFactor, accuracy: 1e-9)
        XCTAssertEqual(link.log, ["list", "solo 0",
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
        link.channels = [channel(0), channel(1), channel(2)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums), 1: tone(.bass), 2: tone(.fx)]
        var session: OrganizerSession?
        session = make(link, audio, sleep: { _ in if link.log.last == "solo 1" { session?.cancel() } })
        XCTAssertEqual(session!.run(), .failure(.cancelled))
        XCTAssertEqual(link.log, ["list", "solo 0", "solo 1", "restore"])
        XCTAssertEqual(audio.stopped, 1)
        session = nil

        // Échap pendant une note d'essai : la note est coupée, puis FL remis.
        let quiet = FakeOrganizerLink()
        quiet.channels = [channel(0)]
        let silentAudio = FakeAudio(link: quiet)
        var second: OrganizerSession?
        second = make(quiet, silentAudio, sleep: { _ in if quiet.log.last == "note 0 48 100" { second?.cancel() } })
        XCTAssertEqual(second!.run(), .failure(.cancelled))
        XCTAssertEqual(quiet.log, ["list", "solo 0", "note 0 48 100", "note 0 48 0", "restore"])
        XCTAssertEqual(silentAudio.stopped, 1)
        second = nil
        XCTAssertEqual(OrganizerError.cancelled.message, "Organiser arrêté : FL est remis comme avant.")
    }

    func testPlayingStopsBeforeListening() {
        let link = FakeOrganizerLink()
        link.channels = [channel(0), channel(1)]
        link.playing = true
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums)]
        XCTAssertEqual(make(link, audio).run(), .failure(.refused(4)))
        XCTAssertEqual(link.log, ["list", "restore"])
        XCTAssertTrue(link.playing, "la lecture de l'utilisateur n'est pas coupée")
        XCTAssertEqual(audio.stopped, 1)
        XCTAssertTrue(OrganizerError.refused(4).message.contains("Stop"))
    }

    func testMixerMajority() throws {
        let link = FakeOrganizerLink()
        link.window = .mixer
        link.channels = [channel(0, fx: 1), channel(1, fx: 1), channel(2, fx: 1), channel(3, fx: 2),
                         channel(4, fx: 3), channel(5, fx: 0), channel(6, fx: 4), channel(7, fx: 4)]
        link.mixer = (0...5).map { MixerTrackInfo(index: $0, color: red, name: "Piste \($0)") }
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums), 1: tone(.drums), 2: tone(.bass), 3: tone(.melody),
                       5: tone(.drums), 6: tone(.bass), 7: tone(.drums)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.page, .mixer)
        XCTAssertEqual(result.mixer.count, 6)
        // 1 : 2 drums contre 1 basse ; 2 : mélodie ; 3 : seulement « À vérifier » ; 4 : égalité → Basse (l'ordre :
        // voix, mélodies, basse, drums, FX) ; Master (0) et piste 5 sans canal : pas touchés.
        XCTAssertEqual(result.mixerFamilies, [1: .drums, 2: .melody, 3: .unsure, 4: .bass])
        XCTAssertEqual(Array(link.log.prefix(2)), ["list", "mixer"])
        XCTAssertEqual(link.log.last, "restore")
    }

    func testOtherPageRefused() {
        let link = FakeOrganizerLink()
        link.window = .pianoRoll
        link.channels = [channel(0)]
        let audio = FakeAudio(link: link)
        XCTAssertEqual(make(link, audio).run(), .failure(.refused(1)))
        XCTAssertEqual(link.log, [])
        XCTAssertEqual(audio.started, 0)
    }

    // MARK: Playlist

    private func track(_ index: Int, _ name: String? = nil, selected: Bool = false) -> PlaylistTrackInfo {
        PlaylistTrackInfo(index: index, selected: selected, color: red, name: name ?? "Track \(index + 1)")
    }

    func testPlaylistFlow() throws {
        let link = FakeOrganizerLink()
        link.window = .playlist
        link.playlist = [track(0, "Lead")] + (1..<10).map { track($0) }
        let audio = FakeAudio(link: link)
        audio.tracks = [0: (from: 0, samples: tone(.melody)), 1: (from: 0.5, samples: tone(.drums)),
                        3: (from: 0, samples: tone(.bass))]
        var steps: [[Int]] = []
        let result = try make(link, audio, progress: { steps.append([$0, $1]) }).run().get()
        XCTAssertEqual(result.page, .playlist)
        XCTAssertEqual(result.playlist.count, 10)
        XCTAssertEqual(result.items.map(\.index), [0, 1, 3])
        XCTAssertEqual(result.items.map(\.family), [.melody, .drums, .bass])
        XCTAssertEqual(result.items.map(\.drum), [nil, .kick, nil], "sorte des drums seulement")
        XCTAssertEqual(result.items[0].name, "Lead")
        // Après la dernière piste renommée (0), 3 pistes muettes de suite (4, 5, 6) arrêtent l'écoute.
        XCTAssertEqual(link.log.filter { $0.hasPrefix("track") }, (0...6).map { "track \($0)" })
        XCTAssertEqual(link.log.first, "playlist")
        XCTAssertEqual(link.log.last, "restore")
        // Piste 1 : 32 mesures → 8 positions ; son trouvé à la 5e (moitié de la chanson).
        let afterOne = link.log.drop(while: { $0 != "track 1" }).dropFirst().prefix(while: { $0.hasPrefix("seek") })
        XCTAssertEqual(Array(afterOne), ["seek 125", "seek 250", "seek 375", "seek 500"])
        XCTAssertEqual(steps.first, [0, 10])
        XCTAssertEqual(steps.last, [10, 10])
        XCTAssertEqual(audio.started, 1)
        XCTAssertEqual(audio.stopped, 1)
    }

    func testPlaylistSelectedTracksOnly() throws {
        let link = FakeOrganizerLink()
        link.window = .playlist
        link.playlist = (0..<8).map { track($0, selected: $0 == 2 || $0 == 5) }
        let audio = FakeAudio(link: link)
        audio.tracks = [0: (from: 0, samples: tone(.vocals)), 5: (from: 0, samples: tone(.fx))]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(link.log.filter { $0.hasPrefix("track") }, ["track 2", "track 5"])
        XCTAssertEqual(result.items.map(\.index), [5])
        XCTAssertEqual(result.items.map(\.family), [.fx])
    }

    func testPlaylistPlayingRefused() {
        let link = FakeOrganizerLink()
        link.window = .playlist
        link.playlist = [track(0)]
        link.playing = true
        let audio = FakeAudio(link: link)
        XCTAssertEqual(make(link, audio).run(), .failure(.refused(4)))
        XCTAssertEqual(link.log, ["playlist", "restore"])
        XCTAssertTrue(link.playing, "la lecture de l'utilisateur n'est pas coupée")
        XCTAssertEqual(audio.stopped, 1)
    }

    func testPlaylistTargetsAndProbes() {
        let unnamed = (0..<500).map { track($0) }
        XCTAssertEqual(OrganizerSession.playlistTargets(unnamed).count, OrganizerSession.extraTracks)
        var named = unnamed
        named[40] = track(40, "Voix")
        XCTAssertEqual(OrganizerSession.lastNamed(named), 40)
        XCTAssertEqual(OrganizerSession.playlistTargets(named).count, OrganizerSession.maxTracks)
        var picked = unnamed
        picked[7] = track(7, selected: true)
        XCTAssertEqual(OrganizerSession.playlistTargets(picked).map(\.index), [7])
        XCTAssertEqual(OrganizerSession.playlistTargets([]), [])

        XCTAssertEqual(OrganizerSession.probePositions(bars: 0).count, 16)
        XCTAssertEqual(OrganizerSession.probePositions(bars: 1), [0])
        XCTAssertEqual(OrganizerSession.probePositions(bars: 32), [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875])
        XCTAssertEqual(OrganizerSession.probePositions(bars: 400).count, 24)

        XCTAssertTrue(track(2, "Track 3").hasDefaultName)
        XCTAssertTrue(track(2, " ").hasDefaultName)
        XCTAssertFalse(track(5, "Track 3").hasDefaultName, "« Track 3 » donné à la piste 6 : un vrai nom")
        XCTAssertFalse(track(0, "Kick").hasDefaultName)
    }

    func testEmptyRackListensToNothing() throws {
        let link = FakeOrganizerLink()
        let audio = FakeAudio(link: link)
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items, [])
        XCTAssertEqual(link.log, ["list"])
        XCTAssertEqual(audio.started, 0)
    }
}
