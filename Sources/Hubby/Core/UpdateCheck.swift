import Foundation

/// The one sanctioned exception to "no network calls" (AGENTS.md rule 4):
/// an OPT-IN, off-by-default check against GitHub's public releases API —
/// a single anonymous GET, at most once a day, only while enabled. It never
/// downloads anything; a newer version just lights a menu item that opens
/// the Releases page. Everything else Hubby does stays on-machine.
@MainActor
final class UpdateChecker: ObservableObject {
    nonisolated static let releasesPage = URL(
        string: "https://github.com/lennoxsaint/hubby/releases/latest")!
    private static let api = URL(
        string: "https://api.github.com/repos/lennoxsaint/hubby/releases/latest")!

    private static let enabledKey = "HubbyUpdateCheck.enabled"
    private static let lastCheckKey = "HubbyUpdateCheck.lastCheck"
    private static let latestSeenKey = "HubbyUpdateCheck.latestSeen"
    private static let minimumInterval: TimeInterval = 24 * 60 * 60

    /// The newer version's tag when one is known, e.g. "1.2.0". Nil = up to
    /// date, never checked, or checking disabled.
    @Published private(set) var availableVersion: String?

    private let defaults: UserDefaults
    private let currentVersion: String

    init(defaults: UserDefaults = .standard, currentVersion: String = AppVersion.short) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        // A previously-seen newer release lights the menu immediately on
        // launch — no network needed until the next scheduled check.
        if let seen = defaults.string(forKey: Self.latestSeenKey),
           SemVer.isNewer(seen, than: currentVersion) {
            availableVersion = seen
        }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue { availableVersion = nil }
        }
    }

    /// Scheduled path: respects the opt-in and the 24h throttle.
    func checkIfDue() {
        guard isEnabled else { return }
        let last = defaults.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= Self.minimumInterval else { return }
        Task { await check() }
    }

    /// Explicit "Check Now" menu action: skips the throttle, not the record.
    func check() async {
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        var request = URLRequest(url: Self.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(LatestRelease.self, from: data)
        else { return } // offline or rate-limited: silently stay quiet
        let tag = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst()) : release.tagName
        defaults.set(tag, forKey: Self.latestSeenKey)
        availableVersion = SemVer.isNewer(tag, than: currentVersion) ? tag : nil
    }

    private struct LatestRelease: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }
}

/// Dotted-numeric version comparison, tolerant of missing components
/// ("1.1" == "1.1.0") and junk (unparseable strings are never "newer").
enum SemVer {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parse(_ version: String) -> [Int]? {
        // "1.2.0-beta.1" compares by its numeric core.
        let core = version.split(separator: "-").first.map(String.init) ?? version
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}

/// The bundle's stamped version (see Makefile: `make app` writes it from
/// the VERSION file). A bare `swift build` binary has no bundle plist and
/// reports "0.0.0" — that's the tell that you're not running a real bundle.
enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
