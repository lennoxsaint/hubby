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
        // A CLI has no icon of its own; the row label says "Claude Code".
        iconBundleID: "com.anthropic.claudefordesktop")

    /// Sessions untouched for longer than this are not worth showing.
    private static let maxAge: TimeInterval = 24 * 3600
    private static let maxThreads = 8
    private static let headBytes = 128 * 1024
    private static let tailBytes = 64 * 1024

    var watchedPaths: [URL] { [projectsDir] }

    /// Claude Code runs inside whatever terminal the user prefers; activate
    /// one that is actually running rather than blindly launching
    /// Terminal.app into a blank window. ghostty leads — it's the house
    /// terminal here.
    private static let terminalBundleIDs = [
        "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.github.wez.wezterm",
        "org.alacritty", "dev.warp.Warp-Stable", "com.apple.Terminal",
        "com.microsoft.VSCode",
    ]

    /// Land on the exact terminal tab when the Accessibility grant allows.
    /// Tabs are NOT separate AX windows in every terminal — Ghostty is one
    /// AXWindow with an AXTabGroup of radio buttons — so WindowLocator
    /// scores tab titles too and presses the winner. The strongest signal
    /// is the session's `aiTitle` slug — Claude Code writes it into the
    /// session file AND sets the terminal tab title to it; cwd and thread
    /// title back it up. `.exactThread` is claimed only on a slug-level
    /// match — a lucky window raise is just `.window`. Without the grant,
    /// fall back to activating a running terminal — and admit a better
    /// landing exists so the UI can offer the grant. Never launch anything.
    func jump(to thread: AgentThread?) -> JumpResolution {
        if let thread {
            let score = raiseScore(for: thread)
            if score >= WindowLocator.slugWeight { return .exactThread }
            if score > 0 { return .window }
        }
        let fallback = activateFirstRunningTerminal()
        if thread != nil, !WindowLocator.isTrusted, fallback != .failed {
            return .needsAccessibility
        }
        return fallback
    }

    /// Raise the session's terminal window/tab; returns the match score
    /// (`>= slugWeight` = the slug matched, a near-certain exact landing).
    private func raiseScore(for thread: AgentThread) -> Int {
        guard WindowLocator.isTrusted else { return 0 }
        let slug = tabSlug(forSessionFile: thread.id)
        return WindowLocator.raiseWindow(bundleIDs: Self.terminalBundleIDs, scorer: {
            WindowLocator.score(
                windowTitle: $0, cwd: thread.cwd, threadTitle: thread.title,
                slug: slug, hints: ["claude"])
        })
    }

    /// Actuation may only type after a slug-certain landing — typing into a
    /// merely-plausible window would answer some OTHER session's prompt.
    private func raiseExactTab(for thread: AgentThread) -> Bool {
        raiseScore(for: thread) >= WindowLocator.slugWeight
    }

    /// Answer a blocked prompt from the hub — the Approve/Choose pill.
    /// `optionIndex` is 0-based into `prompt.options`; nil approves.
    /// Every guard lives in PromptActuator; a fallen-back attempt has
    /// typed nothing (or confirmed nothing) and the UI jumps instead.
    @MainActor
    func answer(
        _ thread: AgentThread, prompt: PendingPrompt, optionIndex: Int?
    ) async -> ActuationOutcome {
        guard prompt.actuatable,
              let keys = PromptKeymap.keys(for: prompt, optionIndex: optionIndex)
        else { return .fellBack }
        let pendingNow = { self.pendingPrompt(forSessionFile: thread.id)?.toolUseID }
        return await PromptActuator.run(
            keys: keys,
            frontmostBundleIDs: Self.terminalBundleIDs,
            stillPending: { pendingNow() == prompt.toolUseID },
            raise: { raiseExactTab(for: thread) },
            confirmAnswered: { pendingNow() != prompt.toolUseID })
    }

    /// Nudge an idle session with "continue". Guards: genuinely idle,
    /// nothing pending (a nudge must never answer a prompt by accident),
    /// and the exact tab raised.
    @MainActor
    func nudge(_ thread: AgentThread) async -> ActuationOutcome {
        // A vanished session file is NOT idle — it's gone; never type at it.
        let idle = {
            self.mtime(forSessionFile: thread.id)
                .map { Date().timeIntervalSince($0) > 120 } ?? false
        }
        return await PromptActuator.run(
            keys: PromptKeymap.nudgeKeys,
            frontmostBundleIDs: Self.terminalBundleIDs,
            stillPending: { self.pendingPrompt(forSessionFile: thread.id) == nil && idle() },
            raise: { raiseExactTab(for: thread) },
            confirmAnswered: { !idle() })
    }

    private func pendingPrompt(forSessionFile filename: String) -> PendingPrompt? {
        guard let file = recentSessionFiles()
            .first(where: { $0.url.lastPathComponent == filename }),
            let tail = FileReading.tail(of: file.url, bytes: Self.tailBytes)
        else { return nil }
        return JSONLParsers.claudeCodePendingPrompt(fromTail: tail)
    }

    private func mtime(forSessionFile filename: String) -> Date? {
        recentSessionFiles().first(where: { $0.url.lastPathComponent == filename })?.mtime
    }

    /// The session's `aiTitle` — the slug Claude Code titles its terminal
    /// tab with. Read on demand at jump time (one tail read); thread.id is
    /// the session file's name, found back via the same listing fetch uses.
    private func tabSlug(forSessionFile filename: String) -> String? {
        guard let file = recentSessionFiles()
            .first(where: { $0.url.lastPathComponent == filename }),
            let tail = FileReading.tail(of: file.url, bytes: Self.tailBytes)
        else { return nil }
        return JSONLParsers.claudeCodeSlug(fromTail: tail)
    }

    /// Activation only — a jump must never open apps or create windows.
    /// `NSRunningApplication.activate()`'s return value is unreliable, so
    /// finding a running terminal counts as landing.
    private func activateFirstRunningTerminal() -> JumpResolution {
        let running = NSWorkspace.shared.runningApplications
        for bundleID in Self.terminalBundleIDs {
            if let app = running.first(where: { $0.bundleIdentifier == bundleID }) {
                app.activate()
                return .window
            }
        }
        return .failed
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
            // One tail read per shown session (≤ maxThreads, off-main):
            // the last assistant message is the hover recap, and an
            // unanswered AskUserQuestion/ExitPlanMode is a blocked prompt.
            let tail = FileReading.tail(of: file.url, bytes: Self.tailBytes)
            let recap = tail.flatMap(JSONLParsers.claudeCodeRecap(fromTail:))
            let pending = tail.flatMap(JSONLParsers.claudeCodePendingPrompt(fromTail:))
            return AgentThread(
                id: file.url.lastPathComponent,
                title: title ?? cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Session",
                lastActivity: file.mtime,
                subtitle: cwd.map(FileReading.abbreviate),
                cwd: cwd,
                recap: pending?.question ?? recap,
                isWaitingOnYou: pending != nil,
                pendingPrompt: pending)
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
