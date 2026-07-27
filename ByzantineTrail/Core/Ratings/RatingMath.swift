/// Pure summary arithmetic for public ratings (spec §0.2). `Rating` records are
/// the source of truth; `RatingSummary` is this rebuildable derived cache.
enum RatingMath {
    /// Apply a rating change to a summary. `old == nil` = a brand-new rating;
    /// `new == nil` = a removal. Editing (both non-nil) leaves `count` unchanged.
    static func applyDelta(to summary: RatingSummary, old: Int?, new: Int?) -> RatingSummary {
        var count = summary.count
        var total = summary.total
        if old == nil, let new { count += 1; total += new }          // new rating
        else if let old, new == nil { count -= 1; total -= old }      // removal
        else if let old, let new { total += new - old }               // edit
        return RatingSummary(siteId: summary.siteId,
                             count: max(0, count), total: max(0, total))
    }

    /// Rebuild a summary from the actual rating values (self-heal / reconcile).
    static func recompute(siteId: String, values: [Int]) -> RatingSummary {
        RatingSummary(siteId: siteId, count: values.count, total: values.reduce(0, +))
    }

    /// True when the delta-maintained cache disagrees with a fresh recompute.
    static func needsReconcile(cached: RatingSummary, recomputed: RatingSummary) -> Bool {
        cached.count != recomputed.count || cached.total != recomputed.total
    }
}
