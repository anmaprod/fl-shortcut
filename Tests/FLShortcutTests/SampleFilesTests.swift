import AVFoundation
import XCTest
@testable import FLShortcut

/// Fichier de son d'un clip audio lu directement par l'Organiser (projets de voix du propriétaire : jouées dans FL, les
/// prises commençaient par un silence et étaient mal reconnues, et l'attente durait).
final class SampleFilesTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/Users/moi/Musique/Mon son.flp")
    private let factory = [URL(fileURLWithPath: "/Applications/FL Studio 2025.app/Contents/Resources/FL")]
    private let user = [URL(fileURLWithPath: "/Users/moi/Documents/Image-Line/FL Studio")]

    /// Où chercher : les dossiers de FL à la place de leurs noms, le chemin tel quel, puis à côté du projet.
    func testCandidates() {
        let packs = SampleFiles.candidates("%FLStudioFactoryData%/Data/Patches/Packs/Drums/Kick 1.wav", project: project,
                                           factory: factory, user: user)
        XCTAssertEqual(packs.first?.path, "/Applications/FL Studio 2025.app/Contents/Resources/FL/Data/Patches/Packs/Drums/Kick 1.wav")
        let recorded = SampleFiles.candidates("%FLStudioUserData%\\Audio\\Recorded\\prise.wav", project: project,
                                              factory: factory, user: user)
        XCTAssertEqual(recorded.first?.path, "/Users/moi/Documents/Image-Line/FL Studio/Audio/Recorded/prise.wav")
        XCTAssertTrue(recorded.map(\.path).contains("/Users/moi/Musique/Recorded/prise.wav"), "à côté du projet aussi")
        let absolute = SampleFiles.candidates("/Volumes/Disque/prise.wav", project: project, factory: factory, user: user)
        XCTAssertEqual(absolute.first?.path, "/Volumes/Disque/prise.wav")
        let relative = SampleFiles.candidates("Audio/prise.wav", project: project, factory: factory, user: user)
        XCTAssertEqual(relative.first?.path, "/Users/moi/Musique/Audio/prise.wav")
        XCTAssertTrue(relative.map(\.path).contains("/Users/moi/Musique/Mon son/Recorded/prise.wav"))
    }

    /// Le premier qui existe ; sinon Spotlight au nom du fichier, de préférence dans un dossier du même nom ; rien :
    /// nil (le clip est alors joué dans FL).
    func testResolve() {
        let path = "%FLStudioUserData%/Audio/Recorded/prise.wav"
        let next = URL(fileURLWithPath: "/Users/moi/Musique/prise.wav")
        XCTAssertEqual(SampleFiles.resolve(path, project: project, factory: factory, user: user,
                                           exists: { $0.path == next.path }, search: { _ in [] })?.path, next.path)
        let elsewhere = [URL(fileURLWithPath: "/Volumes/X/Autre/prise.wav"), URL(fileURLWithPath: "/Volumes/X/Recorded/prise.wav")]
        XCTAssertEqual(SampleFiles.resolve(path, project: project, factory: factory, user: user,
                                           exists: { _ in false }, search: { _ in elsewhere }), elsewhere[1])
        XCTAssertNil(SampleFiles.resolve(path, project: project, factory: factory, user: user,
                                         exists: { _ in false }, search: { _ in [] }))
    }

    /// Le passage le plus fort : son début, silence sauté.
    func testLoudestStart() {
        XCTAssertEqual(SampleAudio.loudestStart([0, 0, 0, 0, 1, 1, 1, 0], window: 3), 4)
        XCTAssertEqual(SampleAudio.loudestStart([0, 0, 1, 0.5], window: 30), 2, "son court : depuis son attaque")
        XCTAssertEqual(SampleAudio.loudestStart([], window: 3), 0)
        XCTAssertEqual(SampleAudio.loudestStart([0.2, 0.2, 0.9, 0.9, 0.1], window: 2), 2)
    }

    /// Un vrai fichier : 1,5 s de silence puis 1 s de son ; le passage lu est le son.
    func testLoudestReadsTheSoundAfterTheSilence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("organiser-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let rate = 48_000.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let frames = AVAudioFrameCount(rate * 2.5)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<Int(frames) {
            data[i] = Double(i) >= rate * 1.5 ? Float(0.5 * sin(2 * Double.pi * 440 * Double(i) / rate)) : 0
        }
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                           AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                           AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try file.write(from: buffer)
        }
        let sound = try XCTUnwrap(SampleAudio.loudest(url, seconds: 1))
        XCTAssertEqual(sound.rate, rate)
        XCTAssertEqual(Double(sound.samples.count), rate, accuracy: rate * 0.11)
        XCTAssertGreaterThan(OrganizerSession.peakDB(sound.samples), -10, "le son, pas le silence")
        XCTAssertNil(SampleAudio.loudest(URL(fileURLWithPath: "/nulle/part.wav")))
    }
}
