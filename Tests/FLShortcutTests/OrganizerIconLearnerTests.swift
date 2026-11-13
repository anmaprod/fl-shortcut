import XCTest
@testable import FLShortcut

/// 12/11 (« oui stp… on le fait une fois et ça fonctionnera partout ») : apprentissage des numéros d'icônes de FL sur
/// un projet vide, avec un faux FL qui écrit dans le fichier le numéro de chaque icône posée, en enregistrant.
final class OrganizerIconLearnerTests: XCTestCase {
    /// Faux FL : le projet ouvert, les icônes posées depuis le dernier enregistrement (place → numéro).
    private final class FakeIconFL {
        let url = URL(fileURLWithPath: "/projets/Icônes.flp")
        var file: FLPFile
        var rack: [Int: UInt32] = [:]
        var mixer: [Int: UInt32] = [:]
        var saves = 0

        init(_ file: FLPFile) { self.file = file }

        var access: ProjectFileAccess {
            ProjectFileAccess(save: { _ in
                self.saves += 1
                var channels: [Int: UInt32] = [:]
                if let project = try? FLPProject(self.file) {
                    for (place, id) in self.rack where project.channels.indices.contains(place) {
                        channels[project.channels[place].iid] = id
                    }
                }
                self.file = FLPProject.withIcons(self.file, channels: channels, inserts: self.mixer).file
                self.rack = [:]
                self.mixer = [:]
                return .success(self.url)
            }, open: { _ in true }, read: { _ in self.file })
        }
    }

    /// Un projet vide comme FL l'écrit : 5 sons (chacun avec son 155), aucun clip ni aucune note, un Mixer à la forme
    /// de FL (Master et 3 pistes).
    private func emptyProject() -> FLPFile {
        var file = FLPSample.sample(clips: [])
        file.events.removeAll { $0.id == 224 }                                // aucune note
        for start in file.events.indices.filter({ file.events[$0].id == 21 }).reversed() {
            file.events.insert(FLPSample.ev(155, 0), at: start + 1)          // FL l'écrit toujours, à 0
        }
        file.events.removeLast(4)                                             // le Mixer de l'exemple…
        for k in 0...3 {                                                      // … remplacé par celui de FL
            if k > 0 { file.events += [FLPSample.ev(42, 0), FLPSample.text(204, "Insert \(k)")] }
            file.events += [FLPSample.text(236, ""), FLPSample.ev(98, 0), FLPSample.text(235, ""),
                            FLPSample.ev(154, 0), FLPSample.ev(147, 0)]
        }
        return file
    }

    private func link() -> FakeOrganizerLink {
        let link = FakeOrganizerLink()
        link.channels = (0..<5).map { ChannelInfo(index: $0, type: 0, mixerTrack: 0, color: RGBColor(r: 0, g: 0, b: 0),
                                                  name: "Son \($0)") }
        link.mixer = (0...3).map { MixerTrackInfo(index: $0, color: RGBColor(r: 0, g: 0, b: 0), name: "") }
        return link
    }

    private static func rackNumber(_ icon: FLIcon) -> UInt32 { UInt32(icon.column * 20 + icon.row + 1) }
    private static func mixerNumber(_ icon: FLIcon) -> UInt32 { rackNumber(icon) + 500 }

    private let cells = Array(FLIconGrid.pickable.prefix(7))

    /// `place` : ce que fait FL après la pose (le numéro est déjà noté ; l'effacer = FL n'a rien pris).
    private func learner(_ fl: FakeIconFL, _ link: FakeOrganizerLink, stop: @escaping () -> Bool = { false },
                         progress: @escaping (Int, Int) -> Void = { _, _ in },
                         place: @escaping (FLIcon, IconTarget) -> OrganizerError? = { _, _ in nil }) -> OrganizerIconLearner {
        OrganizerIconLearner(link: link, placeIcon: { icon, target in
            if target.kind == .channels {
                fl.rack[target.place] = Self.rackNumber(icon)
            } else {
                fl.mixer[target.place] = Self.mixerNumber(icon)
            }
            return place(icon, target)
        }, files: fl.access, wait: { _ in }, cells: cells, stop: stop, progress: progress)
    }

    func testEveryCellIsLearnedOnBothPages() {
        let fl = FakeIconFL(emptyProject())
        let link = link()
        var last = (0, 0)
        let outcome = learner(fl, link, progress: { last = ($0, $1) }).run()
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.rack, Dictionary(uniqueKeysWithValues: cells.map { ($0.code, Self.rackNumber($0)) }))
        XCTAssertEqual(outcome.mixer, Dictionary(uniqueKeysWithValues: cells.map { ($0.code, Self.mixerNumber($0)) }))
        XCTAssertEqual(outcome.missedRack, 0)
        XCTAssertEqual(outcome.missedMixer, 0)
        XCTAssertEqual(fl.saves, 1 + 2 + 3, "le projet, 5 + 2 sons, 3 + 3 + 1 pistes")
        XCTAssertEqual(last.0, last.1)
        XCTAssertTrue(link.channels.allSatisfy { $0.name.hasPrefix("Rack ") }, "les sons renommés pour être retrouvés")
        XCTAssertEqual(link.mixer.dropFirst().map(\.name), ["Mix 1", "Mix 2", "Mix 3"], "jamais les mêmes noms qu'au rack")
    }

    /// Une icône que FL n'a pas prise sans rien dire (le numéro n'a pas changé) est refaite plus tard ; celle qui ne
    /// passe jamais est comptée pas apprise, sans numéro inventé.
    func testSilentMissIsRedoneAndStubbornOneIsMissed() {
        let fl = FakeIconFL(emptyProject())
        let once = cells[1].code, never = cells[2].code
        var missedOnce = false
        let outcome = learner(fl, link(), place: { icon, target in
            guard target.kind == .channels else { return nil }
            if icon.code == never || (icon.code == once && !missedOnce) {
                if icon.code == once { missedOnce = true }
                fl.rack[target.place] = nil                                   // FL n'a rien pris, sans rien dire
            }
            return nil
        }).run()
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.rack[once], Self.rackNumber(cells[1]))
        XCTAssertNil(outcome.rack[never])
        XCTAssertEqual(outcome.missedRack, 1)
        XCTAssertEqual(outcome.rack.count, cells.count - 1)
    }

    /// Jamais sur un vrai projet : des clips ou des notes, rien n'est touché.
    func testOnlyAnEmptyProject() {
        let fl = FakeIconFL(FLPSample.sample())
        var placed = 0
        let outcome = learner(fl, link(), place: { _, _ in
            placed += 1
            return nil
        }).run()
        XCTAssertEqual(outcome.error, .failed(String(localized: "Ouvre un projet vide dans FL (File › New), enregistre-le, puis recommence : l'apprentissage pose des icônes sur ses sons.")))
        XCTAssertEqual(placed, 0)
        XCTAssertTrue(outcome.rack.isEmpty)
    }

    /// 13/11 (le Channel rack ratait : « Nom du son introuvable ») : une page qui échoue n'empêche pas l'autre.
    func testMixerIsTriedWhenTheRackFails() {
        let fl = FakeIconFL(emptyProject())
        let outcome = learner(fl, link(), place: { _, target in
            target.kind == .channels ? .failed("nom du son introuvable dans le Channel rack de FL") : nil
        }).run()
        XCTAssertEqual(outcome.error, .failed("nom du son introuvable dans le Channel rack de FL"))
        XCTAssertTrue(outcome.rack.isEmpty)
        XCTAssertEqual(outcome.mixer.count, cells.count)
        XCTAssertEqual(outcome.missedRack, cells.count)
    }

    /// Échap ou fenêtre fermée : tout s'arrête, ce qui est appris reste.
    func testStopKeepsWhatWasLearned() {
        let fl = FakeIconFL(emptyProject())
        let link = link()
        let outcome = learner(fl, link, stop: { link.window == .mixer }).run()
        XCTAssertEqual(outcome.error, .interrupted)
        XCTAssertEqual(outcome.rack.count, cells.count)
        XCTAssertTrue(outcome.mixer.isEmpty)
    }

    /// 13/11 : la table apprise sur le Mac du propriétaire couvre exactement les cases proposées, un numéro différent
    /// pour chacune.
    func testLearnedTableCoversTheGrid() {
        XCTAssertEqual(Set(FLIconNumbers.table.keys), Set(FLIconGrid.pickable.map(\.code)))
        XCTAssertEqual(Set(FLIconNumbers.table.values).count, FLIconNumbers.table.count)
        XCTAssertEqual(FLIconNumbers.table["7-4"], 30)
    }

    func testTableText() {
        var outcome = OrganizerIconLearner.Outcome()
        outcome.rack = ["7-4": 75, "1-0": 12, "10-2": 3]
        outcome.mixer = ["7-4": 105]
        XCTAssertEqual(OrganizerIconLearner.tableText(outcome),
                       "FL Shortcuts · icônes de FL\nrack 1-0=12 7-4=75 10-2=3\nmixer 7-4=105")
    }
}
