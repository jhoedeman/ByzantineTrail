import Foundation

/// Great-circle distance between catalog coordinates.
///
/// The planner's solver needs hundreds of pairwise distances per generated day,
/// so this must stay allocation-free and synchronous. Real street routes come
/// from `RouteResolving` (M7b) and only for the legs actually displayed.
enum GreatCircle {
    /// Mean Earth radius. Distances are accurate to ~0.5% at planner scale.
    static let earthRadiusMetres = 6_371_000.0

    static func metres(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180

        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMetres * asin(min(1, h.squareRoot()))
    }
}
