import XCTest
@testable import Hubby

final class PendingPromptTests: XCTestCase {
    private let askLine = """
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_ASK1","name":"AskUserQuestion","input":{"questions":[{"question":"Which palette should the orb use?","header":"Palette","multiSelect":false,"options":[{"label":"Blush frost","description":"Warm pink glass. Soft."},{"label":"Ink black","description":"The old look."}]}]}}]}}
    """

    func testPendingAskUserQuestionIsDetectedWithOptions() {
        let tail = Data(askLine.utf8)
        let prompt = JSONLParsers.claudeCodePendingPrompt(fromTail: tail)
        XCTAssertEqual(prompt?.kind, .choose)
        XCTAssertEqual(prompt?.toolUseID, "toolu_ASK1")
        XCTAssertEqual(prompt?.options.map(\.label), ["Blush frost", "Ink black"])
        XCTAssertEqual(prompt?.actuatable, true)
    }

    func testAnsweredPromptIsNotPending() {
        // The answered record echoes the options back — id correlation,
        // not option presence, must decide.
        let tail = Data((askLine + "\n" + """
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ASK1","content":"chosen"}]},"toolUseResult":{"answers":{"Which palette should the orb use?":"Blush frost"}}}
        """).utf8)
        XCTAssertNil(JSONLParsers.claudeCodePendingPrompt(fromTail: tail))
    }

    func testConversationMovingOnClearsPending() {
        let tail = Data((askLine + "\n" + """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Moving on without the answer."}]}}
        """).utf8)
        XCTAssertNil(JSONLParsers.claudeCodePendingPrompt(fromTail: tail))
    }

    func testBookkeepingLinesDoNotClearPending() {
        let tail = Data((askLine + "\n" + """
        {"type":"bridge-session","sessionId":"x"}
        """).utf8)
        XCTAssertNotNil(JSONLParsers.claudeCodePendingPrompt(fromTail: tail))
    }

    func testExitPlanModeIsApproveWithPlanTitle() {
        let tail = Data("""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_PLAN","name":"ExitPlanMode","input":{"plan":"# Ship the fidget orb\\n\\nDetails follow."}}]}}
        """.utf8)
        let prompt = JSONLParsers.claudeCodePendingPrompt(fromTail: tail)
        XCTAssertEqual(prompt?.kind, .approve)
        XCTAssertEqual(prompt?.question, "Approve plan: Ship the fidget orb")
        // Plan approvals are never blind-typed: the dialog's option list
        // is dynamic, so the pill jumps instead.
        XCTAssertEqual(prompt?.actuatable, false)
    }

    func testMultiQuestionPromptIsNotActuatable() {
        let tail = Data("""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_M","name":"AskUserQuestion","input":{"questions":[{"question":"A?","options":[{"label":"x"}]},{"question":"B?","options":[{"label":"y"}]}]}}]}}
        """.utf8)
        let prompt = JSONLParsers.claudeCodePendingPrompt(fromTail: tail)
        XCTAssertEqual(prompt?.actuatable, false)
        XCTAssertNotNil(prompt) // still shows as blocked
    }

    func testKeymap() {
        let choose = PendingPrompt(
            kind: .choose, question: "q",
            options: [.init(label: "a", description: nil), .init(label: "b", description: nil)],
            toolUseID: "t")
        // Arrow navigation, not digits: the plain QuestionView only
        // handles up/down/return, and focus starts on option 1.
        XCTAssertEqual(PromptKeymap.keys(for: choose, optionIndex: 0), [.return])
        XCTAssertEqual(PromptKeymap.keys(for: choose, optionIndex: 1), [.down, .return])
        XCTAssertNil(PromptKeymap.keys(for: choose, optionIndex: 5))
        let approve = PendingPrompt(kind: .approve, question: "q", options: [], toolUseID: "t")
        XCTAssertNil(PromptKeymap.keys(for: approve, optionIndex: nil))
    }

    func testThreadTiers() {
        func thread(_ id: String, waiting: Bool = false, pinned: Bool = false) -> AgentThread {
            var thread = AgentThread(
                id: id, title: id, lastActivity: .distantPast, subtitle: nil, cwd: nil)
            thread.isWaitingOnYou = waiting
            thread.isPinned = pinned
            return thread
        }
        let tiered = ThreadTiers.tiered([
            thread("recent1"), thread("pinned1", pinned: true),
            thread("blocked1", waiting: true), thread("recent2"),
        ])
        XCTAssertEqual(tiered.map(\.id), ["blocked1", "pinned1", "recent1", "recent2"])
        XCTAssertEqual(ThreadTiers.dividerIndex(tiered), 2)
        XCTAssertNil(ThreadTiers.dividerIndex([thread("a"), thread("b")]))
        XCTAssertNil(ThreadTiers.dividerIndex([thread("a", pinned: true)]))
    }

    func testPinStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "HubbyPinTests-\(UUID().uuidString)")!
        let store = ThreadPinStore(defaults: defaults)
        XCTAssertFalse(store.isPinned(appID: "codex", threadID: "t1"))
        store.toggle(appID: "codex", threadID: "t1")
        XCTAssertTrue(store.isPinned(appID: "codex", threadID: "t1"))
        XCTAssertTrue(ThreadPinStore(defaults: defaults).isPinned(appID: "codex", threadID: "t1"))
        store.toggle(appID: "codex", threadID: "t1")
        XCTAssertFalse(store.isPinned(appID: "codex", threadID: "t1"))
    }
}
