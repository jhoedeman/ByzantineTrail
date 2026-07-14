/// Immutable snapshot of user state across all touched sites, as three id sets.
/// `SiteQuery` takes one of these so filtering stays a pure transform.
struct UserStateSnapshot: Equatable {
    let favorites: Set<String>
    let want: Set<String>
    let visited: Set<String>

    static let empty = UserStateSnapshot(favorites: [], want: [], visited: [])

    func flags(for siteId: String) -> SiteUserFlags {
        SiteUserFlags(isFavorite: favorites.contains(siteId),
                      wantsToVisit: want.contains(siteId),
                      visited: visited.contains(siteId))
    }
}
