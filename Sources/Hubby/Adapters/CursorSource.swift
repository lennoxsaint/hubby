import Foundation
import SQLite3

/// Cursor chats, read from the conversation-search index at
/// `~/Library/Application Support/Cursor/User/globalStorage/conversation-search.db`.
/// The database is opened read-only and never locked (immutable snapshot).
struct CursorSource: AgentSource {
    let databaseURL: URL

    let info = AgentAppInfo(
        id: "cursor", name: "Cursor",
        bundleIDs: ["com.todesktop.230313mzl4w4u92"],
        symbol: "cursorarrow.rays", tintHex: 0x4C8DFF)

    private static let maxThreads = 8
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    func fetchThreads() -> [AgentThread] {
        // immutable=1 guarantees we never take any lock on Cursor's live db.
        var db: OpaquePointer?
        let uri = "file:\(databaseURL.path)?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let db else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT id, title, updated_at FROM conversations
            WHERE is_archived = 0 AND title <> ''
            ORDER BY updated_at DESC LIMIT \(Self.maxThreads)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        var threads: [AgentThread] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                  let titleText = sqlite3_column_text(statement, 1) else { continue }
            let updatedMs = sqlite3_column_int64(statement, 2)
            let lastActivity = Date(timeIntervalSince1970: TimeInterval(updatedMs) / 1000)
            guard lastActivity > cutoff else { continue }
            threads.append(AgentThread(
                id: String(cString: idText),
                title: String(cString: titleText),
                lastActivity: lastActivity,
                subtitle: nil,
                cwd: nil))
        }
        return threads
    }
}
