import XCTest
@testable import Hubby

final class DismissedThreadsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "DismissedThreadsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func snapshot(threads: [AgentThread]) -> AgentSnapshot {
        AgentSnapshot(
            info: AgentAppInfo(
                id: "app", name: "App", bundleIDs: [], symbol: "circle", tintHex: 0),
            isRunning: true, threads: threads)
    }

    private func thread(_ id: String, activity: Date) -> AgentThread {
        AgentThread(id: id, title: id, lastActivity: activity, subtitle: nil, cwd: nil)
    }

    func testDismissedThreadIsHidden() {
        let store = DismissedThreadStore(defaults: freshDefaults())
        let old = thread("t1", activity: Date(timeIntervalSinceNow: -100))
        store.dismiss(appID: "app", threadID: "t1")
        let filtered = store.filter([snapshot(threads: [old])])
        XCTAssertTrue(filtered[0].threads.isEmpty)
    }

    func testNewActivityRevivesAndForgets() {
        let store = DismissedThreadStore(defaults: freshDefaults())
        store.dismiss(appID: "app", threadID: "t1", now: Date(timeIntervalSinceNow: -100))
        let woken = thread("t1", activity: Date())
        let filtered = store.filter([snapshot(threads: [woken])])
        XCTAssertEqual(filtered[0].threads.map(\.id), ["t1"])
        // The dismissal is forgotten: even an OLD reading of the same
        // thread stays visible from now on.
        let stale = thread("t1", activity: Date(timeIntervalSinceNow: -100))
        XCTAssertEqual(store.filter([snapshot(threads: [stale])])[0].threads.count, 1)
    }

    func testDismissalPersistsAcrossInstances() {
        let defaults = freshDefaults()
        DismissedThreadStore(defaults: defaults).dismiss(appID: "app", threadID: "t1")
        let reloaded = DismissedThreadStore(defaults: defaults)
        let old = thread("t1", activity: Date(timeIntervalSinceNow: -100))
        XCTAssertTrue(reloaded.filter([snapshot(threads: [old])])[0].threads.isEmpty)
    }

    func testOtherThreadsUntouched() {
        let store = DismissedThreadStore(defaults: freshDefaults())
        store.dismiss(appID: "app", threadID: "t1")
        let other = thread("t2", activity: Date(timeIntervalSinceNow: -100))
        XCTAssertEqual(store.filter([snapshot(threads: [other])])[0].threads.map(\.id), ["t2"])
    }
}
