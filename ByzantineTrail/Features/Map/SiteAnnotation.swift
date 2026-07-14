import MapKit

/// Map annotation backing one catalog `Site`. Reference type as `MKAnnotation`
/// requires; carries the whole `Site` so the delegate can style the marker by
/// tier and open the detail sheet on selection.
final class SiteAnnotation: NSObject, MKAnnotation {
    let site: Site
    var coordinate: CLLocationCoordinate2D
    var title: String?

    init(site: Site) {
        self.site = site
        self.coordinate = CLLocationCoordinate2D(
            latitude: site.coordinate.lat,
            longitude: site.coordinate.lon
        )
        self.title = site.name
    }

    static func annotations(from sites: [Site]) -> [SiteAnnotation] {
        sites.map(SiteAnnotation.init)
    }
}
