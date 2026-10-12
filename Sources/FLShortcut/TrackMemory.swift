// Last left click in FL: event location (not the cursor read later), the FL window it landed in (number and
// size: the macro refuses a point whose window has since closed or changed size), and the click that brings
// FL to the front is kept too (owner of the topmost normal window under the click).
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

    /// Main thread.
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
                    target = top.pid                                   // activation click on FL
                } else {
                    return
                }
                // Normal-level FL window only: clicks in FL's menus / popups are not "the track".
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

    /// Kept for existing callers.
    func lastClick(maxAge: TimeInterval = 600) -> CGPoint? { lastClickInfo(maxAge: maxAge)?.point }
}
