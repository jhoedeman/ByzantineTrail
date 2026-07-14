/// Per-site user flags for one site. Store-free value type so `SiteFilter` can
/// filter by user state without importing the persistence layer.
struct SiteUserFlags: Equatable {
    var isFavorite = false
    var wantsToVisit = false
    var visited = false
}
