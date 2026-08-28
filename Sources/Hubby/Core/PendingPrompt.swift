import Foundation

/// A prompt an agent is blocked on right now, recovered from its session
/// data. Only sources that expose the *content* of the prompt attach one
/// (Claude Code today); a bare `isWaitingOnYou` without a PendingPrompt
/// means "blocked, but Hubby can only show you the door, not open it".
struct PendingPrompt: Hashable {
    enum Kind: Hashable {
        /// A yes/no gate — a plan waiting for approval (green pill).
        case approve
        /// A multi-choice question — pick one option (amber pill).
        case choose
    }

    struct Option: Hashable {
        let label: String
        let description: String?
    }

    let kind: Kind
    /// One-line question / context shown on hover.
    let question: String
    /// The choices for `.choose`; empty for `.approve`.
    let options: [Option]
    /// The `tool_use` id the answer must correlate with — the actuator
    /// re-checks this exact id is still unanswered before typing anything.
    let toolUseID: String
    /// False when the prompt's shape defeats one-shot keystrokes (e.g. an
    /// AskUserQuestion carrying several questions at once — answering one
    /// doesn't complete the tool call). The pill then jumps instead.
    var actuatable: Bool = true
}
