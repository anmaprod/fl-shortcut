// Lecture de l'écran de FL pour les macros sans réglage (autorisation « Enregistrement de l'écran »).
// - Capture limitée aux SEULES fenêtres de FL (ScreenCaptureKit, filtre par processus) : jamais les autres apps.
// - Lecture du texte sur place (Vision, sans réseau) : menus « File », « Open mixer track state », « (none) »…
// - Couleurs et différences entre deux captures : bouton qui s'allume (REC, armement).
// - Rien n'est enregistré ni envoyé : les images restent en mémoire le temps d'une étape de macro,
//   sauf l'outil « Capturer FL » que l'utilisateur lance lui-même (fichiers sur son Bureau).
// Appels bloquants : file de la macro uniquement, jamais le thread principal ni celui du tap clavier.
import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import Vision

enum ScreenAccess {
    /// Autorisation déjà donnée (aucune fenêtre affichée).
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    /// Demande système (une seule fois), puis Réglages si elle a déjà été refusée.
    static func request() {
        if !CGRequestScreenCaptureAccess() { openSettings() }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Un morceau de texte lu à l'écran, en coordonnées globales CoreGraphics (origine en haut à gauche, points).
struct ScreenText: Equatable {
    let text: String
    let rect: CGRect
    let confidence: Float

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

/// Une capture d'une zone de l'écran (fenêtres de FL seulement) et sa correspondance avec l'écran.
struct ScreenShot {
    let image: CGImage
    let rect: CGRect                 // zone capturée, coordonnées globales en points

    var scale: CGFloat { CGFloat(image.width) / max(rect.width, 1) }

    /// Rectangle en pixels de l'image pour une zone de l'écran (bornée à l'image).
    func pixelRect(for r: CGRect) -> CGRect {
        let local = CGRect(x: (r.minX - rect.minX) * scale, y: (r.minY - rect.minY) * scale,
                           width: r.width * scale, height: r.height * scale)
        return local.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
    }
}

enum ScreenReader {
    // MARK: Capture

    /// Capture des fenêtres de FL dans `rect` (coordonnées globales). Nil sans autorisation ou si rien n'est visible.
    static func capture(pid: Int32, rect: CGRect, timeout: TimeInterval = 2) -> ScreenShot? {
        guard ScreenAccess.granted, rect.width >= 4, rect.height >= 4 else { return nil }
        guard #available(macOS 14.0, *) else { return nil }
        let box = Locked<CGImage?>(nil)
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            defer { done.signal() }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
            let windows = content.windows.filter { $0.owningApplication?.processID == pid }
            guard !windows.isEmpty,
                  let display = content.displays.first(where: { $0.frame.intersects(rect) }) ?? content.displays.first
            else { return }
            let area = rect.intersection(display.frame)
            guard !area.isNull, area.width >= 4, area.height >= 4 else { return }
            let filter = SCContentFilter(display: display, including: windows)
            let config = SCStreamConfiguration()
            config.sourceRect = area.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int((area.width * scale).rounded())
            config.height = Int((area.height * scale).rounded())
            config.showsCursor = false
            config.capturesAudio = false
            let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            box.withLock { $0 = image }
        }
        guard done.wait(timeout: .now() + timeout) == .success, let image = box.value else { return nil }
        // La zone réellement capturée est bornée à l'écran : on recalcule depuis la taille obtenue.
        let area = NSScreen.screens.map { $0.cgFrame }.first(where: { $0.intersects(rect) }).map { rect.intersection($0) } ?? rect
        return ScreenShot(image: image, rect: area)
    }

    // MARK: Texte

    /// Texte lu dans la capture (lignes, avec leur place à l'écran).
    static func texts(in shot: ScreenShot) -> [ScreenText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "fr-FR"]
        request.minimumTextHeight = 0.004
        let handler = VNImageRequestHandler(cgImage: shot.image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            return ScreenText(text: best.string, rect: screenRect(observation.boundingBox, in: shot), confidence: best.confidence)
        }
    }

    /// Premier texte qui correspond à l'un des libellés voulus (insensible à la casse, « … » et ponctuation finale
    /// ignorés). Le rectangle renvoyé est celui du mot cherché, pas de toute la ligne.
    static func find(_ wanted: [String], in shot: ScreenShot) -> ScreenText? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "fr-FR"]
        request.minimumTextHeight = 0.004
        let handler = VNImageRequestHandler(cgImage: shot.image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        let targets = wanted.map(normalized)
        for observation in request.results ?? [] {
            for candidate in observation.topCandidates(3) {
                let line = candidate.string
                let norm = normalized(line)
                for target in targets where !target.isEmpty {
                    guard let r = norm.range(of: target) else { continue }
                    // Mot isolé : « file » ne doit pas correspondre à « profile ».
                    let before = r.lowerBound == norm.startIndex ? " " : norm[norm.index(before: r.lowerBound)]
                    let after = r.upperBound == norm.endIndex ? " " : norm[r.upperBound]
                    guard !before.isLetter, !after.isLetter else { continue }
                    let offset = norm.distance(from: norm.startIndex, to: r.lowerBound)
                    var box = observation.boundingBox
                    if let start = line.index(line.startIndex, offsetBy: offset, limitedBy: line.endIndex),
                       let end = line.index(start, offsetBy: target.count, limitedBy: line.endIndex),
                       let sub = try? candidate.boundingBox(for: start..<end) {
                        box = sub.boundingBox
                    }
                    return ScreenText(text: line, rect: screenRect(box, in: shot), confidence: candidate.confidence)
                }
            }
        }
        return nil
    }

    static func normalized(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, last == "." || last == ":" { t.removeLast() }
        return t
    }

    private static func screenRect(_ normalizedBox: CGRect, in shot: ScreenShot) -> CGRect {
        CGRect(x: shot.rect.minX + normalizedBox.minX * shot.rect.width,
               y: shot.rect.minY + (1 - normalizedBox.maxY) * shot.rect.height,
               width: normalizedBox.width * shot.rect.width,
               height: normalizedBox.height * shot.rect.height)
    }

    // MARK: Couleurs

    /// Pixels RGBA 8 bits de la capture (lecture une fois par analyse).
    struct Pixels {
        let width: Int
        let height: Int
        let data: [UInt8]

        init?(_ image: CGImage) {
            let w = image.width, h = image.height
            guard w > 0, h > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                // Dans la mémoire d'un contexte bitmap, la ligne 0 est le haut de l'image (comme l'écran).
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            width = w
            height = h
            data = buffer
        }

        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let i = (y * width + x) * 4
            return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
        }
    }

    /// Part des pixels « allumés » (rouge, orange ou jaune vifs : voyants d'armement et de REC) dans une zone (pixels).
    static func litFraction(_ pixels: Pixels, in rect: CGRect) -> Double {
        let r = rect.intersection(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)).integral
        guard r.width >= 1, r.height >= 1 else { return 0 }
        var lit = 0, total = 0
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) {
                let (red, green, blue) = pixels.rgb(x, y)
                let maxC = max(red, green, blue), minC = min(red, green, blue)
                let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                if maxC > 0.55 && saturation > 0.55 && red >= green && red > blue { lit += 1 }
                total += 1
            }
        }
        return total > 0 ? Double(lit) / Double(total) : 0
    }

    /// Zones qui ont changé entre deux captures de la même zone (cases de `cell` pixels, regroupées).
    static func changedBoxes(_ a: Pixels, _ b: Pixels, cell: Int = 6, threshold: Double = 0.12) -> [CGRect] {
        guard a.width == b.width, a.height == b.height else { return [] }
        var hot: [CGRect] = []
        var y = 0
        while y < a.height {
            var x = 0
            while x < a.width {
                var diff = 0.0, n = 0
                for yy in y..<min(y + cell, a.height) {
                    for xx in x..<min(x + cell, a.width) {
                        let p = a.rgb(xx, yy), q = b.rgb(xx, yy)
                        diff += abs(p.0 - q.0) + abs(p.1 - q.1) + abs(p.2 - q.2)
                        n += 1
                    }
                }
                if n > 0, diff / Double(n * 3) > threshold {
                    hot.append(CGRect(x: x, y: y, width: cell, height: cell))
                }
                x += cell
            }
            y += cell
        }
        // Regroupement simple : cases qui se touchent.
        var groups: [CGRect] = []
        for box in hot {
            if let i = groups.firstIndex(where: { $0.insetBy(dx: -1, dy: -1).intersects(box) }) {
                groups[i] = groups[i].union(box)
            } else {
                groups.append(box)
            }
        }
        return groups
    }
}

extension NSScreen {
    /// Cadre de l'écran en coordonnées globales CoreGraphics (origine en haut à gauche de l'écran principal).
    var cgFrame: CGRect {
        let main = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: main - frame.maxY, width: frame.width, height: frame.height)
    }
}

// MARK: - Piste visée

/// Dernier clic gauche dans FL (position seulement) : « la piste sur laquelle j'ai cliqué ».
/// Moniteur global de souris (permission Accessibilité déjà donnée pour le clavier), actif seulement si une macro
/// automatique existe. Thread principal.
final class TrackMemory {
    static let shared = TrackMemory()

    private var monitor: Any?
    private let last = Locked<(point: CGPoint, date: Date)?>(nil)

    private init() {}

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
    func lastClick(maxAge: TimeInterval = 1800) -> CGPoint? {
        guard let l = last.value, Date().timeIntervalSince(l.date) < maxAge else { return nil }
        return l.point
    }
}

// MARK: - Captures pour le réglage (lancées par l'utilisateur)

/// « Capturer FL » : enregistre sur le Bureau ce que l'app voit de FL (une image par fenêtre de FL, le texte lu,
/// les appareils audio), pour régler la macro sur l'apparence de FL. Rien n'est envoyé : l'utilisateur choisit
/// de partager le dossier ou non.
enum FLCapture {
    static func run(pid: Int32, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            let dir = desktop.appendingPathComponent("FL Shortcut – captures/\(stamp)", isDirectory: true)
            guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var report: [String] = ["Fenêtres de FL (avant → arrière) :"]
            let windows = FLWindows.list(pid: pid).filter { $0.bounds.width > 40 && $0.bounds.height > 20 }
            for (i, w) in windows.enumerated() {
                let b = w.bounds
                report.append("  \(i + 1). niveau \(w.layer) · \(Int(b.width))×\(Int(b.height)) en (\(Int(b.minX)), \(Int(b.minY)))")
                guard let shot = ScreenReader.capture(pid: pid, rect: b) else { continue }
                save(shot.image, to: dir.appendingPathComponent("fenetre-\(i + 1).png"))
                report.append("     texte lu :")
                for t in ScreenReader.texts(in: shot) {
                    report.append("       « \(t.text) » en (\(Int(t.rect.minX)), \(Int(t.rect.minY))) \(Int(t.rect.width))×\(Int(t.rect.height))")
                }
            }
            if let last = TrackMemory.shared.lastClick() {
                report.append("Dernier clic dans FL : (\(Int(last.x)), \(Int(last.y)))")
            }
            let audio = FeedbackRisk.check(flPID: pid)
            report.append("Entrée audio : \(audio.input.map { "\($0.name)\($0.builtIn ? " (intégré)" : "")" } ?? "?")")
            report.append("Sortie audio : \(audio.output.map { "\($0.name)\($0.builtIn ? " (intégré)" : "")\($0.headphones ? " (casque)" : "")" } ?? "?")")
            report.append("Risque de larsen : \(audio.risky ? "oui" : "non")")
            report.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            try? report.joined(separator: "\n").write(to: dir.appendingPathComponent("rapport.txt"), atomically: true, encoding: .utf8)
            DispatchQueue.main.async { completion(dir) }
        }
    }

    private static func save(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
