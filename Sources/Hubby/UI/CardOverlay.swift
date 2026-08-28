import AppKit
import SwiftUI

/// Shared card placement math. One formula used by the overlay's layout,
/// the hub's hover keepalive, and the rect pushed to the panel's hitTest —
/// they must always agree or clicks and dwell fall out of sync.
enum CardGeometry {
    /// Where the floating card for a thread sits: in the side gutter,
    /// top-aligned with its row, y-clamped to the hub — never over the
    /// rows, never under the cursor's path down the list.
    static func rect(
        rowRect: CGRect, prompt: PendingPrompt?, side: CardSide, hubSize: CGSize
    ) -> CGRect {
        let width = HubbyMetrics.cardWidth
        let height: CGFloat
        if let prompt {
            height = prompt.kind == .approve
                ? 120 : 90 + CGFloat(min(prompt.options.count, 4)) * 34
        } else {
            height = 122
        }
        let x = side == .right
            ? hubSize.width + HubbyMetrics.cardGap
            : -(width + HubbyMetrics.cardGap)
        let y = min(max(rowRect.minY, 6), max(hubSize.height - height - 6, 6))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// The floating hover card, rendered OUTSIDE the morphing chrome: the card
/// lives in a side gutter beyond the hub's edge, and MorphChrome's clip
/// would swallow anything the hub draws out there. RootView attaches this
/// after the chrome; the row anchors bubble up to it as preferences.
struct CardOverlay: View {
    let anchors: [String: Anchor<CGRect>]
    let snapshots: [AgentSnapshot]
    let side: CardSide
    @Binding var recapID: String?
    let onAnswer: (AgentSnapshot, AgentThread, Int?) -> Void
    let onMarkRead: (AgentSnapshot, AgentThread) -> Void
    let onNudge: (AgentSnapshot, AgentThread) -> Void

    var body: some View {
        GeometryReader { proxy in
            if let id = recapID, let anchor = anchors[id], let entry = resolve(id) {
                let rect = CardGeometry.rect(
                    rowRect: proxy[anchor],
                    prompt: entry.thread.pendingPrompt,
                    side: side,
                    hubSize: proxy.size)
                card(for: entry)
                    .frame(width: rect.width, alignment: .leading)
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    /// Resolve an anchor key (accordion or strip) back to its thread.
    private func resolve(_ key: String) -> (snapshot: AgentSnapshot, thread: AgentThread)? {
        let id = key.hasPrefix("strip:") ? String(key.dropFirst(6)) : key
        for snapshot in snapshots {
            if let thread = snapshot.threads.first(where: { $0.id == id }) {
                return (snapshot, thread)
            }
        }
        return nil
    }

    @ViewBuilder
    private func card(for entry: (snapshot: AgentSnapshot, thread: AgentThread)) -> some View {
        if let prompt = entry.thread.pendingPrompt {
            PromptCard(thread: entry.thread, prompt: prompt) { optionIndex in
                withAnimation(HubbyAnim.cardFade) { recapID = nil }
                onAnswer(entry.snapshot, entry.thread, optionIndex)
            }
        } else {
            RecapCard(
                thread: entry.thread,
                onCopy: entry.thread.recap.map { recap in
                    {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(recap, forType: .string)
                        withAnimation(HubbyAnim.cardFade) { recapID = nil }
                    }
                },
                onMarkRead: {
                    withAnimation(HubbyAnim.cardFade) { recapID = nil }
                    onMarkRead(entry.snapshot, entry.thread)
                },
                onNudge: canNudge(entry) ? {
                    withAnimation(HubbyAnim.cardFade) { recapID = nil }
                    onNudge(entry.snapshot, entry.thread)
                } : nil)
        }
    }

    /// Nudge only where it can act: an idle Claude Code session with
    /// nothing pending (the actuator re-verifies both before typing).
    private func canNudge(_ entry: (snapshot: AgentSnapshot, thread: AgentThread)) -> Bool {
        entry.snapshot.id == "claude-code"
            && entry.thread.pendingPrompt == nil
            && entry.thread.status() == .idle
    }
}
