import Testing
import Foundation
@testable import ByzantineTrail

struct SiteDecodingTests {
    func decodeSite(_ json: String) throws -> Site {
        try JSONDecoder().decode(Site.self, from: Data(json.utf8))
    }

    @Test func decodesFullSite() throws {
        let site = try decodeSite(#"""
        {
          "id": "hagia-sophia", "name": "Hagia Sophia",
          "alternateNames": ["Ayasofya"], "type": "church", "country": "TR",
          "cityId": "istanbul", "coordinate": {"lat": 41.0086, "lon": 28.9802},
          "importance": "major", "addedInVersion": 1,
          "period": {"century": 6, "era": "justinianic"},
          "summary": "s", "photos": [{"id":"p1","thumb":"thumbs/p1.jpg","full":"photos/p1.jpg"}],
          "semanticTags": ["unesco"], "tags": ["mosaics"],
          "links": [{"title":"Official","url":"https://x"}]
        }
        """#)
        #expect(site.id == "hagia-sophia")
        #expect(site.type == .church)
        #expect(site.importance == .major)
        #expect(site.period?.century == 6)
        #expect(site.semanticTags == ["unesco"])
        #expect(site.photos.count == 1)
    }

    @Test func unknownTypeDecodesToOther() throws {
        let site = try decodeSite(#"""
        {"id":"x","name":"X","type":"spaceport","country":"TR",
         "coordinate":{"lat":0,"lon":0},"importance":"minor"}
        """#)
        #expect(site.type == .other)
    }

    @Test func unknownImportanceDecodesToMinor() throws {
        let site = try decodeSite(#"""
        {"id":"x","name":"X","type":"church","country":"TR",
         "coordinate":{"lat":0,"lon":0},"importance":"legendary"}
        """#)
        #expect(site.importance == .minor)
    }

    @Test func unknownKeysAreIgnored() throws {
        let site = try decodeSite(#"""
        {"id":"x","name":"X","type":"church","country":"TR",
         "coordinate":{"lat":0,"lon":0},"importance":"minor",
         "futureField":{"nested":true},"anotherUnknown":42}
        """#)
        #expect(site.id == "x")
    }

    @Test func missingArraysDefaultToEmpty() throws {
        let site = try decodeSite(#"""
        {"id":"x","name":"X","type":"church","country":"TR",
         "coordinate":{"lat":0,"lon":0},"importance":"minor"}
        """#)
        #expect(site.alternateNames.isEmpty)
        #expect(site.photos.isEmpty)
        #expect(site.semanticTags.isEmpty)
        #expect(site.tags.isEmpty)
        #expect(site.links.isEmpty)
    }
}
