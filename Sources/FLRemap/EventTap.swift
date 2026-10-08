import AppKit
import CoreGraphics

/// Intercepte le clavier au niveau du système et applique les remaps quand FL Studio est au premier plan.
final class EventTap {
    static let shared = EventTap()
    /// Marque nos propres événements pour ne pas les intercepter une deuxième fois ("FLRP").
    static let mark: Int64 = 0x464C5250

    private var tap: CFMachPort?
    private var swallowed = Set<Int64>()

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: eventTapCallback,
                                          userInfo: nil) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // macOS coupe un eventtap jugé trop lent : on le relance aussitôt.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.mark { return pass }

        let store = Store.shared
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyUp {
            return swallowed.remove(code) != nil ? nil : pass
        }
        guard type == .keyDown else { return pass }

        let combo = KeyCombo(keyCode: UInt16(truncatingIfNeeded: code), flags: event.flags)

        // ⌃⌥⌘F : activer / désactiver, fonctionne partout
        if combo == store.toggleCombo {
            swallowed.insert(code)
            DispatchQueue.main.async { store.enabled.toggle() }
            return nil
        }

        guard store.enabled, Self.flStudioIsFrontmost(), let remap = store.index[combo] else { return pass }

        swallowed.insert(code)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        switch remap.kind {
        case .keystroke:
            if let target = remap.target { Self.post(target) }
        case .flAction:
            if !isRepeat { MIDIOut.shared.send(cc: remap.action.cc) }
        }
        return nil
    }

    static func flStudioIsFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.localizedName ?? ""
        return bundle.contains("image-line") || name.contains("FL Studio")
    }

    private static func post(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down) else { continue }
            e.flags = combo.cgFlags
            e.setIntegerValueField(.eventSourceUserData, value: mark)
            e.post(tap: .cgSessionEventTap)
        }
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    EventTap.shared.handle(type: type, event: event)
}
