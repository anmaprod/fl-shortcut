import XCTest
@testable import FLShortcut

/// Organiser : tampon du son capté de FL (mono, dernières secondes seulement).
final class CaptureBufferTests: XCTestCase {
    func testBufferMixesStereoToMono() {
        let buffer = CaptureBuffer(rate: 10, seconds: 10)
        let interleaved: [Float] = [1, 0, 0.5, 0.5, -1, 1]
        interleaved.withUnsafeBufferPointer { buffer.appendInterleaved($0.baseAddress!, frames: 3, channels: 2) }
        XCTAssertEqual(buffer.take(), [0.5, 0.5, 0])

        let left: [Float] = [1, 0.2]
        let right: [Float] = [0, 0.4]
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                buffer.appendPlanar([l.baseAddress!, r.baseAddress!], frames: 2)
            }
        }
        let mono = buffer.take()
        XCTAssertEqual(mono.count, 2)
        XCTAssertEqual(mono[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(mono[1], 0.3, accuracy: 1e-6)
    }

    func testBufferKeepsLastSeconds() {
        let buffer = CaptureBuffer(rate: 4, seconds: 2)
        XCTAssertEqual(buffer.capacity, 8)
        let samples = (0..<12).map(Float.init)
        samples.withUnsafeBufferPointer { buffer.appendInterleaved($0.baseAddress!, frames: 12, channels: 1) }
        XCTAssertEqual(buffer.take(), (4..<12).map(Float.init))
    }

    func testBufferResetAndTake() {
        let buffer = CaptureBuffer(rate: 10, seconds: 1)
        let samples: [Float] = [0.1, 0.2, 0.3]
        samples.withUnsafeBufferPointer { buffer.appendInterleaved($0.baseAddress!, frames: 3, channels: 1) }
        buffer.reset()
        XCTAssertEqual(buffer.take(), [])
        samples.withUnsafeBufferPointer { buffer.appendInterleaved($0.baseAddress!, frames: 3, channels: 1) }
        XCTAssertEqual(buffer.take(), samples)
        XCTAssertEqual(buffer.take(), [], "take vide le tampon")
        samples.withUnsafeBufferPointer { buffer.appendInterleaved($0.baseAddress!, frames: 0, channels: 1) }
        XCTAssertEqual(buffer.take(), [], "zéro trame : rien n'est ajouté")
    }
}
