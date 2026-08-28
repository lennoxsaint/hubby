import XCTest
@testable import Hubby

final class FanRotationTests: XCTestCase {
    private func snapshots(_ ids: [String]) -> [AgentSnapshot] {
        ids.map {
            AgentSnapshot(
                info: AgentAppInfo(
                    id: $0, name: $0, bundleIDs: [], symbol: "circle", tintHex: 0),
                isRunning: false,
                threads: [])
        }
    }

    func testRotation() {
        let base = snapshots(["a", "b", "c"])
        XCTAssertEqual(FanRotation.rotated(base, top: nil).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(FanRotation.rotated(base, top: "a").map(\.id), ["a", "b", "c"])
        XCTAssertEqual(FanRotation.rotated(base, top: "b").map(\.id), ["b", "c", "a"])
        XCTAssertEqual(FanRotation.rotated(base, top: "c").map(\.id), ["c", "a", "b"])
        // A refresh dropped the pinned app: smart order, no crash.
        XCTAssertEqual(FanRotation.rotated(base, top: "gone").map(\.id), ["a", "b", "c"])
        XCTAssertEqual(FanRotation.rotated([], top: "a").map(\.id), [])
    }

    func testCycling() {
        let order = ["a", "b", "c"]
        // First swipe from the natural top pushes 'a' under: 'b' rises.
        XCTAssertEqual(FanRotation.cycled(order, from: nil, direction: 1), "b")
        XCTAssertEqual(FanRotation.cycled(order, from: "b", direction: 1), "c")
        XCTAssertEqual(FanRotation.cycled(order, from: "c", direction: 1), "a") // wraps
        // The other direction pulls the bottom card back up.
        XCTAssertEqual(FanRotation.cycled(order, from: nil, direction: -1), "c")
        XCTAssertEqual(FanRotation.cycled(order, from: "b", direction: -1), "a")
        // A vanished pin restarts from the natural top.
        XCTAssertEqual(FanRotation.cycled(order, from: "gone", direction: 1), "b")
        XCTAssertNil(FanRotation.cycled([], from: nil, direction: 1))
    }
}
