import SwiftUI

/// Gate for the Accessibility offer: shown at most once per launch, and
/// never again after "Not now". The status-bar menu keeps a manual way in
/// for users who change their mind.
@MainActor
enum AXOnboarding {
    static let declinedKey = "HubbyAXDeclined"
    private static var offeredThisLaunch = false

    static var shouldOffer: Bool {
        !WindowLocator.isTrusted && !offeredThisLaunch
            && !UserDefaults.standard.bool(forKey: declinedKey)
    }

    static func markOffered() { offeredThisLaunch = true }

    static func decline() {
        UserDefaults.standard.set(true, forKey: declinedKey)
    }
}

/// The in-panel Accessibility pitch. Never a system alert or popover — the
/// panel is nonactivating, so any system-presented UI would steal focus and
/// fight the hit-test gating. Ink glass like everything else.
struct AXOnboardingCard: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: OctopusGlyph.menuBarImage())
                    .renderingMode(.template)
                    .foregroundStyle(HubbyGlass.accent)
                Text("Land on the exact window")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
            }
            Text(
                "Grant Hubby Accessibility in System Settings and jumps will "
                + "raise the precise terminal or editor window for each thread.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(HubbyGlass.accent)
                    .controlSize(.small)
                Button("Not now", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0xFCF3F5).opacity(0.98)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HubbyGlass.hairline, lineWidth: 0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HubbyGlass.accent.opacity(0.35), lineWidth: 1)
                .blur(radius: 0.6))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}
