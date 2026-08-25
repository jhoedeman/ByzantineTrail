import Foundation
import Testing
@testable import ByzantineTrail

struct PlannerSiteTests {
    /// Decoding a Site is the only way to build one — it has no memberwise init.
    private func decodeSite() throws -> Site {
        let json = """
        {
          "id": "hagia-sophia",
          "name": "Hagia Sophia",
          "alternateNames": [],
          "type": "church",
          "country": "TR",
          "cityId": "istanbul",
          "coordinate": { "lat": 41.0086, "lon": 28.9802 },
          "importance": "major"
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(Site.self, from: json)
    }

    @Test func adapterCopiesOnlyWhatTheSolverNeeds() throws {
        let site = try decodeSite()
        let planner = PlannerSite(site)
        #expect(planner.id == "hagia-sophia")
        #expect(planner.name == "Hagia Sophia")
        #expect(planner.cityId == "istanbul")
        #expect(planner.type == .church)
        #expect(planner.importance == .major)
        #expect(planner.coordinate.lat == 41.0086)
        #expect(planner.coordinate.lon == 28.9802)
    }

    @Test func memberwiseInitBuildsAFixtureWithoutACatalog() {
        let s = PlannerSite(id: "x", name: "X",
                            coordinate: Coordinate(lat: 1, lon: 2),
                            cityId: nil, type: .column, importance: .minor)
        #expect(s.id == "x")
        #expect(s.cityId == nil)
    }

    @Test func equatableByValue() {
        let a = PlannerSite(id: "x", name: "X", coordinate: Coordinate(lat: 1, lon: 2),
                            cityId: nil, type: .column, importance: .minor)
        let b = PlannerSite(id: "x", name: "X", coordinate: Coordinate(lat: 1, lon: 2),
                            cityId: nil, type: .column, importance: .minor)
        #expect(a == b)
    }
}
