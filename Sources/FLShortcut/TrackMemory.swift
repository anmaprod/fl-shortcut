// « La piste sur laquelle j'ai cliqué » pour les macros : position du dernier clic gauche dans FL.
// Moniteur global de souris (permission Accessibilité déjà donnée pour le clavier) : seule la position est
// retenue, seulement quand FL est au premier plan, et seulement s'il existe une macro automatique active.
import AppKit

final class TrackMemory {
    static let shared = TrackMemory()

    private var monitor: Any?
    private let last = Locked<(point: CGPoint, date: Date)?>(nil)

    private init() {}

    /// Thread principal.
    func setActive(_ on: Bool) {
        if on, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                let cfg = EventTap.shared.currentConfig
                guard cfg.flPIDs.contains(cfg.frontmostPID) else { return }
                let p = FLWindows.cursor()
                self?.last.withLock { $0 = (p, Date()) }
            }
        } else if !on, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    /// Dernier clic dans FL depuis moins de `maxAge` secondes.
    func lastClick(maxAge: TimeInterval = 600) -> CGPoint? {
        guard let l = last.value, Date().timeIntervalSince(l.date) < maxAge else { return nil }
        return l.point
    }
}
