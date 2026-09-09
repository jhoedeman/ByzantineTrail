import Testing
import Foundation
@testable import ByzantineTrail

struct CityCentersTests {
    private func site(_ id: String, cityId: String?) -> Site {
        let json = """
        {"id":"\(id)","name":"\(id)","type":"church","country":"TR",
         \(cityId.map { "\"cityId\":\"\($0)\"," } ?? "")
         "coordinate":{"lat":0,"lon":0},"importance":"minor"}
        """
        return try! JSONDecoder().decode(Site.self, from: Data(json.utf8))
    }

    @Test func centerIdsKeepsOnlyCitiesAtOrAboveThreshold() {
        let sites = [
            site("1", cityId: "rome"), site("2", cityId: "rome"), site("3", cityId: "rome"),
            site("4", cityId: "pisa"), site("5", cityId: "pisa"),
            site("6", cityId: "areopoli"),
            site("7", cityId: nil),
        ]
        #expect(CityCenters.centerIds(sites: sites) == ["rome"])
    }

    @Test func centerIdsThresholdIsConfigurable() {
        let sites = [site("1", cityId: "pisa"), site("2", cityId: "pisa")]
        #expect(CityCenters.centerIds(sites: sites, threshold: 2) == ["pisa"])
        #expect(CityCenters.centerIds(sites: sites, threshold: 3).isEmpty)
    }

    @Test func selectedNonCentersReturnsBelowThresholdSelections() {
        let centers: Set<String> = ["rome", "ravenna"]
        let selected: Set<String> = ["rome", "areopoli", "mistra"]
        #expect(CityCenters.selectedNonCenters(selected: selected, centers: centers)
                == ["areopoli", "mistra"])
    }

    @Test func selectedNonCentersEmptyWhenAllSelectedAreCenters() {
        #expect(CityCenters.selectedNonCenters(selected: ["rome"],
                                               centers: ["rome", "ravenna"]).isEmpty)
    }
}
