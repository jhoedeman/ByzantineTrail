import Foundation

enum CatalogError: Error { case bundleResourceMissing }

@MainActor
@Observable
final class CatalogStore {
    private(set) var catalog: Catalog?
    var sites: [Site] { catalog?.sites ?? [] }

    var cities: [City] { catalog?.cities ?? [] }

    var cityNamesByID: [String: String] {
        Dictionary(cities.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Distinct country codes present in the catalog, sorted.
    var countryCodes: [String] {
        Array(Set(sites.map(\.country))).sorted()
    }

    /// Test seam: inject a decoded catalog without hitting the bundle.
    func setCatalogForTesting(_ catalog: Catalog) {
        self.catalog = catalog
    }

    func loadBundled(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.bundleResourceMissing
        }
        let data = try Data(contentsOf: url)
        catalog = try Self.decode(data)
    }

    // nonisolated so tests (and any background caller) can decode without
    // hopping to the main actor.
    nonisolated static func decode(_ data: Data) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: data)
    }
}
