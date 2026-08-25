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

    /// Threads touched within the last 5 minutes count as active.
    func status(now: Date = Date()) -> ThreadStatus {
        now.timeIntervalSince(lastActivity) < 300 ? .active : .idle
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
    /// SF Symbol used for the app's dot in the orb and hub.
    let symbol: String
    /// Hex RGB used as the app's accent color.
    let tintHex: UInt32
}

/// A source's state at one refresh tick.
struct AgentSnapshot: Identifiable {
    let info: AgentAppInfo
    let isRunning: Bool
    let threads: [AgentThread]

    var id: String { info.id }
    var activeCount: Int { threads.filter { $0.status() == .active }.count }
}
