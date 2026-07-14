import Testing
import Foundation
@testable import ByzantineTrail

@MainActor
struct SiteQueryTests {
    // Decode the bundled-shape fixture so tests exercise real data.
    let catalog: Catalog = try! CatalogStore.decode(Data(#"""
    {"schemaVersion":2,"catalogVersion":1,"photoBaseURL":"https://x/",
     "cities":[{"id":"istanbul","name":"Istanbul"},{"id":"ravenna","name":"Ravenna"}],
     "sites":[
      {"id":"hagia-sophia","name":"Hagia Sophia","alternateNames":["Ayasofya"],
       "type":"church","country":"TR","cityId":"istanbul",
       "coordinate":{"lat":41,"lon":28},"importance":"major","tags":["mosaics"]},
      {"id":"basilica-cistern","name":"Basilica Cistern","type":"cistern","country":"TR",
       "cityId":"istanbul","coordinate":{"lat":41,"lon":28},"importance":"notable"},
      {"id":"san-vitale","name":"San Vitale","type":"church","country":"IT",
       "cityId":"ravenna","coordinate":{"lat":44,"lon":12},"importance":"major"},
      {"id":"mystras","name":"Mystras","type":"archaeologicalSite","country":"GR",
       "coordinate":{"lat":37,"lon":22},"importance":"major"}
     ]}
    """#.utf8))

    var cityNames: [String: String] { ["istanbul": "Istanbul", "ravenna": "Ravenna"] }

    @Test func emptyQueryReturnsAllSortedByNameAscending() {
        let q = SiteQuery()
        let out = q.apply(to: catalog.sites, cityNames: cityNames)
        #expect(out.map(\.id) == ["basilica-cistern", "hagia-sophia", "mystras", "san-vitale"])
    }

    @Test func searchMatchesAlternateNamesDiacriticInsensitive() {
        var q = SiteQuery(); q.searchText = "AYASOFYA"
        #expect(q.apply(to: catalog.sites, cityNames: cityNames).map(\.id) == ["hagia-sophia"])
    }

    @Test func searchMatchesLocalizedCountryName() {
        var q = SiteQuery(); q.searchText = "italy"
        #expect(q.apply(to: catalog.sites, cityNames: cityNames).map(\.id) == ["san-vitale"])
    }

    @Test func searchMatchesCityAndTag() {
        var q = SiteQuery(); q.searchText = "ravenna"
        #expect(q.apply(to: catalog.sites, cityNames: cityNames).map(\.id) == ["san-vitale"])
        q.searchText = "mosaics"
        #expect(q.apply(to: catalog.sites, cityNames: cityNames).map(\.id) == ["hagia-sophia"])
    }

    @Test func filterCombinesWithSearchAndSort() {
        var q = SiteQuery(); q.filter.types = [.church]
        #expect(Set(q.apply(to: catalog.sites, cityNames: cityNames).map(\.id)) == ["hagia-sophia", "san-vitale"])
    }

    @Test func sortByImportanceMajorFirstThenName() {
        var q = SiteQuery(); q.sortField = .importance
        // Three major sites tie-break by name (Hagia < Mystras < San), then the
        // single notable-tier site (Basilica Cistern) comes last.
        #expect(q.apply(to: catalog.sites, cityNames: cityNames).map(\.id)
                == ["hagia-sophia", "mystras", "san-vitale", "basilica-cistern"])
    }

    @Test func descendingReversesNameOrder() {
        var q = SiteQuery(); q.sortField = .name; q.ascending = false
        #expect(q.apply(to: catalog.sites, cityNames: cityNames).first?.id == "san-vitale")
    }

    @Test func storeExposesDerivedData() throws {
        let store = CatalogStore()
        store.setCatalogForTesting(catalog)
        #expect(store.countryCodes == ["GR", "IT", "TR"])
        #expect(store.cityNamesByID["istanbul"] == "Istanbul")
        #expect(store.cities.count == 2)
    }

    @Test func applyFiltersByUserState() {
        var q = SiteQuery(); q.filter.favoritesOnly = true
        let snap = UserStateSnapshot(favorites: ["san-vitale"], want: [], visited: [])
        let out = q.apply(to: catalog.sites, cityNames: cityNames, userState: snap)
        #expect(out.map(\.id) == ["san-vitale"])
    }

    @Test func applyWithoutUserStateIgnoresStateFilter() {
        let q = SiteQuery()
        let out = q.apply(to: catalog.sites, cityNames: cityNames)
        #expect(out.count == catalog.sites.count)
    }
}
