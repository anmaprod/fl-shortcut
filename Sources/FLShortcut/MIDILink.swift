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
                case .ack(let id):
                    if id == 0 {
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

    /// Crée client, source et destination. Peut être rappelée : détruit d'abord l'existant.
    @discardableResult
    func connect() -> Bool {
        disconnect()
        var client = MIDIClientRef()
        var status = MIDIClientCreateWithBlock(name, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged { self?.onSetupChanged?() }
        }
        guard status == noErr else { return false }

        var source = MIDIEndpointRef()
        status = MIDISourceCreate(client, name, &source)
        guard status == noErr else { MIDIClientDispose(client); return false }

        var destination = MIDIEndpointRef()
        status = MIDIDestinationCreateWithBlock(client, name, &destination) { [weak self] list, _ in
            guard let self, let sink = self.onBytes else { return }
            CoreMIDITransport.forEachPacket(list) { sink($0) }
        }
        guard status == noErr else { MIDIClientDispose(client); return false }

        let c1 = applyUniqueID(source, key: .source)
        let c2 = applyUniqueID(destination, key: .destination)
        handles.withLock {
            $0 = Handles(client: client, source: source, destination: destination, ready: true, idConflict: c1 || c2)
        }
        return true
    }

    func disconnect() {
        let old = handles.withLock { h -> Handles in
            let o = h
            h = Handles()
            return o
        }
        if old.client != 0 { MIDIClientDispose(old.client) }    // détruit aussi les points de terminaison
    }

    /// Vrai si nos points de terminaison existent toujours (après réinitialisation de CoreMIDI).
    func verify() -> Bool {
        let h = handles.value
        guard h.ready else { return false }
        var value: Int32 = 0
        let ok = MIDIObjectGetIntegerProperty(h.source, kMIDIPropertyUniqueID, &value) == noErr
            && MIDIObjectGetIntegerProperty(h.destination, kMIDIPropertyUniqueID, &value) == noErr
        if !ok { handles.withLock { $0.ready = false } }
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
        let status = MIDIReceived(h.source, list)
        if status != noErr {
            handles.withLock { $0.ready = false }
            return false
        }
        return true
    }

    /// uniqueID aléatoire par installation, conservé dans les préférences (SEC-02). Renvoie vrai en cas de conflit.
    private func applyUniqueID(_ endpoint: MIDIEndpointRef, key: UniqueIDKey) -> Bool {
        var conflict = false
        for attempt in 0..<4 {
            var id = Int32(truncatingIfNeeded: defaults.integer(forKey: key.rawValue))
            if id == 0 || attempt > 0 {
                id = Int32.random(in: 1...Int32.max)
            }
            let status = MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyUniqueID, id)
            if status == noErr {
                defaults.set(Int(id), forKey: key.rawValue)
                return conflict
            }
            if Int(status) == Int(kMIDIIDNotUnique) { conflict = true } else { break }
        }
        return conflict
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
    @Published private(set) var lastAck: (id: Int, date: Date)? = nil
    @Published private(set) var uniqueIDConflict = false

    let core: LinkCore
    private let transport: CoreMIDITransport
    private let secrets: SecretStore
    private var timer: Timer?
    private var lastReconnect = Date.distantPast
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
    }

    func setFLRunning(_ running: Bool) {
        guard running != flRunning else { return }
        flRunning = running
        core.resetPingBackoff()
        if running { core.ping(minInterval: 1) }
        refresh()
    }

    /// Clé changée (installation du script) : nouvelle signature, puis PING pour une nouvelle session.
    func reloadKey() {
        core.setKey(secrets.load())
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

    private func tick() {
        if !transport.isReady, Date().timeIntervalSince(lastReconnect) > 5 {
            lastReconnect = Date()
            if transport.connect() { core.ping(minInterval: 0) }
            uniqueIDConflict = transport.hadUniqueIDConflict
        }
        core.tick(flRunning: flRunning)
        refresh()
    }

    private func checkTransport() {
        // Notre propre connect() déclenche aussi msgSetupChanged : au plus une recréation par seconde ici,
        // sinon la surveillance (tick, toutes les 5 s) prend le relais.
        if !transport.verify(), Date().timeIntervalSince(lastReconnect) > 1 {
            lastReconnect = Date()
            if transport.connect() { core.ping(minInterval: 0) }
        }
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
        if snap != snapshot { snapshot = snap }
        let s = LinkStatus.resolve(flRunning: flRunning, alive: core.routingView().linked)
        if s != status { status = s }
    }
}
