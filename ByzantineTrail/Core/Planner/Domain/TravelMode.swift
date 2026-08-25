import Foundation

/// How the traveller moves between stops.
///
/// The constants below are the single tuning point for all estimated travel
/// time. Changing them changes every estimate in the app and nothing else.
enum TravelMode: String, Codable, CaseIterable, Sendable {
    case walking, driving, transit

    /// Multiplier applied to straight-line distance to approximate the real
    /// path. Streets are not straight; 1.3 is a standard urban detour factor.
    var detourFactor: Double {
        switch self {
        case .walking: 1.30
        case .driving: 1.35
        case .transit: 1.40
        }
    }

    /// Door-to-door average speed. Driving is an urban figure, not a highway
    /// one; transit includes waiting and the walk to and from stops.
    var metresPerSecond: Double {
        switch self {
        case .walking: 4_500.0 / 3_600.0   // 4.5 km/h
        case .driving: 30_000.0 / 3_600.0  // 30 km/h
        case .transit: 18_000.0 / 3_600.0  // 18 km/h
        }
    }
}
