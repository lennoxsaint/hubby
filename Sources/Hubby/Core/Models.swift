import Foundation

/// One conversation/session running inside an agent app.
struct AgentThread: Identifiable, Hashable {
    let id: String
    let title: String
    let lastActivity: Date
    /// Extra context shown under the title (e.g. project directory).
    let subtitle: String?
    /// Working directory of the session, used for terminal-focused jumps.
    let cwd: String?
    /// True when the source *knows* the thread is generating right now
    /// (e.g. an in-progress Codex turn) — not just recently touched.
    var isGenerating: Bool = false

    /// Explicitly generating, or touched within the last 2 minutes.
    func status(now: Date = Date()) -> ThreadStatus {
        isGenerating || now.timeIntervalSince(lastActivity) < 120 ? .active : .idle
    }
}

enum ThreadStatus {
    case active
    case idle
}

/// Static identity of a supported agent app.
struct AgentAppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    /// Bundle identifiers to try, in order, when activating the app.
    let bundleIDs: [String]
    /// SF Symbol used when no real app icon is available.
    let symbol: String
    /// Hex RGB used as the app's accent color.
    let tintHex: UInt32
    /// Bundle whose real icon to show, loaded at runtime from the installed
    /// app (never bundled — trademarks stay on the user's disk).
    var iconBundleID: String? = nil
    /// Small corner-badge symbol layered on the icon (e.g. Claude Code's
    /// terminal glyph over the Claude icon).
    var badgeSymbol: String? = nil
}

/// A source's state at one refresh tick.
struct AgentSnapshot: Identifiable {
    let info: AgentAppInfo
    let isRunning: Bool
    let threads: [AgentThread]

    var id: String { info.id }
    var activeCount: Int { threads.filter { $0.status() == .active }.count }
}
