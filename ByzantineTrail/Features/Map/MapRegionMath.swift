import MapKit

/// Pure helpers for fitting the map camera to a set of coordinates.
enum MapRegionMath {
    /// Smallest region centered on the coordinates' midpoint that covers them
    /// all, padded by `paddingFactor`, never tighter than `minimumSpan`.
    /// Returns `nil` for an empty input (caller shows the empty-state overlay).
    static func boundingRegion(
        for coordinates: [CLLocationCoordinate2D],
        minimumSpan: CLLocationDegrees = 0.02,
        paddingFactor: Double = 1.3
    ) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates.dropFirst() {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(minimumSpan, (maxLat - minLat) * paddingFactor),
            longitudeDelta: max(minimumSpan, (maxLon - minLon) * paddingFactor)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
