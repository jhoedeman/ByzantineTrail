import Testing
import Foundation
@testable import ByzantineTrail

struct SiteFilterModelTests {
    // Sites are built by decoding JSON — Site declares a custom init(from:),
    // so there is NO memberwise init. This mirrors SiteFilterTests' helper.
    private func site(_ id: String, type: SiteType = .church) -> Site {
        let json = """
        {"id":"\(id)","name":"\(id)","type":"\(type.rawValue)","country":"TR",
         "coordinate":{"lat":0,"lon":0},"importance":"major"}
        """
        return try! JSONDecoder().decode(Site.self, from: Data(json.utf8))
    }

    @Test func startsEmpty() {
        let model = SiteFilterModel()
        #expect(model.filter.isEmpty)
        #expect(model.filter.activeCount == 0)
    }

    @Test func holdsMutatedFilter() {
        let model = SiteFilterModel()
        model.filter.types = [.church]
        #expect(!model.filter.isEmpty)
        #expect(model.filter.activeCount == 1)
        #expect(model.filter.matches(site("a", type: .church)))
        #expect(!model.filter.matches(site("b", type: .cistern)))
    }
}
