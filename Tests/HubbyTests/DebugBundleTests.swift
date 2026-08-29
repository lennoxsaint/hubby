import XCTest
@testable import Hubby

final class DebugBundleTests: XCTestCase {
    func testHomeCollapsesToTilde() {
        XCTAssertEqual(
            DebugBundle.redact(
                "db at /Users/lennox/Library/x.db", home: "/Users/lennox"),
            "db at ~/Library/x.db")
    }

    func testOtherUsersAreAnonymizedToo() {
        XCTAssertEqual(
            DebugBundle.redact(
                "saw /Users/someone.else/secret and /Users/third/y",
                home: "/Users/lennox"),
            "saw ~/secret and ~/y")
    }

    func testReportCarriesNoUserPaths() {
        let info = AgentAppInfo(
            id: "claude-code", name: "Claude Code", bundleIDs: [],
            symbol: "terminal", tintHex: 0xD97757, iconBundleID: nil)
        let snapshot = AgentSnapshot(info: info, isRunning: true, threads: [])
        let report = DebugBundle.report(
            snapshots: [snapshot], appVersion: "1.1.0",
            osVersion: "macOS 15 at /Users/lennox/whatever",
            axTrusted: false, home: "/Users/lennox")
        XCTAssertTrue(report.contains("app: 1.1.0"))
        XCTAssertTrue(report.contains("claude-code: running=true threads=0"))
        XCTAssertTrue(report.contains("accessibility (exact jumps): not granted"))
        XCTAssertFalse(report.contains("/Users/"))
    }
}
