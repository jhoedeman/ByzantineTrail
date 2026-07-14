import Testing
import Foundation
import MapKit
@testable import ByzantineTrail

struct SiteAnnotationTests {
    // Site declares a custom init(from:) → no memberwise init; decode JSON.
    private func makeSite(id: String, name: String, lat: Double, lon: Double) -> Site {
        let json = """
        {"id":"\(id)","name":"\(name)","type":"other","country":"TR",
         "coordinate":{"lat":\(lat),"lon":\(lon)},"importance":"major"}
        """
        return try! JSONDecoder().decode(Site.self, from: Data(json.utf8))
    }

    @Test func mapsSiteToAnnotation() {
        let site = makeSite(id: "s1", name: "Hagia Sophia", lat: 41.0086, lon: 28.9802)
        let ann = SiteAnnotation(site: site)
        #expect(ann.title == "Hagia Sophia")
        #expect(abs(ann.coordinate.latitude - 41.0086) < 0.0001)
        #expect(abs(ann.coordinate.longitude - 28.9802) < 0.0001)
        #expect(ann.site.id == "s1")
    }

    @Test func builderMapsAllSites() {
        let sites = [
            makeSite(id: "a", name: "A", lat: 41, lon: 28),
            makeSite(id: "b", name: "B", lat: 44, lon: 12),
        ]
        let anns = SiteAnnotation.annotations(from: sites)
        #expect(anns.count == 2)
        #expect(Set(anns.map(\.site.id)) == ["a", "b"])
    }

    @Test func annotationsCarryVisitedFlag() {
        let sites = [
            makeSite(id: "a", name: "A", lat: 41, lon: 28),
            makeSite(id: "b", name: "B", lat: 44, lon: 12),
        ]
        let anns = SiteAnnotation.annotations(from: sites, visited: ["a"])
        #expect(anns.first { $0.site.id == "a" }?.visited == true)
        #expect(anns.first { $0.site.id == "b" }?.visited == false)
    }
}
