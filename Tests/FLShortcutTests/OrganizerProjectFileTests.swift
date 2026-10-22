// Organiser sur le fichier du projet : ce que joue chaque pattern et chaque piste, le fichier comparé au projet ouvert,
// le nom de la copie rangée (jamais par-dessus un fichier), la marque qui dit que FL l'a ouverte, le titre de FL.
import XCTest
@testable import FLShortcut

final class OrganizerProjectFileTests: XCTestCase {
    func testSoundsComeFromNotesAndClips() throws {
        let project = try FLPProject(FLPSample.sample())
        let sounds = ProjectFile.sounds(project, notSounds: [])
        XCTAssertEqual(sounds.patterns, [0: [2], 1: [3, 4], 2: [1]], "index 0 = pattern 1 ; le pattern vide n'y est pas")
        XCTAssertEqual(sounds.tracks, [0: [2], 1: [3, 4], 2: [2], 3: [3, 4], 5: [1]], "piste 6 : un clip du canal 1")
        XCTAssertEqual(sounds.used, [1, 2, 3, 4], "« Pad » : ni note ni clip")
        XCTAssertNil(ProjectFile.sounds(project, notSounds: [1]).tracks[5], "une automation n'est pas un son")
        XCTAssertEqual(project.clips.map { ProjectFile.group($0, project: project, notSounds: [1]) },
                       [.sounds([2]), .sounds([3, 4]), .sounds([2]), .sounds([3, 4]), .silent(4), .other(1)])
        let snapshot = ProjectFile.snapshot(project, url: URL(fileURLWithPath: "/p.flp"), notSounds: [])
        XCTAssertEqual(snapshot.silentPatterns, 1)
        XCTAssertEqual(snapshot.moving([1: 0, 2: 1, 3: 2, 4: 3]).groups[1], .sounds([2, 3]),
                       "les sons suivent les canaux supprimés")
    }

    /// Le fichier enregistré doit être le projet ouvert dans FL : sinon rien n'est touché (raison sans aucun nom).
    func testFileMustBeTheOpenProject() throws {
        let project = try FLPProject(FLPSample.sample())
        let channels = ["Pad", "Kick", "ZENOLOGY", "Snare", "808"]
        let patterns = [0: "Mélodie", 1: "Drums", 2: "Pattern 3", 3: "Vide"]
        XCTAssertNil(ProjectFile.mismatch(project, channels: channels, patterns: patterns))
        XCTAssertEqual(ProjectFile.mismatch(project, channels: Array(channels.prefix(4)), patterns: patterns),
                       "canaux 5/4")
        var renamed = channels
        renamed[3] = "Clap"
        XCTAssertEqual(ProjectFile.mismatch(project, channels: renamed, patterns: patterns), "nom c3")
        XCTAssertEqual(ProjectFile.mismatch(project, channels: channels, patterns: [0: "Mélodie", 3: "Vide"]),
                       "pattern 2")
        XCTAssertTrue(ProjectFile.same("BETTY WHITE Hat @baby", "BETTY WHITE Hat @babyxprod"), "nom coupé par le script")
        XCTAssertFalse(ProjectFile.same("Hat", "Hat 2"), "un nom court n'est jamais pris pour un début")
    }

    /// Nommée comme « Save new version » de FL (retour du propriétaire), jamais par-dessus un fichier.
    func testCopyNameNeverOverwrites() {
        let original = URL(fileURLWithPath: "/projets/Mon son.flp")
        XCTAssertEqual(ProjectFile.copyURL(for: original, exists: { _ in false }).lastPathComponent, "Mon son_2.flp")
        let taken: Set<String> = ["Mon son_2.flp", "Mon son_3.flp"]
        XCTAssertEqual(ProjectFile.copyURL(for: original, exists: { taken.contains($0.lastPathComponent) })
                        .lastPathComponent, "Mon son_4.flp")
        XCTAssertEqual(ProjectFile.copyURL(for: URL(fileURLWithPath: "/projets/Mon son_2.flp"),
                                           exists: { taken.contains($0.lastPathComponent) }).path,
                       "/projets/Mon son_4.flp", "la version suivante")
        XCTAssertEqual(ProjectFile.copyURL(for: URL(fileURLWithPath: "/projets/_7.flp"), exists: { _ in false })
                        .lastPathComponent, "_7_2.flp", "un nom fait seulement d'un numéro garde son numéro")
    }

    func testMarkerIsPutOnANamedPattern() throws {
        let file = FLPSample.sample()
        let marked = try XCTUnwrap(ProjectFile.marking(file, marker: "FL Shortcuts 42"))
        XCTAssertEqual(marked.mark, .pattern(1))
        let project = try FLPProject(marked.file)
        XCTAssertEqual(project.patternNames, [1: "FL Shortcuts 42", 2: "Drums", 4: "Vide"])
        XCTAssertEqual(project.clips, try FLPProject(file).clips, "rien d'autre ne change")
        // Aucun pattern nommé : le nom est ajouté au premier pattern décrit (pas à celui de ses notes).
        var unnamed = file
        unnamed.events.removeAll { $0.id == 193 }
        let added = try XCTUnwrap(ProjectFile.marking(unnamed, marker: "FL Shortcuts 42"))
        XCTAssertEqual(added.mark, .pattern(1))
        XCTAssertEqual(try FLPProject(added.file).patternNames, [1: "FL Shortcuts 42"])
        XCTAssertEqual(try FLPProject(added.file).notes, try FLPProject(file).notes)
        // Un seul pattern, jamais nommé (prod « Mechanical » du propriétaire : « (patterns) ») : la marque va sur le
        // premier canal nommé ; rien d'autre ne change.
        var bare = unnamed
        bare.events = unnamed.events.enumerated().filter { i, event in
            event.id != 65 || (i + 1 < unnamed.events.count && unnamed.events[i + 1].id == 224)
        }.map(\.element)
        let onChannel = try XCTUnwrap(ProjectFile.marking(bare, marker: "FL Shortcuts 42"))
        XCTAssertEqual(onChannel.mark, .channel(0))
        let channels = try FLPProject(onChannel.file).channels
        XCTAssertEqual(channels.map(\.name), ["FL Shortcuts 42", "Kick", "ZENOLOGY", "Snare", "808"])
        XCTAssertEqual(onChannel.file.events.count, bare.events.count)
        var nameless = bare
        nameless.events.removeAll { $0.id == 203 }
        XCTAssertNil(ProjectFile.marking(nameless, marker: "FL Shortcuts 42"), "ni pattern décrit, ni canal nommé")
    }

    func testProjectNameInFLTitle() {
        XCTAssertEqual(ProjectFile.titleNames("rio leyva typz - FL Studio 2025"), ["rio leyva typz"])
        XCTAssertEqual(ProjectFile.titleNames("FL Studio 2025 - Mon son.flp *"), ["Mon son"])
        XCTAssertEqual(ProjectFile.titleNames("Mon son.flp"), ["Mon son"])
        XCTAssertEqual(ProjectFile.titleNames("FL Studio 2025"), [])
        XCTAssertEqual(ProjectFile.titleNames(""), [])
    }

    /// Rien n'est touché, avec ce qu'il faut faire : piste coupée, dossier refusé par macOS, marque restée d'un essai.
    func testReadingStopsWithAClearReason() throws {
        let channels = ["Pad", "Kick", "ZENOLOGY", "Snare", "808"].enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: 0, color: RGBColor(r: 0, g: 0, b: 0), name: $0.element)
        }
        let patterns = ["Mélodie", "Drums", "Pattern 3", "Vide"].enumerated().map {
            PatternInfo(index: $0.offset, color: RGBColor(r: 0, g: 0, b: 0), name: $0.element)
        }
        let url = URL(fileURLWithPath: "/projets/Mon son.flp")
        var muted = FLPSample.sample()
        let track = muted.events.firstIndex { $0.id == 238 }!
        muted.events[track] = FLPSample.track(1, muted: true)
        var why = ""
        let files = ProjectFileAccess(save: { _ in .success(url) }, open: { _ in false }, read: { _ in muted })
        XCTAssertThrowsError(try ProjectFile.read(files, known: nil, channels: channels, patterns: patterns,
                                                  why: { why = $0 }))
        XCTAssertEqual(why, "piste coupée")
        let locked = ProjectFileAccess(save: { _ in .success(url) }, open: { _ in false }, read: { _ in
            throw CocoaError(.fileReadNoPermission)
        })
        XCTAssertThrowsError(try ProjectFile.read(locked, known: nil, channels: channels, patterns: patterns,
                                                  why: { why = $0 })) {
            XCTAssertEqual($0 as? OrganizerError, ProjectFile.deniedError)
        }
        XCTAssertEqual(why, "autorisation")
        XCTAssertTrue(ProjectFile.isMarker("FL Shortcuts 4821"))
        XCTAssertFalse(ProjectFile.isMarker("FL Shortcuts 4821 bis"))
        // Un nom trop long pour être remis par le script n'est pas pris pour la marque.
        var long = FLPSample.sample()
        let first = long.events.firstIndex { $0.id == 193 }!
        long.events[first] = FLPSample.text(193, String(repeating: "é", count: 40))
        XCTAssertEqual(ProjectFile.marking(long, marker: "FL Shortcuts 1")?.mark, .pattern(2))
    }
}
