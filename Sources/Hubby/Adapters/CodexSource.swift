import AppKit
import Foundation

/// Codex threads — the ChatGPT desktop app (bundle `com.openai.codex`) and
/// the Codex CLI share one home: `~/.codex`. Read-only stores:
///   - `state_N.sqlite` `threads`      → authoritative rows, names, recency
///   - `session_index.jsonl`           → rename overlay (fallback names)
///   - the thread's rollout jsonl      → generating-right-now (RolloutTail)
/// (`thread_history_1.sqlite` is NOT used: it only covers `paginated` threads
/// — 0.3% of a real install — and its `inProgress` rows survive crashes.)
/// If the database is unreadable we degrade to the rollout-file scan.
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

    /// The ChatGPT desktop app registers `codex://threads/<state-thread-id>`
    /// — the only true per-thread deep link among the supported apps.
    func jump(to thread: AgentThread?) -> JumpResolution {
        if let thread, let url = URL(string: "codex://threads/\(thread.id)"),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
            return .exactThread
        }
        return activateApp() ? .appActivated : .failed
    }

    func fetchThreads() -> [AgentThread] {
        guard let stateDB = latestStateDB(),
              let rows = threadRows(from: stateDB) else {
            return rolloutFallback()
        }
        let merged = CodexThreadMerge.merge(
            dbRows: rows,
            index: sessionIndex(),
            activeIDs: liveThreadIDs(rows: rows),
            cap: Self.maxThreads)
        // Recaps only for the rows that survived the cap: one tail read each.
        let rolloutPaths = Dictionary(
            rows.compactMap { row in row.rolloutPath.map { (row.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        return merged.map { thread in
            var thread = thread
            thread.recap = rolloutPaths[thread.id]
                .flatMap { FileReading.tail(of: URL(fileURLWithPath: $0), bytes: RolloutTail.tailBytes) }
                .flatMap(JSONLParsers.codexRecap(fromTail:))
            return thread
        }
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
            SELECT id, name, title, cwd, recency_at_ms, rollout_path FROM threads
            WHERE archived = 0 ORDER BY recency_at_ms DESC LIMIT \(Self.fetchLimit)
            """
        return SQLiteReader.query(db, mode: .liveWAL, sql: sql)?.compactMap { row in
            guard let id = row.string(0) else { return nil }
            return CodexDBRow(
                id: id, name: row.string(1), title: row.string(2), cwd: row.string(3),
                recencyMs: row.int64(4), rolloutPath: row.string(5))
        }
    }

    /// Rollout-tail liveness: recent recency → fresh rollout mtime → last
    /// `task_started` after last `task_complete`. Covers every thread kind
    /// (legacy, paginated, subagent, automation) and self-heals on crashes.
    private func liveThreadIDs(rows: [CodexDBRow], now: Date = Date()) -> Set<String> {
        var live: Set<String> = []
        for row in rows {
            guard let recencyMs = row.recencyMs,
                  now.timeIntervalSince1970 - TimeInterval(recencyMs) / 1000 < 120,
                  let rolloutPath = row.rolloutPath else { continue }
            let url = URL(fileURLWithPath: rolloutPath)
            guard let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
                now.timeIntervalSince(mtime) < RolloutTail.mtimeFreshWindow,
                let tail = FileReading.tail(of: url, bytes: RolloutTail.tailBytes),
                RolloutTail.isLive(tail: tail) else { continue }
            live.insert(row.id)
        }
        return live
    }

    private func sessionIndex() -> [String: JSONLParsers.CodexIndexEntry] {
        let url = codexDir.appendingPathComponent("session_index.jsonl")
        guard let data = FileReading.tail(of: url, bytes: Self.indexTailBytes) else { return [:] }
        return Dictionary(
            JSONLParsers.codexSessionIndex(from: data).map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last })
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
                cwd: meta.cwd,
                recap: FileReading.tail(of: file.url, bytes: RolloutTail.tailBytes)
                    .flatMap(JSONLParsers.codexRecap(fromTail:)))
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
