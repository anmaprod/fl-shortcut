// Per-run macro log: ~/Library/Logs/FL Shortcut/macro.log (0600, dir 0700), rotated at 1 MB, 3 old files kept.
// Contents: timestamps, steps and results, FL window lists (number, layer, bounds), click points, AX hit-tests,
// learned geometry. NEVER: key codes, typed text, file paths, window titles (CG titles are never even read).
// Also mirrored to the unified log (subsystem app.flshortcut.FLShortcut, category macro).
import AppKit
import CoreGraphics
import Foundation
import os
import UniformTypeIdentifiers

final class MacroLog: @unchecked Sendable {
    static let shared = MacroLog()

    static let maxBytes: UInt64 = 1_000_000
    static let keepFiles = 3

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FL Shortcut", isDirectory: true)
    }
    static var current: URL { directory.appendingPathComponent("macro.log") }
    static func rotated(_ i: Int) -> URL { directory.appendingPathComponent("macro.\(i).log") }

    private let queue = DispatchQueue(label: "app.flshortcut.macro-log", qos: .utility)
    private let logger = Logger(subsystem: "app.flshortcut.FLShortcut", category: "macro")
    private let run = Locked<(id: String, t0: UInt64)>(("------", 0))
    private var handle: FileHandle?          // queue only
    private var written: UInt64 = 0          // queue only
    private let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    /// `defaults write app.flshortcut.FLShortcut macroLogVerbose -bool YES`: full window list at every poll change.
    var verbose: Bool { UserDefaults.standard.bool(forKey: "macroLogVerbose") }

    func beginRun(_ title: String, flPID: Int32) {
        run.withLock { $0 = (String(UUID().uuidString.prefix(6)), DispatchTime.now().uptimeNanoseconds) }
        queue.async { self.rotateIfNeeded() }
        write("RUN", "==== \(title) ====")
        for line in Self.environment(flPID: flPID) { write("ENV", line) }
    }

    func endRun(_ outcome: String) {
        write("END", outcome)
        queue.async { try? self.handle?.synchronize() }
    }

    /// Blocks until everything queued is on disk (CLI probe before exit()).
    func flush() { queue.sync { try? self.handle?.synchronize() } }

    func write(_ tag: String, _ text: String) {
        let (id, t0) = run.value
        let now = Date()
        let elapsed = t0 == 0 ? 0 : Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1e9
        logger.info("\(tag, privacy: .public) \(text, privacy: .public)")
        queue.async {
            let tagCol = tag.padding(toLength: 5, withPad: " ", startingAt: 0)
            self.append("\(self.stamp.string(from: now)) +\(String(format: "%7.3f", elapsed))s [\(id)] \(tagCol) \(text)\n")
        }
    }

    func windows(_ label: String, _ snap: WinSnapshot, mark: Set<Int> = []) {
        var line = "\(label): \(snap.fl.count) FL: " + snap.fl.map { (mark.contains($0.number) ? "*" : "") + $0.description }
            .joined(separator: " | ")
        if !snap.panelService.isEmpty { line += " || panel service: " + snap.panelService.map(\.description).joined(separator: " | ") }
        write("WIN", line)
    }

    /// Old files first, then the current one, concatenated into `url`.
    func export(to url: URL, completion: @escaping (Error?) -> Void) {
        queue.async {
            try? self.handle?.synchronize()
            var data = Data()
            let files = (1...Self.keepFiles).reversed().map { Self.rotated($0) } + [Self.current]
            for f in files where SecureFile.kind(at: f.path) == .regular {
                if let d = try? Data(contentsOf: f) { data.append(d) }
            }
            do { try data.write(to: url, options: .atomic); completion(nil) } catch { completion(error) }
        }
    }

    // MARK: File (queue only)

    private func append(_ line: String) {
        if handle == nil { open() }
        guard let handle, written < Self.maxBytes * 4, let data = line.data(using: .utf8) else { return }   // runaway guard
        do {
            try handle.write(contentsOf: data)
            written += UInt64(data.count)
        } catch {
            self.handle = nil
        }
    }

    private func open() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try SecureFile.checkDirectory(Self.directory)              // real dir, owned by the user, not a link
            let path = Self.current.path
            switch SecureFile.kind(at: path) {
            case .none: _ = fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
            case .regular: break
            default: return                                            // symlink or odd file: never write through it
            }
            let h = try FileHandle(forWritingTo: Self.current)
            written = try h.seekToEnd()
            handle = h
        } catch {
            handle = nil
        }
    }

    /// At the start of a run only, so one run never straddles two files.
    private func rotateIfNeeded() {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: Self.current.path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > Self.maxBytes else { return }
        try? handle?.close()
        handle = nil
        try? fm.removeItem(at: Self.rotated(Self.keepFiles))
        for i in stride(from: Self.keepFiles - 1, through: 1, by: -1) {
            try? fm.moveItem(at: Self.rotated(i), to: Self.rotated(i + 1))
        }
        try? fm.moveItem(at: Self.current, to: Self.rotated(1))
    }

    // MARK: Header

    static func environment(flPID: Int32) -> [String] {
        var out: [String] = []
        let info = Bundle.main.infoDictionary
        out.append("FL Shortcut \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
                   + " · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out.append("AX trusted \(AXIsProcessTrusted()) · post access \(CGPreflightPostEventAccess())"
                   + " · warpCursor \(MacroRunner.warpCursor) · clicksToPid \(MacroRunner.clicksToPid)")
        if let app = NSRunningApplication(processIdentifier: flPID) {
            let version = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "?"
            out.append("FL pid \(flPID) \(app.bundleIdentifier ?? "?") \(version)")
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        if CGGetActiveDisplayList(8, &ids, &count) == .success {
            for id in ids.prefix(Int(count)) {
                let b = CGDisplayBounds(id)
                out.append("display \(id)\(CGDisplayIsMain(id) != 0 ? " main" : "") (\(Int(b.minX)),\(Int(b.minY))) \(Int(b.width))x\(Int(b.height)) · \(CGDisplayPixelsWide(id)) px wide")
            }
        }
        for kind in MacroSpots.PathKind.allCases {
            out.append("learned \(kind.rawValue): " + (MacroSpots.loadPath(kind).map(MacroSpots.describe) ?? "none"))
        }
        return out
    }
}

/// UI hooks (main thread): « Exporter le journal des macros… » and « Afficher dans le Finder ».
enum MacroLogExport {
    static func run() {
        let panel = NSSavePanel()
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        panel.nameFieldStringValue = "FL Shortcut macro log \(day).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        MacroLog.shared.export(to: url) { error in
            DispatchQueue.main.async {
                if error == nil { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSSound.beep() }
            }
        }
    }

    static func revealInFinder() {
        let file = MacroLog.current
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(MacroLog.directory)
        }
    }
}
