/// Multi-select filter over catalog sites. An empty set on any dimension
/// imposes no constraint on that dimension. M4/M5 extend this with
/// favorites/want-to-visit/visited/rated-by-me flags AND-ed into `matches`.
struct SiteFilter: Equatable {
    var types: Set<SiteType> = []
    var countries: Set<String> = []
    var cityIds: Set<String> = []
    var importances: Set<Importance> = []
    var favoritesOnly = false
    var wantOnly = false
    var visitedOnly = false

    var isEmpty: Bool {
        types.isEmpty && countries.isEmpty && cityIds.isEmpty && importances.isEmpty
        && !favoritesOnly && !wantOnly && !visitedOnly
    }

    /// Number of dimensions with at least one selection (drives the badge count).
    var activeCount: Int {
        (types.isEmpty ? 0 : 1)
        + (countries.isEmpty ? 0 : 1)
        + (cityIds.isEmpty ? 0 : 1)
        + (importances.isEmpty ? 0 : 1)
        + (favoritesOnly ? 1 : 0)
        + (wantOnly ? 1 : 0)
        + (visitedOnly ? 1 : 0)
    }

    mutating func clear() { self = SiteFilter() }

    func matches(_ site: Site, flags: SiteUserFlags = SiteUserFlags()) -> Bool {
        (types.isEmpty || types.contains(site.type))
        && (countries.isEmpty || countries.contains(site.country))
        && (cityIds.isEmpty || (site.cityId.map { cityIds.contains($0) } ?? false))
        && (importances.isEmpty || importances.contains(site.importance))
        && (!favoritesOnly || flags.isFavorite)
        && (!wantOnly || flags.wantsToVisit)
        && (!visitedOnly || flags.visited)
    }
}
