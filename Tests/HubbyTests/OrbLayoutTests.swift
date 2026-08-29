import XCTest
@testable import Hubby

final class OrbLayoutTests: XCTestCase {
    func testLeadIconSitsAtTwelve() {
        let center = OrbLayout.center(index: 0, spin: 0, pinch: 0)
        let mid = HubbyMetrics.orbDiameter / 2
        XCTAssertEqual(center.x, mid, accuracy: 0.001)
        XCTAssertEqual(center.y, mid - OrbLayout.ringRadius, accuracy: 0.001)
    }

    func testTapOnLeadIconHits() {
        let center = OrbLayout.center(index: 0, spin: 0, pinch: 0)
        XCTAssertEqual(
            OrbLayout.hitIndex(point: center, count: 6, spin: 0, pinch: 0), 0)
    }

    func testTapOnEachIconHitsThatIcon() {
        for index in 0..<6 {
            let center = OrbLayout.center(index: index, spin: 37, pinch: 0)
            XCTAssertEqual(
                OrbLayout.hitIndex(point: center, count: 6, spin: 37, pinch: 0),
                index, "icon \(index)")
        }
    }

    func testTapInDeadCentreMisses() {
        let mid = HubbyMetrics.orbDiameter / 2
        XCTAssertNil(OrbLayout.hitIndex(
            point: CGPoint(x: mid, y: mid), count: 6, spin: 0, pinch: 0))
    }

    func testSpinRotatesTheHit() {
        // After a 60° spin the flower advanced one step: the icon now at
        // twelve o'clock is index 5 (angles moved +60°, so index 5 lands
        // at -90°).
        let twelve = CGPoint(
            x: HubbyMetrics.orbDiameter / 2,
            y: HubbyMetrics.orbDiameter / 2 - OrbLayout.ringRadius)
        XCTAssertEqual(
            OrbLayout.hitIndex(point: twelve, count: 6, spin: -60, pinch: 0), 1)
        XCTAssertEqual(
            OrbLayout.hitIndex(point: twelve, count: 6, spin: 60, pinch: 0), 5)
    }
}
