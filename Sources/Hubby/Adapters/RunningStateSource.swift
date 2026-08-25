import Foundation

/// Fallback adapter for apps whose thread stores are encrypted or opaque
/// (ChatGPT's conversation store, Claude Desktop's LevelDB, Hermes, Grok Bot).
/// Shows whether the app is running and offers a one-click open — nothing else.
struct RunningStateSource: AgentSource {
    let info: AgentAppInfo

    func fetchThreads() -> [AgentThread] { [] }
}
