import Foundation

/// Cheap, synchronous travel-time estimation.
///
/// Deliberately NOT async. The solver calls this hundreds of times while
/// ordering stops; making it async would make the solver async, network-bound,
/// and throttle-bound — the change that would eventually force a backend.
/// Real routes come from `RouteResolving` (M7b), which is async and is called
/// only for the handful of legs actually displayed.
protocol TravelEstimating: Sendable {
    func seconds(from: Coordinate, to: Coordinate, mode: TravelMode) -> TimeInterval
}
