import Foundation

/// The M7a estimator: great-circle distance, inflated by a mode detour factor,
/// divided by a mode speed. Free, offline, and unlimited.
struct HaversineEstimator: TravelEstimating {
    init() {}

    func seconds(from a: Coordinate, to b: Coordinate, mode: TravelMode) -> TimeInterval {
        let straight = GreatCircle.metres(from: a, to: b)
        return straight * mode.detourFactor / mode.metresPerSecond
    }
}
