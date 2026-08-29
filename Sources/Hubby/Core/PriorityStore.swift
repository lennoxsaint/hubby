import Foundation

/// The user's top-three priorities — the tiny personal list pinned to the
/// top of the hub so a glance always answers "what actually matters right
/// now". Not agent state: only the user writes these. Persisted like the
/// other per-user stores (UserDefaults JSON blob, main-actor-only).
@MainActor
final class PriorityStore: ObservableObject {
    struct Priority: Codable, Equatable, Identifiable {
        var id = UUID()
        var text: String = ""
        /// When the checkbox was ticked. A short grace window lets the user
        /// untick before the line clears to an empty slot.
        var checkedAt: Date? = nil
    }

    static let slotCount = 3
    /// How long a ticked line lingers (struck through) before clearing.
    static let clearGrace: TimeInterval = 4

    @Published var slots: [Priority] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let storageKey = "HubbyPriorities.v1"

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        var loaded = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([Priority].self, from: $0) }
            ?? []
        // A line ticked longer than the grace ago has been "done" since the
        // last run — it arrives already cleared.
        loaded = loaded.map { slot in
            guard let checkedAt = slot.checkedAt,
                  now.timeIntervalSince(checkedAt) > Self.clearGrace else { return slot }
            return Priority()
        }
        while loaded.count < Self.slotCount { loaded.append(Priority()) }
        slots = Array(loaded.prefix(Self.slotCount))
    }

    /// Drag-reorder: move the slot at `from` so it sits at `to`.
    func move(from: Int, to: Int) {
        guard slots.indices.contains(from), slots.indices.contains(to), from != to
        else { return }
        let slot = slots.remove(at: from)
        slots.insert(slot, at: to)
    }

    /// Tick/untick a slot's checkbox. Clearing after the grace is the UI's
    /// job (it owns the animation); relaunch-clearing is handled in init.
    func setChecked(_ checked: Bool, at index: Int, now: Date = Date()) {
        guard slots.indices.contains(index) else { return }
        slots[index].checkedAt = checked ? now : nil
    }

    /// The grace expired: the slot empties, ready for the next priority.
    func clear(at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = Priority()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(slots) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
