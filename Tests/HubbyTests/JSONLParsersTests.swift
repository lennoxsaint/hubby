import XCTest
@testable import Hubby

final class JSONLParsersTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testClaudeCodeTitleFromFirstUserMessage() throws {
        let data = try fixture("claude-session")
        XCTAssertEqual(JSONLParsers.claudeCodeTitle(fromHead: data),
                       "Help me build the floating hub app")
    }

    func testClaudeCodeCwd() throws {
        let data = try fixture("claude-session")
        XCTAssertEqual(JSONLParsers.claudeCodeCwd(fromHead: data), "/Users/lennoxsaint/hubby")
    }

    func testClaudeCodeSummaryWinsAndCommandPayloadsSkipped() throws {
        let data = try fixture("claude-session-summary")
        XCTAssertEqual(JSONLParsers.claudeCodeTitle(fromHead: data),
                       "Hubby orb morph animation fixes")
    }

    func testCodexMeta() throws {
        let data = try fixture("codex-rollout")
        let meta = try XCTUnwrap(JSONLParsers.codexMeta(fromHead: data))
        XCTAssertEqual(meta.title, "growth-pilot")
        XCTAssertEqual(meta.cwd, "/Users/lennoxsaint/Documents/Codex/growth-pilot")
    }

    func testClaudeCodeRecapIsLastAssistantText() throws {
        let data = try fixture("claude-session")
        XCTAssertEqual(JSONLParsers.claudeCodeRecap(fromTail: data), "Sure.")
    }

    func testCodexRecapPrefersNewestAgentMessage() throws {
        let data = try fixture("codex-rollout-tail")
        // The event_msg agent_message is newer than the response_item text.
        XCTAssertEqual(
            JSONLParsers.codexRecap(fromTail: data),
            "Shipped the fix and all tests pass.")
    }

    func testCodexRecapReadsResponseItemShape() {
        let line = Data("""
            {"type":"response_item","payload":{"type":"message","role":"assistant",\
            "content":[{"type":"output_text","text":"From the item stream."}]}}
            """.utf8)
        XCTAssertEqual(JSONLParsers.codexRecap(fromTail: line), "From the item stream.")
    }

    func testGarbageInputReturnsNil() {
        let garbage = Data("not json\n{broken".utf8)
        XCTAssertNil(JSONLParsers.claudeCodeTitle(fromHead: garbage))
        XCTAssertNil(JSONLParsers.codexMeta(fromHead: garbage))
        XCTAssertNil(JSONLParsers.claudeCodeRecap(fromTail: garbage))
        XCTAssertNil(JSONLParsers.codexRecap(fromTail: garbage))
    }

    func testLongTitleIsTruncated() {
        let long = String(repeating: "a", count: 200)
        let line = Data("{\"type\":\"summary\",\"summary\":\"\(long)\"}".utf8)
        let title = JSONLParsers.claudeCodeTitle(fromHead: line)
        XCTAssertEqual(title?.count, 61) // 60 chars + ellipsis
    }
}
