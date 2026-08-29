import Foundation

/// The user's top-three priorities — the tiny personal list pinned to the
/// top of the hub so a glance always answers "what actually matters right
/// now". Not agent state: only the user writes these. Persisted like the
/// other per-user stores (UserDefaults JSON blob, main-actor-only).
///
/// The list is a queue, not three checkboxes: completing a line promotes
/// everything below it (2 → 1, 3 → 2) and opens slot 3 for the next
/// priority. Every completion is appended to a durable on-disk ledger with
/// its rank, when it was written, and when it was done.
@MainActor
final class PriorityStore: ObservableObject {
    struct Priority: Codable, Equatable, Identifiable {
        var id = UUID()
        var text: String = ""
        /// When the line's text was first written (metadata for the ledger).
        var createdAt: Date? = nil
        /// When the line was ticked. A short strike-through beat lets the
        /// user untick before it's committed and the queue promotes.
        var checkedAt: Date? = nil
    }

    /// One completed priority, as appended to the history ledger.
    struct CompletionRecord: Codable {
        let text: String
        /// 1-based rank the priority held when completed.
        let rank: Int
        let createdAt: Date?
        let completedAt: Date
        /// How long it sat on the list, when `createdAt` is known.
        let secondsOnList: TimeInterval?
    }

    static let slotCount = 3
    /// How long a ticked line lingers (struck through) before the queue
    /// promotes — long enough to untick a slip, short enough to feel done.
    static let clearGrace: TimeInterval = 1.5

    @Published var slots: [Priority] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let storageKey = "HubbyPriorities.v1"
    private let historyURL: URL

    /// The ledger's default home, beside the app's other durable state.
    nonisolated static func defaultHistoryURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Hubby/priority-history.jsonl")
    }

    init(
        defaults: UserDefaults = .standard,
        historyURL: URL = PriorityStore.defaultHistoryURL(),
        now: Date = Date()
    ) {
        self.defaults = defaults
        self.historyURL = historyURL
        var loaded = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([Priority].self, from: $0) }
            ?? []
        while loaded.count < Self.slotCount { loaded.append(Priority()) }
        loaded = Array(loaded.prefix(Self.slotCount))
        slots = loaded
        // A line ticked longer than the grace ago was completed since the
        // last run — record it and promote, same as the live path.
        for slot in loaded {
            if let checkedAt = slot.checkedAt,
               now.timeIntervalSince(checkedAt) > Self.clearGrace,
               let index = slots.firstIndex(where: { $0.id == slot.id }) {
                finish(at: index, now: checkedAt)
            }
        }
    }

    /// Write a line's text; first ink stamps `createdAt` for the ledger.
    func setText(_ text: String, at index: Int, now: Date = Date()) {
        guard slots.indices.contains(index) else { return }
        slots[index].text = text
        if slots[index].createdAt == nil,
           !text.trimmingCharacters(in: .whitespaces).isEmpty {
            slots[index].createdAt = now
        }
    }

    /// Drag-reorder: move the slot at `from` so it sits at `to`.
    func move(from: Int, to: Int) {
        guard slots.indices.contains(from), slots.indices.contains(to), from != to
        else { return }
        let slot = slots.remove(at: from)
        slots.insert(slot, at: to)
    }

    /// Tick/untick a line. Promotion after the grace is the UI's job (it
    /// owns the animation); it calls `finish` when the beat passes.
    func setChecked(_ checked: Bool, at index: Int, now: Date = Date()) {
        guard slots.indices.contains(index) else { return }
        slots[index].checkedAt = checked ? now : nil
    }

    /// The completion commits: append the line to the ledger, then promote
    /// the queue — the row leaves, everything below moves up one rank, and
    /// a fresh empty slot opens at the bottom.
    func finish(at index: Int, now: Date = Date()) {
        guard slots.indices.contains(index) else { return }
        let slot = slots[index]
        let text = slot.text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            appendToHistory(CompletionRecord(
                text: text,
                rank: index + 1,
                createdAt: slot.createdAt,
                completedAt: slot.checkedAt ?? now,
                secondsOnList: slot.createdAt.map {
                    (slot.checkedAt ?? now).timeIntervalSince($0)
                }))
        }
        slots.remove(at: index)
        slots.append(Priority())
    }

    /// The completions ledger, newest last. Empty if none yet.
    func history() -> [CompletionRecord] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? decoder.decode(CompletionRecord.self, from: Data($0.utf8)) }
    }

    private func appendToHistory(_ record: CompletionRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A)
        let fm = FileManager.default
        try? fm.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: historyURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: historyURL)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(slots) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
