import Foundation

/// Persistent per-thread pins — the user's "keep this one on top" marks.
/// Same shape and discipline as ReadStateStore: UserDefaults blob, keys are
/// `appID/threadID`, main-actor-only via ThreadStore, pruned by age so
/// pins on long-dead threads don't accumulate forever.
final class ThreadPinStore {
    private let defaults: UserDefaults
    private let storageKey = "HubbyThreadPins.v1"
    private let maxAge: TimeInterval = 30 * 24 * 3600
    /// Pin date by key — the date drives pruning and keeps pin order stable.
    private var pins: [String: Date]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pins = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) }
            ?? [:]
    }

    func isPinned(appID: String, threadID: String) -> Bool {
        pins[ReadStateStore.key(appID: appID, threadID: threadID)] != nil
    }

    func toggle(appID: String, threadID: String, now: Date = Date()) {
        let key = ReadStateStore.key(appID: appID, threadID: threadID)
        if pins[key] != nil {
            pins[key] = nil
        } else {
            pins[key] = now
        }
        save(now: now)
    }

    /// Flag pinned threads in place; refresh every tick like read-state.
    func decorate(_ snapshots: [AgentSnapshot]) -> [AgentSnapshot] {
        snapshots.map { snapshot in
            AgentSnapshot(
                info: snapshot.info, isRunning: snapshot.isRunning,
                threads: snapshot.threads.map { thread in
                    var thread = thread
                    thread.isPinned = isPinned(appID: snapshot.info.id, threadID: thread.id)
                    return thread
                })
        }
    }

    private func save(now: Date) {
        pins = pins.filter { now.timeIntervalSince($0.value) < maxAge }
        if let data = try? JSONEncoder().encode(pins) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
