import AppKit
import ApplicationServices

/// Finds and raises the specific window a thread lives in, via the
/// Accessibility API. This is how "jump to thread" lands exactly for apps
/// that expose no per-thread URL route (all of them except Codex): terminal
/// and editor windows are titled after their working directory, so a
/// thread's cwd/title can pick the right one.
///
/// Requires the user's Accessibility grant (TCC); everything degrades to
/// plain app activation without it. Note for testing: TCC keys the grant to
/// the binary, so a `swift build` debug run and `dist/Hubby.app` hold
/// separate grants.
enum WindowLocator {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Trigger the system consent prompt and open the Accessibility pane.
    static func promptForTrust() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Raise the best-scoring window across every running app matching
    /// `bundleIDs`, then select the best-scoring TAB inside it. Ghostty
    /// (and any AXTabGroup terminal) exposes ONE AXWindow whose title is
    /// the *active* tab's; the other tabs are AXRadioButtons inside an
    /// AXTabGroup — raising the window alone lands on whatever tab happens
    /// to be frontmost, so the tab titles are scored too and the winner is
    /// pressed before the raise. Returns the best score achieved (0 = no
    /// match or no grant) so callers can tell an exact landing
    /// (`score >= slugWeight`) from a lucky window.
    static func raiseWindow(bundleIDs: [String], scorer: (String) -> Int) -> Int {
        guard isTrusted else { return 0 }
        var best: (score: Int, window: AXUIElement, tab: AXUIElement?, app: NSRunningApplication)?
        for app in NSWorkspace.shared.runningApplications
        where bundleIDs.contains(app.bundleIdentifier ?? "") {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            // A hung app must never freeze a jump.
            AXUIElementSetMessagingTimeout(element, 0.3)
            var value: CFTypeRef?
            let copyResult = AXUIElementCopyAttributeValue(
                element, kAXWindowsAttribute as CFString, &value)
            guard copyResult == .success, let windows = value as? [AXUIElement] else {
                // A failure here with isTrusted true is the stale-TCC
                // signature: the binary changed and macOS quietly broke
                // the grant until it's toggled off/on in System Settings.
                debugLog("windows-copy failed app=\(app.bundleIdentifier ?? "?") "
                    + "err=\(copyResult.rawValue)")
                continue
            }
            for window in windows {
                // Editors put the file path in AXDocument; terminals title
                // themselves after the cwd. Score whichever reads higher.
                let title = string(of: window, kAXTitleAttribute) ?? ""
                let document = string(of: window, kAXDocumentAttribute) ?? ""
                let windowScore = max(scorer(title), scorer(document))
                var bestTab: (score: Int, tab: AXUIElement)?
                for tab in tabRadioButtons(of: window) {
                    let tabTitle = string(of: tab, kAXTitleAttribute) ?? ""
                    let tabScore = scorer(tabTitle)
                    debugLog("  tab \"\(tabTitle)\" score=\(tabScore)")
                    if tabScore > (bestTab?.score ?? 0) { bestTab = (tabScore, tab) }
                }
                let score = max(windowScore, bestTab?.score ?? 0)
                debugLog(
                    "window app=\(app.bundleIdentifier ?? "?") \"\(title)\" "
                        + "score=\(windowScore) bestTab=\(bestTab?.score ?? 0)")
                if score > (best?.score ?? 0) {
                    // Press the tab only when it matches at least as well as
                    // the window's own title (which mirrors the active tab).
                    let tab = bestTab.flatMap { $0.score >= windowScore ? $0.tab : nil }
                    best = (score, window, tab, app)
                }
            }
        }
        guard let best else { return 0 }
        if let tab = best.tab {
            AXUIElementPerformAction(tab, kAXPressAction as CFString)
        }
        AXUIElementSetAttributeValue(best.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(best.window, kAXRaiseAction as CFString)
        best.app.activate()
        return best.score
    }

    /// The tabs of an AXTabGroup window (Ghostty's shape: one window, one
    /// tab group, one radio button per tab). Empty for apps whose tabs are
    /// separate AX windows — they're covered by the window loop itself.
    private static func tabRadioButtons(of window: AXUIElement) -> [AXUIElement] {
        for child in elements(of: window, kAXChildrenAttribute)
        where role(of: child) == "AXTabGroup" {
            return elements(of: child, kAXChildrenAttribute)
                .filter { role(of: $0) == kAXRadioButtonRole as String }
        }
        return []
    }

    private static func elements(of element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func role(of element: AXUIElement) -> String? {
        string(of: element, kAXRoleAttribute)
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Candidate windows/tabs and their scores, on HUBBY_DEBUG — silent
    /// matching is why the Ghostty tab bug went undiagnosed.
    private static func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["HUBBY_DEBUG"] != nil else { return }
        FileHandle.standardError.write(Data("locator \(message)\n".utf8))
    }

    /// A slug hit scores this much — deliberately above the sum of every
    /// other signal (4+2+2+1), so `score >= slugWeight` ⟺ the slug matched
    /// and callers can honestly claim an exact landing.
    static let slugWeight = 16

    /// How strongly a window title (or AXDocument path) matches a thread.
    /// Pure so tests can pin it against realistic titles:
    ///   +16 the session's tab slug appears (near-certain identity)
    ///   +4 the cwd's folder name appears as its own title segment
    ///   +2 the folder (or a fuller path form) appears anywhere
    ///   +2 the thread title's leading words appear
    ///   +1 an adapter hint token ("claude", "codex") appears
    static func score(
        windowTitle: String, cwd: String?, threadTitle: String?,
        slug: String? = nil, hints: [String] = []
    ) -> Int {
        let title = windowTitle.lowercased()
        guard !title.isEmpty else { return 0 }
        var score = 0

        // The tab slug is written by the agent itself into both the session
        // file and the tab title — a match is near-certain identity.
        if let slug = slug?.lowercased(), !slug.isEmpty, title.contains(slug) {
            score += slugWeight
        }

        if let cwd, !cwd.isEmpty {
            let url = URL(fileURLWithPath: cwd)
            let folder = url.lastPathComponent.lowercased()
            if !folder.isEmpty, folder != "/" {
                // Segment separators terminals actually use; '-' excluded
                // because folder names carry it.
                let separators = CharacterSet(charactersIn: " \t—–:·|/\\()[]")
                let segments = title.components(separatedBy: separators)
                if segments.contains(folder) {
                    score += 4
                } else if title.contains(folder) {
                    score += 2
                }
            }
            let lowered = cwd.lowercased()
            let tail = url.pathComponents.suffix(2).joined(separator: "/").lowercased()
            let home = NSHomeDirectory().lowercased()
            let abbreviated = lowered.hasPrefix(home)
                ? "~" + lowered.dropFirst(home.count) : lowered
            if title.contains(lowered) || title.contains(tail)
                || title.contains(abbreviated) {
                score += 2
            }
        }

        if let threadTitle {
            let prefix = String(threadTitle.lowercased().prefix(24))
                .trimmingCharacters(in: .whitespaces)
            if prefix.count >= 6, title.contains(prefix) { score += 2 }
        }

        if hints.contains(where: { title.contains($0.lowercased()) }) { score += 1 }
        return score
    }
}
