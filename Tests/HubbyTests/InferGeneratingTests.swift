import XCTest
@testable import Hubby

final class InferGeneratingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testRecentWriteInfersGenerating() {
        XCTAssertTrue(AgentThread.inferGenerating(
            lastActivity: now.addingTimeInterval(-3), now: now))
    }

    func testStaleWriteDoesNot() {
        XCTAssertFalse(AgentThread.inferGenerating(
            lastActivity: now.addingTimeInterval(-30), now: now))
    }

    func testBlockedThreadNeverGenerates() {
        // A thread waiting on the human just wrote its blocked prompt —
        // recency must not override the amber state.
        XCTAssertFalse(AgentThread.inferGenerating(
            lastActivity: now.addingTimeInterval(-1), waiting: true, now: now))
    }

    func testStatusOrderStillHoldsWithInference() {
        var thread = AgentThread(
            id: "t", title: "t", lastActivity: now.addingTimeInterval(-2),
            subtitle: nil, cwd: nil,
            isGenerating: AgentThread.inferGenerating(
                lastActivity: now.addingTimeInterval(-2), now: now))
        XCTAssertEqual(thread.status(now: now), .generating)
        thread.isGenerating = false
        thread.isWaitingOnYou = true
        XCTAssertEqual(thread.status(now: now), .waitingOnYou)
    }
}
