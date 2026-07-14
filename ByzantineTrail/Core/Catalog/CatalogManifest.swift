import Foundation

/// The tiny document at `{catalogBaseURL}/catalog-manifest.json` that drives
/// remote refresh. `url` is the catalog location (relative to the base URL, or
/// absolute); `sha256` is the lowercase-hex digest of the catalog bytes.
struct CatalogManifest: Codable, Equatable {
    let catalogVersion: Int
    let url: String
    let sha256: String
}
