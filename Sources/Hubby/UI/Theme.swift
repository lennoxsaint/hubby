import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

extension AgentAppInfo {
    var tint: Color { Color(hex: tintHex) }
}

enum HubbyMetrics {
    /// Big enough for the full six-icon flower with per-icon badges.
    static let orbDiameter: CGFloat = 72
    static let hubWidth: CGFloat = 330
    /// The scrollable rows area is capped; the hub itself hugs its content.
    /// Budgeted so priorities (~96) + capped rows + wordmark (~34) always
    /// fit inside `maxHubHeight` — the rows scroll, nothing clips.
    static let maxRowsHeight: CGFloat = 420
    /// Priorities + capped rows + wordmark; the panel always fits this.
    static let maxHubHeight: CGFloat = 580
    static let cornerRadius: CGFloat = 24
    /// Must exceed the largest shadow radius + offset, or the soft shadow is
    /// hard-clipped at the panel edge and reads as a faint square outline.
    static let panelPadding: CGFloat = 26
    /// Hover-card width (recap and prompt cards share it).
    static let cardWidth: CGFloat = 270
    /// Gap between the hub's edge and a floating card.
    static let cardGap: CGFloat = 10
    /// Transparent side region beside the hub where hover cards float —
    /// wide enough for a card, its gap, and a little shadow room.
    static let cardGutter: CGFloat = cardWidth + cardGap * 2

    /// Horizontal inset from the panel edge to the visible content (orb or
    /// hub): padding + one card gutter. Vertical inset stays `panelPadding`.
    static let contentInsetX: CGFloat = panelPadding + cardGutter

    /// The panel never resizes: it is always big enough for the expanded hub
    /// PLUS a card gutter either side, and the hosting view's hitTest passes
    /// clicks through the unused clear area (including empty gutters).
    static var panelSize: CGSize {
        CGSize(
            width: hubWidth + contentInsetX * 2,
            height: maxHubHeight + panelPadding * 2)
    }
}

/// Which side of the hub the hover card floats on. Chosen at expand time
/// from screen space: right unless the right gutter would clip off-screen.
enum CardSide {
    case right, left
}

/// The blush-frost identity: Hubby's own surface, not a system material.
/// Mostly-white glass warmed with a blush tint and a rose-gold rim light —
/// the same glass wraps the orb, the hub, and every floating card. Text on
/// it is always dark (RootView forces the light color scheme).
enum HubbyGlass {
    // The palette is deliberately two hues: ROSE for information (new
    // results, accents) and AMBER for action (blocked on you). Everything
    // else is ink and glass — "generating" is told by the shimmer's motion,
    // not by a colour of its own.
    /// Generating right now — a calm warm gray; the shimmer is the signal.
    static let running = Color(hex: 0x8A7A80)
    /// Blocked waiting on the human. The one loud colour.
    static let needsYou = Color(hex: 0xD97706)
    /// Finished, not yet jumped to — rose, matching the brand accent.
    static let unread = Color(hex: 0xB8798A)

    /// Rose gold — the brand accent behind the rim light.
    static let accent = Color(hex: 0xB76E79)
    /// Blush frost surface; translucency is the desk-pet feel (settled at
    /// a light frost — see-through, but with enough body to read as glass).
    static let base = Color(hex: 0xF9EDF0).opacity(0.84)
    /// Opacity floor behind `base` so the desktop never bleeds through text.
    static let floor = Color.white.opacity(0.52)
    /// Inner 0.5pt glass edge — dark on light glass.
    static let hairline = Color.black.opacity(0.10)

    /// The cursive wordmark at the hub's bottom centre ("running writing").
    static let wordmark = Font.custom("SnellRoundhand-Bold", size: 16)
}

enum HubbyAnim {
    /// The one spring that drives the entire orb <-> hub morph.
    static let morph = Animation.spring(response: 0.30, dampingFraction: 0.78)
    /// Ring segments growing/shrinking as thread states change.
    static let badge = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// One fan-swipe step: top card slides under, its neighbor rises.
    static let fanCycle = Animation.spring(response: 0.35, dampingFraction: 0.75)
    /// One hub row falling into place during the expand cascade.
    static let cascade = Animation.spring(response: 0.32, dampingFraction: 0.8)
    /// Accordion drop-down open/close.
    static let accordion = Animation.spring(duration: 0.22)
    /// Hover card in/out.
    static let cardFade = Animation.easeOut(duration: 0.10)
}

let relativeTimeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()
