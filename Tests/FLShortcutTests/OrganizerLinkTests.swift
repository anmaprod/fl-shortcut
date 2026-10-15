import XCTest
@testable import FLShortcut

/// Lien v5 (PROTOCOL.md §8) : réponses signées FL → appli et façade de l'Organiser.
final class OrganizerLinkTests: XCTestCase {
    private let key = Array(UInt8(0)..<UInt8(16))
    private let nonce: [UInt8] = [17, 42, 99, 5]
    /// Actions 1 à 42 (41 = données, 42 = opérations de l'Organiser).
    private let capsV5 = CapabilityMask(bits: (1 << 42) - 1).ccValues

    private func responseBytes(op: UInt8, units: [UInt8], mac: [UInt8]) -> [UInt8] {
        Bytes.cc(112, op) + units.flatMap { Bytes.cc(113, $0) } + Bytes.cc(114, 0) + mac.flatMap { Bytes.cc(115, $0) }
    }

    // MARK: Décodage et MAC

    func testResponseDecodeAndMac() throws {
        let units = Pack7.pack([1, 0, 2, 0, 0, 0, 0])
        XCTAssertEqual(units, [0, 1, 0, 2, 0, 0, 0, 0])
        let signer = try XCTUnwrap(FrameSigner(keyBytes: key))
        // Vecteur commun avec le script (test_response_mac_vector, PROTOCOL.md §8)
        XCTAssertEqual(signer.mac(nonce: nonce, seq: 300, action: 2, data: units), [89, 95, 58, 61])
        var d = IncomingDecoder()
        var events: [IncomingEvent] = []
        var parser = MIDIByteParser()
        for m in parser.feed(responseBytes(op: 2, units: units, mac: [89, 95, 58, 61])) {
            if let e = d.feed(status: m.status, data1: m.data1, data2: m.data2) { events.append(e) }
        }
        XCTAssertEqual(events, [.response(op: 2, units: units, mac: [89, 95, 58, 61])])
    }

    func testBrokenResponseDropped() {
        func decode(_ pairs: [(UInt8, UInt8)]) -> [IncomingEvent] {
            var d = IncomingDecoder()
            return pairs.compactMap { d.feed(status: 0xBF, data1: $0.0, data2: $0.1) }
        }
        XCTAssertEqual(decode([(113, 1), (114, 0), (115, 1), (115, 2), (115, 3), (115, 4)]), [])   // sans début
        XCTAssertEqual(decode([(112, 2), (113, 1), (115, 1), (115, 2), (115, 3), (115, 4)]), [])   // sans fin
        XCTAssertEqual(decode([(112, 2), (114, 0), (113, 1), (115, 1), (115, 2), (115, 3), (115, 4)]), [])
        let units: [(UInt8, UInt8)] = Array(repeating: (113, 0), count: 601)
        let end: [(UInt8, UInt8)] = [(114, 0), (115, 1), (115, 2), (115, 3), (115, 4)]
        let tooLong: [(UInt8, UInt8)] = [(112, 2)] + units + end
        XCTAssertEqual(decode(tooLong), [])
        // Une nouvelle réponse repart de zéro.
        XCTAssertEqual(decode([(112, 2), (113, 9), (112, 2), (113, 1), (114, 0), (115, 1), (115, 2), (115, 3), (115, 4)]),
                       [.response(op: 2, units: [1], mac: [1, 2, 3, 4])])
    }

    // MARK: LinkCore : réponse liée à sa commande

    private func linkedCore() -> (LinkCore, FakeTransport) {
        let transport = FakeTransport()
        let core = LinkCore(transport: transport, key: key)
        core.receive(Bytes.hello(nonce: nonce, caps: capsV5))
        return (core, transport)
    }

    /// FL répond comme le script : réponse signée (MAC sur le seq de la trame reçue, ou `seqShift` de plus pour
    /// simuler une réponse d'une autre commande), puis l'accusé 41.
    private func answer(_ core: LinkCore, _ transport: FakeTransport, data: [UInt8], badMac: Bool = false,
                        seqShift: UInt32 = 0) {
        let signer = FrameSigner(keyBytes: key)!
        let nonce = self.nonce
        transport.onSend = { [unowned transport] messages in
            guard messages.last?.cc == 111 else { return }
            let all = transport.sent.flatMap { $0 }
            let frame = all.suffix(8).map(\.value)
            let seq = (UInt32(frame[0]) << 14 | UInt32(frame[1]) << 7 | UInt32(frame[2])) + seqShift
            let units = Pack7.pack(data)
            var mac = signer.mac(nonce: nonce, seq: seq, action: 2, data: units)
            if badMac { mac[0] ^= 1 }
            let bytes = self.responseBytes(op: 2, units: units, mac: mac) + Bytes.cc(119, 41)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { core.receive(bytes) }
        }
    }

    func testRequestAnsweredWithVerifiedResponse() {
        let (core, transport) = linkedCore()
        let page: [UInt8] = [1, 0, 1, 0, 0, 1, 0, 2, 0, 1, 0xE0, 0x45, 0x3A, 4] + Array("Kick".utf8)
        answer(core, transport, data: page)
        XCTAssertEqual(core.runRequest(OrganizerPayload.list(.channels, start: 0), brief: true, timeout: 1), .answered(page))
        let sentData = transport.sent.flatMap { $0 }.filter { $0.cc == 97 }.map(\.value)
        XCTAssertEqual(Pack7.unpack(sentData), [2, 1, 0, 0])
    }

    func testResponseWrongMacIgnored() {
        let (core, transport) = linkedCore()
        answer(core, transport, data: [1, 0, 0, 0, 0, 0, 0], badMac: true)
        XCTAssertEqual(core.runRequest([2, 1, 0, 0], brief: true, timeout: 1), .answered([]))
    }

    func testResponseBoundToSeq() {
        let (core, transport) = linkedCore()
        answer(core, transport, data: [1, 0, 0, 0, 0, 0, 0], seqShift: 1)       // signée pour une autre commande
        XCTAssertEqual(core.runRequest([2, 1, 0, 0], brief: true, timeout: 1), .answered([]))
    }

    func testRequestNeedsScriptV5() {
        let transport = FakeTransport()
        let core = LinkCore(transport: transport, key: key)
        core.receive(Bytes.hello(nonce: nonce, caps: CapabilityMask(bits: (1 << 41) - 1).ccValues))   // script v4
        guard case .failed = core.runRequest([2, 1, 0, 0], brief: true, timeout: 1) else {
            return XCTFail("le bit 42 manque : rien ne doit partir")
        }
        XCTAssertFalse(transport.sent.flatMap { $0 }.contains { $0.cc == 96 })
    }

    // MARK: Charges et façade

    func testPayloadSizes() {
        let colors = (0..<65).map { (index: $0, color: RGBColor(r: 255, g: 128, b: UInt8($0))) }
        let chunks = OrganizerPayload.setColors(.channels, colors)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 3 + 5 * 64)
        XCTAssertEqual(Array(chunks[1].prefix(3)), [4, 1, 1])
        XCTAssertLessThanOrEqual(Pack7.pack(chunks[0]).count, FLProtocol.maxDataUnits)
        XCTAssertEqual(OrganizerPayload.selectOne(.mixer, 300), [5, 2, 1, 44])
        XCTAssertEqual(OrganizerPayload.playSolo(3), [6, 0, 3])
        XCTAssertEqual(OrganizerPayload.audition(channel: 2, note: 48, velocity: 0), [3, 0, 2, 48, 0])
        XCTAssertEqual(OrganizerPayload.gradient(first: RGBColor(r: 1, g: 2, b: 3), last: RGBColor(r: 4, g: 5, b: 6)),
                       [8, 1, 2, 3, 4, 5, 6])
    }

    /// Page telle que le script l'écrit (`_op_list`).
    private func channelPage(total: Int, start: Int, names: [String], filtered: Bool = false) -> [UInt8] {
        var out: [UInt8] = [1] + OrganizerPayload.be16(total) + OrganizerPayload.be16(start)
            + [UInt8(names.count), filtered ? 1 : 0]
        for (k, name) in names.enumerated() {
            let raw = Array(name.utf8)
            out += [2] + OrganizerPayload.be16(start + k + 1) + [0x10, 0x20, UInt8(k)] + [UInt8(raw.count)] + raw
        }
        return out
    }

    func testChannelListPagesDecode() throws {
        let names = (0..<20).map { "Son \($0) é" }
        var requests: [[UInt8]] = []
        var slept: [TimeInterval] = []
        let link = RequestOrganizerLink(request: { bytes in
            requests.append(bytes)
            let start = Int(bytes[2]) << 8 | Int(bytes[3])
            let page = Array(names[start..<min(start + 16, names.count)])
            return .answered(self.channelPage(total: 20, start: start, names: page, filtered: start == 16))
        }, window: { .channelRack }, sleep: { slept.append($0) })
        let (channels, filtered) = try link.listChannels()
        XCTAssertEqual(requests, [[2, 1, 0, 0], [2, 1, 0, 16]])
        XCTAssertEqual(channels.count, 20)
        XCTAssertEqual(channels[17], ChannelInfo(index: 17, type: 2, mixerTrack: 18, color: RGBColor(r: 0x10, g: 0x20, b: 1),
                                                 name: "Son 17 é"))
        XCTAssertTrue(filtered)
        XCTAssertEqual(slept.count, 1)                              // 60 ms au moins entre deux commandes
        XCTAssertNil(OrganizerPayload.decodeChannels(channelPage(total: 20, start: 0, names: ["a"]) + [0]))   // octet de trop
        XCTAssertNil(OrganizerPayload.decodeChannels(Array(channelPage(total: 20, start: 0, names: ["abc"]).dropLast())))
        XCTAssertNil(OrganizerPayload.decodeMixer(channelPage(total: 1, start: 0, names: ["a"])))           // autre genre
    }

    func testRefusalsBecomeErrors() {
        var calls = 0
        let link = RequestOrganizerLink(request: { _ in
            calls += 1
            return .refused(4)
        }, window: { .channelRack }, sleep: { _ in })
        XCTAssertThrowsError(try link.playSolo(1)) { error in
            XCTAssertEqual(error as? OrganizerError, .refused(4))
            XCTAssertEqual((error as? OrganizerError)?.message, "FL joue : appuie sur Stop, puis relance Organiser.")
        }
        calls = 0
        link.stopRestore()                                          // jamais d'erreur ; deux essais
        XCTAssertEqual(calls, 2)
    }
}
