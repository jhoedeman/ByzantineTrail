import Testing
import SwiftUI
@testable import ByzantineTrail

struct SiteDisplayTests {
    @Test func importanceIsCaseIterableInTierOrder() {
        #expect(Importance.allCases == [.major, .notable, .minor])
    }

    @Test func importanceRankOrders() {
        #expect(Importance.major.rank < Importance.notable.rank)
        #expect(Importance.notable.rank < Importance.minor.rank)
    }

    @Test func siteTypeLabelsAreHumanReadable() {
        #expect(SiteType.church.displayLabel == "Church")
        #expect(SiteType.cityWalls.displayLabel == "City Walls")
        #expect(SiteType.other.displayLabel == "Site")
    }

    @Test func siteTypeHasIconForEveryCase() {
        for type in SiteType.allCases {
            #expect(!type.iconName.isEmpty)
        }
    }

    @Test func countryNameLocalizesValidCodeAndPassesThroughInvalid() {
        #expect(CountryName.localized("TR") != "TR")   // resolves to a country name
        #expect(CountryName.localized("ZZ") == "ZZ")   // invalid code passes through
    }

    @Test func tierColorMapsToThemeTokens() {
        let theme = Theme.chrysos(.dark)
        #expect(Importance.major.tierColor(theme) == theme.tierMajor)
        #expect(Importance.notable.tierColor(theme) == theme.tierNotable)
        #expect(Importance.minor.tierColor(theme) == theme.tierMinor)
    }
}
