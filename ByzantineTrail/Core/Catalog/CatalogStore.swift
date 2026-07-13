import Foundation

enum CatalogError: Error { case bundleResourceMissing }

@MainActor
@Observable
final class CatalogStore {
    private(set) var catalog: Catalog?
    var sites: [Site] { catalog?.sites ?? [] }

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
