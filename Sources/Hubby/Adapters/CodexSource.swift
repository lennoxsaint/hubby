import Foundation

/// Codex threads — the ChatGPT desktop app (bundle `com.openai.codex`) and
/// the Codex CLI share one home: `~/.codex`. Three read-only stores:
///   - `state_N.sqlite` `threads`      → authoritative rows + recency
///   - `session_index.jsonl`           → human thread names (renames land here)
///   - `thread_history_1.sqlite`       → exact "generating right now" turns
/// If the databases are unreadable we degrade to the rollout-file scan.
struct CodexSource: AgentSource {
    let codexDir: URL

    let info = AgentAppInfo(
        id: "codex", name: "Codex",
        bundleIDs: ["com.openai.codex"],
        symbol: "chevron.left.forwardslash.chevron.right", tintHex: 0x000000,
        iconBundleID: "com.openai.codex")

    private static let maxThreads = 8
    /// Fetch more rows than we show so in-progress threads survive the cap.
    private static let fetchLimit = 24
    private static let indexTailBytes = 256 * 1024

    var watchedPaths: [URL] { [codexDir] }

    func fetchThreads() -> [AgentThread] {
        guard let stateDB = latestStateDB(),
              let rows = threadRows(from: stateDB) else {
            return rolloutFallback()
        }
        return CodexThreadMerge.merge(
            dbRows: rows,
            index: sessionIndex(),
            activeIDs: inProgressThreadIDs(),
            cap: Self.maxThreads)
    }

    /// `state_N.sqlite` with the highest N — strict match so the backup
    /// copies Codex leaves around (`state_5.sqlite.backup-…`) never win.
    private func latestStateDB() -> URL? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: codexDir.path) else { return nil }
        let candidates = names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst("state_".count).dropLast(".sqlite".count))
            else { return nil }
            return (version, name)
        }
        return candidates.max { $0.0 < $1.0 }
            .map { codexDir.appendingPathComponent($0.1) }
    }

    private func threadRows(from db: URL) -> [CodexDBRow]? {
        let sql = """
            SELECT id, title, cwd, recency_at_ms FROM threads
            WHERE archived = 0 ORDER BY recency_at_ms DESC LIMIT \(Self.fetchLimit)
            """
        return SQLiteReader.query(db, mode: .liveWAL, sql: sql)?.compactMap { row in
            guard let id = row.string(0) else { return nil }
            return CodexDBRow(
                id: id, title: row.string(1), cwd: row.string(2), recencyMs: row.int64(3))
        }
    }

    private func sessionIndex() -> [String: JSONLParsers.CodexIndexEntry] {
        let url = codexDir.appendingPathComponent("session_index.jsonl")
        guard let data = FileReading.tail(of: url, bytes: Self.indexTailBytes) else { return [:] }
        return Dictionary(
            JSONLParsers.codexSessionIndex(from: data).map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last })
    }

    private func inProgressThreadIDs() -> Set<String> {
        let db = codexDir.appendingPathComponent("thread_history_1.sqlite")
        let sql = """
            SELECT DISTINCT thread_id FROM thread_turns
            WHERE status = 'inProgress' AND completed_at IS NULL
            """
        guard let rows = SQLiteReader.query(db, mode: .liveWAL, sql: sql) else { return [] }
        return Set(rows.compactMap { $0.string(0) })
    }

    // MARK: - Fallback: v0.1 rollout-file scan (today + yesterday)

    private func rolloutFallback() -> [AgentThread] {
        recentRollouts().compactMap { file in
            guard let head = FileReading.head(of: file.url, bytes: 64 * 1024),
                  let meta = JSONLParsers.codexMeta(fromHead: head) else { return nil }
            return AgentThread(
                id: file.url.lastPathComponent,
                title: meta.title,
                lastActivity: file.mtime,
                subtitle: meta.cwd.map(FileReading.abbreviate),
                cwd: meta.cwd)
        }
    }

    private func recentRollouts() -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        let sessionsDir = codexDir.appendingPathComponent("sessions")
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let calendar = Calendar.current

        var files: [(URL, Date)] = []
        for day in [Date(), Date().addingTimeInterval(-24 * 3600)] {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let y = parts.year, let m = parts.month, let d = parts.day else { continue }
            let dir = sessionsDir
                .appendingPathComponent(String(format: "%04d", y))
                .appendingPathComponent(String(format: "%02d", m))
                .appendingPathComponent(String(format: "%02d", d))
            guard let rollouts = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles) else { continue }
            for rollout in rollouts where rollout.pathExtension == "jsonl" {
                guard let mtime = try? rollout.resourceValues(
                    forKeys: [.contentModificationDateKey]).contentModificationDate,
                    mtime > cutoff else { continue }
                files.append((rollout, mtime))
            }
        }
        return files.sorted { $0.1 > $1.1 }.prefix(Self.maxThreads).map { $0 }
    }
}
