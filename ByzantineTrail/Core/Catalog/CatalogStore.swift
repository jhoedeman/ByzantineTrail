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

    /// Resolver for the current catalog's photos, or nil if unavailable.
    var photoResolver: PhotoResolver? {
        guard let base = catalog?.photoBaseURL, let url = URL(string: base) else { return nil }
        return PhotoResolver(photoBaseURL: url)
    }

    /// Test seam: inject a decoded catalog without hitting the bundle.
    func setCatalogForTesting(_ catalog: Catalog) {
        self.catalog = catalog
    }

    func loadBundled(bundle: Bundle = .main) throws {
        catalog = try Self.bundledCatalog(bundle: bundle)
    }

    /// Decode the catalog shipped in the app bundle.
    nonisolated static func bundledCatalog(bundle: Bundle = .main) throws -> Catalog {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.bundleResourceMissing
        }
        return try decode(Data(contentsOf: url))
    }

    /// Pure selection (spec §3.2 step 1): use the cached catalog iff it decodes
    /// AND is at least as new as the bundled one; otherwise the bundled one.
    nonisolated static func newestValid(cachedData: Data?, bundled: Catalog) -> Catalog {
        if let data = cachedData,
           let cached = try? decode(data),
           cached.catalogVersion >= bundled.catalogVersion {
            return cached
        }
        return bundled
    }

    /// Load the newest valid catalog at launch (offline-safe, no network).
    func loadNewestValid(cache: CatalogCache, bundle: Bundle = .main) throws {
        catalog = Self.newestValid(cachedData: cache.load(),
                                   bundled: try Self.bundledCatalog(bundle: bundle))
    }

    /// Publish a freshly refreshed catalog (called after CatalogRefresher succeeds).
    func apply(_ catalog: Catalog) {
        self.catalog = catalog
    }

    // nonisolated so tests (and any background caller) can decode without
    // hopping to the main actor.
    nonisolated static func decode(_ data: Data) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: data)
    }
}
