// Dernier clic gauche dans FL : position de l'événement (pas le curseur relu plus tard), fenêtre de FL où il est tombé
// (numéro et taille : la macro refuse un point dont la fenêtre a depuis été fermée ou redimensionnée) ; le clic qui
// met FL au premier plan est gardé aussi (propriétaire de la fenêtre normale tout devant sous le clic).
import AppKit

final class TrackMemory {
    static let shared = TrackMemory()

    struct Click {
        let point: CGPoint
        let date: Date
        let window: Int
        let windowSize: CGSize
    }

    private var monitor: Any?
    private let last = Locked<Click?>(nil)

    private init() {}

    /// Thread principal.
    func setActive(_ on: Bool) {
        if on, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == EventTap.mark { return }
                if MacroRunner.shared.isRunning { return }
                let p = event.cgEvent?.location ?? FLWindows.cursor()
                let cfg = EventTap.shared.currentConfig
                let target: Int32
                if cfg.flPIDs.contains(cfg.frontmostPID) {
                    target = cfg.frontmostPID
                } else if let top = FLWindows.topNormalWindow(at: p), cfg.flPIDs.contains(top.pid) {
                    target = top.pid                                   // clic d'activation sur FL
                } else {
                    return
                }
                // Fenêtre normale (niveau 0) de FL seulement : les clics dans les menus de FL ne sont pas « la piste ».
                guard let w = WinSnapshot.take(pid: target).hit(p), w.layer == 0 else { return }
                self?.last.withLock { $0 = Click(point: p, date: Date(), window: w.number, windowSize: w.bounds.size) }
            }
        } else if !on, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    func lastClickInfo(maxAge: TimeInterval = 600) -> Click? {
        guard let l = last.value, Date().timeIntervalSince(l.date) < maxAge else { return nil }
        return l
    }

    /// Gardé pour les appelants existants.
    func lastClick(maxAge: TimeInterval = 600) -> CGPoint? { lastClickInfo(maxAge: maxAge)?.point }
}
