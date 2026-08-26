import Foundation

/// Grok Bot agents, read from the roster blob in
/// `~/Library/Application Support/Grok Bot/sand-client-persistence/`.
/// The roster carries names, activity, and `awaitingUserResponse` — the
/// "this agent needs you" signal (see GrokRoster).
struct GrokBotSource: AgentSource {
    let persistenceDir: URL

    let info = AgentAppInfo(
        id: "grok-bot", name: "Grok Bot",
        bundleIDs: ["com.anysphere.sand"],
        symbol: "bolt.fill", tintHex: 0x3B3B3B,
        iconBundleID: "com.anysphere.sand")

    private static let maxThreads = 8

    var watchedPaths: [URL] { [persistenceDir] }

    func fetchThreads() -> [AgentThread] {
        guard let names = try? FileManager.default
            .contentsOfDirectory(atPath: persistenceDir.path) else { return [] }
        for name in names {
            guard let key = GrokRoster.key(forBlobFilename: name),
                  key.hasSuffix("roster.last-roster") else { continue }
            let url = persistenceDir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return [] }
            return GrokRoster.parse(data, cap: Self.maxThreads)
        }
        return []
    }
}
