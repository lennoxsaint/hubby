import Foundation

/// Per-adapter enable/disable, persisted as a set of disabled source IDs.
/// Everything is enabled by default; the menu-bar Adapters submenu flips
/// entries. Disabling stops fetching AND hides the app's row/icon.
struct SourceToggleStore {
    private static let key = "HubbyDisabledSources.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var disabledIDs: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func isEnabled(_ id: String) -> Bool {
        !disabledIDs.contains(id)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        var ids = disabledIDs
        if enabled { ids.remove(id) } else { ids.insert(id) }
        defaults.set(Array(ids).sorted(), forKey: Self.key)
    }
}
