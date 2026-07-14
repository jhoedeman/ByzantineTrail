import Foundation

/// Persists the newest downloaded catalog in Application Support. `save` is
/// atomic (spec §3.2 step 6): `Data.write(options: .atomic)` writes to a temp
/// file and renames into place, so a crashed/interrupted download never leaves
/// a half-written catalog.
struct CatalogCache: Sendable {
    let fileURL: URL

    /// `directory` is the folder that will hold `catalog.json`.
    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("catalog.json")
    }

    /// The real on-device location: `<Application Support>/Catalog/catalog.json`.
    static func makeDefault() throws -> CatalogCache {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return CatalogCache(directory: base.appendingPathComponent("Catalog", isDirectory: true))
    }

    /// Cached catalog bytes, or `nil` if none are stored yet.
    func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    /// Atomically replace the cached catalog with `data`.
    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
