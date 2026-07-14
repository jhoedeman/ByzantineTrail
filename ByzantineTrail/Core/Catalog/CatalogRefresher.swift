import Foundation

/// Background catalog refresh (spec §3.2). Pure orchestration over injected
/// seams (`fetch`, `cache`) so it is fully testable without the network.
/// Every failure path returns `nil` — a silent no-op that leaves the current
/// catalog in place (Global Constraint: no blocking alerts, offline-tolerant).
struct CatalogRefresher: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> Data

    let baseURL: URL
    let cache: CatalogCache
    let fetch: Fetch

    init(baseURL: URL, cache: CatalogCache, fetch: @escaping Fetch) {
        self.baseURL = baseURL
        self.cache = cache
        self.fetch = fetch
    }

    /// Fetch the manifest; if it advertises a version newer than `currentVersion`,
    /// download + verify (sha256) + validate (decode & version match) + atomically
    /// cache the catalog. Returns the decoded catalog on success, else `nil`.
    func refresh(currentVersion: Int) async -> Catalog? {
        do {
            let manifestData = try await fetch(baseURL.appendingPathComponent("catalog-manifest.json"))
            let manifest = try JSONDecoder().decode(CatalogManifest.self, from: manifestData)

            // Version gate — skip the download entirely if we're already current.
            guard manifest.catalogVersion > currentVersion else { return nil }

            // Resolve the catalog URL: relative against the base, or absolute.
            // `.absoluteURL` normalizes away the relativeTo/baseURL representation
            // so the result is Equatable/Hashable-compatible with URLs built via
            // `appendingPathComponent` (matters for callers that key requests by URL).
            let catalogURL = URL(string: manifest.url, relativeTo: baseURL)?.absoluteURL
                ?? baseURL.appendingPathComponent(manifest.url)
            let data = try await fetch(catalogURL)

            // Integrity: bytes must match the advertised digest.
            guard CatalogHash.verify(data, matches: manifest.sha256) else { return nil }

            // Validity: must decode AND the decoded version must match the manifest.
            let catalog = try CatalogStore.decode(data)
            guard catalog.catalogVersion == manifest.catalogVersion else { return nil }

            // Only persist bytes that passed every check above.
            try cache.save(data)
            return catalog
        } catch {
            return nil   // silent no-op: keep the current catalog
        }
    }

    /// Live network fetch used by the app; tests inject their own closure.
    static let urlSessionFetch: Fetch = { url in
        try await URLSession.shared.data(from: url).0
    }
}
