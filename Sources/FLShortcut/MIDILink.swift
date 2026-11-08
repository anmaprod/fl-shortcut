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
        /// Le script a dit être sur une autre entrée MIDI que « FL Shortcuts Link » (jusqu'au prochain HELLO).
        var wrongInput = false
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
        var wrongInput = false
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

    /// Ports retirés : FL a déchargé son script, le prochain réveil repart de zéro (PING, puis HELLO d'un nouveau
    /// nonce).
    func forgetScript() {
        state.withLock { s in
            s.hello = nil
            s.helloAt = nil
            s.lastBeat = nil
            s.pendingSend = nil
        }
    }

    // MARK: Réception

    /// Octets reçus sur la destination « FL Shortcuts ». Renvoie les événements décodés.
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
                    s.wrongInput = false
                case .wrongInput:
                    s.wrongInput = true
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
            guard hello.capabilities.contains(id) else { return String(localized: "action indisponible dans ce FL (mets FL à jour)") }
            switch sendAction(id) {
            case .sent: break
            case .noKey: return String(localized: "lien avec FL non installé")
            default: return String(localized: "FL n'a pas reçu la commande")
            }
        }
        // Les trames partent d'affilée et FL les exécute dans l'ordre : on attend l'accusé de la dernière.
        let ackDeadline = Date().addingTimeInterval(1.5)
        while Date() < ackDeadline {
            switch state.withLock({ $0.lastAckedID }) {
            case .some(last): return nil
            case .some(0): return String(localized: "FL a refusé la commande : redémarre FL (le script vient d'être mis à jour)")
            default: Thread.sleep(forTimeInterval: 0.01)
            }
        }
        return String(localized: "FL n'a pas confirmé (armement / REC)")
    }

    private enum Wake {
        case ready(HelloInfo)
        case failed(String)
    }

    /// Script de FL muet. FL relie lui-même le script à l'appareil « FL Shortcuts Link » quand il le trouve en
    /// démarrant (en-tête `supportedDevices` du script) ; sinon, le plus souvent, l'entrée est activée avec le
    /// Controller type « (generic controller) » (le script n'est pas chargé), ou sans le même Port que la sortie.
    static let noResponse = String(localized: "FL ne répond pas : quitte et rouvre FL Studio, il relie « \(CoreMIDITransport.portName) » tout seul en démarrant. Toujours rien : dans Options › MIDI Settings, entrée « \(CoreMIDITransport.portName) », choisis le Controller type « FL Shortcuts » (pas « generic controller »), et donne le même numéro de Port à l'entrée et à la sortie")

    /// Réveille le script si besoin (PING) et attend son HELLO. Script déjà réveillé depuis peu : aucun PING, sauf
    /// `force` (il s'est rendormi alors que son dernier battement semblait récent).
    private func wake(brief: Bool, timeout: TimeInterval, force: Bool = false) -> Wake {
        let start = clock()
        let state0: (hasKey: Bool, fresh: Bool) = state.withLock { s in
            let fresh = !force && s.hello != nil && (s.lastAlive.map { start.timeIntervalSince($0) < 4 } ?? false)
            return (s.signer != nil, fresh)
        }
        guard state0.hasKey else {
            return .failed(String(localized: "lien avec FL non installé : fiche du raccourci › Installer le lien avec FL"))
        }
        if !state0.fresh {
            let sent: Bool = state.withLock { s in
                s.hello = nil                  // le HELLO attendu est celui de ce réveil
                s.lastPing = start
                return transport.send([brief ? .pingBrief : .ping])
            }
            guard sent else { return .failed(String(localized: "ports MIDI « FL Shortcuts Link » indisponibles")) }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if state.withLock({ s in s.hello != nil && (s.lastAlive.map { $0 >= start } ?? false) }) { break }
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
        guard let hello = state.withLock({ $0.hello }) else { return .failed(Self.noResponse) }
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
            return .failed(String(localized: "FL a refusé la commande : redémarre FL si le script vient d'être mis à jour"))
        }
    }

    /// Opération 2 à 8 (Organiser, dégradé ; PROTOCOL.md §8) : comme `runData`, puis la réponse signée de FL s'il
    /// y en a une (`.answered([])` sinon). Demande le script v5 (capacité 42).
    func runRequest(_ bytes: [UInt8], brief: Bool, timeout: TimeInterval = 4) -> RequestReply {
        let units = Pack7.pack(bytes)
        guard units.count <= FLProtocol.maxDataUnits else { return .failed(String(localized: "données trop longues")) }
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
            return .reply(.failed(String(localized: "mets à jour le lien avec FL : redémarre FL pour charger le nouveau script")))
        }
        state.withLock { $0.lastAckedID = nil }
        switch sendData(units) {
        case .sent: break
        case .noKey: return .reply(.failed(String(localized: "lien avec FL non installé")))
        default: return .reply(.failed(String(localized: "FL n'a pas reçu la commande")))
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
        return .reply(.failed(String(localized: "FL n'a pas confirmé")))
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
    /// Sans réponse, l'intervalle double (6, 12, 24, 48, 60 s) : FL Shortcuts se fait oublier.
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
                     responseMs: LinkCore.median(s.latencies).map { ($0 * 10).rounded() / 10 },
                     wrongInput: s.wrongInput)
        }
    }
}

/// Source + destination virtuelles CoreMIDI « FL Shortcuts Link ».
final class CoreMIDITransport: MIDITransport {
    /// Nom de l'appareil dans FL (Options › MIDI Settings), le même que dans l'en-tête `supportedDevices` du script :
    /// FL y relie le script tout seul (Controller type et Port) quand il le trouve en démarrant. Nouveau nom (avant :
    /// « FL Shortcuts ») : un FL qui avait gardé l'ancien appareil en « generic controller » le voit comme neuf.
    static let portName = "FL Shortcuts Link"

    /// Identifiants neufs avec le nouveau nom (FL voit un appareil neuf, sans réglage gardé).
    enum UniqueIDKey: String {
        case source = "midiSourceUniqueID.v2"
        case destination = "midiDestinationUniqueID.v2"
    }

    private struct Handles {
        var client = MIDIClientRef()
        var source = MIDIEndpointRef()
        var destination = MIDIEndpointRef()
        var ready = false
        var idConflict = false
    }

    private let handles = Locked(Handles())
    private let name = CoreMIDITransport.portName as CFString
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

    /// Crée la source et la destination « FL Shortcuts Link ». Si elles existent encore, ne touche à rien :
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

    /// Retire la source et la destination (FL ne voit plus « FL Shortcuts Link » et décharge son script) ; le client
    /// CoreMIDI reste pour les recréer plus tard.
    func closePorts() {
        let old = handles.withLock { h -> (MIDIEndpointRef, MIDIEndpointRef) in
            defer { h.source = 0; h.destination = 0; h.ready = false }
            return (h.source, h.destination)
        }
        if old.0 != 0 { MIDIEndpointDispose(old.0) }
        if old.1 != 0 { MIDIEndpointDispose(old.1) }
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
        users.withLock { $0 = [] }
        transport.disconnect()
    }

    // MARK: Lien seulement quand on s'en sert (mode léger)

    /// Retour du propriétaire du 01/11 : tant que FL voyait « FL Shortcuts Link » avec son script, son image saccadait
    /// (Playlist au zoom), même script endormi ; entrée désactivée dans MIDI Settings et FL relancé : plus rien. Ses
    /// mots : « le mieux ça serait qu'il soit désactivé quand Organiser n'est pas ouvert ». Mode léger : les ports
    /// n'existent qu'entre « Démarrer » et la fermeture de l'Organiser, ou le temps d'un bloc de macro qui ne peut pas
    /// s'en passer (nom et couleur, dégradé, son par son numéro). Jamais avant « Démarrer », même juste après
    /// l'installation (2e retour du 01/11 : un réglage qui gardait l'appareil dès le lancement faisait saccader FL avant
    /// « Démarrer ») : FL voit l'appareil apparaître ; s'il ne répond pas, l'Organiser demande de le relancer (ports
    /// présents) ou montre MIDI Settings.
    enum User: Hashable {
        case organizer
        case macro
    }

    private let users = Locked(Set<User>())
    /// Création et retrait des ports, d'un fil à la fois (Organiser, macro, notifications de CoreMIDI).
    private let portLock = NSLock()
    /// Macro : ports retirés `macroLinger` secondes après son dernier bloc qui s'en est servi (les blocs suivants de
    /// la même macro ne les recréent pas).
    private let macroGeneration = Locked(0)
    static let macroLinger: TimeInterval = 3
    /// Blocs de macro en train de se servir du lien (le surveillant n'y touche jamais pendant un bloc), et la fin du
    /// dernier.
    private let activeBorrows = Locked(0)
    private let lastBorrowEnd = Locked(Date.distantPast)
    /// Ouverture des ports (journal : combien de temps FL a vu l'appareil).
    private let openedAt = Locked<Date?>(nil)

    /// Ports voulus en ce moment : mode MIDI complet (toujours), sinon quelqu'un s'en sert.
    private var portsWanted: Bool { !AppMode.light || !users.value.isEmpty }

    /// `user` a besoin du lien : ports créés s'ils n'existent pas (lien installé). Vrai s'ils viennent d'être créés :
    /// FL met un moment à voir l'appareil et à charger son script. N'importe quel fil.
    @discardableResult
    func use(_ user: User) -> Bool {
        users.withLock { _ = $0.insert(user) }
        return openPorts()
    }

    /// `user` n'en a plus besoin ; plus personne (mode léger) : ports retirés, FL décharge le script. N'importe quel fil.
    func release(_ user: User) {
        let nobody = users.withLock { s -> Bool in
            s.remove(user)
            return s.isEmpty
        }
        guard AppMode.light, nobody else { return }
        closeLink(why: "nobody uses them")
    }

    /// Ports retirés tout de suite (mode léger) : FL ne voit plus « FL Shortcuts Link » et décharge le script.
    private func closeLink(why: String) {
        portLock.lock()
        let had = transport.isReady || transport.verify()
        transport.closePorts()
        portLock.unlock()
        core.forgetScript()
        let since = openedAt.withLock { d -> Date? in
            defer { d = nil }
            return d
        }
        if had {
            let seconds = since.map { String(format: " after %.1f s", Date().timeIntervalSince($0)) } ?? ""
            MacroLog.shared.write("MIDI", "link ports removed\(seconds) (\(why))")
        }
        DispatchQueue.main.async { [weak self] in
            self?.stopWatch()
            self?.refresh()
        }
    }

    /// Fin d'une macro (réussie, ratée ou arrêtée ; file de la macro). Retour du 08/11 (« FL rame… dès que l'action est
    /// terminée, ou si elle a échoué, ça se ferme ») : le lien qu'elle a ouvert est retiré tout de suite, sans attendre
    /// les 3 s laissées entre deux blocs.
    func macroEnded() {
        guard AppMode.light, activeBorrows.value == 0, users.value.contains(.macro) else { return }
        macroGeneration.withLock { $0 += 1 }            // le retrait prévu 3 s après le dernier bloc n'a plus lieu
        release(.macro)
    }

    // MARK: Surveillant (mode léger)

    /// Retour du 08/11 (« il faudrait un capteur… dès que le MIDI est activé, qu'il regarde si c'est vraiment
    /// valable ») : tant que les ports existent en mode léger, chaque seconde, le surveillant vérifie que quelqu'un
    /// s'en sert vraiment (un bloc de macro en cours ou juste fini, l'Organiser ouvert entre « Démarrer » et la fin du
    /// rangement). Sinon il les retire et le note dans le journal (ligne MIDI « watchdog »).
    private var watchTimer: Timer?
    /// L'Organiser tient-il encore le lien ? (thread principal : sa fenêtre ouverte et son rangement pas fini).
    var organizerHoldsLink: () -> Bool = { OrganizerWindow.controller?.holdsLink ?? false }
    private var organizerGoneSince: Date?
    /// Grâce laissée à l'Organiser fermé pour remettre FL comme avant par le lien (`OrganizerController.releaseDeadline`).
    static let organizerGrace: TimeInterval = 4

    private func startWatch() {
        guard AppMode.light, watchTimer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.watch() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        watchTimer = t
    }

    private func stopWatch() {
        watchTimer?.invalidate()
        watchTimer = nil
        organizerGoneSince = nil
    }

    private func watch() {
        guard AppMode.light else { stopWatch(); return }
        guard transport.isReady || transport.verify() else { stopWatch(); return }
        let verdict = LinkWatch.verdict(holders: users.value, activeBorrows: activeBorrows.value,
                                        sinceLastBorrow: Date().timeIntervalSince(lastBorrowEnd.value),
                                        organizerHolds: organizerHoldsLink(),
                                        organizerGoneFor: organizerGoneSince.map { Date().timeIntervalSince($0) })
        organizerGoneSince = verdict.organizerGone ? (organizerGoneSince ?? Date()) : nil
        for user in verdict.release {
            MacroLog.shared.write("MIDI", "watchdog: \(user == .macro ? "macro" : "organizer") hold dropped")
            if user == .macro { macroGeneration.withLock { $0 += 1 } }
            release(user)
        }
        if verdict.closeNow { closeLink(why: "watchdog: nobody uses them") }
    }

    /// Ports créés s'ils manquent (lien installé, mode léger). Vrai s'ils viennent d'être créés.
    @discardableResult
    private func openPorts() -> Bool {
        guard AppMode.light, core.snapshot.hasKey else { return false }
        portLock.lock()
        defer { portLock.unlock() }
        guard !users.value.isEmpty, !transport.verify() else { return false }
        let made = transport.connect()
        let conflict = transport.hadUniqueIDConflict
        if made { openedAt.withLock { $0 = Date() } }
        MacroLog.shared.write("MIDI", made ? "link ports created" : "link ports could not be created")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if made {
                self.lastReconnect = Date()
                self.startWatch()
            }
            if conflict != self.uniqueIDConflict { self.uniqueIDConflict = conflict }
            self.refresh()
        }
        return made
    }

    /// Bloc de macro (file de la macro) : le lien le temps du bloc. Ports tout juste créés : FL a besoin d'un moment
    /// pour voir l'appareil et charger son script, on l'attend (PING répété, `warmUpLimit` secondes au plus).
    private func borrow<T>(_ body: () -> T) -> T {
        guard AppMode.light, !users.value.contains(.organizer) else { return body() }
        let generation = macroGeneration.withLock { g -> Int in
            g += 1
            return g
        }
        activeBorrows.withLock { $0 += 1 }
        defer {
            activeBorrows.withLock { $0 -= 1 }
            lastBorrowEnd.withLock { $0 = Date() }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.macroLinger) { [weak self] in
                guard let self, self.macroGeneration.value == generation else { return }
                self.release(.macro)
            }
        }
        if use(.macro) { warmUp() }
        return body()
    }

    /// FL relie le script à un appareil qui vient d'apparaître : PING jusqu'à son HELLO.
    static let warmUpLimit: TimeInterval = 8

    private func warmUp() {
        let deadline = Date().addingTimeInterval(Self.warmUpLimit)
        Thread.sleep(forTimeInterval: 0.5)
        while Date() < deadline {
            if core.runBriefly([], brief: true, timeout: 0.7) == nil {
                MacroLog.shared.write("MIDI", "script ready after the ports appeared")
                return
            }
        }
        MacroLog.shared.write("MIDI", "no answer from FL after the ports appeared")
    }

    private var unavailable: String {
        core.snapshot.hasKey
            ? String(localized: "ports MIDI « FL Shortcuts Link » indisponibles : relance FL Shortcuts")
            : String(localized: "lien avec FL non installé : Organiser › Installer le lien")
    }

    /// Macro : commande avec données (Nom et couleur…), même réveil bref que `runBriefly`.
    func runData(_ units: [UInt8]) -> DataReply {
        borrow { () -> DataReply in
            guard transport.isReady else { return .failed(unavailable) }
            return core.runData(units, brief: AppMode.light, timeout: 1.5)
        }
    }

    /// Organiser : opération 2 à 8 du script v5, avec sa réponse signée (file de l'Organiser, bloquant).
    func runRequest(_ bytes: [UInt8]) -> RequestReply {
        borrow { () -> RequestReply in
            guard transport.isReady else { return .failed(unavailable) }
            return core.runRequest(bytes, brief: AppMode.light, timeout: 1.5)
        }
    }

    /// Organiser : opération du script, seulement tant que l'Organiser tient le lien (de « Démarrer » à la fin du
    /// rangement ou à la fermeture). Retour du 01/11 au soir (« quand on valide Organiser ça rame toujours ») : une
    /// demande arrivée après ne recrée jamais l'appareil dans FL (pas d'emprunt comme un bloc de macro), elle échoue.
    func runOrganizerRequest(_ bytes: [UInt8]) -> RequestReply {
        if AppMode.light, !users.value.contains(.organizer) {
            return .failed(String(localized: "lien avec FL fermé (Organiser fini)"))
        }
        guard transport.isReady else { return .failed(unavailable) }
        return core.runRequest(bytes, brief: AppMode.light, timeout: 1.5)
    }

    /// « Vérifier » (créateur de macro) : FL répond-il ? Le lien le temps de la vérification.
    func checkLink() -> String? {
        borrow { () -> String? in
            guard transport.isReady else { return unavailable }
            return core.runBriefly([], brief: AppMode.light, timeout: 1.5)
        }
    }

    /// Lien resté muet il y a moins de 20 s (FL sans le script) : les blocs passent tout de suite au clavier, sans
    /// attendre 1,5 s chacun. Dès que FL répond de nouveau (annonce), le lien sert de nouveau.
    private let mutedUntil = Locked(Date.distantPast)
    static let muteDelay: TimeInterval = 20

    /// Macro : réveil bref du script, actions, puis il se rendort (file de la macro, bloquant). Ces blocs ont leur
    /// touche de repli : lien fermé (mode léger, ni Organiser ni bloc qui s'en sert), ils passent tout de suite au
    /// clavier, sans faire apparaître « FL Shortcuts Link » dans FL.
    /// `borrowing` (07/11 au soir, « j'ai bien installé le lien et ça ne fonctionne toujours pas ») : une action SANS
    /// touche de repli (Bypass, Piste suivante…) ouvre le lien le temps du bloc, comme « Nom et couleur » ; avant, elle
    /// échouait toujours (« lien fermé »), le lien n'était jamais ouvert pour elle.
    func runBriefly(_ ids: [Int], borrowing: Bool = false) -> String? {
        if borrowing, AppMode.light {
            if mutedRecently { return Self.mutedMessage }
            return borrow { runActions(ids) }
        }
        if AppMode.light, users.value.isEmpty, core.snapshot.hasKey {
            return String(localized: "lien avec FL fermé (ouvert seulement pendant l'Organiser)")
        }
        return runActions(ids)
    }

    private func runActions(_ ids: [Int]) -> String? {
        guard transport.isReady else { return unavailable }
        if mutedRecently { return Self.mutedMessage }
        // 1,5 s au plus : un script qui ne répond pas ne doit pas figer la macro (réponse normale : quelques ms).
        let why = core.runBriefly(ids, brief: AppMode.light, timeout: 1.5)
        if why != nil { rememberSilence() }
        return why
    }

    /// Macro : opération du script (canal par son numéro…), même mémoire du lien muet que `runBriefly` : le bloc
    /// passe tout de suite à son repli.
    func runMacroRequest(_ bytes: [UInt8]) -> RequestReply {
        if mutedRecently { return .failed(Self.mutedMessage) }
        let reply = runRequest(bytes)
        if case .failed = reply { rememberSilence() }
        return reply
    }

    /// Macro : commande avec données (nom de la piste…), même mémoire du lien muet que `runBriefly`.
    func runMacroData(_ units: [UInt8]) -> DataReply {
        if mutedRecently { return .failed(Self.mutedMessage) }
        let reply = runData(units)
        if case .failed = reply { rememberSilence() }
        return reply
    }

    private static let mutedMessage = String(localized: "FL ne répond pas (essayé il y a peu)")

    private var mutedRecently: Bool { core.snapshot.hello == nil && Date() < mutedUntil.value }

    /// Script resté muet (aucune annonce de FL) : les blocs suivants passent à leur repli pendant 20 s.
    private func rememberSilence() {
        guard core.snapshot.hello == nil else { return }
        mutedUntil.withLock { $0 = Date().addingTimeInterval(Self.muteDelay) }
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
            // Installé pendant que l'Organiser s'en sert (après « Démarrer ») : ports présents tout de suite.
            if !users.value.isEmpty { openPorts() }
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

    /// Recrée les ports seulement s'ils ont disparu alors qu'on s'en sert (mode léger : Organiser ouvert, bloc de
    /// macro), avec un délai croissant (5 s → 5 min) en cas d'échec.
    private func reconnectIfNeeded() {
        portLock.lock()
        defer { portLock.unlock() }
        guard portsWanted, Date().timeIntervalSince(lastReconnect) > reconnectDelay, !transport.verify() else { return }
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

/// Décision du surveillant du lien (pure, essayée) : qui ne tient plus vraiment le lien, et faut-il retirer les ports.
enum LinkWatch {
    struct Verdict: Equatable {
        var release: [MIDILink.User] = []
        var closeNow = false
        /// L'Organiser ne tient plus le lien (sa grâce court).
        var organizerGone = false
    }

    /// - macro : aucun bloc en cours et le dernier fini depuis plus de `macroLinger` + 2 s ;
    /// - Organiser : fenêtre fermée ou rangement fini depuis `organizerGrace` s (le temps de remettre FL comme avant) ;
    /// - personne : ports retirés tout de suite.
    static func verdict(holders: Set<MIDILink.User>, activeBorrows: Int, sinceLastBorrow: TimeInterval,
                        organizerHolds: Bool, organizerGoneFor: TimeInterval?) -> Verdict {
        var v = Verdict()
        if holders.contains(.macro), activeBorrows == 0, sinceLastBorrow > MIDILink.macroLinger + 2 {
            v.release.append(.macro)
        }
        if holders.contains(.organizer), !organizerHolds {
            v.organizerGone = true
            if let gone = organizerGoneFor, gone >= MIDILink.organizerGrace { v.release.append(.organizer) }
        }
        v.closeNow = holders.isEmpty && activeBorrows == 0
        return v
    }
}
