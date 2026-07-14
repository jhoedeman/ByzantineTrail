import Testing
@testable import ByzantineTrail

struct SiteRowGlyphTests {
    @Test func noGlyphsWhenNoState() {
        #expect(SiteUserFlags().rowGlyphs.isEmpty)
    }

    @Test func oneGlyphPerActiveFlagInOrder() {
        let all = SiteUserFlags(isFavorite: true, wantsToVisit: true, visited: true)
        #expect(all.rowGlyphs.map(\.id) == ["favorite", "want", "visited"])
    }

    @Test func visitedGlyphUsesVisitedRole() {
        let f = SiteUserFlags(isFavorite: false, wantsToVisit: false, visited: true)
        #expect(f.rowGlyphs.count == 1)
        #expect(f.rowGlyphs[0].colorRole == .visited)
        #expect(f.rowGlyphs[0].symbol == "checkmark.circle.fill")
    }
}
