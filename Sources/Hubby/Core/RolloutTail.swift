import Foundation

/// Liveness from a Codex rollout file's tail.
///
/// `thread_history_1.sqlite`'s `inProgress` turns cover only threads with
/// `history_mode='paginated'` (43 of 11,739 on a real install) and linger for
/// days after a crash. The rollout jsonl is written for EVERY thread — legacy,
/// paginated, subagent, automation — and its event stream marks turn bounds:
///
///   {"type":"event_msg","payload":{"type":"task_started", ...}}
///   {"type":"event_msg","payload":{"type":"task_complete", ...}}
///
/// A thread is generating iff its last `task_started` has no later
/// `task_complete`. A crashed/interrupted turn can leave `task_started`
/// dangling, so callers must also require the file's mtime to be fresh
/// (`mtimeFreshWindow`) — a dead thread stops being "live" within seconds.
enum RolloutTail {
    static let tailBytes = 64 * 1024
    /// A rollout untouched this long is idle regardless of its tail.
    static let mtimeFreshWindow: TimeInterval = 90

    static func isLive(tail: Data) -> Bool {
        let started = lastOffset(of: "\"type\":\"task_started\"", in: tail)
        guard let started else { return false }
        guard let complete = lastOffset(of: "\"type\":\"task_complete\"", in: tail) else {
            return true
        }
        return started > complete
    }

    private static func lastOffset(of marker: String, in data: Data) -> Int? {
        data.range(of: Data(marker.utf8), options: .backwards)?.lowerBound
    }
}
