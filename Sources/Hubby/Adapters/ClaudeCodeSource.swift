import AppKit
import Foundation

/// Claude Code sessions, read from `~/.claude/projects/<project>/<uuid>.jsonl`.
/// A session's mtime is its last activity; titles come from summary lines or
/// the first user message. Jumping activates the terminal.
struct ClaudeCodeSource: AgentSource {
    let projectsDir: URL

    let info = AgentAppInfo(
        id: "claude-code", name: "Claude Code",
        bundleIDs: ["com.apple.Terminal"],
        symbol: "terminal.fill", tintHex: 0xCC785C)

    /// Sessions untouched for longer than this are not worth showing.
    private static let maxAge: TimeInterval = 24 * 3600
    private static let maxThreads = 8
    private static let headBytes = 128 * 1024

    // Claude Code runs inside a terminal, so a running Terminal.app proves
    // nothing; liveness comes from recent session files (snapshot() ORs in
    // non-empty threads).
    func isRunning(runningBundleIDs: Set<String>) -> Bool { false }

    func fetchThreads() -> [AgentThread] {
        recentSessionFiles().compactMap { file in
            guard let head = FileReading.head(of: file.url, bytes: Self.headBytes) else { return nil }
            let title = JSONLParsers.claudeCodeTitle(fromHead: head)
            let cwd = JSONLParsers.claudeCodeCwd(fromHead: head)
            return AgentThread(
                id: file.url.lastPathComponent,
                title: title ?? cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Session",
                lastActivity: file.mtime,
                subtitle: cwd.map(FileReading.abbreviate),
                cwd: cwd)
        }
    }

    private func recentSessionFiles() -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }

        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        var files: [(URL, Date)] = []
        for project in projects {
            guard let sessions = try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles) else { continue }
            for session in sessions where session.pathExtension == "jsonl" {
                guard let mtime = try? session.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate, mtime > cutoff else { continue }
                files.append((session, mtime))
            }
        }
        return files.sorted { $0.1 > $1.1 }.prefix(Self.maxThreads).map { $0 }
    }
}
