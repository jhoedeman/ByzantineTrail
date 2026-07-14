import Testing
import Foundation
@testable import ByzantineTrail

struct CatalogStoreTests {
    // Decode is tested against an embedded fixture so it is deterministic and
    // does not depend on app-bundle resource copying into the test process.
    // The end-to-end "10 sites load from the app bundle" is verified by the
    // manual launch in Task 6.

    @Test func decodesMultiSiteFixture() throws {
        let catalog = try CatalogStore.decode(sampleCatalogData)
        #expect(catalog.sites.count == 3)
        #expect(catalog.photoBaseURL == "https://x/")
        #expect(catalog.sites.first?.id == "a")
    }

    @Test func decodeRejectsMalformedJSON() {
        #expect(throws: (any Error).self) {
            _ = try CatalogStore.decode(Data("{ not json".utf8))
        }
    }

    @Test func decodeToleratesUnknownTypeInCatalog() throws {
        let json = #"""
        {"schemaVersion":2,"catalogVersion":9,"photoBaseURL":"https://x/","cities":[],
         "sites":[{"id":"a","name":"A","type":"unknownType","country":"TR",
         "coordinate":{"lat":0,"lon":0},"importance":"minor"}]}
        """#
        let catalog = try CatalogStore.decode(Data(json.utf8))
        #expect(catalog.sites.first?.type == .other)
    }

    // --- newest-valid selection (M1-remote Task 5) ---

    private func catalog(version: Int) -> Catalog {
        let json = #"""
        {"schemaVersion":2,"catalogVersion":\#(version),"photoBaseURL":"https://x/","cities":[],
         "sites":[{"id":"a","name":"A","type":"church","country":"TR",
         "coordinate":{"lat":0,"lon":0},"importance":"major"}]}
        """#
        return try! CatalogStore.decode(Data(json.utf8))
    }
    private func catalogData(version: Int) -> Data {
        Data(#"""
        {"schemaVersion":2,"catalogVersion":\#(version),"photoBaseURL":"https://x/","cities":[],"sites":[]}
        """#.utf8)
    }

    @Test func newestValidPrefersNewerCache() {
        let picked = CatalogStore.newestValid(cachedData: catalogData(version: 5),
                                              bundled: catalog(version: 3))
        #expect(picked.catalogVersion == 5)
    }

    @Test func newestValidPrefersBundledWhenCacheOlder() {
        let picked = CatalogStore.newestValid(cachedData: catalogData(version: 2),
                                              bundled: catalog(version: 3))
        #expect(picked.catalogVersion == 3)
    }

    @Test func newestValidUsesBundledWhenNoCache() {
        let picked = CatalogStore.newestValid(cachedData: nil, bundled: catalog(version: 3))
        #expect(picked.catalogVersion == 3)
    }

    @Test func newestValidFallsBackWhenCacheCorrupt() {
        let picked = CatalogStore.newestValid(cachedData: Data("{garbage".utf8),
                                              bundled: catalog(version: 3))
        #expect(picked.catalogVersion == 3)
    }
}

private let sampleCatalogData = Data(#"""
{"schemaVersion":2,"catalogVersion":1,"photoBaseURL":"https://x/","cities":[],
 "sites":[
  {"id":"a","name":"A","type":"church","country":"TR","coordinate":{"lat":0,"lon":0},"importance":"major"},
  {"id":"b","name":"B","type":"cistern","country":"IT","coordinate":{"lat":1,"lon":1},"importance":"minor"},
  {"id":"c","name":"C","type":"museum","country":"GR","coordinate":{"lat":2,"lon":2},"importance":"notable"}
 ]}
"""#.utf8)
