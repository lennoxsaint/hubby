import AppKit
import Foundation

/// One synthetic key press in an actuation sequence. Pure so keymaps are
/// unit-testable without posting anything.
enum PromptKey: Equatable {
    case down
    case `return`
    case text(String)
}

/// What the guarded actuation attempt came to.
enum ActuationOutcome {
    /// The keystrokes landed and the session data confirms the answer.
    case answered
    /// A guard failed before or after typing — the caller should fall back
    /// to a plain jump so the user can answer by hand.
    case fellBack
}

enum PromptKeymap {
    /// The TUI keys that answer a prompt, verified against Claude Code's
    /// own dialog source (the AskUserQuestion QuestionView handles ONLY
    /// up/down/return — digit keys exist only in the preview variant, so
    /// digits would silently no-op and Return would answer whatever is
    /// focused). Focus starts on option 1; Down i times reaches 0-based
    /// option i, Return selects — and a single-question, non-multiSelect
    /// selection submits the whole tool call immediately.
    ///
    /// Plan approvals (`.approve`) return nil deliberately: the dialog's
    /// option list is built dynamically (clear-context / auto-mode /
    /// Ultraplan variants shift every index), so a blind sequence could
    /// select "bypass permissions". The pill jumps to the dialog instead.
    static func keys(for prompt: PendingPrompt, optionIndex: Int?) -> [PromptKey]? {
        switch prompt.kind {
        case .approve:
            return nil
        case .choose:
            guard let optionIndex, prompt.options.indices.contains(optionIndex)
            else { return nil }
            return Array(repeating: .down, count: optionIndex) + [.return]
        }
    }

    /// The Nudge: un-stall an idle session.
    static let nudgeKeys: [PromptKey] = [.text("continue"), .return]
}

/// Executes a keystroke sequence against a raised window, with the guard
/// discipline: verify → raise → confirm frontmost → type → confirm answered.
/// Any failed step means nothing (more) is typed and the caller falls back.
@MainActor
enum PromptActuator {
    /// Re-check hooks are closures so the engine stays adapter-agnostic:
    /// `stillPending` re-reads the source of truth, `raise` must land the
    /// exact window (a mere app activation is NOT enough to type into).
    static func run(
        keys: [PromptKey],
        frontmostBundleIDs: [String],
        stillPending: () -> Bool,
        raise: () -> Bool,
        confirmAnswered: @escaping () -> Bool
    ) async -> ActuationOutcome {
        guard stillPending(), raise() else { return .fellBack }
        // Let the raise/activation settle before trusting frontmost.
        try? await Task.sleep(for: .milliseconds(350))
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              frontmostBundleIDs.contains(front),
              stillPending() else { return .fellBack }

        for key in keys {
            switch key {
            case .down: Keystrokes.pressDown()
            case .return: Keystrokes.pressReturn()
            case .text(let text): Keystrokes.type(text)
            }
            try? await Task.sleep(for: .milliseconds(90))
        }

        // The answer takes a moment to hit the session file.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(300))
            if confirmAnswered() { return .answered }
        }
        return .fellBack
    }
}
