import Testing
import Foundation
@testable import ByzantineTrail

@MainActor
struct ThemeManagerPersistenceTests {
    private func freshDefaults(_ suite: String) -> UserDefaults {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func defaultsToSystemWhenEmpty() {
        let m = ThemeManager(defaults: freshDefaults("m6.theme.empty"))
        #expect(m.preference == .system)
    }

    @Test func persistsAndRestoresAcrossInstances() {
        let d = freshDefaults("m6.theme.roundtrip")
        let m = ThemeManager(defaults: d)
        m.preference = .dark
        let restored = ThemeManager(defaults: d)
        #expect(restored.preference == .dark)
    }

    @Test func garbageValueFallsBackToSystem() {
        let d = freshDefaults("m6.theme.garbage")
        d.set("purple", forKey: "settings.appearance")
        let m = ThemeManager(defaults: d)
        #expect(m.preference == .system)
    }
}
