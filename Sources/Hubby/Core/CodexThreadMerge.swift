import Foundation

/// One row of the Codex `threads` table (state_N.sqlite).
struct CodexDBRow {
    let id: String
    /// Explicit rename made in the app — the strongest title signal.
    let name: String?
    /// First user message text — can be XML/plugin junk, so it's a last
    /// resort behind `name` and the session index.
    let title: String?
    let cwd: String?
    /// Epoch milliseconds; the authoritative recency signal.
    let recencyMs: Int64?
    /// Absolute path of the thread's rollout jsonl (liveness source).
    let rolloutPath: String?

    init(id: String, name: String? = nil, title: String?, cwd: String?,
         recencyMs: Int64?, rolloutPath: String? = nil) {
        self.id = id
        self.name = name
        self.title = title
        self.cwd = cwd
        self.recencyMs = recencyMs
        self.rolloutPath = rolloutPath
    }
}

/// Pure merge of the Codex stores into displayable threads.
/// Kept free of sqlite/filesystem so tests can drive it directly.
/// `activeIDs` comes from the rollout-tail liveness check, which is already
/// freshness-bounded (RolloutTail.mtimeFreshWindow) — no zombie guard needed.
enum CodexThreadMerge {
    static func merge(
        dbRows: [CodexDBRow],
        index: [String: JSONLParsers.CodexIndexEntry],
        activeIDs: Set<String>,
        cap: Int = 8,
        now: Date = Date()
    ) -> [AgentThread] {
        // Detect scheduled automations from the RAW row: the "Automation:"
        // prefix lives in the first-user-message title, while the resolved
        // display title usually comes from the session index without it.
        let automationIDs = Set(dbRows.filter {
            ($0.title ?? "").hasPrefix("Automation:") || ($0.name ?? "").hasPrefix("Automation:")
        }.map(\.id))
        let threads = dbRows.map { row -> AgentThread in
            let entry = index[row.id]
            let dbTitle = row.title
                .map { JSONLParsers.clean($0) }
                .flatMap { $0.isEmpty || $0.hasPrefix("<") ? nil : $0 }
            let name = row.name
                .map { JSONLParsers.clean($0) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let recency = row.recencyMs
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
            let lastActivity = [recency, entry?.updatedAt].compactMap { $0 }.max()
                ?? .distantPast
            return AgentThread(
                id: row.id,
                title: name
                    ?? entry?.name
                    ?? dbTitle
                    ?? row.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "Codex session",
                lastActivity: lastActivity,
                subtitle: row.cwd.map(FileReading.abbreviate),
                cwd: row.cwd,
                isGenerating: activeIDs.contains(row.id))
        }
        // Scheduled automations re-run every few minutes and would flood
        // the recency cap, evicting the user's real threads. Collapse
        // repeat runs to one row per title (newest wins; a generating run
        // always survives) and rank automations below interactive work —
        // spinners first, then interactive threads by recency, then the
        // deduped automations.
        var seenTitles = Set<String>()
        let deduped = threads
            .sorted { $0.lastActivity > $1.lastActivity }
            .filter { thread in
                guard automationIDs.contains(thread.id), !thread.isGenerating
                else { return true }
                return seenTitles.insert(thread.title).inserted
            }
        let sorted = deduped.sorted {
            ($0.isGenerating ? 1 : 0,
             automationIDs.contains($0.id) ? 0 : 1,
             $0.lastActivity.timeIntervalSince1970)
                > ($1.isGenerating ? 1 : 0,
                   automationIDs.contains($1.id) ? 0 : 1,
                   $1.lastActivity.timeIntervalSince1970)
        }
        return Array(sorted.prefix(cap))
    }
}
