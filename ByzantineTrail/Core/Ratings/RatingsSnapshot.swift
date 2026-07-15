/// Immutable rating data for the pure `SiteQuery` sort — community averages plus
/// the user's own ratings. Assembled by the view from RatingsStore + UserStateStore.
struct RatingsSnapshot: Equatable {
    let summaries: [String: RatingSummary]
    let myRatings: [String: Int]

    static let empty = RatingsSnapshot(summaries: [:], myRatings: [:])

    func average(for siteId: String) -> Double? {
        guard let s = summaries[siteId], s.count > 0 else { return nil }
        return s.average
    }
    func mine(for siteId: String) -> Int? { myRatings[siteId] }
}
