import XCTest
@testable import Hubby

final class RecapTests: XCTestCase {
    func testPlainStripsMarkdown() {
        let raw = """
        ## Done ✅
        - Fixed the **parser** in `windows.js`
        - See [the docs](https://example.com/docs)

        ```swift
        let x = 1
        ```
        All 38 tests green.
        """
        XCTAssertEqual(
            RecapText.plain(raw),
            "Done ✅ Fixed the parser in windows.js See the docs All 38 tests green.")
    }

    func testPlainDropsRulesAndOrderedMarkers() {
        XCTAssertEqual(
            RecapText.plain("1. First thing\n---\n2) Second thing"),
            "First thing Second thing")
    }

    func testExcerptShortTextPassesThrough() {
        XCTAssertEqual(RecapText.excerpt("Build finished."), "Build finished.")
    }

    func testExcerptKeepsWholeSentencesUnderLimit() {
        let text = "The build finished with 38 tests green. Next I would look at the "
            + "release pipeline. Then the notarization flow needs a full dry run "
            + "before anything ships to users at all."
        let excerpt = RecapText.excerpt(text)
        XCTAssertEqual(
            excerpt,
            "The build finished with 38 tests green. Next I would look at the release pipeline.")
    }

    func testExcerptSkipsAbbreviationsAndDottedNumbers() {
        let text = "Ship v1. 2 fixes the flag, e.g. the retry path works now. "
            + String(repeating: "Padding sentence follows here. ", count: 6)
        let excerpt = RecapText.excerpt(text)
        XCTAssertEqual(
            excerpt?.hasPrefix("Ship v1. 2 fixes the flag, e.g. the retry path works now."),
            true)
    }

    func testExcerptWordBoundaryCutWhenNoSentenceFits() {
        let text = String(repeating: "word ", count: 60)
        let excerpt = RecapText.excerpt(text)
        XCTAssertNotNil(excerpt)
        XCTAssertLessThanOrEqual(excerpt!.count, 141)
        XCTAssertTrue(excerpt!.hasSuffix("…"))
        XCTAssertFalse(excerpt!.contains("wor…")) // never mid-word
    }

    func testExcerptEmptyIsNil() {
        XCTAssertNil(RecapText.excerpt("   \n "))
        XCTAssertNil(RecapText.excerpt("```\ncode only\n```"))
    }

    func testRecapCapsAtWordBoundary() {
        let recap = RecapText.recap(String(repeating: "alpha ", count: 60))
        XCTAssertNotNil(recap)
        XCTAssertLessThanOrEqual(recap!.count, 201)
        XCTAssertTrue(recap!.hasSuffix("…"))
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

}
