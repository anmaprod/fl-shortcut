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

    func testCopyNameNeverOverwrites() {
        let word = String(localized: "rangé")
        let original = URL(fileURLWithPath: "/projets/Mon son.flp")
        XCTAssertEqual(ProjectFile.copyURL(for: original, exists: { _ in false }).lastPathComponent,
                       "Mon son (\(word)).flp")
        let taken: Set<String> = ["Mon son (\(word)).flp", "Mon son (\(word) 2).flp"]
        XCTAssertEqual(ProjectFile.copyURL(for: original, exists: { taken.contains($0.lastPathComponent) })
                        .lastPathComponent, "Mon son (\(word) 3).flp")
        let organized = URL(fileURLWithPath: "/projets/Mon son (\(word)).flp")
        XCTAssertEqual(ProjectFile.copyURL(for: organized, exists: { taken.contains($0.lastPathComponent) }).path,
                       "/projets/Mon son (\(word) 3).flp", "une copie rangée de nouveau garde son nom de base")
    }

    func testMarkerIsPutOnANamedPattern() throws {
        let file = FLPSample.sample()
        let marked = try XCTUnwrap(ProjectFile.marking(file, marker: "FL Shortcuts 42"))
        XCTAssertEqual(marked.pattern, 1)
        let project = try FLPProject(marked.file)
        XCTAssertEqual(project.patternNames, [1: "FL Shortcuts 42", 2: "Drums", 4: "Vide"])
        XCTAssertEqual(project.clips, try FLPProject(file).clips, "rien d'autre ne change")
        // Aucun pattern nommé : le nom est ajouté au premier pattern décrit (pas à celui de ses notes).
        var unnamed = file
        unnamed.events.removeAll { $0.id == 193 }
        let added = try XCTUnwrap(ProjectFile.marking(unnamed, marker: "FL Shortcuts 42"))
        XCTAssertEqual(added.pattern, 1)
        XCTAssertEqual(try FLPProject(added.file).patternNames, [1: "FL Shortcuts 42"])
        XCTAssertEqual(try FLPProject(added.file).notes, try FLPProject(file).notes)
        var bare = unnamed
        bare.events.removeAll { $0.id == 65 }
        XCTAssertNil(ProjectFile.marking(bare, marker: "FL Shortcuts 42"), "aucun pattern décrit")
    }

    func testProjectNameInFLTitle() {
        XCTAssertEqual(ProjectFile.titleNames("rio leyva typz - FL Studio 2025"), ["rio leyva typz"])
        XCTAssertEqual(ProjectFile.titleNames("FL Studio 2025 - Mon son.flp *"), ["Mon son"])
        XCTAssertEqual(ProjectFile.titleNames("Mon son.flp"), ["Mon son"])
        XCTAssertEqual(ProjectFile.titleNames("FL Studio 2025"), [])
        XCTAssertEqual(ProjectFile.titleNames(""), [])
    }
}
