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
    /// Script v14 simulé ; faux : un ancien script, qui refuse ses nouvelles opérations (FL à redémarrer).
    var v14 = true
    /// Longueur de chaque pattern en temps (16 si absente) et tempo du projet.
    var lengths: [Int] = []
    var tempo = 120.0
    /// Canaux sélectionnés dans FL : par « Select unused channels », ou par le script (opération 23).
    var unusedSelection: Set<Int> = []
    /// Faux : FL trop ancien pour jouer toute la chanson (relevé de la Playlist impossible).
    var song = true
    /// Sons qui jouent dans chaque pattern (1 = le premier), pistes et sons qui jouent à chaque position de la
    /// chanson, sons qui jouent quand une piste de la Playlist joue seule (index 0 = piste 1).
    var patternSounds: [Int: Set<Int>] = [:]
    var songAt: (Double) -> (tracks: Set<Int>, channels: Set<Int>) = { _ in ([], []) }
    /// Chanson jouée en entier : chaque lecture de sa position l'avance d'autant (finie : elle repart du début).
    var songStep = 0.5
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
    private(set) var songCursor: Double?
    private(set) var selected: Int?
    private(set) var selectedTrack: Int?
    /// Index des couleurs ignorées par ce faux FL (pour tester la vérification), et genre concerné.
    var ignoredColors: Set<Int> = []
    var ignoredKind: ItemKind = .channels

    func page() throws -> FLWindow { window }

    var allChannels = false
    /// Channel rack sur un groupe : les rangs dans « All » des canaux qu'il montre ; nil : tous (« All »).
    var group: [Int]?

    func listChannels() throws -> [ChannelInfo] {
        log.append("list")
        guard let group, !allChannels else { return channels }
        return group.enumerated().map { k, i in
            let c = channels[i]
            return ChannelInfo(index: k, type: c.type, mixerTrack: c.mixerTrack, color: c.color, name: c.name)
        }
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
        log.append("patterns")
        return patternList
    }

    func routes(from track: Int) throws -> [Int] {
        log.append("routes \(track)")
        return routes[track] ?? []
    }

    func setRoutes(_ track: Int, to dests: [Int]) throws {
        log.append("send \(track) \(dests.sorted().map(String.init).joined(separator: ","))")
        routes[track] = dests.sorted()
    }

    func patternLengths() throws -> (tempo: Double, beats: [Int]) {
        guard v14 else { throw OrganizerError.outdatedScript }
        return (tempo, patternList.indices.map { $0 < lengths.count ? lengths[$0] : 16 })
    }

    func speed(_ factor: Int) throws -> (before: Double, now: Double) {
        guard memo else { throw OrganizerError.refused(5) }
        log.append("speed \(factor)")
        return (tempo, min(tempo * Double(factor), 520))
    }

    func heardChannels() throws -> Set<Int> { try activeChannels() }

    func selectedChannels() throws -> Set<Int> { unusedSelection }

    /// Page que l'utilisateur garde devant : `show` ne la change pas.
    var keptWindow: FLWindow?

    func show(_ window: FLWindow) throws {
        log.append("show \(window)")
        self.window = keptWindow ?? window
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
            func swapped(_ t: Int) -> Int { t == at ? at - 1 : t == at - 1 ? at : t }
            channels = channels.map { c in
                ChannelInfo(index: c.index, type: c.type, mixerTrack: swapped(c.mixerTrack), color: c.color, name: c.name)
            }
            // Les envois suivent les pistes, comme dans FL.
            routes = Dictionary(uniqueKeysWithValues: routes.map { (swapped($0.key), $0.value.map(swapped).sorted()) })
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
        songCursor = nil
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

    func pickPattern(_ pattern: Int) throws -> Int {
        guard v14 else { throw OrganizerError.outdatedScript }
        log.append("pick \(pattern)")
        currentPattern = pattern
        return pattern
    }

    /// Clips de la Playlist : piste de chaque pattern (1 = le premier) ; `trackChannels` en est déduit. Faux : ⇧C ne
    /// sélectionne rien (« Typing keyboard to piano » allumé…), et FL décale alors tous les clips.
    var clipTracks: [Int: Int] = [:] { didSet { syncClips() } }
    var selectBySource = true
    private var clipSelection: Int?

    private func syncClips() {
        var tracks: [Int: Set<Int>] = [:]
        for (pattern, track) in clipTracks { tracks[track, default: []].formUnion(patternSounds[pattern] ?? []) }
        trackChannels = tracks
    }

    /// ⌘D, ⇧C puis ⇧↓ ou ⇧↑ simulés : les clips du pattern ouvert (sans sélection : tous) changent de piste.
    func moveClips(_ pattern: Int?, _ rows: Int) -> Int {
        if let pattern {
            guard (try? pickPattern(pattern)) != nil else { return 0 }
            clipSelection = selectBySource ? pattern : nil
        }
        log.append("clips \(rows)")
        let moving = clipSelection.map { [$0] } ?? Array(clipTracks.keys)
        var tracks = clipTracks
        for p in moving { if let t = tracks[p] { tracks[p] = max(t + rows, 0) } }
        clipTracks = tracks
        return abs(rows)
    }

    func activeChannels() throws -> Set<Int> {
        if let track { return trackChannels[track] ?? [] }
        if let at = songCursor { return songAt(at).channels }
        if solo == nil, let p = playedPattern { return patternSounds[p] ?? [] }
        return []
    }

    func activeTracks() throws -> Set<Int> {
        songCursor.map { songAt($0).tracks } ?? []
    }

    func heardTracks() throws -> Set<Int> {
        guard v14 else { throw OrganizerError.outdatedScript }
        return try activeTracks()
    }

    func songPosition() throws -> Double {
        guard let at = songCursor else { return 0 }
        let next = at + songStep
        songCursor = next >= 1 - 1e-9 ? 0 : next
        return songCursor ?? 0
    }

    func selectChannels(_ set: Set<Int>, count: Int) throws {
        guard count == channels.count else { throw OrganizerError.refused(5) }
        log.append("select \(set.sorted().map(String.init).joined(separator: ","))")
        unusedSelection = set
    }

    func linkChannel(_ channel: Int, to track: Int) throws {
        guard channels.indices.contains(channel) else { throw OrganizerError.refused(5) }
        log.append("link \(channel) \(track)")
        let c = channels[channel]
        channels[channel] = ChannelInfo(index: c.index, type: c.type, mixerTrack: track, color: c.color, name: c.name)
    }

    /// ⌥ + Suppr simulé : les canaux sélectionnés supprimés, les suivants remontent (Channel rack devant).
    func deleteSelected() -> Bool {
        guard window == .channelRack else { return false }
        log.append("delete")
        channels = channels.filter { !unusedSelection.contains($0.index) }.enumerated()
            .map { Self.copy($0.element, index: $0.offset, color: $0.element.color) }
        unusedSelection = []
        return true
    }

    /// « Move up » simulé : la piste de la Playlist à cette place remonte d'autant (Playlist devant).
    func moveTrackUp(_ place: Int, _ count: Int) -> Int {
        var done = 0
        var at = place
        while done < count, window == .playlist, at > 0, at < playlist.count {
            playlist.swapAt(at, at - 1)
            at -= 1
            done += 1
        }
        playlist = playlist.enumerated().map {
            PlaylistTrackInfo(index: $0.offset, selected: $0.element.selected, color: $0.element.color, name: $0.element.name)
        }
        return done
    }

    func playSong(at fraction: Double) throws -> Int {
        guard song else { throw OrganizerError.refused(6) }
        if !memo && playing { throw OrganizerError.refused(4) }
        memo = true
        playing = true
        solo = nil
        track = nil
        songCursor = fraction
        log.append("song \(Int((fraction * 1000).rounded()))")
        return bars
    }

    func playTrack(_ index: Int) throws -> Int {
        if !memo && playing { throw OrganizerError.refused(4) }
        memo = true
        playing = true
        songCursor = nil
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
        songCursor = nil
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
        guard let v = samples.first, v > 0.01 else { return (.unsure, 0, "silence") }
        return (SoundFamily.order[Int((v / 0.1).rounded()) - 1], 0.9, "faux")
    }

    private func channel(_ index: Int, type: Int = 2, fx: Int = 0) -> ChannelInfo {
        ChannelInfo(index: index, type: type, mixerTrack: fx, color: red, name: "Son \(index)")
    }

    private func named(_ index: Int, _ name: String, fx: Int = 0) -> ChannelInfo {
        ChannelInfo(index: index, type: 2, mixerTrack: fx, color: red, name: name)
    }

    private func make(_ link: FakeOrganizerLink, _ audio: FakeAudio, timing: OrganizerSession.Timing? = nil,
                      sleep: @escaping (TimeInterval) -> Void = { _ in },
                      prepare: @escaping () -> Bool = { false },
                      progress: @escaping (Int, Int) -> Void = { _, _ in }) -> OrganizerSession {
        OrganizerSession(link: link, audio: audio, classify: classify, nameDrum: { _, _ in .kick },
                         timing: timing ?? self.timing, sleep: sleep, prepare: prepare, progress: progress)
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
        // Patterns relevés en entier, à leur tempo (jamais accéléré) ; la Playlist avant l'écoute des sons (un son qui
        // joue dans la chanson n'est jamais laissé de côté).
        XCTAssertEqual(link.log, ["patterns", "list", "mixer", "all 1", "all 2", "song 0", "playlist", "track 0",
                                  "track 1", "track 2", "seek 500", "solo 1 p2", "routes 1", "routes 2", "routes 3",
                                  "routes 4", "restore"])
        XCTAssertEqual(steps.last.map { $0[0] == $0[1] }, true, "fini à 100 %")
        XCTAssertEqual([audio.started, audio.stopped], [1, 1])
        let diag = session.diagnostics
        XCTAssertEqual([diag.byName, diag.listened, diag.scanned, diag.withSounds, diag.tracks, diag.tracksSolo],
                       [3, 1, 2, 2, 3, 3])
        XCTAssertFalse(diag.text.contains("KICK"), "jamais un nom dans le diagnostic")
        XCTAssertEqual(diag.rules, ["c1:faux"], "règle de chaque son écouté, par son numéro")
        XCTAssertEqual(diag.tempo, 120, "le tempo du projet, jamais changé")
        XCTAssertTrue(diag.text.contains("tempo=120"))
        XCTAssertTrue(diag.text.contains("patterns-sons=pattern1:c0,c3 pattern2:c1"), diag.text)
    }

    /// Retour de l'utilisateur : « j'avais dit non pour l'accélérateur de BPM ». Patterns, chanson et sons : tout
    /// joue au tempo du projet, il n'est jamais changé.
    func testTempoIsNeverChanged() throws {
        let link = FakeOrganizerLink()
        link.channels = [channel(0), channel(1)]
        link.patternSounds = [1: [0, 1]]
        link.bars = 4
        link.songAt = { _ in ([0], [0, 1]) }
        link.trackChannels = [0: [0, 1]]
        link.playlist = [PlaylistTrackInfo(index: 0, selected: false, color: red, name: "Track 1")]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.melody), 1: tone(.drums)]
        let session = make(link, audio)
        _ = try session.run().get()
        XCTAssertFalse(link.log.contains { $0.hasPrefix("speed") }, "aucune accélération")
        XCTAssertTrue(link.log.contains("song 0"))
        XCTAssertEqual(session.diagnostics.listened, 2)
    }

    /// Un ancien script (v11 ou avant) : rien n'est touché, FL doit être redémarré.
    func testOldScriptAsksForARestart() {
        let link = FakeOrganizerLink()
        link.v14 = false
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
        audio.parts = [0: tone(.drums)]
        audio.testSounds = [3: tone(.vocals)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.index), [0, 3])
        XCTAssertEqual(result.items.map(\.family), [.drums, .vocals])
        XCTAssertEqual(result.items.map(\.testNotes), [false, false])
        XCTAssertEqual(result.channels.map(\.index), [0, 1, 2, 3])
        // Le clip audio (canal 3) ne joue pas dans les patterns : sa note de base (C5), tel quel (retour de
        // l'utilisateur : une boucle de batterie entendue deux octaves plus bas était classée « Mélodie »).
        XCTAssertEqual(link.log, ["patterns", "list", "mixer", "solo 0", "solo 3", "note 3 60 100", "note 3 60 0",
                                  "restore"])
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
        quiet.song = false
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

    /// FL sélectionne les sons sans note (« Select unused channels ») : laissés de côté, ni écoutés ni classés ; un
    /// clip audio sélectionné reste (il joue dans la Playlist sans note), un son entendu aussi.
    func testUnusedSoundsAreLeftAside() throws {
        let link = FakeOrganizerLink()
        link.song = false
        link.channels = [named(0, "BEAM KICK"), named(1, "Kick 2"), channel(2, type: ChannelInfo.audioClipType),
                         channel(3)]
        link.patternList = [PatternInfo(index: 0, color: red, name: "Pattern 1")]
        link.patternSounds = [1: [0, 3]]
        link.unusedSelection = [1, 2, 3]
        let audio = FakeAudio(link: link)
        audio.parts = [2: tone(.vocals), 3: tone(.melody)]
        var prepared = 0
        let session = make(link, audio, prepare: { prepared += 1; return true })
        let result = try session.run().get()
        XCTAssertEqual(prepared, 1)
        XCTAssertEqual(result.unused, [1])
        XCTAssertEqual(result.items.map(\.index), [0, 2, 3])
        XCTAssertFalse(link.log.contains("solo 1"), "pas écouté")
        XCTAssertEqual(session.diagnostics.unused, 1)
        XCTAssertEqual(session.diagnostics.selection, "oui")
    }

    /// Un nom que l'Organiser a pu donner est vérifié à l'écoute (retour de l'utilisateur : une boucle de batterie
    /// restait « Mélodie 3 ») ; il reste s'il ne la contredit pas, ou si rien n'est entendu.
    func testGeneratedNamesAreHeardAgain() throws {
        let link = FakeOrganizerLink()
        link.song = false
        link.channels = [named(0, "Mélodie 3"), named(1, "Lead"), named(2, "Kick 2"), named(3, "BEAM KICK")]
        let audio = FakeAudio(link: link)
        audio.parts = [0: tone(.drums), 1: tone(.melody)]
        let result = try make(link, audio).run().get()
        XCTAssertEqual(result.items.map(\.family), [.drums, .melody, .drums, .drums])
        XCTAssertEqual(result.items.map(\.kind), [.kick, .lead, .kick, .kick], "drums écoutés : leur sorte entendue")
        XCTAssertEqual(result.items.map(\.byName), [false, true, true, true])
        XCTAssertFalse(link.log.contains("solo 3"), "un nom de pack n'est pas écouté")
        XCTAssertTrue(SoundNames.isGenerated("Mélodie 3"))
        XCTAssertTrue(SoundNames.isGenerated("Hi-hat"))
        XCTAssertTrue(SoundNames.isGenerated("Drums 12"))
        XCTAssertFalse(SoundNames.isGenerated("BEAM KICK"))
        XCTAssertFalse(SoundNames.isGenerated("kick"), "nom écrit par l'utilisateur")
        XCTAssertTrue(SoundNames.keeps(.lead, heard: Verdict(family: .melody)))
        XCTAssertFalse(SoundNames.keeps(.snare, heard: Verdict(family: .drums, kind: .hiHat)))
        XCTAssertFalse(SoundNames.keeps(.melody, heard: Verdict(family: .drums, kind: .drums)))
        XCTAssertTrue(SoundNames.keeps(.kick, heard: Verdict(family: .unsure)))
    }

    /// Toute la chanson jouée d'un bout à l'autre : une piste qui ne joue qu'à un endroit est trouvée (retour de
    /// l'utilisateur : des pistes manquées, des trous).
    func testWholeSongIsPlayed() throws {
        let link = FakeOrganizerLink()
        link.channels = [named(0, "BEAM KICK"), named(1, "ALTER OPEN HAT")]
        link.bars = 8
        link.songStep = 0.25
        link.songAt = { at in at >= 0.5 && at < 0.75 ? ([0, 3], [0, 1]) : ([0], [0]) }
        link.trackChannels = [0: [0], 3: [1]]
        link.playlist = (0..<5).map { PlaylistTrackInfo(index: $0, selected: false, color: red, name: "Track \($0 + 1)") }
        let audio = FakeAudio(link: link)
        let session = make(link, audio)
        let result = try session.run().get()
        XCTAssertEqual(result.trackSounds, [0: [0], 3: [1]])
        XCTAssertEqual(result.playlist.count, 4, "lue jusqu'à la dernière piste qui joue")
        XCTAssertTrue(link.log.contains("seek 500"), "la piste 4 écoutée seule là où elle joue")
        XCTAssertEqual(session.diagnostics.activeSamples, 4, "une tranche par quart de chanson, puis la fin")
    }

    func testUnusedAndPatternLength() {
        let channels = [channel(0), channel(1), channel(2, type: ChannelInfo.audioClipType),
                        channel(3, type: ChannelInfo.automationType)]
        XCTAssertEqual(OrganizerSession.unused(channels, selected: [1, 2, 3], heard: [], complete: false), [1])
        XCTAssertEqual(OrganizerSession.unused(channels, selected: [0, 1], heard: [0], complete: true), [1],
                       "entendu : jamais de côté")
        XCTAssertEqual(OrganizerSession.unused(channels, selected: nil, heard: [0], complete: true), [1],
                       "sans la sélection de FL : ce qui n'a joué nulle part")
        XCTAssertEqual(OrganizerSession.unused(channels, selected: nil, heard: [0], complete: false), [])
        XCTAssertEqual(OrganizerSession.unused(channels, selected: nil, heard: [], complete: true), [], "rien relevé")
        XCTAssertEqual(OrganizerSession.patternSeconds(beats: 16, tempo: 120, cap: 8), 8)
        XCTAssertEqual(OrganizerSession.patternSeconds(beats: 16, tempo: 480, cap: 8), 2)
        XCTAssertEqual(OrganizerSession.patternSeconds(beats: 0, tempo: 0, cap: 20), 8, "4 mesures à 120 par défaut")
    }

    func testPureHelpers() {
        XCTAssertEqual(OrganizerSession.homes([2: [5, 1], 0: [1]]), [1: 1, 5: 3], "le premier pattern où le son joue")
        XCTAssertEqual(OrganizerSession.soundMap([3: [2, 0], 0: [1]], label: "piste"), "piste1:c1 piste4:c0,c2",
                       "des numéros seulement, dans l'ordre")
        XCTAssertEqual(OrganizerSession.quietestSample([0, 1, 2], samples: [[0, 1, 2], [0], [0, 3]]), 1)
        XCTAssertEqual(OrganizerSession.quietestSample([0, 2], samples: [[0, 1], [5], [0, 3]]), 0, "égalité : le premier")
        XCTAssertNil(OrganizerSession.quietestSample([], samples: [[0]]))
        // Deux pistes qui jouent toujours ensemble : le son va sur les deux.
        let samples: [(tracks: Set<Int>, channels: Set<Int>)] = [([0, 1], [5]), ([0, 1], [5]), ([2], [6])]
        let sounds = OrganizerSession.trackSounds(samples)
        XCTAssertEqual(sounds[0]?.keys.sorted(), [5])
        XCTAssertEqual(sounds[1]?.keys.sorted(), [5])
        XCTAssertEqual(sounds[2], [6: 1.0])
        // 16 mesures à 480 BPM : 8 s, tranches de 0,25 s, une de plus pour finir ; 90 s au plus.
        XCTAssertEqual(OrganizerSession.songSlices(bars: 16, tempo: 480, slice: 0.25, cap: 90), 33)
        XCTAssertEqual(OrganizerSession.songSlices(bars: 0, tempo: 0, slice: 0.25, cap: 90), 129, "16 mesures à 120")
        XCTAssertEqual(OrganizerSession.songSlices(bars: 500, tempo: 120, slice: 0.25, cap: 90), 361)
        // Où écouter chaque son pour vérifier qu'il a changé de piste : la tranche où le moins de pistes jouent.
        let song: [(position: Double, tracks: Set<Int>, channels: Set<Int>)] =
            [(0, [0, 1], [5, 6]), (0.25, [1], [6]), (0.5, [0, 2], [5, 7])]
        XCTAssertEqual(OrganizerSession.soundPositions(song), [5: 0, 6: 0.25, 7: 0.5])
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

    /// Voix enregistrées dans FL (projets du propriétaire : rangées en Mélodies, FX et Drums à l'écoute) : reconnues à
    /// leur nom ; lead, back et ambiance d'après les mots d'un nom de voix.
    func testRecordedVocalsAndVocalLayers() {
        XCTAssertEqual(SoundNames.kind(of: "untitled_2026-10-15 23-37-42_Insert 5"), .vocal)
        XCTAssertEqual(SoundNames.kind(of: "Kick Prod_2026-10-15 23-37-42_Insert 3"), .vocal, "le nom du projet ne compte pas")
        XCTAssertEqual(SoundNames.kind(of: "number one_2026-10-15 23-37-42_Back"), .backing)
        XCTAssertEqual(SoundNames.kind(of: "Lead Vox"), .vocalLead)
        XCTAssertEqual(SoundNames.kind(of: "Lead"), .lead, "sans mot de voix : une mélodie")
        XCTAssertEqual(SoundNames.kind(of: "Backs"), .backing)
        XCTAssertEqual(SoundNames.kind(of: "Vocal Ambiance"), .ambiance)
        XCTAssertNil(SoundNames.kind(of: "Ambiance"), "sans mot de voix : rien de sûr")
        XCTAssertEqual(SoundNames.kind(of: "Adlib Vox"), .adlib)
        XCTAssertEqual(SoundFamily.vocals.kinds, [.vocalLead, .backing, .ambiance, .adlib, .choir, .vocal])
        XCTAssertTrue(SoundNames.isGenerated("Voix lead 2"))
    }

    /// Analyse sur le fichier du projet (retour du propriétaire, vidéo du 21/10 : des mélodies classées « FX », des
    /// patterns oubliés) : FL enregistre le projet, les sons de chaque pattern et de chaque piste viennent de ses notes
    /// et de ses clips. Ni pattern relevé, ni chanson jouée, ni piste écoutée ; rien n'est retiré de FL avant.
    func testProjectFileGivesExactSounds() throws {
        let link = FakeOrganizerLink()
        link.channels = ["Pad", "Kick", "ZENOLOGY", "Snare", "808"].enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: $0.offset + 1, color: red, name: $0.element)
        }
        link.patternList = ["Mélodie", "Drums", "Pattern 3", "Vide"].enumerated().map {
            PatternInfo(index: $0.offset, color: red, name: $0.element)
        }
        link.mixer = (0...6).map { MixerTrackInfo(index: $0, color: red, name: $0 == 0 ? "Master" : "Insert \($0)") }
        let audio = FakeAudio(link: link)
        audio.parts = [2: tone(.melody)]
        let url = URL(fileURLWithPath: "/projets/Mon son.flp")
        var saves = 0
        let files = ProjectFileAccess(save: { _ in
            saves += 1
            return .success(url)
        }, open: { _ in false }, read: { _ in FLPSample.sample() })
        var prepared = false
        let session = OrganizerSession(link: link, audio: audio, classify: classify, nameDrum: { _, _ in .kick },
                                       timing: timing, sleep: { _ in }, prepare: {
                                           prepared = true
                                           return true
                                       }, files: files)
        let result = try session.run().get()

        XCTAssertEqual(saves, 1, "FL enregistre le projet avant la lecture")
        XCTAssertFalse(prepared, "rien n'est retiré ni sélectionné dans FL avant l'enregistrement")
        XCTAssertEqual(result.patternSounds, [0: [2], 1: [3, 4], 2: [1]], "index 0 = pattern 1")
        XCTAssertEqual(result.trackSounds, [0: [2], 1: [3, 4], 2: [2], 3: [3, 4], 5: [1]])
        XCTAssertEqual(result.unused, [0], "ni note ni clip")
        XCTAssertEqual(result.items.map(\.index), [1, 2, 3, 4])
        XCTAssertEqual(result.items.first { $0.index == 2 }?.family, .melody, "écouté seul dans son pattern")
        XCTAssertEqual(result.project?.url, url)
        XCTAssertEqual(result.project?.clips.count, 6)
        XCTAssertEqual(result.project?.silentPatterns, 1)
        XCTAssertFalse(link.log.contains { $0.hasPrefix("all") || $0.hasPrefix("song") || $0.hasPrefix("track") },
                       "rien n'est deviné : \(link.log)")
        XCTAssertTrue(link.log.contains("solo 2 p1"), "\(link.log)")
        let diag = session.diagnostics
        XCTAssertEqual(diag.file, "oui")
        XCTAssertEqual(diag.clips, 6)
        XCTAssertTrue(diag.text.contains("fichier=oui clips=6"), diag.text)
        XCTAssertFalse(diag.text.contains("ZENOLOGY"), "jamais un nom dans le diagnostic")
    }

    /// Channel rack sur un groupe (retour du propriétaire : « le truc du All […] c'est pas à la personne de le
    /// faire ») : sur le fichier, tous les sons sont comptés comme dans « All », sans rien demander.
    func testProjectFileCountsAllChannelsWhateverTheGroup() throws {
        let link = FakeOrganizerLink()
        link.channels = ["Pad", "Kick", "ZENOLOGY", "Snare", "808"].enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: $0.offset + 1, color: red, name: $0.element)
        }
        link.group = [1, 3]
        link.patternList = ["Mélodie", "Drums", "Pattern 3", "Vide"].enumerated().map {
            PatternInfo(index: $0.offset, color: red, name: $0.element)
        }
        link.mixer = (0...6).map { MixerTrackInfo(index: $0, color: red, name: $0 == 0 ? "Master" : "Insert \($0)") }
        let audio = FakeAudio(link: link)
        audio.parts = [2: tone(.melody)]
        let files = ProjectFileAccess(save: { _ in .success(URL(fileURLWithPath: "/projets/Mon son.flp")) },
                                      open: { _ in false }, read: { _ in FLPSample.sample() })
        let session = OrganizerSession(link: link, audio: audio, classify: classify, nameDrum: { _, _ in .kick },
                                       nameMelody: { _, _ in .pad }, timing: timing, sleep: { _ in }, files: files)
        let result = try session.run().get()
        XCTAssertTrue(link.allChannels)
        XCTAssertEqual(result.channels.count, 5)
        XCTAssertEqual(result.items.map(\.index), [1, 2, 3, 4])
        XCTAssertEqual(result.items.first { $0.index == 2 }?.kind, .pad, "mélodie écoutée : sa sorte (retour du propriétaire)")

        let live = OrganizerSession(link: link, audio: audio, classify: classify, timing: timing, sleep: { _ in })
        _ = live.run()
        XCTAssertFalse(link.allChannels, "sans le fichier : le groupe affiché, comme avant")
    }

    /// Le fichier enregistré n'est pas le projet ouvert (autres sons) : rien n'est touché, la raison est dite.
    func testOtherProjectFileStopsEverything() {
        let link = FakeOrganizerLink()
        link.channels = [named(0, "Pad"), named(1, "Kick")]
        let audio = FakeAudio(link: link)
        let files = ProjectFileAccess(save: { _ in .success(URL(fileURLWithPath: "/projets/Autre.flp")) },
                                      open: { _ in false }, read: { _ in FLPSample.sample() })
        let session = OrganizerSession(link: link, audio: audio, classify: classify, timing: timing, sleep: { _ in },
                                       files: files)
        guard case .failure(.failed(let message)) = session.run() else { return XCTFail("refusé") }
        XCTAssertTrue(message.contains("rien n'a été touché"), message)
        XCTAssertEqual(session.diagnostics.file, "canaux 5/2")
        XCTAssertEqual(audio.started, 0, "rien n'est écouté")
        let unsaved = OrganizerSession(link: link, audio: audio, classify: classify, timing: timing, sleep: { _ in },
                                       files: ProjectFileAccess(save: { _ in .failure(.failed("pas enregistré")) },
                                                                open: { _ in false }))
        XCTAssertEqual(unsaved.run(), .failure(.failed("pas enregistré")))
    }
}
