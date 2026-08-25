import Foundation

/// Codex CLI / Codex Desktop rollouts, read from
/// `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
struct CodexSource: AgentSource {
    let sessionsDir: URL

    let info = AgentAppInfo(
        id: "codex", name: "Codex",
        bundleIDs: ["com.openai.chat", "com.openai.codex"],
        symbol: "chevron.left.forwardslash.chevron.right", tintHex: 0x000000)

    private static let maxAge: TimeInterval = 24 * 3600
    private static let maxThreads = 8
    private static let headBytes = 64 * 1024

    func fetchThreads() -> [AgentThread] {
        recentRollouts().compactMap { file in
            guard let head = FileReading.head(of: file.url, bytes: Self.headBytes),
                  let meta = JSONLParsers.codexMeta(fromHead: head) else { return nil }
            return AgentThread(
                id: file.url.lastPathComponent,
                title: meta.title,
                lastActivity: file.mtime,
                subtitle: meta.cwd.map(FileReading.abbreviate),
                cwd: meta.cwd)
        }
    }

    /// Sessions are sharded by date, so only today's and yesterday's
    /// directories can contain files inside the age window.
    private func recentRollouts() -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        let calendar = Calendar.current
        let days = [Date(), Date().addingTimeInterval(-24 * 3600)]

        var files: [(URL, Date)] = []
        for day in days {
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
                guard let mtime = try? rollout.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate, mtime > cutoff else { continue }
                files.append((rollout, mtime))
            }
        }
        return files.sorted { $0.1 > $1.1 }.prefix(Self.maxThreads).map { $0 }
    }
}
