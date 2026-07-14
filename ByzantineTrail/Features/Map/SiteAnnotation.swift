import MapKit

/// Map annotation backing one catalog `Site`. Reference type as `MKAnnotation`
/// requires; carries the whole `Site` plus the user's `visited` flag so the
/// delegate can style the marker (tier color + visited badge) and open detail.
final class SiteAnnotation: NSObject, MKAnnotation {
    let site: Site
    /// Mutable so `updateUIView` can refresh a persisted pin when the user
    /// toggles visited while it stays on-screen.
    var visited: Bool
    var coordinate: CLLocationCoordinate2D
    var title: String?

    init(site: Site, visited: Bool = false) {
        self.site = site
        self.visited = visited
        self.coordinate = CLLocationCoordinate2D(latitude: site.coordinate.lat,
                                                 longitude: site.coordinate.lon)
        self.title = site.name
    }

    static func annotations(from sites: [Site], visited: Set<String> = []) -> [SiteAnnotation] {
        sites.map { SiteAnnotation(site: $0, visited: visited.contains($0.id)) }
    }
}
