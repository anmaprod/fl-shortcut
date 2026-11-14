// « Consolider la piste dans la Playlist » (retour du 08/11 : « armer la piste si éteinte… dans playlist, ça render,
// ça consolide… tu vas la renommer en consolider une track dans playlist… utilisable que dans playlist »). FL n'a ni
// touche ni fonction du script pour ça : seulement « Consolidate this track » dans le menu du clic droit de l'en-tête
// d'une piste de la Playlist. Donc :
// - la piste est la dernière cliquée dans FL ; son rond mute (MuteDots.swift) dit si le clic était bien sur l'en-tête
//   d'une piste de la Playlist (le rond est à droite du clic) : jamais un clic droit sur un clip (FL l'effacerait), ni
//   dans le Mixer ou le Channel rack ;
// - clic droit sur l'en-tête, puis « Consolidate… » retrouvé à son nom dans le menu (lecture de la seule fenêtre du
//   menu de FL, autorisation « Enregistrement de l'écran ») et cliqué ; un menu sans lui est refermé (Échap).
import AppKit

/// Choix d'un élément dans le menu du clic droit de FL, retrouvé au début de son nom.
enum TrackMenuPick {
    enum Outcome: Equatable { case clicked, stopped, refused, noMenu, notInMenu, unreadable }

    /// Pure (testée) : l'élément dont le texte commence par `prefix`, le plus haut du menu (sans casse ni accents).
    static func item(startingWith prefix: String, in items: [TextLook.Item]) -> TextLook.Item? {
        let wanted = TextLook.normalized(prefix)
        guard !wanted.isEmpty else { return nil }
        return items.filter { TextLook.normalized($0.text).hasPrefix(wanted) }.min { $0.box.minY < $1.box.minY }
    }

    /// Clic droit en `target`, puis l'élément `prefix…` du menu qui s'ouvre. Tout ce qui s'est ouvert est refermé
    /// (Échap) quand l'élément n'est pas cliqué : jamais de clic à l'aveugle.
    static func pick(_ prefix: String, at target: CGPoint, driver: IconPlacementDriver) -> Outcome {
        let base = Set(driver.windows().map(\.number))
        guard driver.rightClick(target) else { return .refused }
        let menu: WinInfo
        switch IconPlacement.awaitWindow(excluding: base, missing: .noMenu, driver: driver, accept: IconPlacement.isMenu) {
        case .success(let w): menu = w
        case .failure(let failure):
            driver.note("no menu after the right-click; new windows: \(IconPlacement.fresh(base, driver))")
            return failure == .stopped ? .stopped : .noMenu
        }
        driver.note("menu \(menu)")
        switch driver.readItem(startingWith: prefix, in: menu) {
        case .found(let p):
            driver.note("item read at \(p.logText)")
            guard driver.click(p) else {
                _ = IconPlacement.close([menu], driver: driver, .clickRefused)
                return .refused
            }
            return .clicked
        case .absent:
            driver.note("item not in this menu")
            _ = IconPlacement.close([menu], driver: driver, .notInMenu)
            return .notInMenu
        case .unreadable:
            _ = IconPlacement.close([menu], driver: driver, .notShown)
            return .unreadable
        }
    }
}

extension MacroEffectsMac {
    static let consolidateItem = "Consolidate"
    static let consolidateWhere = String(localized: "seulement dans la Playlist : clique sur le nom d'une piste de la Playlist, puis relance")

    func consolidateTrack(ctx: Context) -> StepResult {
        guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel(String(localized: "relâche les touches du raccourci")) }
        defer { restoreCursor() }
        switch trackDot(ctx: ctx, notFound: Self.consolidateWhere) {
        case .success(let dot) where dot.page == .playlist:
            break
        case .success(let dot):
            MacroLog.shared.write("CONSOLIDATE", "clicked track is in the \(dot.page.rawValue)")
            return .fail(Self.consolidateWhere)
        case .failure(let stop):
            return result(stop)
        }
        switch TrackMenuPick.pick(Self.consolidateItem, at: ctx.track, driver: FLIconDriver(fx: self)) {
        case .clicked:
            MacroLog.shared.write("CONSOLIDATE", "Consolidate clicked")
            return .ok
        case .stopped: return .cancel(IconPlacement.Failure.stopped.message)
        case .refused: return .fail(IconPlacement.Failure.clickRefused.message)
        case .noMenu: return .fail(String(localized: "le menu de la piste ne s'est pas ouvert"))
        case .notInMenu: return .fail(Self.consolidateWhere)
        case .unreadable:
            return .fail(String(localized: "autorise « Enregistrement de l'écran » : « Consolidate » est retrouvé dans le menu de FL"))
        }
    }
}
