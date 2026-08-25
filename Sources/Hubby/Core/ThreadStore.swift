import Foundation

/// Observable store the UI reads. Polls every source on a background queue
/// every `refreshInterval` seconds and publishes fresh snapshots.
@MainActor
final class ThreadStore: ObservableObject {
    @Published private(set) var snapshots: [AgentSnapshot] = []

    private let sources: [AgentSource]
    private let refreshInterval: TimeInterval
    private var timer: Timer?

    init(sources: [AgentSource] = ThreadStore.defaultSources(), refreshInterval: TimeInterval = 5) {
        self.sources = sources
        self.refreshInterval = refreshInterval
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let sources = self.sources
        Task.detached(priority: .utility) {
            let fresh = sources.map { $0.snapshot() }
            await MainActor.run { [weak self] in
                self?.snapshots = fresh
            }
        }
    }

    func source(for id: String) -> AgentSource? {
        sources.first { $0.info.id == id }
    }

    var totalActive: Int {
        snapshots.reduce(0) { $0 + $1.activeCount }
    }

    nonisolated static func defaultSources() -> [AgentSource] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support")
        return [
            ClaudeCodeSource(projectsDir: home.appendingPathComponent(".claude/projects")),
            CodexSource(sessionsDir: home.appendingPathComponent(".codex/sessions")),
            RunningStateSource(info: AgentAppInfo(
                id: "chatgpt", name: "ChatGPT",
                bundleIDs: ["com.openai.chat", "com.openai.codex"],
                symbol: "bubble.left.and.bubble.right.fill", tintHex: 0x10A37F)),
            RunningStateSource(info: AgentAppInfo(
                id: "claude-desktop", name: "Claude",
                bundleIDs: ["com.anthropic.claudefordesktop"],
                symbol: "sparkle", tintHex: 0xD97757)),
            CursorSource(databaseURL: appSupport.appendingPathComponent(
                "Cursor/User/globalStorage/conversation-search.db")),
            RunningStateSource(info: AgentAppInfo(
                id: "hermes", name: "Hermes",
                bundleIDs: ["com.nousresearch.hermes"],
                symbol: "wind", tintHex: 0x8E7CFF)),
            RunningStateSource(info: AgentAppInfo(
                id: "grok-bot", name: "Grok Bot",
                bundleIDs: ["com.anysphere.sand"],
                symbol: "bolt.fill", tintHex: 0x3B3B3B)),
        ]
    }
}
