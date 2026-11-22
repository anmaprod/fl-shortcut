// Fichiers venus d'ailleurs (21/11, « rendre ce logiciel très sécurisé ») : une macro de la Communauté, des raccourcis
// partagés, un projet de FL abîmé ne doivent jamais faire tomber l'app. Des milliers de versions abîmées exprès (octets
// changés, coupés, ajoutés ; valeurs JSON remplacées ou retirées) : une erreur lancée est permise (l'app l'attrape et la
// montre), un arrêt net (index hors limite, dépassement, valeur forcée) ne l'est pas : il ferait tomber cet essai.
// Graine fixe : un échec se rejoue à l'identique. Miroir de RobustnessTests (Windows), qui a trouvé trois défauts.
import XCTest
@testable import FLShortcut

final class RobustnessTests: XCTestCase {
    /// Tirage reproductible (SplitMix64).
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testADamagedMacroNeverCrashes() throws {
        var rng = Seeded(state: 2111)
        var runs = 0
        for template in MacroTemplates.gallery(layout: FakeLayout.qwerty) {
            let valid = try MacroExchange.export(template.make(FakeLayout.qwerty), appVersion: "1.2", home: "/Users/flshortcuts")
            for i in 0..<1200 {
                let data = i < 400 ? Self.bytes(valid, &rng) : Self.json(valid, &rng)
                _ = try? MacroExchange.prepareImport(data, home: "/Users/autre", layout: FakeLayout.qwerty,
                                                     presets: "/Users/autre/Documents/FL Shortcuts/Presets",
                                                     existing: { _ in nil }, installed: { _ in ["Vital"] })
                runs += 1
            }
        }
        XCTAssertGreaterThan(runs, 0)
    }

    func testDamagedSharedShortcutsNeverCrash() throws {
        var rng = Seeded(state: 2112)
        for preset in ProfilePreset.allCases {
            let valid = try ProfileCodec.encode(preset.remaps(layout: FakeLayout.qwerty))
            for i in 0..<900 {
                let data = i < 300 ? Self.bytes(valid, &rng) : Self.json(valid, &rng)
                _ = try? ProfileImporter.prepare(data, forbidden: .physical, layout: FakeLayout.qwerty)
            }
        }
    }

    func testADamagedProjectNeverCrashes() {
        var rng = Seeded(state: 2113)
        let valid = Data(FLPSample.sample().encoded())
        for _ in 0..<4000 {
            let data = Self.bytes(valid, &rng)
            guard let file = try? FLPFile(bytes: [UInt8](data)), let project = try? FLPProject(file) else { continue }
            _ = try? project.splitByChannel(file)
        }
    }

    // MARK: fichiers abîmés

    /// Des octets changés, coupés, ajoutés, retirés ou doublés.
    private static func bytes(_ source: Data, _ rng: inout Seeded) -> Data {
        var b = [UInt8](source)
        switch Int.random(in: 0..<5, using: &rng) {
        case 0:
            for _ in 0..<Int.random(in: 1...8, using: &rng) where !b.isEmpty {
                b[Int.random(in: 0..<b.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng)
            }
        case 1:
            b = Array(b.prefix(Int.random(in: 0...b.count, using: &rng)))
        case 2:
            let extra = (0..<Int.random(in: 1...63, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            b.insert(contentsOf: extra, at: Int.random(in: 0...b.count, using: &rng))
        case 3:
            if b.count > 1 {
                let start = Int.random(in: 0..<b.count, using: &rng)
                b.removeSubrange(start..<min(b.count, start + Int.random(in: 1...64, using: &rng)))
            }
        default:
            if b.count > 1 {
                let start = Int.random(in: 0..<b.count, using: &rng)
                let piece = Array(b[start..<min(b.count, start + Int.random(in: 1...127, using: &rng))])
                b.insert(contentsOf: piece, at: start)
            }
        }
        return Data(b)
    }

    /// Une valeur du JSON remplacée par une autre d'un autre genre, ou retirée (le fichier reste du JSON).
    private static func json(_ source: Data, _ rng: inout Seeded) -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: source, options: [.fragmentsAllowed]) else { return source }
        for _ in 0..<Int.random(in: 1...3, using: &rng) {
            var paths: [[Any]] = []
            collect(root, [], &paths)
            guard !paths.isEmpty else { break }
            let path = paths[Int.random(in: 0..<paths.count, using: &rng)]
            let remove = Int.random(in: 0..<5, using: &rng) == 0
            root = replaced(root, path[...], with: remove ? nil : value(&rng))
        }
        return (try? JSONSerialization.data(withJSONObject: root, options: [.fragmentsAllowed])) ?? source
    }

    private static func collect(_ node: Any, _ path: [Any], _ out: inout [[Any]]) {
        if let object = node as? [String: Any] {
            for (key, child) in object {
                out.append(path + [key])
                collect(child, path + [key], &out)
            }
        } else if let array = node as? [Any] {
            for (index, child) in array.enumerated() {
                out.append(path + [index])
                collect(child, path + [index], &out)
            }
        }
    }

    /// `new` nil : la valeur est retirée.
    private static func replaced(_ node: Any, _ path: ArraySlice<Any>, with new: Any?) -> Any {
        guard let head = path.first else { return new ?? NSNull() }
        if var object = node as? [String: Any], let key = head as? String, let child = object[key] {
            if path.count == 1 && new == nil { object.removeValue(forKey: key) } else {
                object[key] = replaced(child, path.dropFirst(), with: new)
            }
            return object
        }
        if var array = node as? [Any], let index = head as? Int, index < array.count {
            if path.count == 1 && new == nil { array.remove(at: index) } else {
                array[index] = replaced(array[index], path.dropFirst(), with: new)
            }
            return array
        }
        return node
    }

    private static func value(_ rng: inout Seeded) -> Any {
        switch Int.random(in: 0..<13, using: &rng) {
        case 0: return NSNull()
        case 1: return true
        case 2: return -1
        case 3: return 0
        case 4: return 1e308
        case 5: return Int64.max
        case 6: return ""
        case 7: return "x"
        case 8: return String(repeating: "é", count: 20_000)
        case 9: return [Any]()
        case 10: return [String: Any]()
        case 11: return Int64(Int32.min)
        default:
            var nested: Any = [Any]()
            for _ in 0..<Int.random(in: 1...200, using: &rng) { nested = [nested] }
            return nested
        }
    }
}
