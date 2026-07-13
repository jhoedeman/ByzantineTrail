import Testing
import Foundation
@testable import ByzantineTrail

struct SiteFilterTests {
    func site(_ id: String, type: SiteType = .church, country: String = "TR",
              cityId: String? = "istanbul", importance: Importance = .major) -> Site {
        let json = """
        {"id":"\(id)","name":"\(id)","type":"\(type.rawValue)","country":"\(country)",
         \(cityId.map { "\"cityId\":\"\($0)\"," } ?? "")
         "coordinate":{"lat":0,"lon":0},"importance":"\(importance.rawValue)"}
        """
        return try! JSONDecoder().decode(Site.self, from: Data(json.utf8))
    }

    @Test func emptyFilterMatchesEverything() {
        let f = SiteFilter()
        #expect(f.isEmpty)
        #expect(f.activeCount == 0)
        #expect(f.matches(site("a")))
    }

    @Test func typeFilterMatchesOnlySelectedTypes() {
        var f = SiteFilter(); f.types = [.cistern]
        #expect(!f.isEmpty)
        #expect(f.activeCount == 1)
        #expect(f.matches(site("a", type: .cistern)))
        #expect(!f.matches(site("b", type: .church)))
    }

    @Test func countryAndImportanceAreANDed() {
        var f = SiteFilter(); f.countries = ["IT"]; f.importances = [.major]
        #expect(f.activeCount == 2)
        #expect(f.matches(site("a", country: "IT", importance: .major)))
        #expect(!f.matches(site("b", country: "IT", importance: .minor)))
        #expect(!f.matches(site("c", country: "TR", importance: .major)))
    }

    @Test func cityFilterExcludesSitesWithNoCity() {
        var f = SiteFilter(); f.cityIds = ["istanbul"]
        #expect(f.matches(site("a", cityId: "istanbul")))
        #expect(!f.matches(site("b", cityId: nil)))
    }

    @Test func clearResetsAllDimensions() {
        var f = SiteFilter(); f.types = [.church]; f.countries = ["TR"]
        f.clear()
        #expect(f.isEmpty)
    }
}
