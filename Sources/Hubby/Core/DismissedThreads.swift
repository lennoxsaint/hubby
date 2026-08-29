import Foundation

/// Swipe-dismissed threads — swept out of the list until they show new
/// activity. Same shape and discipline as ThreadPinStore: UserDefaults
/// blob, `appID/threadID` keys, main-actor-only via ThreadStore, pruned by
/// age. Sessions on disk are never touched; this only hides rows.
final class DismissedThreadStore {
    private let defaults: UserDefaults
    private let storageKey = "HubbyDismissed.v1"
    private let maxAge: TimeInterval = 14 * 24 * 3600
    /// Dismissal date by key. Any thread activity after it revives the row —
    /// a woken agent must never be invisible.
    private var dismissed: [String: Date]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dismissed = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) }
            ?? [:]
    }

    func dismiss(appID: String, threadID: String, now: Date = Date()) {
        dismissed[ReadStateStore.key(appID: appID, threadID: threadID)] = now
        save(now: now)
    }

    /// Drop threads still resting under a dismissal; forget dismissals the
    /// moment a thread outdates them so the revived row stays for good.
    func filter(_ snapshots: [AgentSnapshot], now: Date = Date()) -> [AgentSnapshot] {
        var revived = false
        let filtered = snapshots.map { snapshot in
            AgentSnapshot(
                info: snapshot.info, isRunning: snapshot.isRunning,
                threads: snapshot.threads.filter { thread in
                    let key = ReadStateStore.key(appID: snapshot.info.id, threadID: thread.id)
                    guard let at = dismissed[key] else { return true }
                    guard thread.lastActivity > at else { return false }
                    dismissed[key] = nil
                    revived = true
                    return true
                })
        }
        if revived { save(now: now) }
        return filtered
    }

    private func save(now: Date) {
        dismissed = dismissed.filter { now.timeIntervalSince($0.value) < maxAge }
        if let data = try? JSONEncoder().encode(dismissed) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
