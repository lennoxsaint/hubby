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

    func testMergeZombieInProgressTurnsAreNotSpinners() {
        // Crashed turns stay `inProgress` in thread_history for days; a
        // thread with no recent activity must not pulse as generating.
        let now = Date()
        let fresh = Int64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1000)
        let stale = Int64(now.addingTimeInterval(-4 * 24 * 3600).timeIntervalSince1970 * 1000)
        let rows = [
            CodexDBRow(id: "live", title: "Fresh", cwd: nil, recencyMs: fresh),
            CodexDBRow(id: "zombie", title: "Stale", cwd: nil, recencyMs: stale),
        ]
        let merged = CodexThreadMerge.merge(
            dbRows: rows, index: [:], activeIDs: ["live", "zombie"], now: now)
        XCTAssertTrue(merged.first { $0.id == "live" }?.isGenerating == true)
        XCTAssertFalse(merged.first { $0.id == "zombie" }?.isGenerating == true)
    }
}
