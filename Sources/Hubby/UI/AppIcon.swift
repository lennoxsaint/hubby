import AppKit
import SwiftUI

/// Loads real app icons at runtime from the installed apps and caches them.
/// Nothing is bundled with Hubby — if an app isn't installed, callers fall
/// back to the SF Symbol placeholder.
@MainActor
enum AppIconLoader {
    /// nil is cached too — a missing app shouldn't hit NSWorkspace on
    /// every render pass.
    private static var cache: [String: NSImage?] = [:]

    static func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let image = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { url -> NSImage in
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 64, height: 64)
                return icon
            }
        cache[bundleID] = image
        return image
    }
}

/// One agent app's icon: the real installed-app icon when available,
/// else the tinted-symbol circle.
struct AppIconView: View {
    let info: AgentAppInfo
    let size: CGFloat
    var dimmed: Bool = false
    /// When set (and non-empty), a segmented status ring circumscribes the
    /// icon; the icon shrinks slightly to make room.
    var ring: RingCounts? = nil

    private var hasRing: Bool { ring.map { !$0.isEmpty } ?? false }

    var body: some View {
        iconBody
            .frame(
                width: size - (hasRing ? 7 : 0),
                height: size - (hasRing ? 7 : 0))
            .opacity(dimmed ? 0.45 : 1)
            .saturation(dimmed ? 0.2 : 1)
            .frame(width: size, height: size)
            .overlay {
                if hasRing, let ring {
                    SegmentedStatusRing(counts: ring)
                        .padding(0.5)
                }
            }
    }

    @ViewBuilder
    private var iconBody: some View {
        if let bundleID = info.iconBundleID,
           let icon = AppIconLoader.icon(forBundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            ZStack {
                Circle().fill(info.tint)
                Image(systemName: info.symbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
