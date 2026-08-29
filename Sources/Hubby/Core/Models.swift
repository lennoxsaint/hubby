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
    /// One-line recap of what the thread last did (last assistant message,
    /// blocked-on reason, ...) shown in the hover card. Nil when the source
    /// can't say; the card falls back to title/status.
    var recap: String? = nil
    /// True when the source *knows* the thread is generating right now
    /// (e.g. a live Codex rollout turn) — not just recently touched.
    var isGenerating: Bool = false
    /// True when the source knows the agent is blocked waiting for the
    /// human (Grok Bot's `awaitingUserResponse`).
    var isWaitingOnYou: Bool = false
    /// True when a generation finished and the user hasn't jumped to the
    /// thread since. Set by `ReadStateStore.decorate`, never by adapters.
    var isFinishedUnread: Bool = false
    /// The prompt this thread is blocked on, when the source can recover
    /// its content (question + options). Implies `isWaitingOnYou`.
    var pendingPrompt: PendingPrompt? = nil
    /// User-pinned to the top of its app's drop-down (below blocked
    /// threads). Set by `ThreadPinStore.decorate`, never by adapters.
    var isPinned: Bool = false

    /// For sources with no authoritative generating signal (Claude Code,
    /// Cursor, Grok): their stores are written many times a second mid-turn,
    /// so a thread touched within the last few seconds of the fetch is
    /// generating — unless it is known to be blocked on the human. Applied
    /// at fetch time so ReadState sees the same transitions it sees from
    /// authoritative sources (Codex, Hermes) and every app shimmers alike.
    static func inferGenerating(
        lastActivity: Date, waiting: Bool = false, now: Date = Date()
    ) -> Bool {
        !waiting && now.timeIntervalSince(lastActivity) < 10
    }

    /// Spinner > needs-you > finished-unread > recently-touched > idle.
    func status(now: Date = Date()) -> ThreadStatus {
        if isGenerating { return .generating }
        if isWaitingOnYou { return .waitingOnYou }
        if isFinishedUnread { return .finishedUnread }
        return now.timeIntervalSince(lastActivity) < 120 ? .active : .idle
    }
}

enum ThreadStatus {
    case generating
    case waitingOnYou
    case finishedUnread
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
}

/// A source's state at one refresh tick.
struct AgentSnapshot: Identifiable {
    let info: AgentAppInfo
    let isRunning: Bool
    let threads: [AgentThread]

    var id: String { info.id }
    /// Threads generating right now (spinners; drives the orb badge).
    var runningCount: Int { threads.filter { $0.status() == .generating }.count }
    /// Agents blocked waiting for the human (amber badge).
    var needsYouCount: Int { threads.filter { $0.status() == .waitingOnYou }.count }
    /// Finished results the user hasn't jumped to yet (blue badge).
    var unreadCount: Int { threads.filter { $0.status() == .finishedUnread }.count }
}

/// The tier order inside an app's drop-down: blocked-on-you first, then
/// pinned, then everything else in the adapter's own order (adapters
/// already order by generating/recency). Stable within each tier.
enum ThreadTiers {
    static func tiered(_ threads: [AgentThread]) -> [AgentThread] {
        let blocked = threads.filter { $0.status() == .waitingOnYou }
        let pinned = threads.filter { $0.isPinned && $0.status() != .waitingOnYou }
        let rest = threads.filter { !$0.isPinned && $0.status() != .waitingOnYou }
        return blocked + pinned + rest
    }

    /// Index of the first non-pinned row after tiering — where the
    /// pinned/recent hairline divider sits. Nil when no divider is needed.
    static func dividerIndex(_ tiered: [AgentThread]) -> Int? {
        guard let last = tiered.lastIndex(where: {
            $0.isPinned || $0.status() == .waitingOnYou
        }) else { return nil }
        return last + 1 < tiered.count ? last + 1 : nil
    }
}
