struct RatingSummary: Equatable, Sendable {
    let siteId: String
    let count, total: Int
    var average: Double { count == 0 ? 0 : Double(total) / Double(count) }
}

/// Aggregate + the caller's own rating for one site.
struct SiteRatingState: Equatable, Sendable {
    let summary: RatingSummary?
    let mine: Int?
}

/// Public-ratings backend seam. `Rating` records are source of truth;
/// `RatingSummary` is a rebuildable derived cache (spec §0.2).
protocol RatingsServicing: Sendable {
    /// Aggregate + the caller's own rating (one round-trip; runs the reconcile).
    func load(for siteId: String) async throws -> SiteRatingState
    /// All summaries for list rows + rating sort.
    func allSummaries() async throws -> [String: RatingSummary]
    /// Upsert the caller's rating; returns the updated summary.
    func submit(rating: Int, for siteId: String) async throws -> RatingSummary
    /// Delete the caller's rating; returns the updated summary.
    func removeRating(for siteId: String) async throws -> RatingSummary
}
