import AppKit
import Foundation

/// Observable store the UI reads. Refreshes when the agent apps' data files
/// change (FSEvents) plus a slow fallback timer, and publishes snapshots
/// sorted by recency so the orb fan and hub rows always agree.
@MainActor
final class ThreadStore: ObservableObject {
    @Published private(set) var snapshots: [AgentSnapshot] = []

    private let sources: [AgentSource]
    private let refreshInterval: TimeInterval
    private var timer: Timer?
    private var watcher: FileWatcher?
    /// Guards against a slow, stale refresh overwriting a newer one.
    private var generation = 0

    init(sources: [AgentSource] = ThreadStore.defaultSources(), refreshInterval: TimeInterval = 30) {
        self.sources = sources
        self.refreshInterval = refreshInterval
    }

    func start() {
        refresh()
        // FSEvents does the instant updates; the timer only backstops
        // running-app state, which has no file to watch.
        watcher = FileWatcher(paths: sources.flatMap(\.watchedPaths)) { [weak self] in
            self?.refresh()
        }
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let sources = self.sources
        // NSWorkspace is main-thread territory; capture the running set here
        // so the background snapshot pass never touches AppKit.
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        generation += 1
        let tick = generation
        Task.detached(priority: .utility) {
            let fresh = Self.ordered(sources.map { $0.snapshot(runningBundleIDs: runningIDs) })
            await MainActor.run { [weak self] in
                guard let self, self.generation == tick else { return }
                self.snapshots = fresh
            }
        }
    }

    /// Shared ordering: generating first, then needs-you, then most recent
    /// thread activity, then merely-running apps, then stable input order.
    nonisolated static func ordered(_ snapshots: [AgentSnapshot]) -> [AgentSnapshot] {
        func key(_ snapshot: AgentSnapshot, _ offset: Int) -> (Int, Int, TimeInterval, Int, Int) {
            (snapshot.threads.contains(where: \.isGenerating) ? 1 : 0,
             snapshot.threads.contains(where: \.isWaitingOnYou) ? 1 : 0,
             snapshot.threads.map(\.lastActivity.timeIntervalSince1970).max() ?? 0,
             snapshot.isRunning ? 1 : 0,
             -offset)
        }
        return snapshots.enumerated()
            .sorted { key($0.element, $0.offset) > key($1.element, $1.offset) }
            .map(\.element)
    }

    func source(for id: String) -> AgentSource? {
        sources.first { $0.info.id == id }
    }

    /// Threads generating right now, across every app (green orb badge).
    var totalRunning: Int {
        snapshots.reduce(0) { $0 + $1.runningCount }
    }

    /// Agents blocked on the human, across every app (amber orb badge).
    var totalNeedsYou: Int {
        snapshots.reduce(0) { $0 + $1.needsYouCount }
    }

    nonisolated static func defaultSources() -> [AgentSource] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support")
        return [
            ClaudeCodeSource(projectsDir: home.appendingPathComponent(".claude/projects")),
            // The ChatGPT desktop app (com.openai.codex) and the Codex CLI
            // share ~/.codex — one merged row covers both.
            CodexSource(codexDir: home.appendingPathComponent(".codex")),
            RunningStateSource(info: AgentAppInfo(
                id: "claude-desktop", name: "Claude",
                bundleIDs: ["com.anthropic.claudefordesktop"],
                symbol: "sparkle", tintHex: 0xD97757,
                iconBundleID: "com.anthropic.claudefordesktop")),
            CursorSource(databaseURL: appSupport.appendingPathComponent(
                "Cursor/User/globalStorage/conversation-search.db")),
            HermesSource(stateDB: home.appendingPathComponent(".hermes/state.db")),
            GrokBotSource(persistenceDir: appSupport.appendingPathComponent(
                "Grok Bot/sand-client-persistence")),
        ]
    }
}
