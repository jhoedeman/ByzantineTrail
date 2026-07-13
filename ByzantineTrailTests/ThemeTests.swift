import Testing
import SwiftUI
@testable import ByzantineTrail

struct ThemeTests {
    // Verifies the semantic token → Chrysos hex mapping from COLOR_SYSTEM.md §2.
    @Test func darkAccentPrimaryIsGold400() {
        #expect(Theme.hexes(.dark)["accentPrimary"] == Palette.gold400)
    }

    @Test func lightAccentPrimaryIsGold700() {
        #expect(Theme.hexes(.light)["accentPrimary"] == Palette.gold700)
    }

    @Test func darkBackgroundIsStone950() {
        #expect(Theme.hexes(.dark)["bgApp"] == Palette.stone950)
    }

    @Test func visitedCheckDiffersByScheme() {
        #expect(Theme.hexes(.light)["visitedCheck"] == Palette.jadeLight)
        #expect(Theme.hexes(.dark)["visitedCheck"] == Palette.jadeDark)
    }

    @Test func themeExposesColorForEveryToken() {
        let t = Theme.chrysos(.dark)
        // Compile-time proof every token resolves to a Color; spot-check one.
        #expect(t.accentPrimary == Color(hex: Palette.gold400))
    }

    @Test func preferenceMapsToColorScheme() {
        #expect(ThemePreference.system.colorScheme == nil)
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
    }
}
