import Foundation

/// Cursor chats, read from the conversation-search index at
/// `~/Library/Application Support/Cursor/User/globalStorage/conversation-search.db`.
/// Cursor writes it via WAL while running, so it opens plain read-only
/// (immutable=1 fails or reads empty against a live WAL).
struct CursorSource: AgentSource {
    let databaseURL: URL

    let info = AgentAppInfo(
        id: "cursor", name: "Cursor",
        bundleIDs: ["com.todesktop.230313mzl4w4u92"],
        symbol: "cursorarrow.rays", tintHex: 0x4C8DFF,
        iconBundleID: "com.todesktop.230313mzl4w4u92")

    private static let maxThreads = 8
    private static let maxAge: TimeInterval = 14 * 24 * 3600

    var watchedPaths: [URL] { [databaseURL.deletingLastPathComponent()] }

    /// Cursor registers no chat deep link (verified against the bundle;
    /// adopt one the moment it ships). Best effort: raise the window whose
    /// title carries the chat's words — conversation rows store no cwd.
    func jump(to thread: AgentThread?) -> JumpResolution {
        if let thread, WindowLocator.isTrusted,
           WindowLocator.raiseWindow(bundleIDs: info.bundleIDs, scorer: {
               WindowLocator.score(windowTitle: $0, cwd: nil, threadTitle: thread.title)
           }) > 0 {
            return .window
        }
        return activateApp() ? .appActivated : .failed
    }

    func fetchThreads() -> [AgentThread] {
        // No recap: the FTS body interleaves user + assistant text with no
        // role markers, so any "recap" from it is an unattributed fragment.
        // A missing recap beats a wrong one — the card shows verdict + title.
        let sql = """
            SELECT c.id, c.title, c.updated_at
            FROM conversations c
            WHERE c.is_archived = 0 AND c.title <> ''
            ORDER BY c.updated_at DESC LIMIT \(Self.maxThreads)
            """
        guard let rows = SQLiteReader.query(databaseURL, mode: .liveWAL, sql: sql) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        return rows.compactMap { row in
            guard let id = row.string(0), let title = row.string(1),
                  let updatedMs = row.int64(2) else { return nil }
            let lastActivity = Date(timeIntervalSince1970: TimeInterval(updatedMs) / 1000)
            guard lastActivity > cutoff else { return nil }
            return AgentThread(
                id: id, title: title, lastActivity: lastActivity, subtitle: nil, cwd: nil,
                isGenerating: AgentThread.inferGenerating(lastActivity: lastActivity))
        }
    }
}
