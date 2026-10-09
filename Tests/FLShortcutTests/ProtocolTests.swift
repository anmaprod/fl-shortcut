import CoreMIDI
import XCTest
@testable import FLShortcut

/// PROTOCOL.md §3-§4 : vecteur de test, encodage des trames, masque de capacités, HELLO.
final class ProtocolTests: XCTestCase {
    private let key = Array(UInt8(0)..<UInt8(16))
    private let nonce: [UInt8] = [17, 42, 99, 5]

    func testHMACTestVector() throws {
        XCTAssertEqual(FrameSigner.message(nonce: nonce, seq: 300, action: 12), [17, 42, 99, 5, 0, 2, 44, 12])
        let signer = try XCTUnwrap(FrameSigner(keyBytes: key))
        XCTAssertEqual(signer.mac(nonce: nonce, seq: 300, action: 12), [87, 59, 101, 12])
    }

    func testSignerRejectsWrongKeyLength() {
        XCTAssertNil(FrameSigner(keyBytes: Array(repeating: 0, count: 15)))
        XCTAssertNil(FrameSigner(keyBytes: Array(repeating: 0, count: 32)))
    }

    func testFrameEncoding() throws {
        let signer = try XCTUnwrap(FrameSigner(keyBytes: key))
        let frame = try XCTUnwrap(FrameEncoder.frame(seq: 300, action: 12, nonce: nonce, signer: signer))
        XCTAssertEqual(frame.map(\.cc), [104, 105, 106, 107, 108, 109, 110, 111])
        XCTAssertEqual(frame.map(\.value), [0, 2, 44, 12, 87, 59, 101, 12])
        XCTAssertEqual(frame[0].bytes, [0xBF, 104, 0])
        XCTAssertTrue(frame.allSatisfy { $0.value < 128 })
    }

    func testSequenceBytesBigEndian7Bits() {
        XCTAssertEqual(FLProtocol.seqBytes(1), [0, 0, 1])
        XCTAssertEqual(FLProtocol.seqBytes(300), [0, 2, 44])
        XCTAssertEqual(FLProtocol.seqBytes(FLProtocol.seqMax), [127, 127, 127])
    }

    func testFrameRejectsOutOfRangeValues() throws {
        let signer = try XCTUnwrap(FrameSigner(keyBytes: key))
        XCTAssertNil(FrameEncoder.frame(seq: 0, action: 1, nonce: nonce, signer: signer))
        XCTAssertNil(FrameEncoder.frame(seq: FLProtocol.seqMax + 1, action: 1, nonce: nonce, signer: signer))
        XCTAssertNil(FrameEncoder.frame(seq: 1, action: 0, nonce: nonce, signer: signer))
        XCTAssertNil(FrameEncoder.frame(seq: 1, action: 43, nonce: nonce, signer: signer))
        XCTAssertNil(FrameEncoder.frame(seq: 1, action: 1, nonce: [1, 2, 3], signer: signer))
        XCTAssertNil(FrameEncoder.frame(seq: 1, action: 1, nonce: [1, 2, 3, 128], signer: signer))
    }

    func testMac28Split() {
        // 0xFFFFFFFF >> 4 = 0x0FFFFFFF : quatre groupes de 7 bits à 127.
        XCTAssertEqual(FLProtocol.mac28([0xFF, 0xFF, 0xFF, 0xFF]), [127, 127, 127, 127])
        XCTAssertEqual(FLProtocol.mac28([0x00, 0x00, 0x00, 0x10]), [0, 0, 0, 1])
    }

    func testCapabilityMaskBitLayout() {
        // CC 90+k porte les bits 7k…7k+6 ; bit j = action 7k+j+1.
        let mask = CapabilityMask(ccValues: [0b1, 0b1, 0, 0, 0, 0b100])
        XCTAssertTrue(mask.contains(1))
        XCTAssertTrue(mask.contains(8))
        XCTAssertTrue(mask.contains(38))
        XCTAssertFalse(mask.contains(2))
        XCTAssertFalse(mask.contains(37))
        XCTAssertFalse(mask.contains(0))
        XCTAssertFalse(mask.contains(43))
    }

    func testCapabilityMaskRoundTrip() {
        let all = CapabilityMask(bits: (1 << 38) - 1)
        let decoded = CapabilityMask(ccValues: all.ccValues)
        XCTAssertEqual(decoded, all)
        for id in 1...38 { XCTAssertTrue(decoded.contains(id), "action \(id)") }
        XCTAssertFalse(decoded.contains(39))
        XCTAssertTrue(all.ccValues.allSatisfy { $0 < 128 })
    }

    func testHelloDecoding() {
        var parser = MIDIByteParser()
        var decoder = IncomingDecoder()
        let caps: [UInt8] = [127, 127, 127, 127, 127, 7]
        var events: [IncomingEvent] = []
        for m in parser.feed(Bytes.hello(nonce: nonce, api: 19, caps: caps)) {
            if let e = decoder.feed(status: m.status, data1: m.data1, data2: m.data2) { events.append(e) }
        }
        XCTAssertEqual(events, [.hello(HelloInfo(nonce: nonce, apiVersion: 19, protocolVersion: 2,
                                                 capabilities: CapabilityMask(ccValues: caps)))])
    }

    func testHelloWithOtherProtocolIsIncompatible() {
        var parser = MIDIByteParser()
        var decoder = IncomingDecoder()
        let events = parser.feed(Bytes.hello(nonce: nonce, proto: 3, caps: Bytes.allCaps))
            .compactMap { decoder.feed(status: $0.status, data1: $0.data1, data2: $0.data2) }
        XCTAssertEqual(events, [.incompatible(protocolVersion: 3)])
    }

    func testIncompleteHelloIsIgnored() {
        var parser = MIDIByteParser()
        var decoder = IncomingDecoder()
        var bytes = Bytes.hello(nonce: nonce, caps: Bytes.allCaps)
        bytes.removeSubrange(3..<6)                 // retire CC 121
        let events = parser.feed(bytes).compactMap { decoder.feed(status: $0.status, data1: $0.data1, data2: $0.data2) }
        XCTAssertTrue(events.isEmpty)
    }

    func testOtherChannelIgnoredAndStatusMessages() {
        var parser = MIDIByteParser()
        var decoder = IncomingDecoder()
        let bytes: [UInt8] = [0xB0, 118, 1]          // canal 1 : ignoré
            + Bytes.cc(118, 0) + Bytes.cc(117, 3) + Bytes.cc(119, 12) + Bytes.cc(119, 0) + Bytes.cc(117, 99)
        let events = parser.feed(bytes).compactMap { decoder.feed(status: $0.status, data1: $0.data1, data2: $0.data2) }
        XCTAssertEqual(events, [.heartbeat, .window(.pianoRoll), .ack(12), .ack(0), .window(.unknown)])
    }

    func testParserRunningStatusAndRealtime() {
        var parser = MIDIByteParser()
        let out = parser.feed([0xBF, 118, 1, 0xF8, 117, 2, 0xF0, 1, 2, 0xF7, 0xBF, 119, 5])
        XCTAssertEqual(out.map { [$0.status, $0.data1, $0.data2] }, [[0xBF, 118, 1], [0xBF, 117, 2], [0xBF, 119, 5]])
    }

    func testPacketListWalkReadsEveryPacket() throws {
        let size = 1024
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let first = MIDIPacketListInit(list)
        let a: [UInt8] = [0xBF, 118, 1]
        let b: [UInt8] = [0xBF, 117, 2, 0xBF, 119, 5]
        // Horodatages distincts : deux paquets séparés.
        let p1: UnsafeMutablePointer<MIDIPacket>? = MIDIPacketListAdd(list, size, first, 1, a.count, a)
        let anchor = try XCTUnwrap(p1)
        let p2: UnsafeMutablePointer<MIDIPacket>? = MIDIPacketListAdd(list, size, anchor, 2, b.count, b)
        XCTAssertNotNil(p2)
        var seen: [[UInt8]] = []
        CoreMIDITransport.forEachPacket(list) { seen.append($0) }
        XCTAssertEqual(seen, [a, b])
    }

    func testLinkStatusResolution() {
        XCTAssertEqual(LinkStatus.resolve(flRunning: false, alive: true), .flClosed)
        XCTAssertEqual(LinkStatus.resolve(flRunning: true, alive: false), .inactive)
        XCTAssertEqual(LinkStatus.resolve(flRunning: true, alive: true), .linked)
    }
}

/// Lien complet (LinkCore) avec transport et horloge simulés.
final class LinkCoreTests: XCTestCase {
    private let key = Array(UInt8(0)..<UInt8(16))
    private let nonce: [UInt8] = [17, 42, 99, 5]
    private var transport: FakeTransport!
    private var clock: FakeClock!
    private var core: LinkCore!

    override func setUp() {
        transport = FakeTransport()
        clock = FakeClock()
        let c = clock!
        core = LinkCore(transport: transport, key: key, clock: { c.now })
    }

    func testNotLinkedBeforeHello() {
        XCTAssertEqual(core.sendAction(1), .notLinked)
        XCTAssertTrue(transport.frames.isEmpty)
        XCTAssertFalse(core.routingView().linked)
    }

    func testFramesNumberedFromOneAfterHelloAndSigned() throws {
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps))
        XCTAssertTrue(core.routingView().linked)
        XCTAssertEqual(core.sendAction(12), .sent(seq: 1))
        XCTAssertEqual(core.sendAction(12), .sent(seq: 2))
        let signer = try XCTUnwrap(FrameSigner(keyBytes: key))
        XCTAssertEqual(transport.frames.first, FrameEncoder.frame(seq: 1, action: 12, nonce: nonce, signer: signer))
    }

    func testRepeatedHelloWithSameNonceKeepsSequence() {
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps))
        _ = core.sendAction(1)
        _ = core.sendAction(1)
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps))
        XCTAssertEqual(core.sendAction(1), .sent(seq: 3))
        core.receive(Bytes.hello(nonce: [1, 2, 3, 4], caps: Bytes.allCaps))
        XCTAssertEqual(core.sendAction(1), .sent(seq: 1))
    }

    func testUnavailableActionNotSent() {
        core.receive(Bytes.hello(nonce: nonce, caps: [1, 0, 0, 0, 0, 0]))     // seule l'action 1
        XCTAssertEqual(core.sendAction(2), .unavailable)
        XCTAssertEqual(core.sendAction(99), .unavailable)
        XCTAssertEqual(core.sendAction(1), .sent(seq: 1))
        XCTAssertFalse(core.routingView().canRun(2))
        XCTAssertTrue(core.routingView().canRun(1))
    }

    func testNoKeyRefusesToSign() {
        core.setKey(nil)
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps))
        XCTAssertEqual(core.sendAction(1), .noKey)
        XCTAssertFalse(core.routingView().canRun(1))
    }

    func testLinkExpiresAfterSixSecondsWithoutHeartbeat() {
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps))
        clock.advance(4)
        core.receive(Bytes.cc(118, 1))
        clock.advance(5)
        XCTAssertTrue(core.routingView().linked)
        clock.advance(1.5)
        XCTAssertFalse(core.routingView().linked)
        XCTAssertEqual(core.sendAction(1), .notLinked)
    }

    func testPingPolicy() {
        XCTAssertTrue(core.ping(minInterval: 0))
        XCTAssertFalse(core.ping(minInterval: 0))            // jamais plus de ~3 PING/s
        clock.advance(1)
        core.tick(flRunning: false)                          // FL fermé : pas de PING
        XCTAssertEqual(transport.pings, 1)
        clock.advance(6)
        core.tick(flRunning: true)                           // aucun HELLO depuis 6 s : PING
        XCTAssertEqual(transport.pings, 2)
        core.tick(flRunning: true)
        XCTAssertEqual(transport.pings, 2)
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps))
        clock.advance(7)
        core.tick(flRunning: true)
        XCTAssertEqual(transport.pings, 3)
    }

    func testUnansweredPingsBackOff() {
        // FL ouvert mais lien pas activé : 6 s, 12 s, 24 s, 48 s, puis 60 s au plus entre deux PING.
        var times: [Double] = []
        var t = 0.0
        while t < 400 {
            clock.advance(1)
            t += 1
            let before = transport.pings
            core.tick(flRunning: true)
            if transport.pings > before { times.append(t) }
        }
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        XCTAssertEqual(Array(gaps.prefix(4)), [12, 24, 48, 60])
        XCTAssertTrue(gaps.allSatisfy { $0 <= 60 })
        // Un HELLO remet l'intervalle à 6 s.
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps))
        let before = transport.pings
        clock.advance(7)
        core.tick(flRunning: true)
        XCTAssertEqual(transport.pings, before + 1)
    }

    func testTwoRejectionsTriggerResync() {
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps))
        core.receive(Bytes.cc(119, 0))
        XCTAssertEqual(transport.pings, 0)
        core.receive(Bytes.cc(119, 0))
        XCTAssertEqual(transport.pings, 1)
    }

    func testWindowTrackedAndResetOnHello() {
        core.receive(Bytes.hello(nonce: nonce, caps: Bytes.allCaps) + Bytes.cc(117, 0))
        XCTAssertEqual(core.routingView().knownWindow, .mixer)
        core.receive(Bytes.hello(nonce: [9, 9, 9, 9], caps: Bytes.allCaps))
        XCTAssertNil(core.routingView().knownWindow)
    }
}
