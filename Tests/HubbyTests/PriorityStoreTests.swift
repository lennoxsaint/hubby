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

    func testAlwaysThreeSlots() {
        let store = PriorityStore(defaults: freshDefaults())
        XCTAssertEqual(store.slots.count, 3)
        XCTAssertTrue(store.slots.allSatisfy { $0.text.isEmpty && $0.checkedAt == nil })
    }

    func testPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let store = PriorityStore(defaults: defaults)
        store.slots[0].text = "Ship the milestone"
        store.slots[2].text = "Call Davide"
        let reloaded = PriorityStore(defaults: defaults)
        XCTAssertEqual(reloaded.slots[0].text, "Ship the milestone")
        XCTAssertEqual(reloaded.slots[2].text, "Call Davide")
    }

    func testMoveReorders() {
        let store = PriorityStore(defaults: freshDefaults())
        store.slots[0].text = "a"
        store.slots[1].text = "b"
        store.slots[2].text = "c"
        store.move(from: 2, to: 0)
        XCTAssertEqual(store.slots.map(\.text), ["c", "a", "b"])
        store.move(from: 0, to: 1)
        XCTAssertEqual(store.slots.map(\.text), ["a", "c", "b"])
    }

    func testCheckedBeyondGraceClearsOnReload() {
        let defaults = freshDefaults()
        let store = PriorityStore(defaults: defaults)
        store.slots[0].text = "done thing"
        store.setChecked(true, at: 0, now: Date(timeIntervalSinceNow: -60))
        let reloaded = PriorityStore(defaults: defaults)
        XCTAssertEqual(reloaded.slots[0].text, "")
        XCTAssertNil(reloaded.slots[0].checkedAt)
    }

    func testCheckedWithinGraceSurvivesReload() {
        let defaults = freshDefaults()
        let store = PriorityStore(defaults: defaults)
        store.slots[0].text = "just ticked"
        store.setChecked(true, at: 0)
        let reloaded = PriorityStore(defaults: defaults)
        XCTAssertEqual(reloaded.slots[0].text, "just ticked")
        XCTAssertNotNil(reloaded.slots[0].checkedAt)
    }
}
