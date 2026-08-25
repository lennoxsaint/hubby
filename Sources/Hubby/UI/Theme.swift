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
    static let hubSize = CGSize(width: 330, height: 460)
    static let cornerRadius: CGFloat = 24
    /// Panel is padded slightly beyond content for shadow breathing room.
    static let panelPadding: CGFloat = 8
}

let relativeTimeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()
