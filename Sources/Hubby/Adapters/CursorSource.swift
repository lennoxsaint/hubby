import Foundation

/// Cursor chats, read from the conversation-search index at
/// `~/Library/Application Support/Cursor/User/globalStorage/conversation-search.db`.
/// The database is opened read-only and never locked (immutable snapshot).
struct CursorSource: AgentSource {
    let databaseURL: URL

    let info = AgentAppInfo(
        id: "cursor", name: "Cursor",
        bundleIDs: ["com.todesktop.230313mzl4w4u92"],
        symbol: "cursorarrow.rays", tintHex: 0x4C8DFF,
        iconBundleID: "com.todesktop.230313mzl4w4u92")

    private static let maxThreads = 8
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    var watchedPaths: [URL] { [databaseURL.deletingLastPathComponent()] }

    func fetchThreads() -> [AgentThread] {
        let sql = """
            SELECT id, title, updated_at FROM conversations
            WHERE is_archived = 0 AND title <> ''
            ORDER BY updated_at DESC LIMIT \(Self.maxThreads)
            """
        guard let rows = SQLiteReader.query(databaseURL, mode: .immutable, sql: sql) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        return rows.compactMap { row in
            guard let id = row.string(0), let title = row.string(1),
                  let updatedMs = row.int64(2) else { return nil }
            let lastActivity = Date(timeIntervalSince1970: TimeInterval(updatedMs) / 1000)
            guard lastActivity > cutoff else { return nil }
            return AgentThread(
                id: id, title: title, lastActivity: lastActivity, subtitle: nil, cwd: nil)
        }
    }
}
