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
    static let orbDiameter: CGFloat = 56
    static let hubWidth: CGFloat = 330
    /// The scrollable rows area is capped; the hub itself hugs its content.
    static let maxRowsHeight: CGFloat = 520
    /// Header + divider + capped rows; the panel is sized to always fit this.
    static let maxHubHeight: CGFloat = 580
    static let cornerRadius: CGFloat = 24
    /// Must exceed the largest shadow radius + offset, or the soft shadow is
    /// hard-clipped at the panel edge and reads as a faint square outline.
    static let panelPadding: CGFloat = 26

    /// The panel never resizes: it is always big enough for the expanded hub,
    /// and the hosting view's hitTest passes clicks through the unused area.
    static var panelSize: CGSize {
        CGSize(
            width: hubWidth + panelPadding * 2,
            height: maxHubHeight + panelPadding * 2)
    }
}

/// The ink-glass identity: Hubby's own surface, not a system material.
/// Near-opaque obsidian with a violet rim light — the same glass wraps the
/// orb, the hub, and every floating card.
enum HubbyGlass {
    /// Generating right now.
    static let running = Color(hex: 0x34D27A)
    /// Blocked waiting on the human.
    static let needsYou = Color.orange
    /// Finished, not yet jumped to.
    static let unread = Color(hex: 0x5AA2FF)

    /// Hubby violet — the brand accent behind the rim light.
    static let accent = Color(hex: 0x8E7CFF)
    /// Obsidian surface; a hint of translucency keeps the desk-pet feel.
    static let base = Color(hex: 0x0A0A0F).opacity(0.94)
    /// Opacity floor behind `base` so the desktop never bleeds through text.
    static let floor = Color.black.opacity(0.62)
    /// Inner 0.5pt glass edge.
    static let hairline = Color.white.opacity(0.22)

    /// The colored rim light: accent circling the edge, brightest top-left.
    static let rim = AngularGradient(
        gradient: Gradient(stops: [
            .init(color: accent.opacity(0.85), location: 0),
            .init(color: accent.opacity(0.12), location: 0.3),
            .init(color: accent.opacity(0.35), location: 0.55),
            .init(color: accent.opacity(0.12), location: 0.8),
            .init(color: accent.opacity(0.85), location: 1),
        ]),
        center: .center,
        angle: .degrees(-125))

    /// Soft top-third light catch on the glass.
    static let sheen = LinearGradient(
        colors: [Color.white.opacity(0.09), Color.white.opacity(0)],
        startPoint: .top,
        endPoint: .center)
}

enum HubbyAnim {
    /// The one spring that drives the entire orb <-> hub morph.
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Ring segments growing/shrinking as thread states change.
    static let badge = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// One fan-swipe step: top card slides under, its neighbor rises.
    static let fanCycle = Animation.spring(response: 0.35, dampingFraction: 0.75)
}

let relativeTimeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()
