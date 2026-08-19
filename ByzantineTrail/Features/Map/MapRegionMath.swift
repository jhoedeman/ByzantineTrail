import MapKit

/// Pure helpers for fitting the map camera to a set of coordinates.
enum MapRegionMath {
    /// Default camera on first appearance: an Aegean-focused frame with Greece
    /// near the center, reaching Italy in the west and Anatolia in the east.
    /// The catalog also holds sites in the Americas/NW Europe, but fitting all
    /// of them zooms out to the mid-Atlantic (the exact complaint) — the
    /// outliers stay reachable via search and the country/city filters.
    /// On a portrait phone `regionThatFits` expands the latitude span to match
    /// the aspect ratio, so the longitude span is what actually frames this.
    static let initialFocusRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.5, longitude: 23.5),
        span: MKCoordinateSpan(latitudeDelta: 15.0, longitudeDelta: 27.0)
    )

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
