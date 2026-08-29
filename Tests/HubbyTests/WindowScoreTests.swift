import XCTest
@testable import Hubby

final class WindowScoreTests: XCTestCase {
    private let cwd = "/Users/lennox/code/hubby"

    func testFolderAsTitleSegmentWinsOverSubstring() {
        // Ghostty/iTerm style: "folder — command".
        let exact = WindowLocator.score(
            windowTitle: "hubby — claude", cwd: cwd, threadTitle: nil, hints: ["claude"])
        // Another project whose title merely contains the letters.
        let loose = WindowLocator.score(
            windowTitle: "hubby-website — zsh", cwd: cwd, threadTitle: nil, hints: ["claude"])
        XCTAssertGreaterThan(exact, loose)
        XCTAssertGreaterThanOrEqual(exact, 5) // segment match + hint
    }

    func testPathFormsMatch() {
        // Terminal.app style: the cwd path itself.
        XCTAssertGreaterThanOrEqual(
            WindowLocator.score(
                windowTitle: "lennox — -zsh — /Users/lennox/code/hubby — 80×24",
                cwd: cwd, threadTitle: nil),
            6) // folder segment + path containment
        // Tail form ("code/hubby") common in prompt-styled titles.
        XCTAssertGreaterThanOrEqual(
            WindowLocator.score(
                windowTitle: "wez: code/hubby", cwd: cwd, threadTitle: nil),
            6)
    }

    func testEditorTitleWithFileAndProject() {
        // VS Code/Cursor style: "file — project — app".
        XCTAssertGreaterThanOrEqual(
            WindowLocator.score(
                windowTitle: "RootView.swift — hubby — Visual Studio Code",
                cwd: cwd, threadTitle: nil),
            4)
    }

    func testThreadTitleFallback() {
        // No cwd (Cursor chats): leading words of the thread title.
        XCTAssertEqual(
            WindowLocator.score(
                windowTitle: "refactor the panel controller — cursor",
                cwd: nil, threadTitle: "Refactor the panel controller into two files"),
            2)
        // Too-short prefixes must not match everything.
        XCTAssertEqual(
            WindowLocator.score(windowTitle: "a — cursor", cwd: nil, threadTitle: "a b"),
            0)
    }

    func testNoSignalScoresZero() {
        XCTAssertEqual(
            WindowLocator.score(
                windowTitle: "somethingelse — vim", cwd: cwd, threadTitle: "Fix panel"),
            0)
        XCTAssertEqual(WindowLocator.score(windowTitle: "", cwd: cwd, threadTitle: "x"), 0)
    }

    func testSlugMatchClearsTheExactnessBar() {
        // Ghostty tab titles are "✳ <aiTitle>" — the prefix must not block
        // the slug hit, and a slug hit alone must reach slugWeight so the
        // adapter can honestly claim an exact landing.
        XCTAssertGreaterThanOrEqual(
            WindowLocator.score(
                windowTitle: "✳ hubby-snappy-timings-card-gutter",
                cwd: cwd, threadTitle: nil, slug: "hubby-snappy-timings-card-gutter"),
            WindowLocator.slugWeight)
    }

    func testSiblingTabSharingCwdStaysBelowExactness() {
        // Sessions in the same cwd produce tabs that match on folder/path/
        // hint but NOT the slug — every such signal combined must stay
        // below slugWeight, or a wrong tab could be typed into.
        XCTAssertLessThan(
            WindowLocator.score(
                windowTitle: "✳ some-other-session — hubby — claude",
                cwd: cwd, threadTitle: "Fix the panel hierarchy",
                slug: "hubby-snappy-timings-card-gutter", hints: ["claude"]),
            WindowLocator.slugWeight)
    }

    func testHintAloneIsWeakButNonzero() {
        XCTAssertEqual(
            WindowLocator.score(
                windowTitle: "claude", cwd: "/Users/x/other", threadTitle: nil,
                hints: ["claude"]),
            1)
    }
}
