import Foundation

/// Derives the catalog's "center" cities — those with enough sites to be worth
/// surfacing as ready-made City filter options. Pure and synchronous so it is
/// trivially testable and cheap to recompute from the loaded catalog.
enum CityCenters {
    /// IDs of cities with at least `threshold` sites in `sites` (nil cityIds ignored).
    static func centerIds(sites: [Site], threshold: Int = 3) -> Set<String> {
        var counts: [String: Int] = [:]
        for site in sites {
            if let cityId = site.cityId { counts[cityId, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value >= threshold }.keys)
    }

    /// Selected city IDs that are NOT centers. The picker pins these in a
    /// "Selected" section so a below-threshold town stays visible and removable.
    static func selectedNonCenters(selected: Set<String>,
                                   centers: Set<String>) -> Set<String> {
        selected.subtracting(centers)
    }
}
