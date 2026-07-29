import SwiftUI

@MainActor
@Observable
final class ThemeManager {
    private let defaults: UserDefaults
    private static let key = "settings.appearance"

    /// Persisted appearance preference. `.system` follows the device.
    var preference: ThemePreference {
        didSet { defaults.set(preference.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.key)
        self.preference = raw.flatMap(ThemePreference.init(rawValue:)) ?? .system
    }

    /// Resolves the active Theme. When preference is `.system`, use the
    /// environment's colorScheme; otherwise use the forced preference.
    func theme(for environmentScheme: ColorScheme) -> Theme {
        Theme.chrysos(preference.colorScheme ?? environmentScheme)
    }
}
