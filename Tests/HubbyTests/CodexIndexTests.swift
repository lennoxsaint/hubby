import XCTest
@testable import Hubby

final class CodexIndexTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "Fixtures/\(name)", withExtension: nil))
        return try Data(contentsOf: url)
    }

    func testSessionIndexParsing() throws {
        let entries = JSONLParsers.codexSessionIndex(from: try fixture("codex-session-index.jsonl"))
        // Truncated final line is unparseable JSON and dropped.
        XCTAssertEqual(entries.map(\.id), ["aaa-1", "bbb-2", "ccc-3", "ddd-4", "aaa-1"])

        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        XCTAssertEqual(byID["aaa-1"]?.name, "Renamed Thread") // last entry wins
        XCTAssertNil(byID["ddd-4"]?.name) // empty name → nil
        XCTAssertNil(byID["bbb-2"]?.updatedAt) // malformed date → nil
        XCTAssertNil(byID["ccc-3"]?.updatedAt) // epoch sentinel → nil
        XCTAssertNotNil(byID["aaa-1"]?.updatedAt)
    }

    func testLenientISODate() {
        XCTAssertNotNil(JSONLParsers.lenientISODate("2026-08-26T06:46:37.975102Z"))
        XCTAssertNotNil(JSONLParsers.lenientISODate("2026-08-26T06:46:37Z"))
        XCTAssertNil(JSONLParsers.lenientISODate("2026-05-25T03:16:17.3NZ"))
        XCTAssertNil(JSONLParsers.lenientISODate("2000-01-01T00:00:00Z"))
        XCTAssertNil(JSONLParsers.lenientISODate("garbage"))
    }

    func testMergePrefersIndexNameAndRejectsXMLTitles() {
        let now = Date()
        let rows = [
            CodexDBRow(id: "a", title: "<codex_delegation>junk", cwd: "/tmp/proj-a",
                       recencyMs: Int64(now.timeIntervalSince1970 * 1000)),
            CodexDBRow(id: "b", title: "what's the outbound skill", cwd: nil,
                       recencyMs: Int64(now.timeIntervalSince1970 * 1000) - 1000),
        ]
        let index = ["a": JSONLParsers.CodexIndexEntry(id: "a", name: "Nice Name", updatedAt: nil)]
        let merged = CodexThreadMerge.merge(dbRows: rows, index: index, activeIDs: [])
        XCTAssertEqual(merged.map(\.title), ["Nice Name", "what's the outbound skill"])
    }

    func testMergeXMLTitleFallsBackToCwd() {
        let rows = [CodexDBRow(id: "a", title: "<codex_delegation>", cwd: "/tmp/proj-a", recencyMs: 1000)]
        let merged = CodexThreadMerge.merge(dbRows: rows, index: [:], activeIDs: [])
        XCTAssertEqual(merged.first?.title, "proj-a")
    }

    func testMergeSpinnersSurviveTheCapAndSortFirst() {
        let base = Int64(1_787_720_000_000)
        let rows = (0..<10).map { i in
            CodexDBRow(id: "t\(i)", title: "Thread \(i)", cwd: nil, recencyMs: base - Int64(i) * 1000)
        }
        // t9 is the oldest but generating — it must sort first and survive cap 8.
        let now = Date(timeIntervalSince1970: TimeInterval(base) / 1000 + 60)
        let merged = CodexThreadMerge.merge(dbRows: rows, index: [:], activeIDs: ["t9"], now: now)
        XCTAssertEqual(merged.count, 8)
        XCTAssertEqual(merged.first?.id, "t9")
        XCTAssertTrue(merged.first?.isGenerating == true)
        XCTAssertEqual(merged[1].id, "t0")
    }

    func testMergeExplicitNameBeatsIndexAndTitle() {
        let rows = [CodexDBRow(
            id: "a", name: "Renamed In App", title: "first user msg", cwd: nil,
            recencyMs: 1000, rolloutPath: nil)]
        let index = ["a": JSONLParsers.CodexIndexEntry(id: "a", name: "Index Name", updatedAt: nil)]
        let merged = CodexThreadMerge.merge(dbRows: rows, index: index, activeIDs: [])
        XCTAssertEqual(merged.first?.title, "Renamed In App")
    }
}

final class RolloutTailTests: XCTestCase {
    private func rollout(_ events: [String]) -> Data {
        Data(events.map {
            #"{"timestamp":"2026-08-26T12:00:00.000Z","type":"event_msg","payload":{"type":"\#($0)"}}"#
        }.joined(separator: "\n").utf8)
    }

    func testStartedAfterCompleteIsLive() {
        XCTAssertTrue(RolloutTail.isLive(tail: rollout(
            ["task_started", "task_complete", "task_started", "token_count"])))
    }

    func testCompleteAfterStartedIsIdle() {
        XCTAssertFalse(RolloutTail.isLive(tail: rollout(
            ["task_started", "token_count", "task_complete"])))
    }

    func testStartedWithNoCompleteIsLive() {
        XCTAssertTrue(RolloutTail.isLive(tail: rollout(["session_meta", "task_started"])))
    }

    func testNoMarkersIsIdle() {
        XCTAssertFalse(RolloutTail.isLive(tail: rollout(["session_meta", "token_count"])))
        XCTAssertFalse(RolloutTail.isLive(tail: Data()))
        XCTAssertFalse(RolloutTail.isLive(tail: Data("garbage not json".utf8)))
    }
}

extension CodexIndexTests {
    func testAutomationRunsDedupeAndRankBelowInteractive() {
        let now = Date()
        // Mirrors the wild: the "Automation:" prefix only exists in the
        // raw first-user-message title; the session index supplies the
        // clean display name that actually wins title resolution.
        let rows = (0..<6).map { i in
            CodexDBRow(
                id: "auto\(i)", name: nil, title: "Automation: Ledger Refresh task",
                cwd: nil, recencyMs: Int64((now.timeIntervalSince1970 - Double(i) * 900) * 1000))
        } + [
            CodexDBRow(
                id: "real", name: "THREADIFY OUTBOUND", title: nil, cwd: nil,
                recencyMs: Int64((now.timeIntervalSince1970 - 7200) * 1000)),
        ]
        let index = Dictionary(uniqueKeysWithValues: (0..<6).map {
            ("auto\($0)", JSONLParsers.CodexIndexEntry(
                id: "auto\($0)", name: "Ledger Refresh", updatedAt: nil))
        })
        let merged = CodexThreadMerge.merge(dbRows: rows, index: index, activeIDs: [], cap: 8)
        // One automation row (the newest run), and the older interactive
        // thread outranks it.
        XCTAssertEqual(merged.map(\.id), ["real", "auto0"])
    }
}
