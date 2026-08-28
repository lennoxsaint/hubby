import Foundation

/// Tracks which finished threads the user has looked at. This is Hubby's
/// only writable store — everything else it touches belongs to other apps.
///
/// Unread is defined against *generation*, not raw activity: `lastActivity`
/// keeps moving as agents write trailing bytes after a turn, so comparing it
/// to a read timestamp re-flags threads the user already visited. Instead:
///
///     finishedUnread = !isGenerating && lastGenSeenAt > lastReadAt
///
/// `lastGenSeenAt` only advances while a thread is observed generating, so a
/// finished thread stays read until a *new* generation starts and ends.
/// Threads never seen generating (e.g. found already finished at launch)
/// never go unread — first launch doesn't light up the whole hub.
///
/// Not thread-safe by design: `ThreadStore` (MainActor) is the only caller.
final class ReadStateStore {
    struct Entry: Codable, Equatable {
        var genSeen: Date?
        var readAt: Date?
    }

    private let defaults: UserDefaults
    private let storageKey = "HubbyReadState.v1"
    /// Entries idle longer than the longest adapter window are dropped on
    /// save so the blob can't grow forever.
    private let maxAge: TimeInterval = 14 * 24 * 3600
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) }
            ?? [:]
    }

    /// Record which threads are generating this tick and flag finished-unread
    /// ones in place. Call on every refresh, with the freshly built snapshots.
    func decorate(_ snapshots: [AgentSnapshot], now: Date = Date()) -> [AgentSnapshot] {
        var dirty = false
        let decorated = snapshots.map { snapshot in
            let threads = snapshot.threads.map { thread -> AgentThread in
                var thread = thread
                let key = Self.key(appID: snapshot.info.id, threadID: thread.id)
                var entry = entries[key] ?? Entry()
                if thread.isGenerating {
                    entry.genSeen = now
                    entries[key] = entry
                    dirty = true
                }
                thread.isFinishedUnread = !thread.isGenerating
                    && (entry.genSeen ?? .distantPast) > (entry.readAt ?? .distantPast)
                return thread
            }
            return AgentSnapshot(
                info: snapshot.info, isRunning: snapshot.isRunning, threads: threads)
        }
        if dirty { save(now: now) }
        return decorated
    }

    /// A click on the thread row means "seen", whether or not the jump lands.
    func markRead(appID: String, threadID: String, now: Date = Date()) {
        let key = Self.key(appID: appID, threadID: threadID)
        var entry = entries[key] ?? Entry()
        entry.readAt = now
        entries[key] = entry
        save(now: now)
    }

    private func save(now: Date) {
        entries = entries.filter { _, entry in
            now.timeIntervalSince(
                max(entry.genSeen ?? .distantPast, entry.readAt ?? .distantPast)) < maxAge
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func key(appID: String, threadID: String) -> String {
        "\(appID)/\(threadID)"
    }
}
