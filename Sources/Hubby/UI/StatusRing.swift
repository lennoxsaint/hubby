import SwiftUI

/// What a status ring summarizes: how many of an app's threads are running,
/// blocked on the human, or finished-but-unread, out of how many total.
struct RingCounts: Equatable {
    var running: Int
    var needsYou: Int
    var unread: Int
    var total: Int

    init(running: Int, needsYou: Int, unread: Int, total: Int) {
        self.running = running
        self.needsYou = needsYou
        self.unread = unread
        self.total = max(total, 1)
    }

    init(snapshot: AgentSnapshot) {
        self.init(
            running: snapshot.runningCount,
            needsYou: snapshot.needsYouCount,
            unread: snapshot.unreadCount,
            total: snapshot.threads.count)
    }

    /// Everything that wants the human's eyes: blocked + unread results.
    var attention: Int { needsYou + unread }
    var isEmpty: Bool { running + needsYou + unread == 0 }
}

/// A thin ring whose colored arcs are proportional to the thread states:
/// green running, orange needs-you, blue finished-unread, over a faint
/// track. Reads at a glance and never grows, whatever the counts.
struct SegmentedStatusRing: View {
    let counts: RingCounts
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.10), lineWidth: lineWidth)
            ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                Circle()
                    .trim(from: slice.start, to: slice.end)
                    .stroke(
                        slice.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(HubbyAnim.badge, value: counts)
        .allowsHitTesting(false)
    }

    /// Proportional arc per non-zero state, clockwise from 12 o'clock, with
    /// a small gap between neighbors and a floor so one thread of many is
    /// still visible.
    private var slices: [(color: Color, start: CGFloat, end: CGFloat)] {
        let total = CGFloat(counts.total)
        let states: [(Color, Int)] = [
            (HubbyGlass.running, counts.running),
            (HubbyGlass.needsYou, counts.needsYou),
            (HubbyGlass.unread, counts.unread),
        ]
        let gap: CGFloat = 0.015
        var cursor: CGFloat = 0
        return states.compactMap { color, count in
            guard count > 0 else { return nil }
            let fraction = max(CGFloat(count) / total, 0.08)
            let start = min(cursor, 1)
            let end = min(cursor + fraction - gap, 1)
            cursor = min(cursor + fraction, 1)
            return (color, start, max(end, start + 0.03))
        }
    }
}

