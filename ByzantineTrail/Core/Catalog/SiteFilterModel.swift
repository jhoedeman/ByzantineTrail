import Observation

/// The single `SiteFilter` shared by the Sites list and the Map tab.
/// Search and sort remain list-local; only the multi-select filter is shared.
/// M4/M5 grow `SiteFilter.matches` for per-user flags — because both tabs read
/// this one model, that growth reaches list + map together.
@Observable final class SiteFilterModel {
    var filter = SiteFilter()
    init() {}
}
