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
}

private let sampleCatalogData = Data(#"""
{"schemaVersion":2,"catalogVersion":1,"photoBaseURL":"https://x/","cities":[],
 "sites":[
  {"id":"a","name":"A","type":"church","country":"TR","coordinate":{"lat":0,"lon":0},"importance":"major"},
  {"id":"b","name":"B","type":"cistern","country":"IT","coordinate":{"lat":1,"lon":1},"importance":"minor"},
  {"id":"c","name":"C","type":"museum","country":"GR","coordinate":{"lat":2,"lon":2},"importance":"notable"}
 ]}
"""#.utf8)
