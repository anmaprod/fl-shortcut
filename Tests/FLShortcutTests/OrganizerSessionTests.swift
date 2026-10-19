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
    /// Script v11 simulé (patterns, ce qui joue) ; faux : un ancien script, qui refuse ces opérations.
    var v11 = false
    var patternCount = 1
    var currentPattern = 1
    /// Sons qui jouent dans chaque pattern, et ce qui joue à chaque position de la chanson (pistes, sons).
    var patternSounds: [Int: Set<Int>] = [:]
    var songAt: (Double) -> (tracks: Set<Int>, channels: Set<Int>) = { _ in ([], []) }
    /// Pattern joué par la dernière opération 6 (nil : celui qui est ouvert), position de la chanson jouée en entier.
    private(set) var playedPattern: Int?
    private(set) var songPosition: Double?

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

    func playSolo(_ channel: Int, pattern: Int?) throws {
        if !memo && playing { throw OrganizerError.refused(4) }
        if pattern != nil && !v11 { throw OrganizerError.outdatedScript }
        memo = true
        playing = true
        playedPattern = pattern
        songPosition = nil
        if channel == OrganizerPayload.allChannels {
            solo = nil
            log.append("all \(pattern ?? 0)")
        } else {
            solo = channel
            log.append(pattern.map { "solo \(channel) p\($0)" } ?? "solo \(channel)")
        }
    }

    func patterns() throws -> (count: Int, current: Int) {
        guard v11 else { throw OrganizerError.refused(6) }
        return (patternCount, currentPattern)
    }

    func activeChannels() throws -> Set<Int> {
        guard v11 else { throw OrganizerError.refused(6) }
        if let at = songPosition { return songAt(at).channels }
        if solo == nil, let p = playedPattern { return patternSounds[p] ?? [] }
        return []
    }

    func activeTracks() throws -> Set<Int> {
        guard v11 else { throw OrganizerError.refused(6) }
        return songPosition.map { songAt($0).tracks } ?? []
    }

    func playSong(at fraction: Double) throws -> Int {
        guard v11 else { throw OrganizerError.refused(6) }
        if !memo && playing { throw OrganizerError.refused(4) }
        memo = true
        playing = true
        solo = nil
        songPosition = fraction
        log.append("song \(Int((fraction * 1000).rounded()))")
        return bars
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

/// Capture simulée : le son de la partie du canal en solo, ou celui de ses notes d'essai ; Playlist : le son de la
/// piste écoutée seule, à partir de la position où ses clips commencent.
final class FakeAudio: AudioSource {
    let rate = 48_000.0
    let link: FakeOrganizerLink
    var parts: [Int: [Float]] = [:]
    var testSounds: [Int: [Float]] = [:]
    var tracks: [Int: (from: Double, samples: [Float])] = [:]
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
        if let track = link.track {
            guard let sound = tracks[track], link.position >= sound.from else { return [] }
            return sound.samples
        }
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

    // MARK: Noms, patterns, ce qui joue (script v11)

    private func named(_ index: Int, _ name: String, fx: Int = 0) -> ChannelInfo {
        ChannelInfo(index: index, type: 2, mixerTrack: fx, color: red, name: name)
    }

    /// Un nom qui dit la famille suffit (rien n'est écouté pour lui) ; les autres sont écoutés.
    func testNamesClassifyWithoutListening() throws {
        let link = FakeOrganizerLink()
        link.channels = [named(0, "BEAM KICK"), named(1, "ZEBRA 808"), named(2, "Serum 2")]
        let audio = FakeAudio(link: link)
        audio.parts = [2: tone(.melody)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.family), [.drums, .bass, .melody])
        XCTAssertEqual(result.items.map(\.byName), [true, true, false])
        XCTAssertEqual(result.items[0].drum, .kick)
        XCTAssertEqual(link.log, ["list", "solo 2", "restore"], "seul « Serum 2 » est écouté")
    }

    /// Capture muette : les sons nommés restent classés, les autres « À vérifier » ; tout muet et rien de nommé :
    /// `noSound`.
    func testNamesSurviveASilentCapture() throws {
        let link = FakeOrganizerLink()
        link.channels = [named(0, "BEAM KICK"), named(1, "Serum 2")]
        let audio = FakeAudio(link: link)
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.family), [.drums, .unsure])
        link.channels = [named(0, "Serum 2")]
        XCTAssertEqual(make(link, audio).run(), .failure(.noSound))
    }

    /// Un son muet dans le pattern ouvert est écouté dans le pattern où il joue (repéré par FL, sans écoute).
    func testSoundsListenedInTheirPattern() throws {
        let link = FakeOrganizerLink()
        link.v11 = true
        link.patternCount = 3
        link.patternSounds = [1: [0], 2: [1]]
        link.channels = [channel(0), channel(1)]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums), 1: tone(.bass)]
        audio.partPattern = [1: 2]
        let session = make(link, audio)
        let result = try session.run().get()
        XCTAssertEqual(result.items.map(\.family), [.drums, .bass])
        XCTAssertEqual(result.items.map(\.testNotes), [false, false], "plus de notes d'essai")
        XCTAssertEqual(link.log, ["list", "all 1", "all 2", "solo 0 p1", "solo 1 p2", "restore"])
        let diag = session.diagnostics
        XCTAssertEqual([diag.patterns, diag.scanned, diag.homes, diag.listened, diag.heard], [3, 2, 2, 2, 2])
        XCTAssertFalse(diag.text.contains("Son"), "jamais un nom dans le diagnostic")
    }

    /// Playlist : la chanson parcourue, FL dit quelles pistes et quels sons jouent ensemble ; chaque piste prend la
    /// famille de ses sons (leur nom, sinon leur écoute).
    func testPlaylistFromWhatPlays() throws {
        let link = FakeOrganizerLink()
        link.v11 = true
        link.window = .playlist
        link.bars = 16
        link.playlist = (0..<5).map { track($0) }
        link.channels = [named(0, "BEAM KICK"), named(1, "ZEBRA 808"), named(2, "Serum 2"), named(3, "ALTER OPEN HAT")]
        link.songAt = { at in
            if at < 0.25 { return ([0], [0, 3]) }
            if at < 0.5 { return ([0, 1], [0, 1, 3]) }
            return ([0, 1, 2], [0, 1, 2, 3])
        }
        let audio = FakeAudio(link: link)
        audio.parts = [2: tone(.melody)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.page, .playlist)
        XCTAssertEqual(result.items.map(\.index), [0, 1, 2])
        XCTAssertEqual(result.items.map(\.family), [.drums, .bass, .melody])
        XCTAssertEqual(result.items[0].drum, .kit, "kick et hi-hat : « Drums »")
        XCTAssertEqual(result.items.map(\.byName), [true, true, false])
        XCTAssertEqual(link.log.filter { $0.hasPrefix("song") }.count, 8, "16 mesures : toutes les 2")
        XCTAssertEqual(link.log.filter { $0.hasPrefix("solo") }, ["solo 2"])
        XCTAssertEqual(link.log.last, "restore")
        XCTAssertEqual(audio.started, 1)
    }

    func testTrackSoundsAndFamily() {
        // Deux pistes qui jouent toujours ensemble : le son va sur les deux.
        let samples: [(tracks: Set<Int>, channels: Set<Int>)] = [([0, 1], [5]), ([0, 1], [5]), ([2], [6])]
        let sounds = OrganizerSession.trackSounds(samples)
        XCTAssertEqual(sounds[0]?.keys.sorted(), [5])
        XCTAssertEqual(sounds[1]?.keys.sorted(), [5])
        XCTAssertEqual(sounds[2], [6: 1.0])
        let items: [Int: OrganizerItem] = [
            5: OrganizerItem(index: 5, name: "", family: .unsure, confidence: 0.2, testNotes: true, mixerTrack: 0,
                             color: red),
            6: OrganizerItem(index: 6, name: "", family: .drums, confidence: 0.9, testNotes: false, mixerTrack: 0,
                             color: red, drum: .snare),
        ]
        XCTAssertEqual(OrganizerSession.trackFamily([5: 1], items: items)?.family, .unsure, "rien d'autre")
        XCTAssertEqual(OrganizerSession.trackFamily([5: 1, 6: 0.5], items: items)?.family, .drums)
        XCTAssertEqual(OrganizerSession.trackFamily([6: 1], items: items)?.drum, .snare)
        XCTAssertNil(OrganizerSession.trackFamily([9: 1], items: items))
        XCTAssertEqual(OrganizerSession.songPositions(bars: 16).count, 8)
        XCTAssertEqual(OrganizerSession.songPositions(bars: 0).count, 16)
        XCTAssertEqual(OrganizerSession.songPositions(bars: 500).count, OrganizerSession.maxPositions)
    }

    func testSoundNames() {
        XCTAssertEqual(SoundNames.family(of: "BEAM KICK"), .drums)
        XCTAssertEqual(SoundNames.drum(of: "BEAM KICK"), .kick)
        XCTAssertEqual(SoundNames.family(of: "ZEBRA 808"), .bass)
        XCTAssertEqual(SoundNames.drum(of: "ANOTHER BASIC HI HAT"), .hiHat)
        XCTAssertEqual(SoundNames.drum(of: "@MEH CLAP"), .clap)
        XCTAssertEqual(SoundNames.drum(of: "ALSO GOOD..OLD CRASH"), .cymbal)
        XCTAssertEqual(SoundNames.family(of: "808 Kick"), .drums, "un mot de drums précis l'emporte")
        XCTAssertEqual(SoundNames.family(of: "Kick01"), .drums)
        XCTAssertEqual(SoundNames.family(of: "Synth Bass"), .bass)
        XCTAssertEqual(SoundNames.family(of: "Vocal Chop"), .vocals)
        XCTAssertEqual(SoundNames.family(of: "Riser FX"), .fx)
        XCTAssertEqual(SoundNames.family(of: "Piano"), .melody)
        XCTAssertEqual(SoundNames.family(of: "Mélodie"), .melody)
        XCTAssertNil(SoundNames.family(of: "Serum 2"))
        XCTAssertNil(SoundNames.family(of: "1SHOT - ARPME"))
        XCTAssertNil(SoundNames.family(of: "Subtle"), "mots entiers seulement")
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

    /// Page choisie avec les boutons de l'Organiser : organisée telle quelle, même si FL ne la dit pas devant (vidéo
    /// de l'utilisateur : Mixer et Playlist bien affichés, FL répondait « aucune page »).
    func testChosenPageIsUsedWhateverFLSays() throws {
        let link = FakeOrganizerLink()
        link.window = .unknown
        link.channels = [channel(0, fx: 1)]
        link.mixer = (0...1).map { MixerTrackInfo(index: $0, color: red, name: "Piste \($0)") }
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums)]
        let mixer = try make(link, audio).run(on: .mixer).get()
        XCTAssertEqual(mixer.page, .mixer)
        XCTAssertEqual(mixer.mixerFamilies, [1: .drums])
        link.playlist = [track(0, "Lead")]
        audio.tracks = [0: (from: 0, samples: tone(.melody))]
        let playlist = try make(link, audio).run(on: .playlist).get()
        XCTAssertEqual(playlist.page, .playlist)
        XCTAssertEqual(playlist.items.map(\.family), [.melody])
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
        // Les 12 premières pistes sont toujours écoutées (des pistes vides peuvent précéder des clips) : ici toutes.
        XCTAssertEqual(link.log.filter { $0.hasPrefix("track") }, (0...9).map { "track \($0)" })
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

    /// Pistes vides au début, des clips plus loin (projet de l'utilisateur) : rien n'est manqué dans les 12
    /// premières ; au-delà, 3 pistes muettes de suite arrêtent l'écoute.
    func testPlaylistEmptyTracksBeforeClips() throws {
        let link = FakeOrganizerLink()
        link.window = .playlist
        link.playlist = (0..<20).map { track($0) }
        let audio = FakeAudio(link: link)
        audio.tracks = [0: (from: 0, samples: tone(.melody)), 7: (from: 0, samples: tone(.drums))]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.index), [0, 7])
        XCTAssertEqual(link.log.filter { $0.hasPrefix("track") }, (0...14).map { "track \($0)" })
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
