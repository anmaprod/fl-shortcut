// Mesure du temps de réponse de FL Studio : `FLShortcut --mesure`.
// Aucune action n'est exécutée dans FL : on chronomètre
//   - un PING jusqu'au début du HELLO (1 message envoyé, réponse du script) ;
//   - une trame complète de 8 messages portant un id d'action inconnu (127), que le script refuse avant toute
//     vérification et à laquelle il répond par l'accusé 0 (CC 119). C'est le même chemin qu'une vraie action.
// Rien n'est lu au clavier ; seules des durées sont affichées.
import CoreMIDI
import Foundation

enum Bench {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--mesure") else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        let transport = CoreMIDITransport()
        let lock = NSLock()
        var parser = MIDIByteParser()
        var expected: (cc: UInt8, value: UInt8?)? = nil
        let hit = DispatchSemaphore(value: 0)
        transport.onBytes = { bytes in
            lock.lock(); defer { lock.unlock() }
            for m in parser.feed(bytes) where m.status == FLProtocol.statusCC {
                if let e = expected, m.data1 == e.cc, e.value == nil || m.data2 == e.value! {
                    expected = nil
                    hit.signal()
                }
            }
        }
        guard transport.connect() else { print("MIDI indisponible"); exit(1) }

        func roundTrip(_ messages: [CCMessage], cc: UInt8, value: UInt8?, timeout: Double = 1.5) -> Double? {
            while hit.wait(timeout: .now()) == .success {}          // vide un éventuel signal en retard
            lock.lock(); expected = (cc, value); lock.unlock()
            let t0 = DispatchTime.now().uptimeNanoseconds
            guard transport.send(messages) else { return nil }
            guard hit.wait(timeout: .now() + timeout) == .success else {
                lock.lock(); expected = nil; lock.unlock()
                return nil
            }
            return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        }

        // FL doit d'abord retrouver le port (il réapparaît avec le même identifiant) : PING jusqu'à 20 s.
        print("Attente de FL…")
        var linked = false
        for _ in 0..<40 {
            if roundTrip([.ping], cc: FLProtocol.ccHello, value: 1, timeout: 0.5) != nil { linked = true; break }
        }
        guard linked else { print("FL ne répond pas (entrée/sortie « FL Shortcut » activées dans FL ?)"); exit(2) }
        Thread.sleep(forTimeInterval: 0.6)

        func report(_ name: String, _ values: [Double], lost: Int) {
            let s = values.sorted()
            guard !s.isEmpty else { print("\(name) : aucune réponse (\(lost) perdues)"); return }
            let med = s[s.count / 2], p90 = s[min(s.count - 1, Int(Double(s.count) * 0.9))]
            print(String(format: "%@ : médiane %.1f ms · 90 %% %.1f ms · min %.1f · max %.1f · %d mesures, %d perdues",
                         name, med, p90, s.first!, s.last!, s.count, lost))
        }

        var pings: [Double] = [], pingLost = 0
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.35)                      // le script ignore plus de 4 PING/s
            if let ms = roundTrip([.ping], cc: FLProtocol.ccHello, value: 1) { pings.append(ms) } else { pingLost += 1 }
        }
        let frame = [0, 0, 1, 127, 0, 0, 0, 0].enumerated().map {
            CCMessage(cc: FLProtocol.ccFrameFirst + UInt8($0.offset), value: UInt8($0.element))
        }
        var frames: [Double] = [], frameLost = 0
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.15)
            if let ms = roundTrip(frame, cc: FLProtocol.ccAck, value: 0) { frames.append(ms) } else { frameLost += 1 }
        }
        report("PING → réponse ", pings, lost: pingLost)
        report("Trame → accusé ", frames, lost: frameLost)
        transport.disconnect()
        exit(0)
    }
}
