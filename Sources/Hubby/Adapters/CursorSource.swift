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
           }) {
            return .window
        }
        return activateApp() ? .appActivated : .failed
    }

    func fetchThreads() -> [AgentThread] {
        // The FTS body concatenates the conversation's text; its tail is
        // the freshest exchange and feeds the hover recap.
        let sql = """
            SELECT c.id, c.title, c.updated_at, substr(f.body, -400)
            FROM conversations c
            LEFT JOIN conversation_fts f ON f.rowid = c.fts_rowid
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
                recap: row.string(3).flatMap(Self.recapFromBodyTail))
        }
    }

    /// A raw FTS tail starts mid-sentence; skip through the first sentence
    /// boundary so the recap begins on a clean one.
    static func recapFromBodyTail(_ tail: String) -> String? {
        let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for boundary in [". ", "! ", "? ", "\n"] {
            if let range = trimmed.range(of: boundary),
               trimmed.distance(from: trimmed.startIndex, to: range.lowerBound) < 200 {
                let rest = trimmed[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return rest.isEmpty ? nil : JSONLParsers.clean(String(rest), limit: 200)
            }
        }
        return JSONLParsers.clean(trimmed, limit: 200)
    }
}
