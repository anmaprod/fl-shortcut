// Audit : REL-03 (état partagé entre le thread du tap et le thread principal, lecture thread-safe).
import os

/// Petit conteneur verrouillé (OSAllocatedUnfairLock, macOS 13+).
/// Les variantes « Unchecked » sont utilisées pour ne pas imposer `Sendable` aux types d'AppKit / CoreFoundation
/// (CFMachPort, CFRunLoop) que l'on y range. Ne jamais appeler `withLock` de façon réentrante.
final class Locked<State>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<State>

    init(_ initialState: State) {
        lock = OSAllocatedUnfairLock(uncheckedState: initialState)
    }

    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        try lock.withLockUnchecked(body)
    }

    /// Copie de l'état (les structures stockées ici sont immuables une fois publiées).
    var value: State {
        withLock { $0 }
    }
}
