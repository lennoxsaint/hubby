import Foundation

/// The swipe-the-stack model: a pinned app id rotates the store's smart
/// order so that app leads the fan and the hub. An id (not an index) so a
/// background refresh reordering the apps can never silently change what's
/// on top. Pure, so the gesture's arithmetic is testable without UI.
enum FanRotation {
    /// Rotate so `id` is first; identity for nil or unknown ids.
    static func rotated(_ snapshots: [AgentSnapshot], top id: String?) -> [AgentSnapshot] {
        guard let id,
              let index = snapshots.firstIndex(where: { $0.id == id }),
              index > 0 else { return snapshots }
        return Array(snapshots[index...]) + Array(snapshots[..<index])
    }

    /// Same rotation over bare ids (the spin-settle path has no snapshots).
    static func rotatedIDs(_ order: [String], top id: String?) -> [String] {
        guard let id, let index = order.firstIndex(of: id), index > 0 else { return order }
        return Array(order[index...]) + Array(order[..<index])
    }

    /// The id on top after one swipe step: the current top card slides under
    /// the stack and its neighbor rises (or the reverse for the other
    /// direction). `order` is the store's base order.
    static func cycled(_ order: [String], from current: String?, direction: Int) -> String? {
        guard !order.isEmpty else { return nil }
        let count = order.count
        let currentIndex = current.flatMap { order.firstIndex(of: $0) } ?? 0
        let step = direction >= 0 ? 1 : -1
        return order[((currentIndex + step) % count + count) % count]
    }
}
