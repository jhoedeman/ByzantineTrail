import Foundation

/// The only view of a site the solver needs.
///
/// Keeping this separate from `Site` means the domain never depends on photos,
/// links, descriptions, or decoding, and tests can build fixtures in one line
/// instead of assembling catalog JSON.
struct PlannerSite: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let coordinate: Coordinate
    let cityId: String?
    let type: SiteType
    let importance: Importance

    init(id: String, name: String, coordinate: Coordinate,
         cityId: String?, type: SiteType, importance: Importance) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.cityId = cityId
        self.type = type
        self.importance = importance
    }

    init(_ site: Site) {
        self.init(id: site.id, name: site.name, coordinate: site.coordinate,
                  cityId: site.cityId, type: site.type, importance: site.importance)
    }
}
