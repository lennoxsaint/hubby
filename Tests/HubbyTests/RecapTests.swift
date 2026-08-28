import XCTest
@testable import Hubby

final class RecapTests: XCTestCase {
    func testFirstSentenceCutsAtBoundary() {
        let text = "The build finished with 38 tests green. Next I would look at the release pipeline and the notarization flow."
        XCTAssertEqual(
            Recap.firstSentence(of: text),
            "The build finished with 38 tests green.")
    }

    func testFirstSentenceTrimsLongRuns() {
        let text = String(repeating: "word ", count: 60)
        let sentence = Recap.firstSentence(of: text)
        XCTAssertNotNil(sentence)
        XCTAssertLessThanOrEqual(sentence!.count, 92)
        XCTAssertTrue(sentence!.hasSuffix("…"))
    }

    func testFirstSentenceFlattensNewlines() {
        XCTAssertEqual(
            Recap.firstSentence(of: "Done!\nEverything passed. More detail follows."),
            "Done! Everything passed.")
    }

    func testFirstSentenceEmptyIsNil() {
        XCTAssertNil(Recap.firstSentence(of: "   \n "))
    }

    func testClaudeCodeSlugFromTail() {
        let tail = Data("""
        {"type":"user","message":{"content":"hi"}}
        {"aiTitle":"hubby-blush-redesign","type":"summary"}
        {"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}
        """.utf8)
        XCTAssertEqual(JSONLParsers.claudeCodeSlug(fromTail: tail), "hubby-blush-redesign")
    }

    func testSlugDominatesWindowScore() {
        let withSlug = WindowLocator.score(
            windowTitle: "◐ hubby-blush-redesign", cwd: "/Users/x/proj",
            threadTitle: "Something unrelated", slug: "hubby-blush-redesign")
        let without = WindowLocator.score(
            windowTitle: "◐ another-session", cwd: "/Users/x/proj",
            threadTitle: "Something unrelated", slug: "hubby-blush-redesign")
        XCTAssertGreaterThanOrEqual(withSlug, 8)
        XCTAssertEqual(without, 0)
    }

    func testCursorBodyTailSkipsPartialSentence() {
        let tail = "artial words from mid sentence. The fix landed cleanly and tests pass."
        XCTAssertEqual(
            CursorSource.recapFromBodyTail(tail),
            "The fix landed cleanly and tests pass.")
    }
}
