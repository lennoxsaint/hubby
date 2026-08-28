import XCTest
@testable import Hubby

final class ReadStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "HubbyReadStateTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func snapshot(_ threads: [AgentThread]) -> [AgentSnapshot] {
        [AgentSnapshot(
            info: AgentAppInfo(
                id: "test-app", name: "Test", bundleIDs: [], symbol: "circle", tintHex: 0),
            isRunning: true,
            threads: threads)]
    }

    private func thread(generating: Bool, activity: Date = Date()) -> AgentThread {
        AgentThread(
            id: "t1", title: "Thread", lastActivity: activity,
            subtitle: nil, cwd: nil, isGenerating: generating)
    }

    func testGenerationFinishBecomesUnreadAndReadClears() {
        let store = ReadStateStore(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1000)

        // Observed generating: not unread while the spinner runs.
        var decorated = store.decorate(snapshot([thread(generating: true)]), now: t0)
        XCTAssertFalse(decorated[0].threads[0].isFinishedUnread)

        // Generation ends: unread.
        decorated = store.decorate(snapshot([thread(generating: false)]), now: t0 + 10)
        XCTAssertTrue(decorated[0].threads[0].isFinishedUnread)
        XCTAssertEqual(decorated[0].threads[0].status(now: t0 + 10), .finishedUnread)
        XCTAssertEqual(decorated[0].unreadCount, 1)

        // Jumping marks it read.
        store.markRead(appID: "test-app", threadID: "t1", now: t0 + 20)
        decorated = store.decorate(snapshot([thread(generating: false)]), now: t0 + 30)
        XCTAssertFalse(decorated[0].threads[0].isFinishedUnread)
    }

    func testTrailingActivityDoesNotReflag() {
        let store = ReadStateStore(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = store.decorate(snapshot([thread(generating: true)]), now: t0)
        store.markRead(appID: "test-app", threadID: "t1", now: t0 + 10)

        // The session file keeps getting trailing writes: lastActivity moves,
        // but no new generation was observed — stays read.
        let touched = thread(generating: false, activity: t0 + 500)
        let decorated = store.decorate(snapshot([touched]), now: t0 + 600)
        XCTAssertFalse(decorated[0].threads[0].isFinishedUnread)
    }

    func testNewGenerationRearms() {
        let store = ReadStateStore(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = store.decorate(snapshot([thread(generating: true)]), now: t0)
        store.markRead(appID: "test-app", threadID: "t1", now: t0 + 10)

        // A fresh generation starts and ends after the read: unread again.
        _ = store.decorate(snapshot([thread(generating: true)]), now: t0 + 100)
        let decorated = store.decorate(snapshot([thread(generating: false)]), now: t0 + 200)
        XCTAssertTrue(decorated[0].threads[0].isFinishedUnread)
    }

    func testNeverSeenGeneratingNeverUnread() {
        // First launch over a pile of finished sessions must not light up.
        let store = ReadStateStore(defaults: defaults)
        let decorated = store.decorate(snapshot([thread(generating: false)]))
        XCTAssertFalse(decorated[0].threads[0].isFinishedUnread)
    }

    func testPersistenceRoundTrip() {
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = ReadStateStore(defaults: defaults)
            .decorate(snapshot([thread(generating: true)]), now: t0)

        // A fresh store (new launch) still knows the generation was seen.
        let reloaded = ReadStateStore(defaults: defaults)
        let decorated = reloaded.decorate(snapshot([thread(generating: false)]), now: t0 + 10)
        XCTAssertTrue(decorated[0].threads[0].isFinishedUnread)
    }

    func testPruneDropsAncientEntries() {
        let store = ReadStateStore(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = store.decorate(snapshot([thread(generating: true)]), now: t0)

        // 15 days later any save prunes the stale entry…
        store.markRead(appID: "test-app", threadID: "other", now: t0 + 15 * 24 * 3600)

        // …so a fresh store treats t1 as never seen generating.
        let reloaded = ReadStateStore(defaults: defaults)
        let decorated = reloaded.decorate(
            snapshot([thread(generating: false)]), now: t0 + 15 * 24 * 3600)
        XCTAssertFalse(decorated[0].threads[0].isFinishedUnread)
    }

    func testStatusPriority() {
        var t = thread(generating: true)
        t.isWaitingOnYou = true
        t.isFinishedUnread = true
        XCTAssertEqual(t.status(), .generating)
        t.isGenerating = false
        XCTAssertEqual(t.status(), .waitingOnYou)
        t.isWaitingOnYou = false
        XCTAssertEqual(t.status(), .finishedUnread)
    }
}
