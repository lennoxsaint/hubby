import XCTest
@testable import Hubby

@MainActor
final class PriorityStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "PriorityStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func freshHistoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PriorityStoreTests-\(UUID().uuidString).jsonl")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeStore(
        defaults: UserDefaults? = nil, historyURL: URL? = nil
    ) -> PriorityStore {
        PriorityStore(
            defaults: defaults ?? freshDefaults(),
            historyURL: historyURL ?? freshHistoryURL())
    }

    func testAlwaysThreeSlots() {
        let store = makeStore()
        XCTAssertEqual(store.slots.count, 3)
        XCTAssertTrue(store.slots.allSatisfy { $0.text.isEmpty && $0.checkedAt == nil })
    }

    func testPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let history = freshHistoryURL()
        let store = PriorityStore(defaults: defaults, historyURL: history)
        store.setText("Ship the milestone", at: 0)
        store.setText("Call Davide", at: 2)
        let reloaded = PriorityStore(defaults: defaults, historyURL: history)
        XCTAssertEqual(reloaded.slots[0].text, "Ship the milestone")
        XCTAssertEqual(reloaded.slots[2].text, "Call Davide")
    }

    func testMoveReorders() {
        let store = makeStore()
        store.setText("a", at: 0)
        store.setText("b", at: 1)
        store.setText("c", at: 2)
        store.move(from: 2, to: 0)
        XCTAssertEqual(store.slots.map(\.text), ["c", "a", "b"])
    }

    func testFinishPromotesTheQueue() {
        // Completing #1: 2 -> 1, 3 -> 2, and slot 3 opens fresh.
        let store = makeStore()
        store.setText("first", at: 0)
        store.setText("second", at: 1)
        store.setText("third", at: 2)
        store.setChecked(true, at: 0)
        store.finish(at: 0)
        XCTAssertEqual(store.slots.map(\.text), ["second", "third", ""])
        XCTAssertNil(store.slots[2].checkedAt)
    }

    func testFinishWritesTheLedger() {
        let history = freshHistoryURL()
        let store = makeStore(historyURL: history)
        store.setText("write the ledger", at: 1)
        store.setChecked(true, at: 1)
        store.finish(at: 1)
        let records = store.history()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].text, "write the ledger")
        XCTAssertEqual(records[0].rank, 2)
        XCTAssertNotNil(records[0].createdAt)
        XCTAssertNotNil(records[0].secondsOnList)
    }

    func testFinishingAnEmptySlotRecordsNothing() {
        let history = freshHistoryURL()
        let store = makeStore(historyURL: history)
        store.finish(at: 0)
        XCTAssertTrue(store.history().isEmpty)
        XCTAssertEqual(store.slots.count, 3)
    }

    func testCheckedBeyondGraceFinishesOnReload() {
        // Ticked, then the app quit: next launch records the completion
        // and arrives already promoted.
        let defaults = freshDefaults()
        let history = freshHistoryURL()
        let store = PriorityStore(defaults: defaults, historyURL: history)
        store.setText("done thing", at: 0)
        store.setText("survivor", at: 1)
        store.setChecked(true, at: 0, now: Date(timeIntervalSinceNow: -60))
        let reloaded = PriorityStore(defaults: defaults, historyURL: history)
        XCTAssertEqual(reloaded.slots.map(\.text), ["survivor", "", ""])
        XCTAssertEqual(reloaded.history().map(\.text), ["done thing"])
    }

    func testCheckedWithinGraceSurvivesReload() {
        let defaults = freshDefaults()
        let history = freshHistoryURL()
        let store = PriorityStore(defaults: defaults, historyURL: history)
        store.setText("just ticked", at: 0)
        store.setChecked(true, at: 0)
        let reloaded = PriorityStore(defaults: defaults, historyURL: history)
        XCTAssertEqual(reloaded.slots[0].text, "just ticked")
        XCTAssertNotNil(reloaded.slots[0].checkedAt)
    }
}
