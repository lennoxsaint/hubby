import Foundation

/// One row of the Codex `threads` table (state_N.sqlite).
struct CodexDBRow {
    let id: String
    /// First user message text — can be XML/plugin junk, so it's a last
    /// resort behind the session index's human-set `thread_name`.
    let title: String?
    let cwd: String?
    /// Epoch milliseconds; the authoritative recency signal.
    let recencyMs: Int64?
}

/// Pure merge of the three Codex stores into displayable threads.
/// Kept free of sqlite/filesystem so tests can drive it directly.
enum CodexThreadMerge {
    /// An in-progress turn only counts as a live spinner while the thread
    /// shows recent activity — crashed turns linger as `inProgress` in
    /// thread_history for days and would otherwise pulse forever.
    static let generatingStaleAfter: TimeInterval = 30 * 60

    static func merge(
        dbRows: [CodexDBRow],
        index: [String: JSONLParsers.CodexIndexEntry],
        activeIDs: Set<String>,
        cap: Int = 8,
        now: Date = Date()
    ) -> [AgentThread] {
        let threads = dbRows.map { row -> AgentThread in
            let entry = index[row.id]
            let dbTitle = row.title
                .map { JSONLParsers.clean($0) }
                .flatMap { $0.isEmpty || $0.hasPrefix("<") ? nil : $0 }
            let recency = row.recencyMs
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
            let lastActivity = [recency, entry?.updatedAt].compactMap { $0 }.max()
                ?? .distantPast
            return AgentThread(
                id: row.id,
                title: entry?.name
                    ?? dbTitle
                    ?? row.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "Codex session",
                lastActivity: lastActivity,
                subtitle: row.cwd.map(FileReading.abbreviate),
                cwd: row.cwd,
                isGenerating: activeIDs.contains(row.id)
                    && now.timeIntervalSince(lastActivity) < Self.generatingStaleAfter)
        }
        // Spinners always survive the cap; the rest by recency.
        let sorted = threads.sorted {
            ($0.isGenerating ? 1 : 0, $0.lastActivity.timeIntervalSince1970)
                > ($1.isGenerating ? 1 : 0, $1.lastActivity.timeIntervalSince1970)
        }
        return Array(sorted.prefix(cap))
    }
}
