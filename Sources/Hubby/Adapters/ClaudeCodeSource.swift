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
        symbol: "terminal.fill", tintHex: 0xCC785C,
        // A CLI has no icon of its own: real Claude icon + terminal badge.
        iconBundleID: "com.anthropic.claudefordesktop",
        badgeSymbol: "terminal.fill")

    /// Sessions untouched for longer than this are not worth showing.
    private static let maxAge: TimeInterval = 24 * 3600
    private static let maxThreads = 8
    private static let headBytes = 128 * 1024

    var watchedPaths: [URL] { [projectsDir] }

    /// Claude Code runs inside whatever terminal the user prefers; activate
    /// the first one actually running rather than blindly launching
    /// Terminal.app into a blank window.
    private static let terminalBundleIDs = [
        "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.github.wez.wezterm",
        "org.alacritty", "dev.warp.Warp-Stable", "com.apple.Terminal",
        "com.microsoft.VSCode",
    ]

    func jump(to thread: AgentThread?) -> Bool {
        let running = NSWorkspace.shared.runningApplications
        for bundleID in Self.terminalBundleIDs {
            if let app = running.first(where: { $0.bundleIdentifier == bundleID }) {
                return app.activate()
            }
        }
        return activateApp()
    }

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

    // Plain path-based listing + stat. The URL-enumerator variant fetches
    // per-entry metadata through CoreServices and can spin indefinitely when
    // the directory is being written at high frequency (a live Claude Code
    // session appends to its jsonl many times a second).
    private func recentSessionFiles() -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: projectsDir.path) else { return [] }

        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        var files: [(URL, Date)] = []
        for project in projects where !project.hasPrefix(".") {
            let projectPath = projectsDir.path + "/" + project
            guard let sessions = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }
            for session in sessions where session.hasSuffix(".jsonl") {
                let path = projectPath + "/" + session
                var info = stat()
                guard stat(path, &info) == 0 else { continue }
                let mtime = Date(
                    timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                        + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
                guard mtime > cutoff else { continue }
                files.append((URL(fileURLWithPath: path), mtime))
            }
        }
        return files.sorted { $0.1 > $1.1 }.prefix(Self.maxThreads).map { $0 }
    }
}
