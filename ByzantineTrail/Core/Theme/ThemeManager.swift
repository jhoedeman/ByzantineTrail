import SwiftUI

@MainActor
@Observable
final class ThemeManager {
    var preference: ThemePreference = .system

    /// Resolves the active Theme. When preference is `.system`, use the
    /// environment's colorScheme; otherwise use the forced preference.
    func theme(for environmentScheme: ColorScheme) -> Theme {
        Theme.chrysos(preference.colorScheme ?? environmentScheme)
    }
}
