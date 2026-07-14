/// In-memory `RatingsServicing` for tests, previews, and the pre-CloudKit app
/// wiring. `seed` models *other users'* ratings so averages look realistic;
/// the caller's own rating is tracked separately and layered on via RatingMath.
actor MockRatingsService: RatingsServicing {
    private var others: [String: RatingSummary]
    private var mine: [String: Int] = [:]

    init(seed: [String: RatingSummary] = [:]) { self.others = seed }

    private func base(_ siteId: String) -> RatingSummary {
        others[siteId] ?? RatingSummary(siteId: siteId, count: 0, total: 0)
    }

    private func combined(_ siteId: String) -> RatingSummary {
        RatingMath.applyDelta(to: base(siteId), old: nil, new: mine[siteId])
    }

    func load(for siteId: String) async throws -> SiteRatingState {
        let s = combined(siteId)
        return SiteRatingState(summary: s.count == 0 ? nil : s, mine: mine[siteId])
    }

    func allSummaries() async throws -> [String: RatingSummary] {
        var out: [String: RatingSummary] = [:]
        for id in Set(others.keys).union(mine.keys) { out[id] = combined(id) }
        return out
    }

    func submit(rating: Int, for siteId: String) async throws -> RatingSummary {
        mine[siteId] = rating
        return combined(siteId)
    }

    func removeRating(for siteId: String) async throws -> RatingSummary {
        mine[siteId] = nil
        return combined(siteId)
    }
}
