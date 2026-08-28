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
    /// `bundleIDs`. Returns false when nothing scores above zero (or the
    /// grant is missing) so callers can fall back to app activation.
    static func raiseWindow(bundleIDs: [String], scorer: (String) -> Int) -> Bool {
        guard isTrusted else { return false }
        var best: (score: Int, window: AXUIElement, app: NSRunningApplication)?
        for app in NSWorkspace.shared.runningApplications
        where bundleIDs.contains(app.bundleIdentifier ?? "") {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            // A hung app must never freeze a jump.
            AXUIElementSetMessagingTimeout(element, 0.3)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, kAXWindowsAttribute as CFString, &value) == .success,
                let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                // Editors put the file path in AXDocument; terminals title
                // themselves after the cwd. Score whichever reads higher.
                let title = string(of: window, kAXTitleAttribute) ?? ""
                let document = string(of: window, kAXDocumentAttribute) ?? ""
                let score = max(scorer(title), scorer(document))
                if score > (best?.score ?? 0) {
                    best = (score, window, app)
                }
            }
        }
        guard let best else { return false }
        AXUIElementSetAttributeValue(best.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(best.window, kAXRaiseAction as CFString)
        best.app.activate()
        return true
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// How strongly a window title (or AXDocument path) matches a thread.
    /// Pure so tests can pin it against realistic titles:
    ///   +4 the cwd's folder name appears as its own title segment
    ///   +2 the folder (or a fuller path form) appears anywhere
    ///   +2 the thread title's leading words appear
    ///   +1 an adapter hint token ("claude", "codex") appears
    static func score(
        windowTitle: String, cwd: String?, threadTitle: String?, hints: [String] = []
    ) -> Int {
        let title = windowTitle.lowercased()
        guard !title.isEmpty else { return 0 }
        var score = 0

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
