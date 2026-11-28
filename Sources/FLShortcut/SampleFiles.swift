// Fichier de son d'un clip audio de FL, lu directement par l'Organiser (analyse sur le fichier) : plus besoin de le
// faire jouer par FL. Une prise de voix commence souvent par un long silence : jouée dans FL, l'écoute n'entendait
// que ce silence ou du bruit (projets de voix du propriétaire, voix rangées en Mélodies, FX ou Drums), et l'attente
// durait. Ici, le passage le plus fort du fichier est pris, en un instant. Le chemin écrit par FL est retrouvé sur le
// disque (dossiers de FL à la place de leurs noms, dossier du projet, sinon Spotlight au nom du fichier) ; rien
// n'est journalisé de ses noms. Même principe prévu pour Windows (Media Foundation).
import AppKit
import AVFoundation
import Foundation

/// Un passage de son, en mono.
struct SampleSound: Equatable {
    var samples: [Float]
    var rate: Double
}

enum SampleFiles {
    /// Pur (testé) : où peut être le fichier, dans l'ordre. Le chemin tel quel s'il est complet ; les dossiers de FL
    /// à la place de leurs noms (« %FLStudioFactoryData% », « %FLStudioUserData% ») ; sinon à côté du projet (chemin
    /// relatif, ou le seul nom du fichier, dans le dossier du projet et ses sous-dossiers habituels).
    static func candidates(_ path: String, project: URL, factory: [URL], user: [URL]) -> [URL] {
        let clean = path.replacingOccurrences(of: "\\", with: "/")
        var out: [URL] = []
        func add(_ url: URL) { if !out.contains(url) { out.append(url) } }
        let variables: [(String, [URL])] = [("%FLStudioFactoryData%", factory), ("%FLStudioUserData%", user)]
        var replaced = false
        for (name, folders) in variables where clean.range(of: name, options: .caseInsensitive) != nil {
            replaced = true
            let rest = clean.replacingOccurrences(of: name, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            for folder in folders { add(folder.appendingPathComponent(rest)) }
        }
        let folder = project.deletingLastPathComponent()
        if !replaced {
            if clean.hasPrefix("/") {
                add(URL(fileURLWithPath: clean))
            } else if !clean.contains("%") {
                add(folder.appendingPathComponent(clean))
            }
        }
        let file = (clean as NSString).lastPathComponent
        if !file.isEmpty {
            let base = project.deletingPathExtension().lastPathComponent
            for sub in ["", "Recorded", "Audio", "Samples", base, base + "/Recorded", base + "/Audio"] {
                add(sub.isEmpty ? folder.appendingPathComponent(file)
                    : folder.appendingPathComponent(sub).appendingPathComponent(file))
            }
        }
        return out
    }

    /// Le premier qui existe ; sinon un fichier du même nom trouvé ailleurs (`search`), de préférence dans un dossier
    /// du même nom.
    static func resolve(_ path: String, project: URL, factory: [URL], user: [URL], exists: (URL) -> Bool,
                        search: (String) -> [URL]) -> URL? {
        if let found = candidates(path, project: project, factory: factory, user: user).first(where: exists) {
            return found
        }
        let clean = path.replacingOccurrences(of: "\\", with: "/")
        let file = (clean as NSString).lastPathComponent
        guard !file.isEmpty else { return nil }
        let parent = ((clean as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let found = search(file)
        return found.first { $0.deletingLastPathComponent().lastPathComponent == parent } ?? found.first
    }

    /// Dossiers de FL sur ce Mac : les données d'usine dans l'app (celle qui tourne d'abord), celles de l'utilisateur
    /// dans Documents.
    static func liveFolders() -> (factory: [URL], user: [URL]) {
        var apps: [URL] = []
        if let pid = OrganizerEnvironment.flPID(), let url = NSRunningApplication(processIdentifier: pid)?.bundleURL {
            apps.append(url)
        }
        let applications = URL(fileURLWithPath: "/Applications")
        let installed = (try? FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil)) ?? []
        apps += installed.filter { $0.lastPathComponent.hasPrefix("FL Studio") && $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        let factory = apps.map { $0.appendingPathComponent("Contents/Resources/FL") }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let user = [home.appendingPathComponent("Documents/Image-Line/FL Studio")]
        return (factory, user)
    }

    /// Spotlight, au nom exact du fichier (3 secondes au plus, 20 au plus).
    static func spotlight(_ file: String) -> [URL] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        let quoted = file.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        task.arguments = ["kMDItemFSName == \"\(quoted)\""]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let deadline = Date().addingTimeInterval(3)
        while task.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if task.isRunning { task.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(20)
        return lines.map { URL(fileURLWithPath: String($0)) }
    }

    /// Lecture réelle : le fichier retrouvé, puis son passage le plus fort.
    static func liveReader() -> (String, URL) -> SampleSound? {
        let folders = liveFolders()
        return { path, project in
            guard let url = resolve(path, project: project, factory: folders.factory, user: folders.user,
                                    exists: { FileManager.default.isReadableFile(atPath: $0.path) },
                                    search: { spotlight($0) }) else { return nil }
            return SampleAudio.loudest(url)
        }
    }
}

enum SampleAudio {
    /// Tranche de mesure de l'énergie (secondes).
    static let block = 0.1
    /// 10 minutes lues au plus.
    static let maxSeconds = 600.0

    /// Le passage le plus fort du fichier, `seconds` au plus, en mono ; nil s'il ne se lit pas (format inconnu).
    static func loudest(_ url: URL, seconds: Double = 3) -> SampleSound? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        guard rate >= 8_000, file.length > 0 else { return nil }
        let frames = min(file.length, AVAudioFramePosition(rate * maxSeconds))
        let perBlock = max(1, Int(rate * block))
        // Énergie de chaque tranche, le fichier lu une fois par morceaux de 10 s.
        var energies: [Float] = []
        var carry: [Float] = []
        var read: AVAudioFramePosition = 0
        let chunk = AVAudioFramePosition(rate * 10)
        while read < frames {
            let want = AVAudioFrameCount(min(chunk, frames - read))
            guard let mono = readMono(file, format: format, frames: want), !mono.isEmpty else { break }
            read += AVAudioFramePosition(mono.count)
            carry += mono
            var at = 0
            while carry.count - at >= perBlock {
                energies.append(rms(carry[at..<at + perBlock]))
                at += perBlock
            }
            carry.removeFirst(at)
        }
        if !carry.isEmpty { energies.append(rms(carry[...])) }
        guard !energies.isEmpty else { return nil }
        let start = loudestStart(energies, window: max(1, Int((seconds / block).rounded())))
        let from = min(AVAudioFramePosition(start * perBlock), frames)
        file.framePosition = from
        let length = AVAudioFrameCount(min(AVAudioFramePosition(rate * seconds), frames - from))
        guard length > 0, let samples = readMono(file, format: format, frames: length) else { return nil }
        return SampleSound(samples: samples, rate: rate)
    }

    /// Pur (testé) : la tranche où commence le passage le plus fort de `window` tranches ; le silence du début de ce
    /// passage est sauté (un son court commence à son attaque).
    static func loudestStart(_ energies: [Float], window: Int) -> Int {
        guard !energies.isEmpty else { return 0 }
        let w = max(1, min(window, energies.count))
        var sum: Float = energies[0..<w].reduce(0, +)
        var bestStart = 0
        var bestSum = sum
        if energies.count > w {
            for i in 1...(energies.count - w) {
                sum += energies[i + w - 1] - energies[i - 1]
                if sum > bestSum {
                    bestSum = sum
                    bestStart = i
                }
            }
        }
        let peak = energies.max() ?? 0
        var start = bestStart
        while start < bestStart + w - 1, start < energies.count - 1, energies[start] < peak * 0.05 { start += 1 }
        return start
    }

    private static func readMono(_ file: AVAudioFile, format: AVAudioFormat, frames: AVAudioFrameCount) -> [Float]? {
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        do { try file.read(into: buffer, frameCount: frames) } catch { return nil }
        let n = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        guard n > 0 else { return [] }
        guard channels > 0, let data = buffer.floatChannelData else { return nil }
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            let p = data[c]
            for i in 0..<n { mono[i] += p[i] }
        }
        if channels > 1 {
            let scale = 1 / Float(channels)
            for i in 0..<n { mono[i] *= scale }
        }
        return mono
    }

    private static func rms(_ slice: ArraySlice<Float>) -> Float {
        guard !slice.isEmpty else { return 0 }
        var sum: Float = 0
        for v in slice { sum += v * v }
        return (sum / Float(slice.count)).squareRoot()
    }
}
