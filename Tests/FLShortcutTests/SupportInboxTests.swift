@testable import FLShortcut
import XCTest

/// Aide › Mes messages (20/11) : lecture des messages du serveur, état (envoyé, réponse vue, nouvelle réponse),
/// serveur d'avant reconnu, « Ça t'aide peut-être ».
final class SupportInboxTests: XCTestCase {
    func testThreadsAreReadWithTheirRepliesInOrder() throws {
        let json = """
        [{"id":"6f1d2c1e-0000-4000-8000-0000000000a1","kind":"autre","reference":"FLS-3F9A2C",
          "message":"Export Stems s'arrête.\\nAu menu Export.","created_at":"2026-11-17T10:00:00+00:00",
          "support_replies":[
            {"id":"6f1d2c1e-0000-4000-8000-0000000000b2","team":false,"message":"Merci","created_at":"2026-11-18T10:00:00+00:00"},
            {"id":"6f1d2c1e-0000-4000-8000-0000000000b1","team":true,"message":"Corrigé","created_at":"2026-11-18T09:00:00+00:00"}]}]
        """
        let threads = try JSONDecoder().decode([SupportThread].self, from: Data(json.utf8))
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].firstLine, "Export Stems s'arrête.")
        XCTAssertEqual(threads[0].replies.map(\.message), ["Corrigé", "Merci"])
        XCTAssertEqual(threads[0].kindLabel, SupportKind.autre.label)
    }

    func testStateFollowsTheTeamsLastReply() {
        var thread = SupportInbox.demoThreads[1]
        XCTAssertEqual(SupportInboxRules.state(thread, seen: []), .sent)
        let answer = SupportReply(id: UUID(), team: true, message: "Oui", createdAt: "2026-11-19T10:00:00+00:00")
        thread.replies.append(answer)
        XCTAssertEqual(SupportInboxRules.state(thread, seen: []), .newAnswer)
        XCTAssertEqual(SupportInboxRules.state(thread, seen: [answer.id]), .answered)
        // Ma propre réponse après la sienne ne la rend pas « nouvelle ».
        thread.replies.append(SupportReply(id: UUID(), team: false, message: "Merci", createdAt: "2026-11-19T11:00:00+00:00"))
        XCTAssertEqual(SupportInboxRules.state(thread, seen: [answer.id]), .answered)
        XCTAssertEqual(SupportInboxRules.unread([thread, SupportInbox.demoThreads[0]], seen: [answer.id]), 1)
    }

    func testOldServerIsRecognised() {
        XCTAssertTrue(SupportInboxRules.isMissing(status: 404, message: ""))
        XCTAssertTrue(SupportInboxRules.isMissing(
            status: 400, message: "Could not find a relationship between 'support_requests' and 'support_replies'"))
        XCTAssertFalse(SupportInboxRules.isMissing(status: 401, message: "JWT expired"))
        XCTAssertTrue(SupportInboxRules.needsOldForm(
            status: 400, message: "new row violates check constraint \"support_requests_kind_check\""))
        XCTAssertTrue(SupportInboxRules.needsOldForm(status: 400, message: "Could not find the 'capture' column"))
        XCTAssertFalse(SupportInboxRules.needsOldForm(status: 429, message: "Trop de messages en ce moment"))
    }

    func testTipsComeFromTheWordsOfTheMessage() {
        let faq = [HelpEntry(id: 1, question: "FL ne répond pas au lien", answer: "Relance FL.", keywords: "midi"),
                   HelpEntry(id: 2, question: "Exporter mes macros", answer: "Macros › Exporter.")]
        XCTAssertEqual(SupportInboxRules.tips(for: "Le lien MIDI ne marche plus", kind: .probleme, in: faq).map(\.id), [1])
        XCTAssertTrue(SupportInboxRules.tips(for: "Le lien MIDI", kind: .idee, in: faq).isEmpty)
        XCTAssertTrue(SupportInboxRules.tips(for: "a b c", kind: .question, in: faq).isEmpty)
    }

    func testCaptureStaysUnderTheServerLimit() throws {
        let side = 2400
        let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side / 2, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for i in 0..<200 {
            context.setFillColor(CGColor(red: CGFloat(i % 7) / 7, green: CGFloat(i % 5) / 5, blue: CGFloat(i % 3) / 3, alpha: 1))
            context.fill(CGRect(x: (i * 37) % side, y: (i * 53) % (side / 2), width: 90, height: 60))
        }
        let image = try XCTUnwrap(context.makeImage())
        let text = try XCTUnwrap(SupportCapture.base64(from: image))
        XCTAssertLessThanOrEqual(text.count, SupportCapture.maxBase64)
        XCTAssertTrue(text.hasPrefix("/9j/"))
        let back = try XCTUnwrap(SupportCapture.image(text))
        XCTAssertLessThanOrEqual(Int(back.representations.first?.pixelsWide ?? 0), SupportCapture.maxWidth)
    }
}
