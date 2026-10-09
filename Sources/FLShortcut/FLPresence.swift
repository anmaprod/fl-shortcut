// Audit : SEC-04 (FL identifié par bundle ID exact, jamais par sous-chaîne de nom), audit 04 §3 (FL Studio
//         Mobile / Remote exclus ; version lue dans le bundle pour griser les actions avant le handshake),
//         REL-05 (ensemble des PID de FL tenu à jour par notifications), SEC-11 / REL-04 (purge des appuis
//         sur changement d'appli au premier plan), REL-28 (vérification en temps constant dans le tap).
import AppKit
import Combine
import Foundation

enum FLMatcher {
    /// Liste blanche exacte. « FL Studio Mobile », « FL Studio Remote » et tout autre identifiant
    /// contenant « image-line » sont exclus.
    static let bundleIDs: Set<String> = ["com.image-line.flstudio"]

    static func isFL(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return bundleIDs.contains(id)
    }
}

enum FLDetector {
    /// Version lue dans l'Info.plist du bundle (`CFBundleShortVersionString`, sinon `CFBundleVersion`).
    static func version(atBundle url: URL) -> FLVersion? {
        guard let bundle = Bundle(url: url) else { return nil }
        let text = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        return text.flatMap(FLVersion.init)
    }

    /// Version de l'app FL installée (même si elle ne tourne pas).
    static func installedVersion() -> FLVersion? {
        for id in FLMatcher.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), let v = version(atBundle: url) {
                return v
            }
        }
        return nil
    }
}

/// Suit FL Studio (thread principal) et pousse PID / premier plan vers le tap.
final class FLMonitor: ObservableObject {
    static let shared = FLMonitor()

    @Published private(set) var running = false
    @Published private(set) var frontmost = false
    @Published private(set) var version: FLVersion? = nil

    private var observers: [NSObjectProtocol] = []
    private var pids: Set<pid_t> = []
    private var frontPID: pid_t = 0

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didLaunchApplicationNotification,
                                          NSWorkspace.didTerminateApplicationNotification,
                                          NSWorkspace.didActivateApplicationNotification,
                                          NSWorkspace.didDeactivateApplicationNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        refresh()
    }

    func refresh() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && FLMatcher.isFL(bundleID: $0.bundleIdentifier)
        }
        let newPIDs = Set(apps.map(\.processIdentifier))
        let newFront = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0

        if newPIDs != pids || version == nil {
            version = apps.first?.bundleURL.flatMap(FLDetector.version(atBundle:)) ?? FLDetector.installedVersion()
        }
        let frontChanged = newFront != frontPID
        pids = newPIDs
        frontPID = newFront

        EventTap.shared.updateConfig {
            $0.flPIDs = newPIDs
            $0.frontmostPID = newFront
        }
        if frontChanged { EventTap.shared.purge() }
        EventTap.shared.setActive(newPIDs.contains(newFront))
        MIDILink.shared.setFLRunning(!newPIDs.isEmpty)

        let isRunning = !newPIDs.isEmpty
        let isFront = newPIDs.contains(newFront)
        if running != isRunning { running = isRunning }
        if frontmost != isFront { frontmost = isFront }
    }
}
