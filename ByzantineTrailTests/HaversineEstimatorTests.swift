import Testing
@testable import ByzantineTrail

struct HaversineEstimatorTests {
    private let estimator = HaversineEstimator()
    private func c(_ lat: Double, _ lon: Double) -> Coordinate {
        Coordinate(lat: lat, lon: lon)
    }

    @Test func modeConstantsAreTheSpecValues() {
        #expect(TravelMode.walking.detourFactor == 1.30)
        #expect(TravelMode.driving.detourFactor == 1.35)
        #expect(TravelMode.transit.detourFactor == 1.40)
        // 4.5 km/h, 30 km/h, 18 km/h expressed as metres per second.
        #expect(abs(TravelMode.walking.metresPerSecond - 1.25) < 0.0001)
        #expect(abs(TravelMode.driving.metresPerSecond - 8.3333) < 0.001)
        #expect(abs(TravelMode.transit.metresPerSecond - 5.0) < 0.0001)
    }

    /// Colosseum to St Peter's: 3439.42 m * 1.30 / 1.25 = 3577.0 s.
    @Test func walkingSecondsForKnownPair() {
        let s = estimator.seconds(from: c(41.8902, 12.4922),
                                  to: c(41.9022, 12.4539), mode: .walking)
        #expect(abs(s - 3_577.0) < 2.0)
    }

    @Test func drivingIsFasterThanWalkingOverTheSamePair() {
        let a = c(41.8902, 12.4922), b = c(41.9022, 12.4539)
        #expect(estimator.seconds(from: a, to: b, mode: .driving)
                < estimator.seconds(from: a, to: b, mode: .walking))
    }

    @Test func zeroSecondsForIdenticalCoordinates() {
        let a = c(41.0086, 28.9802)
        #expect(estimator.seconds(from: a, to: a, mode: .walking) == 0)
    }

    @Test func symmetric() {
        let a = c(41.8902, 12.4922), b = c(41.9022, 12.4539)
        #expect(abs(estimator.seconds(from: a, to: b, mode: .walking)
                    - estimator.seconds(from: b, to: a, mode: .walking)) < 0.001)
    }
}
