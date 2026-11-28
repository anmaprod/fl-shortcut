// Cartes des pages de raccourcis (maquette du 28/10) : chaque raccourci d'origine de FL dans un groupe et un seul.
import XCTest
@testable import FLShortcut

final class CatalogGroupsTests: XCTestCase {
    func testEveryNativeShortcutHasExactlyOneGroup() {
        let entries = Catalog.entries(layout: FakeLayout.qwerty).filter(\.isNative)
        for section in FLSection.allCases {
            let keys = CatalogGroups.groups(for: section).flatMap(\.keys)
            XCTAssertEqual(Set(keys).count, keys.count, "groupes de \(section) : raccourci en double")
            let mine = entries.filter { $0.section == section }.map(CatalogGroups.key(of:))
            XCTAssertEqual(Set(mine), Set(keys), "groupes de \(section) : raccourcis sans groupe ou inconnus")
        }
    }

    func testCardsKeepCatalogOrderAndPutUnknownLast() {
        let entries = Catalog.entries(layout: FakeLayout.qwerty).filter { $0.isNative && $0.section == .playlist }
        let cards = CatalogGroups.cards(for: .playlist, rows: entries, entry: { $0 })
        XCTAssertEqual(cards.first?.title, String(localized: "Outils"))
        XCTAssertEqual(cards.first.map { Array($0.rows.prefix(3).map(\.id)) },
                       ["fl.playlist.p", "fl.playlist.b", "fl.playlist.d"])
        XCTAssertEqual(cards.reduce(0) { $0 + $1.rows.count }, entries.count, "aucun raccourci perdu")
        XCTAssertFalse(cards.contains { $0.title == String(localized: "Autres") })

        let stray = CatalogEntry(id: "fl.playlist.inconnu", section: .playlist, title: "Nouveau", detail: "",
                                 kind: .native(KeyCombo(keyCode: 0)), defaultTrigger: nil)
        let withStray = CatalogGroups.cards(for: .playlist, rows: entries + [stray], entry: { $0 })
        XCTAssertEqual(withStray.last?.title, String(localized: "Autres"))
        XCTAssertEqual(withStray.last?.rows.map(\.id), ["fl.playlist.inconnu"])
    }
}
