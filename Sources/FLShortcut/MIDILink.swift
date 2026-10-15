// Audit : SEC-01 (trames signées, séquence monotone, nonce de session), SEC-02 (uniqueID aléatoire par
//         installation, source ET destination), SEC-10 (PING borné, resynchronisation limitée),
//         REL-06 (statut Relié / Lien inactif / FL fermé publié pour l'interface et le tap),
//         REL-07 (conflit d'uniqueID détecté), REL-10 (CoreMIDI surveillé, recréé, nouvelle tentative paresseuse,
//         échec de MIDIPacketListAdd / MIDIReceived pris en compte). PROTOCOL.md §1, §3, §4, §5.
import Combine
import CoreMIDI
import Foundation

/// Sortie MIDI vers FL. Injectable pour les tests.
protocol MIDITransport: AnyObject {
    var isReady: Bool { get }
    @discardableResult func send(_ messages: [CCMessage]) -> Bool
}

/// Logique du lien, sans CoreMIDI. Thread-safe : reçoit depuis le thread CoreMIDI, envoie depuis le thread
/// du tap clavier, est interrogée depuis le thread principal.
final class LinkCore {
    enum SendResult: Equatable {
        case sent(seq: UInt32)
        case notLinked, noKey, unavailable, sequenceExhausted, transportFailed
    }

    struct Snapshot: Equatable {
        var hello: HelloInfo?
        var lastAlive: Date?
        var window: FLWindow
        var hasKey: Bool
        var seq: UInt32
        var incompatibleProtocol: Int?
        var transportReady: Bool
        /// Temps de réponse de FL (médiane des 15 dernières actions, en ms), mesuré de l'envoi de la trame
        /// à l'accusé d'exécution (CC 119). Aucune frappe n'est mémorisée : seulement des durées.
        var responseMs: Double? = nil
    }

    private struct State {
        var parser = MIDIByteParser()
        var decoder = IncomingDecoder()
        var signer: FrameSigner?
        var hello: HelloInfo?
        var helloAt: Date?
        var lastBeat: Date?
        var window: FLWindow = .unknown
        var seq: UInt32 = 0
        var lastPing: Date?
        /// Intervalle des PING sans réponse : 6 s, puis doublé jusqu'à 60 s tant que FL ne répond pas.
        var pingBackoff: TimeInterval = FLProtocol.pingInterval
        var consecutiveRejects = 0
        /// Dernier accusé reçu (0 = refus) : la macro attend celui de sa dernière commande.
        var lastAckedID: Int?
        /// Raison du dernier refus d'une commande avec données (CC 116), remise à nil à chaque envoi.
        var lastReason: Int?
        /// Seq de la dernière commande avec données : une réponse signée doit lui être liée (PROTOCOL.md §8).
        var dataSeq: UInt32?
        /// Réponse vérifiée (MAC juste, liée à `dataSeq`), octets dépaquetés ; remise à nil à chaque envoi.
        var lastResponse: [UInt8]?
        var incompatible: Int?
        var pendingSend: (id: Int, at: UInt64)?
        var latencies: [Double] = []

        var lastAlive: Date? {
            switch (helloAt, lastBeat) {
            case let (a?, b?): return max(a, b)
            case let (a?, nil): return a
            default: return nil          // battement sans HELLO : nonce inconnu, pas « relié »
            }
        }
    }

    private let state: Locked<State>
    private let transport: MIDITransport
    private let clock: () -> Date

    init(transport: MIDITransport, key: [UInt8]?, clock: @escaping () -> Date = Date.init) {
        self.transport = transport
        self.clock = clock
        var s = State()
        s.signer = key.flatMap(FrameSigner.init(keyBytes:))
        state = Locked(s)
    }

    func setKey(_ key: [UInt8]?) {
        state.withLock { $0.signer = key.flatMap(FrameSigner.init(keyBytes:)) }
    }

    // MARK: Réception

    /// Octets reçus sur la destination « FL Shortcut ». Renvoie les événements décodés.
    @discardableResult
    func receive<S: Sequence>(_ bytes: S) -> [IncomingEvent] where S.Element == UInt8 {
        let now = clock()
        var needsResync = false
        let events: [IncomingEvent] = state.withLock { s in
            var out: [IncomingEvent] = []
            for m in s.parser.feed(bytes) {
                guard let e = s.decoder.feed(status: m.status, data1: m.data1, data2: m.data2) else { continue }
                out.append(e)
                switch e {
                case .hello(let h):
                    // Même nonce (HELLO renvoyé) : la séquence du script n'a pas été remise à zéro.
                    if s.hello?.nonce != h.nonce { s.seq = 0 }
                    s.hello = h
                    s.helloAt = now
                    s.pingBackoff = FLProtocol.pingInterval
                    s.window = .unknown        // le script renvoie la fenêtre juste après
                    s.consecutiveRejects = 0
                    s.incompatible = nil
                case .incompatible(let p):
                    s.hello = nil
                    s.helloAt = nil
                    s.incompatible = p
                case .heartbeat:
                    s.lastBeat = now
                    s.pingBackoff = FLProtocol.pingInterval
                case .window(let w):
                    s.window = w
                case .reason(let r):
                    s.lastReason = r
                case .response(let op, let units, let mac):
                    // Retenue seulement si son MAC est juste pour la dernière commande avec données (liée à son
                    // seq : une réponse rejouée ou destinée à une autre commande est ignorée).
                    guard let signer = s.signer, let nonce = s.hello?.nonce, let seq = s.dataSeq,
                          (0...127).contains(op),
                          signer.mac(nonce: nonce, seq: seq, action: UInt8(op), data: units) == mac,
                          let bytes = Pack7.unpack(units) else { break }
                    s.lastResponse = bytes
                case .ack(let id):
                    s.lastAckedID = id
                    // Un refus expliqué (CC 116 : rien de sélectionné…) n'est pas un rejet de trame.
                    if id == 0 && s.lastReason == nil {
                        s.consecutiveRejects += 1
                        if s.consecutiveRejects >= 2 { needsResync = true; s.consecutiveRejects = 0 }
                    } else {
                        s.consecutiveRejects = 0
                        if let p = s.pendingSend, p.id == id {
                            let ms = Double(DispatchTime.now().uptimeNanoseconds &- p.at) / 1_000_000
                            if ms >= 0, ms < 2000 {
                                s.latencies.append(ms)
                                if s.latencies.count > 15 { s.latencies.removeFirst(s.latencies.count - 15) }
                            }
                        }
                    }
                    s.pendingSend = nil
                }
            }
            return out
        }
        if needsResync { ping(minInterval: FLProtocol.resyncPingInterval) }
        return events
    }

    // MARK: Envoi

    /// PING (CC 103 = 1), limité à un tous les `minInterval` (le script ignore plus de 4 PING/s).
    @discardableResult
    func ping(minInterval: TimeInterval = 1) -> Bool {
        let now = clock()
        return state.withLock { s in
            if let last = s.lastPing, now.timeIntervalSince(last) < max(minInterval, 0.3) { return false }
            s.lastPing = now
            return transport.send([.ping])
        }
    }

    /// Macro (file de la macro, bloquant) : réveille le script si besoin, puis envoie les actions dans l'ordre.
    /// `brief` (mode léger) : PING = 2, le script se rendort tout seul ensuite ; sinon PING = 1 (mode MIDI
    /// complet, le script reste éveillé). Script déjà réveillé depuis peu : aucun nouveau PING.
    /// Renvoie nil si tout est parti, sinon la raison.
    func runBriefly(_ ids: [Int], brief: Bool, timeout: TimeInterval = 4) -> String? {
        let hello: HelloInfo
        switch wake(brief: brief, timeout: timeout) {
        case .ready(let h): hello = h
        case .failed(let why): return why
        }
        guard let last = ids.last else { return nil }
        state.withLock { $0.lastAckedID = nil }
        for id in ids {
            guard hello.capabilities.contains(id) else { return "action indisponible dans ce FL (mets FL à jour)" }
            switch sendAction(id) {
            case .sent: break
            case .noKey: return "lien avec FL non installé"
            default: return "FL n'a pas reçu la commande"
            }
        }
        // Les trames partent d'affilée et FL les exécute dans l'ordre : on attend l'accusé de la dernière.
        let ackDeadline = Date().addingTimeInterval(1.5)
        while Date() < ackDeadline {
            switch state.withLock({ $0.lastAckedID }) {
            case .some(last): return nil
            case .some(0): return "FL a refusé la commande : redémarre FL (le script vient d'être mis à jour)"
            default: Thread.sleep(forTimeInterval: 0.01)
            }
        }
        return "FL n'a pas confirmé (armement / REC)"
    }

    private enum Wake {
        case ready(HelloInfo)
        case failed(String)
    }

    /// Réveille le script si besoin (PING) et attend son HELLO. Script déjà réveillé depuis peu : aucun PING, sauf
    /// `force` (il s'est rendormi alors que son dernier battement semblait récent).
    private func wake(brief: Bool, timeout: TimeInterval, force: Bool = false) -> Wake {
        let start = clock()
        let state0: (hasKey: Bool, fresh: Bool) = state.withLock { s in
            let fresh = !force && s.hello != nil && (s.lastAlive.map { start.timeIntervalSince($0) < 4 } ?? false)
            return (s.signer != nil, fresh)
        }
        guard state0.hasKey else { return .failed("lien avec FL non installé : fiche du raccourci › Installer le lien avec FL") }
        if !state0.fresh {
            let sent: Bool = state.withLock { s in
                s.hello = nil                  // le HELLO attendu est celui de ce réveil
                s.lastPing = start
                return transport.send([brief ? .pingBrief : .ping])
            }
            guard sent else { return .failed("ports MIDI « FL Shortcut » indisponibles") }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if state.withLock({ s in s.hello != nil && (s.lastAlive.map { $0 >= start } ?? false) }) { break }
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
        guard let hello = state.withLock({ $0.hello }) else {
            return .failed("FL ne répond pas : redémarre FL (nouvelle version du script), et vérifie dans Options › MIDI Settings que « FL Shortcut » est activé en entrée et en sortie")
        }
        return .ready(hello)
    }

    private enum DataAttempt {
        case reply(DataReply)
        /// Accusé 0 sans raison : trame ignorée (script rendormi entre-temps…).
        case refusedSilently
    }

    /// Macro (file de la macro, bloquant) : commande avec données (PROTOCOL.md §7). Réveil comme `runBriefly`,
    /// puis attente de l'accusé 41, ou de la raison du refus suivie de l'accusé 0. Un refus sans raison vient en
    /// général d'un script qui s'est rendormi (8 s après la dernière commande) alors que son dernier battement
    /// semblait récent : il est réveillé par un PING et la commande est renvoyée une seule fois.
    func runData(_ units: [UInt8], brief: Bool, timeout: TimeInterval = 4,
                 needs capability: Int = FLProtocol.dataActionID) -> DataReply {
        if case .reply(let r) = attemptData(units, brief: brief, timeout: timeout, forceWake: false,
                                            needs: capability) { return r }
        switch attemptData(units, brief: brief, timeout: timeout, forceWake: true, needs: capability) {
        case .reply(let r): return r
        case .refusedSilently:
            return .failed("FL a refusé la commande : redémarre FL si le script vient d'être mis à jour")
        }
    }

    /// Opération 2 à 8 (Organiser, dégradé ; PROTOCOL.md §8) : comme `runData`, puis la réponse signée de FL s'il
    /// y en a une (`.answered([])` sinon). Demande le script v5 (capacité 42).
    func runRequest(_ bytes: [UInt8], brief: Bool, timeout: TimeInterval = 4) -> RequestReply {
        let units = Pack7.pack(bytes)
        guard units.count <= FLProtocol.maxDataUnits else { return .failed("données trop longues") }
        switch runData(units, brief: brief, timeout: timeout, needs: FLProtocol.extActionID) {
        case .done: return .answered(state.withLock { $0.lastResponse } ?? [])
        case .refused(let reason): return .refused(reason)
        case .failed(let why): return .failed(why)
        }
    }

    private func attemptData(_ units: [UInt8], brief: Bool, timeout: TimeInterval, forceWake: Bool,
                             needs capability: Int) -> DataAttempt {
        let hello: HelloInfo
        switch wake(brief: brief, timeout: timeout, force: forceWake) {
        case .ready(let h): hello = h
        case .failed(let why): return .reply(.failed(why))
        }
        guard hello.capabilities.contains(capability) else {
            return .reply(.failed("mets à jour le lien avec FL : redémarre FL pour charger le nouveau script"))
        }
        state.withLock { $0.lastAckedID = nil }
        switch sendData(units) {
        case .sent: break
        case .noKey: return .reply(.failed("lien avec FL non installé"))
        default: return .reply(.failed("FL n'a pas reçu la commande"))
        }
        let ackDeadline = Date().addingTimeInterval(1.5)
        while Date() < ackDeadline {
            let (ack, reason) = state.withLock { ($0.lastAckedID, $0.lastReason) }
            switch ack {
            case .some(FLProtocol.dataActionID): return .reply(.done)
            case .some(0):
                if let reason { return .reply(.refused(reason)) }
                return .refusedSilently
            default: Thread.sleep(forTimeInterval: 0.01)
            }
        }
        return .reply(.failed("FL n'a pas confirmé"))
    }

    /// Commande avec données : CC 96, unités, trame signée de l'action 41. Envoyée par paquets (256 octets au plus
    /// pour CoreMIDI), dans l'ordre et sous le verrou : jamais mélangée avec une autre trame.
    func sendData(_ units: [UInt8]) -> SendResult {
        let now = clock()
        var exhausted = false
        let result: SendResult = state.withLock { s in
            guard let signer = s.signer else { return .noKey }
            guard let hello = s.hello, let alive = s.lastAlive,
                  now.timeIntervalSince(alive) < FLProtocol.aliveTimeout else { return .notLinked }
            guard hello.capabilities.contains(FLProtocol.dataActionID) else { return .unavailable }
            guard s.seq < FLProtocol.seqMax else { exhausted = true; return .sequenceExhausted }
            let next = s.seq + 1
            guard let messages = FrameEncoder.dataFrame(seq: next, units: units, nonce: hello.nonce, signer: signer) else {
                return .unavailable
            }
            s.seq = next
            s.lastReason = nil
            s.dataSeq = next
            s.lastResponse = nil
            s.pendingSend = (id: FLProtocol.dataActionID, at: DispatchTime.now().uptimeNanoseconds)
            var from = 0
            while from < messages.count {
                let to = min(from + FLProtocol.messagesPerSend, messages.count)
                guard transport.send(Array(messages[from..<to])) else { return .transportFailed }
                from = to
            }
            return .sent(seq: next)
        }
        if exhausted { ping(minInterval: FLProtocol.resyncPingInterval) }
        return result
    }

    /// À appeler toutes les secondes : PING après 6 s sans battement (ou sans HELLO) quand FL tourne.
    /// Sans réponse, l'intervalle double (6, 12, 24, 48, 60 s) : FL Shortcut se fait oublier.
    func tick(flRunning: Bool) {
        guard flRunning else { return }
        let now = clock()
        let (stale, interval): (Bool, TimeInterval) = state.withLock { s in
            guard let alive = s.lastAlive, s.hello != nil else { return (true, s.pingBackoff) }
            return (now.timeIntervalSince(alive) >= FLProtocol.aliveTimeout, s.pingBackoff)
        }
        guard stale, ping(minInterval: interval) else { return }
        state.withLock { $0.pingBackoff = min($0.pingBackoff * 2, FLProtocol.maxPingInterval) }
    }

    /// Relance immédiate de la recherche de FL (lancement de FL, bouton Tester, nouvelle clé).
    func resetPingBackoff() {
        state.withLock { $0.pingBackoff = FLProtocol.pingInterval }
    }

    /// Envoie une trame authentifiée. Les frames sont émises sous le verrou : jamais deux trames mélangées.
    func sendAction(_ id: Int) -> SendResult {
        let now = clock()
        var exhausted = false
        let result: SendResult = state.withLock { s in
            guard let signer = s.signer else { return .noKey }
            guard let hello = s.hello, let alive = s.lastAlive,
                  now.timeIntervalSince(alive) < FLProtocol.aliveTimeout else { return .notLinked }
            guard FLActions.isKnown(id), hello.capabilities.contains(id) else { return .unavailable }
            guard s.seq < FLProtocol.seqMax else { exhausted = true; return .sequenceExhausted }
            let next = s.seq + 1
            guard let frame = FrameEncoder.frame(seq: next, action: id, nonce: hello.nonce, signer: signer) else {
                return .unavailable
            }
            s.seq = next
            s.lastReason = nil
            s.pendingSend = (id: id, at: DispatchTime.now().uptimeNanoseconds)
            return transport.send(frame) ? .sent(seq: next) : .transportFailed
        }
        if exhausted { ping(minInterval: FLProtocol.resyncPingInterval) }
        return result
    }

    // MARK: Lecture

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let v = values.sorted()
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    func routingView() -> LinkRoutingView {
        let now = clock()
        return state.withLock { s in
            let alive = s.hello != nil && s.lastAlive.map { now.timeIntervalSince($0) < FLProtocol.aliveTimeout } == true
            return LinkRoutingView(linked: alive, window: s.window,
                                   capabilities: s.hello?.capabilities, canSign: s.signer != nil)
        }
    }

    var snapshot: Snapshot {
        let ready = transport.isReady
        return state.withLock { s in
            Snapshot(hello: s.hello, lastAlive: s.lastAlive, window: s.window, hasKey: s.signer != nil,
                     seq: s.seq, incompatibleProtocol: s.incompatible, transportReady: ready,
                     responseMs: LinkCore.median(s.latencies).map { ($0 * 10).rounded() / 10 })
        }
    }
}

/// Source + destination virtuelles CoreMIDI « FL Shortcut ».
final class CoreMIDITransport: MIDITransport {
    enum UniqueIDKey: String {
        case source = "midiSourceUniqueID"
        case destination = "midiDestinationUniqueID"
    }

    private struct Handles {
        var client = MIDIClientRef()
        var source = MIDIEndpointRef()
        var destination = MIDIEndpointRef()
        var ready = false
        var idConflict = false
    }

    private let handles = Locked(Handles())
    private let name = "FL Shortcut" as CFString
    private let defaults: UserDefaults
    var onBytes: (([UInt8]) -> Void)?
    var onSetupChanged: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isReady: Bool { handles.value.ready }
    var hadUniqueIDConflict: Bool { handles.value.idConflict }

    /// Un seul client CoreMIDI pour toute la vie de l'app (Apple déconseille de le détruire et le recréer).
    private func ensureClient() -> MIDIClientRef? {
        let existing = handles.value.client
        if existing != 0 { return existing }
        var client = MIDIClientRef()
        let status = MIDIClientCreateWithBlock(name, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged { self?.onSetupChanged?() }
        }
        guard status == noErr else { return nil }
        handles.withLock { $0.client = client }
        return client
    }

    /// Crée la source et la destination « FL Shortcut ». Si elles existent encore, ne touche à rien :
    /// chaque création ou destruction de port fait rescanner le MIDI à FL (à-coup, rechargement des scripts).
    @discardableResult
    func connect() -> Bool {
        if verify() { return true }
        guard let client = ensureClient() else { return false }
        let old = handles.withLock { h -> (MIDIEndpointRef, MIDIEndpointRef) in
            defer { h.source = 0; h.destination = 0; h.ready = false }
            return (h.source, h.destination)
        }
        if old.0 != 0 { MIDIEndpointDispose(old.0) }
        if old.1 != 0 { MIDIEndpointDispose(old.1) }

        var source = MIDIEndpointRef()
        guard MIDISourceCreate(client, name, &source) == noErr else { return false }
        var destination = MIDIEndpointRef()
        let status = MIDIDestinationCreateWithBlock(client, name, &destination) { [weak self] list, _ in
            guard let self, let sink = self.onBytes else { return }
            CoreMIDITransport.forEachPacket(list) { sink($0) }
        }
        guard status == noErr else { MIDIEndpointDispose(source); return false }

        let c1 = applyUniqueID(source, key: .source)
        let c2 = applyUniqueID(destination, key: .destination)
        handles.withLock {
            $0.source = source
            $0.destination = destination
            $0.ready = true
            $0.idConflict = c1 || c2
        }
        return true
    }

    /// Fermeture de l'app uniquement.
    func disconnect() {
        let old = handles.withLock { h -> Handles in
            defer { h = Handles() }
            return h
        }
        if old.source != 0 { MIDIEndpointDispose(old.source) }
        if old.destination != 0 { MIDIEndpointDispose(old.destination) }
        if old.client != 0 { MIDIClientDispose(old.client) }
    }

    /// Vrai si nos points de terminaison existent toujours (après réinitialisation de CoreMIDI).
    func verify() -> Bool {
        let h = handles.value
        guard h.source != 0, h.destination != 0 else { return false }
        var value: Int32 = 0
        let ok = MIDIObjectGetIntegerProperty(h.source, kMIDIPropertyUniqueID, &value) == noErr
            && MIDIObjectGetIntegerProperty(h.destination, kMIDIPropertyUniqueID, &value) == noErr
        if ok != h.ready { handles.withLock { $0.ready = ok } }
        return ok
    }

    @discardableResult
    func send(_ messages: [CCMessage]) -> Bool {
        let h = handles.value
        guard h.ready, !messages.isEmpty else { return false }
        let bytes = messages.flatMap(\.bytes)
        let size = 1024
        guard bytes.count <= 256 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let first = MIDIPacketListInit(list)
        let added: UnsafeMutablePointer<MIDIPacket>? = MIDIPacketListAdd(list, size, first, mach_absolute_time(), bytes.count, bytes)
        guard added != nil else { return false }
        // Une erreur d'envoi ne détruit jamais les ports : verify() décidera s'ils ont vraiment disparu.
        return MIDIReceived(h.source, list) == noErr
    }

    /// uniqueID aléatoire par installation, conservé dans les préférences (SEC-02). Renvoie vrai en cas de conflit.
    /// En cas de conflit, l'identifiant enregistré n'est jamais remplacé : FL retrouve le même port au
    /// lancement suivant (sinon il le verrait comme un nouvel appareil, désactivé).
    private func applyUniqueID(_ endpoint: MIDIEndpointRef, key: UniqueIDKey) -> Bool {
        let stored = Int32(truncatingIfNeeded: defaults.integer(forKey: key.rawValue))
        let id = stored != 0 ? stored : Int32.random(in: 1...Int32.max)
        let status = MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyUniqueID, id)
        if status == noErr {
            if stored == 0 { defaults.set(Int(id), forKey: key.rawValue) }
            return false
        }
        return Int(status) == Int(kMIDIIDNotUnique)   // identifiant attribué par le système pour cette session
    }

    /// Parcourt la liste de paquets en mémoire (jamais de copie de MIDIPacket : pointeurs valides).
    /// `packet.pointee` copierait 256 octets de données et pourrait lire au-delà d'un paquet court :
    /// seuls `numPackets` et `length` sont lus, directement à leur position.
    static func forEachPacket(_ list: UnsafePointer<MIDIPacketList>, _ body: ([UInt8]) -> Void) {
        let base = UnsafeRawPointer(list)
        guard let countOffset = MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.numPackets),
              let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet),
              let lengthOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.length),
              let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data) else { return }
        let count = Int(base.loadUnaligned(fromByteOffset: countOffset, as: UInt32.self))
        guard count > 0 else { return }
        var packet = (base + packetOffset).assumingMemoryBound(to: MIDIPacket.self)
        for i in 0..<count {
            let raw = UnsafeRawPointer(packet)
            let length = Int(raw.loadUnaligned(fromByteOffset: lengthOffset, as: UInt16.self))
            let data = UnsafeRawBufferPointer(start: raw + dataOffset, count: length)
            body(Array(data))
            if i + 1 < count { packet = UnsafePointer(MIDIPacketNext(packet)) }
        }
    }
}

/// Façade publiée pour l'interface : statut du lien, capacités, accusés. Possède le transport CoreMIDI.
final class MIDILink: ObservableObject {
    static let shared = MIDILink()

    @Published private(set) var status: LinkStatus = .flClosed
    @Published private(set) var snapshot: LinkCore.Snapshot
    /// Pas publié : aucune vue ne le lit (chaque accusé redessinerait sinon l'interface).
    private(set) var lastAck: (id: Int, date: Date)? = nil
    @Published private(set) var uniqueIDConflict = false

    let core: LinkCore
    private let transport: CoreMIDITransport
    private let secrets: SecretStore
    private var timer: Timer?
    private var lastReconnect = Date.distantPast
    private var reconnectDelay: TimeInterval = 5
    private var flRunning = false

    private init() {
        let transport = CoreMIDITransport()
        let secrets = PreferredSecretStore()
        self.transport = transport
        self.secrets = secrets
        core = LinkCore(transport: transport, key: secrets.load())
        snapshot = core.snapshot
        transport.onBytes = { [weak self] bytes in
            guard let self else { return }
            let events = self.core.receive(bytes)
            guard !events.isEmpty else { return }
            DispatchQueue.main.async { self.handle(events) }
        }
        transport.onSetupChanged = { [weak self] in
            DispatchQueue.main.async { self?.checkTransport() }
        }
    }

    /// Démarre CoreMIDI, envoie le PING de lancement et la surveillance (1 s).
    func start() {
        if transport.connect() { lastReconnect = Date() }
        uniqueIDConflict = transport.hadUniqueIDConflict
        core.ping(minInterval: 0)
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        transport.disconnect()
        onDemand = false
    }

    /// Mode léger avec une macro qui arme / lance le REC : ports « FL Shortcut » présents (FL les voit), mais
    /// aucun PING, aucune surveillance : rien ne circule tant qu'une macro ne réveille pas le script.
    private(set) var onDemand = false

    /// Une fois créés, les ports restent jusqu'à la fermeture de l'app : les détruire / recréer ferait relire
    /// les appareils MIDI à FL (à-coups, script rechargé). Créés seulement si le lien a été installé.
    func setOnDemand(_ wanted: Bool) {
        guard AppMode.light, wanted, !onDemand, core.snapshot.hasKey else { return }
        onDemand = true
        if transport.connect() { lastReconnect = Date() }
        uniqueIDConflict = transport.hadUniqueIDConflict
    }

    /// Macro : commande avec données (Nom et couleur…), même réveil bref que `runBriefly`.
    func runData(_ units: [UInt8]) -> DataReply {
        guard transport.isReady else {
            return .failed(core.snapshot.hasKey ? "ports MIDI « FL Shortcut » indisponibles : relance FL Shortcut"
                                                : "lien avec FL non installé : fiche du raccourci › Installer le lien avec FL")
        }
        return core.runData(units, brief: AppMode.light, timeout: 1.5)
    }

    /// Organiser : opération 2 à 8 du script v5, avec sa réponse signée (file de l'Organiser, bloquant).
    func runRequest(_ bytes: [UInt8]) -> RequestReply {
        guard transport.isReady else {
            return .failed(core.snapshot.hasKey ? "ports MIDI « FL Shortcut » indisponibles : relance FL Shortcut"
                                                : "lien avec FL non installé : fiche du raccourci › Installer le lien avec FL")
        }
        return core.runRequest(bytes, brief: AppMode.light, timeout: 1.5)
    }

    /// Macro : réveil bref du script, actions, puis il se rendort (file de la macro, bloquant).
    func runBriefly(_ ids: [Int]) -> String? {
        guard transport.isReady else {
            return core.snapshot.hasKey ? "ports MIDI « FL Shortcut » indisponibles : relance FL Shortcut"
                                   : "lien avec FL non installé : fiche du raccourci › Installer le lien avec FL"
        }
        // 1,5 s au plus : un script qui ne répond pas ne doit pas figer la macro (réponse normale : quelques ms).
        return core.runBriefly(ids, brief: AppMode.light, timeout: 1.5)
    }

    func setFLRunning(_ running: Bool) {
        guard running != flRunning else { return }
        flRunning = running
        if AppMode.light { return }                    // mode léger : aucun lien MIDI
        core.resetPingBackoff()
        if running { core.ping(minInterval: 1) }
        refresh()
    }

    /// Clé changée (installation du script) : nouvelle signature, puis PING pour une nouvelle session.
    /// Mode léger : pas de PING (le script reste endormi jusqu'à la prochaine macro).
    func reloadKey() {
        core.setKey(secrets.load())
        guard !AppMode.light else {
            refresh()
            setOnDemand(true)                          // lien installé : ports présents (sans trafic)
            return
        }
        core.resetPingBackoff()
        core.ping(minInterval: 0)
        refresh()
    }

    /// Bouton « Tester » : PING immédiat.
    func testLink() {
        core.resetPingBackoff()
        core.ping(minInterval: 0.5)
    }

    /// « Tester » dans la fiche : envoie l'action choisie à FL (trame signée), puis met le statut à jour.
    @discardableResult
    func test(action id: Int) -> Bool {
        let result = core.sendAction(id)
        refresh()
        if case .sent = result { return true }
        return false
    }

    /// Recrée les ports seulement s'ils ont disparu, avec un délai croissant (5 s → 5 min) en cas d'échec.
    private func reconnectIfNeeded() {
        guard Date().timeIntervalSince(lastReconnect) > reconnectDelay, !transport.verify() else { return }
        lastReconnect = Date()
        if transport.connect() {
            reconnectDelay = 5
            if !AppMode.light { core.ping(minInterval: 0) }   // mode léger : le script reste endormi
        } else {
            reconnectDelay = min(reconnectDelay * 2, 300)
        }
        uniqueIDConflict = transport.hadUniqueIDConflict
    }

    private func tick() {
        if !transport.isReady { reconnectIfNeeded() }
        core.tick(flRunning: flRunning)
        refresh()
    }

    private func checkTransport() {
        // Changement de configuration MIDI (y compris ceux de FL quand il rescanne) : on ne recrée nos ports
        // que s'ils ont réellement disparu, jamais plus d'une fois par délai de reconnexion.
        reconnectIfNeeded()
        refresh()
    }

    private func handle(_ events: [IncomingEvent]) {
        for e in events {
            if case .ack(let id) = e { lastAck = (id: id, date: Date()) }
        }
        refresh()
    }

    private func refresh() {
        var snap = core.snapshot
        // `lastAlive` change à chaque battement : on garde l'ancienne valeur pour ne pas redessiner l'interface
        // toutes les 2 s (le statut « relié / inactif » est calculé à part, juste en dessous).
        if snap.hello == snapshot.hello { snap.lastAlive = snapshot.lastAlive }
        // Champs qui changent à chaque action ou changement de fenêtre de FL mais qu'aucune vue n'affiche :
        // ils ne déclenchent pas de publication (la logique du lien les lit directement dans `core`).
        snap.seq = snapshot.seq
        snap.window = snapshot.window
        snap.transportReady = snapshot.transportReady
        if snap != snapshot { snapshot = snap }
        let s = LinkStatus.resolve(flRunning: flRunning, alive: core.routingView().linked)
        if s != status { status = s }
    }
}
