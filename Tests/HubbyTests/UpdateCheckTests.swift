import XCTest
@testable import Hubby

final class UpdateCheckTests: XCTestCase {
    func testNewerPatchMinorMajor() {
        XCTAssertTrue(SemVer.isNewer("1.1.1", than: "1.1.0"))
        XCTAssertTrue(SemVer.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(SemVer.isNewer("2.0.0", than: "1.9.9"))
    }

    func testEqualAndOlderAreNotNewer() {
        XCTAssertFalse(SemVer.isNewer("1.1.0", than: "1.1.0"))
        XCTAssertFalse(SemVer.isNewer("1.0.9", than: "1.1.0"))
        XCTAssertFalse(SemVer.isNewer("0.9.0", than: "1.0.0"))
    }

    func testMissingComponentsMeanZero() {
        XCTAssertFalse(SemVer.isNewer("1.1", than: "1.1.0"))
        XCTAssertTrue(SemVer.isNewer("1.1.1", than: "1.1"))
    }

    func testDoubleDigitComponentsCompareNumerically() {
        XCTAssertTrue(SemVer.isNewer("1.10.0", than: "1.9.0"))
    }

    func testJunkIsNeverNewer() {
        XCTAssertFalse(SemVer.isNewer("latest", than: "1.0.0"))
        XCTAssertFalse(SemVer.isNewer("", than: "1.0.0"))
        // Junk CURRENT must not make everything an update either.
        XCTAssertFalse(SemVer.isNewer("1.0.0", than: "unknown"))
    }

    func testPrereleaseComparesByNumericCore() {
        XCTAssertTrue(SemVer.isNewer("1.2.0-beta.1", than: "1.1.0"))
    }

    @MainActor
    func testDisableClearsAvailableAndSeenSurvivesRestart() {
        let defaults = UserDefaults(suiteName: "UpdateCheckTests")!
        defaults.removePersistentDomain(forName: "UpdateCheckTests")
        defaults.set("9.9.9", forKey: "HubbyUpdateCheck.latestSeen")

        let checker = UpdateChecker(defaults: defaults, currentVersion: "1.1.0")
        XCTAssertEqual(checker.availableVersion, "9.9.9") // remembered offline

        checker.isEnabled = false
        XCTAssertNil(checker.availableVersion) // opting out silences the item
        defaults.removePersistentDomain(forName: "UpdateCheckTests")
    }
}
