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

enum HubbyAnim {
    /// The one spring that drives the entire orb <-> hub morph.
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.78)
}

let relativeTimeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()
