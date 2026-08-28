import Foundation

/// Hermes sessions, read from `~/.hermes/state.db` (SQLite, live WAL).
/// `sessions` is a first-class store: `ended_at IS NULL` marks an open
/// session, `display_name`/`title` are human names, `cwd` is the project.
struct HermesSource: AgentSource {
    let stateDB: URL

    let info = AgentAppInfo(
        id: "hermes", name: "Hermes",
        bundleIDs: ["com.nousresearch.hermes"],
        symbol: "wind", tintHex: 0x8E7CFF,
        iconBundleID: "com.nousresearch.hermes")

    private static let maxThreads = 8
    private static let maxAge: TimeInterval = 14 * 24 * 3600

    var watchedPaths: [URL] { [stateDB.deletingLastPathComponent()] }

    /// Sessions carry a cwd, so window matching works the same way it does
    /// for terminals: raise the window titled after the project.
    func jump(to thread: AgentThread?) -> JumpResolution {
        if let thread, WindowLocator.isTrusted,
           WindowLocator.raiseWindow(bundleIDs: info.bundleIDs, scorer: {
               WindowLocator.score(
                   windowTitle: $0, cwd: thread.cwd, threadTitle: thread.title)
           }) {
            return .window
        }
        return activateApp() ? .appActivated : .failed
    }

    func fetchThreads() -> [AgentThread] {
        // messages is small (~10k rows); the group-by keeps last activity
        // honest for sessions that stay open for weeks.
        let sql = """
            SELECT s.id,
                   COALESCE(NULLIF(s.display_name, ''), NULLIF(s.title, '')),
                   s.cwd,
                   COALESCE(m.last_ts, s.started_at),
                   s.ended_at IS NULL
            FROM sessions s
            LEFT JOIN (SELECT session_id, MAX(timestamp) AS last_ts
                       FROM messages GROUP BY session_id) m ON m.session_id = s.id
            WHERE s.archived IS NOT 1
            ORDER BY 4 DESC LIMIT \(Self.maxThreads)
            """
        guard let rows = SQLiteReader.query(stateDB, mode: .liveWAL, sql: sql) else {
            return []
        }
        let now = Date()
        return threads(from: rows, now: now)
    }

    /// The newest ASSISTANT message of a session — the hover recap. Without
    /// the role filter this surfaced the user's own words or tool JSON.
    /// One tiny query per shown session (≤ maxThreads), nil-tolerant.
    private func lastMessage(sessionID: String) -> String? {
        let escaped = sessionID.replacingOccurrences(of: "'", with: "''")
        let sql = """
            SELECT content FROM messages
            WHERE session_id = '\(escaped)'
              AND role = 'assistant'
              AND content IS NOT NULL AND content <> ''
            ORDER BY timestamp DESC LIMIT 1
            """
        guard let rows = SQLiteReader.query(stateDB, mode: .liveWAL, sql: sql),
              let content = rows.first.flatMap({ $0.string(0) }) else { return nil }
        return RecapText.recap(content)
    }

    private func threads(from rows: [SQLiteReader.Row], now: Date) -> [AgentThread] {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        return rows.compactMap { row in
            guard let id = row.string(0) else { return nil }
            let lastActivity = Date(
                timeIntervalSince1970: row.double(3) ?? 0)
            guard lastActivity > cutoff else { return nil }
            let cwd = row.string(2).flatMap { $0.isEmpty ? nil : $0 }
            return AgentThread(
                id: id,
                title: row.string(1).map { JSONLParsers.clean($0) }
                    ?? cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "Session",
                lastActivity: lastActivity,
                subtitle: cwd.map(FileReading.abbreviate),
                cwd: cwd,
                recap: lastMessage(sessionID: id),
                isGenerating: row.int64(4) == 1
                    && now.timeIntervalSince(lastActivity) < 120)
        }
    }
}
