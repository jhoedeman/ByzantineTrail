import Testing
import Foundation
@testable import ByzantineTrail

struct VisitedProgressTests {
    func site(_ id: String, country: String = "TR", importance: Importance = .major) -> Site {
        let json = """
        {"id":"\(id)","name":"\(id)","type":"church","country":"\(country)",
         "coordinate":{"lat":0,"lon":0},"importance":"\(importance.rawValue)"}
        """
        return try! JSONDecoder().decode(Site.self, from: Data(json.utf8))
    }

    @Test func zeroVisited() {
        let p = VisitedProgress.compute(visited: [], sites: [site("a"), site("b")])
        #expect(p.visited == 0)
        #expect(p.total == 2)
        #expect(p.fraction == 0)
    }

    @Test func allVisited() {
        let sites = [site("a"), site("b")]
        let p = VisitedProgress.compute(visited: ["a", "b"], sites: sites)
        #expect(p.visited == 2)
        #expect(p.fraction == 1)
    }

    @Test func perCountryTally() {
        let sites = [site("a", country: "TR"), site("b", country: "TR"), site("c", country: "IT")]
        let p = VisitedProgress.compute(visited: ["a"], sites: sites)
        #expect(p.byCountry.first { $0.id == "TR" }?.visited == 1)
        #expect(p.byCountry.first { $0.id == "TR" }?.total == 2)
        #expect(p.byCountry.first { $0.id == "IT" }?.visited == 0)
        #expect(p.byCountry.first { $0.id == "IT" }?.total == 1)
    }

    @Test func perTierTallyInFixedOrder() {
        let sites = [site("a", importance: .major), site("b", importance: .minor)]
        let p = VisitedProgress.compute(visited: ["b"], sites: sites)
        #expect(p.byTier.map(\.id) == ["major", "notable", "minor"])
        #expect(p.byTier.first { $0.id == "minor" }?.visited == 1)
        #expect(p.byTier.first { $0.id == "notable" }?.total == 0)
    }
}
