import Testing
@testable import ByzantineTrail

struct StopSequencerExactTests {
    private let estimator = HaversineEstimator()

    private func seq(_ coords: [Coordinate], closed: Bool = false) -> [Int] {
        StopSequencer.sequence(coordinates: coords, mode: .walking,
                               estimator: estimator, closed: closed)
    }

    private func cost(_ order: [Int], _ coords: [Coordinate], closed: Bool = false) -> Double {
        StopSequencer.totalSeconds(order: order, coordinates: coords,
                                   mode: .walking, estimator: estimator, closed: closed)
    }

    // MARK: degenerate inputs

    @Test func emptyInput() { #expect(seq([]) == []) }

    @Test func singleStop() {
        #expect(seq([Coordinate(lat: 0, lon: 0)]) == [0])
    }

    @Test func twoStopsKeepInputOrder() {
        #expect(seq([Coordinate(lat: 0, lon: 0), Coordinate(lat: 1, lon: 0)]) == [0, 1])
    }

    // MARK: the provable optimum

    /// Five collinear points fed in scrambled order. The shortest open path is
    /// simply to walk the line, so the answer is the indices sorted by latitude
    /// (or that sequence reversed — both are optimal).
    @Test func collinearPointsAreWalkedInOrder() {
        let coords = [
            Coordinate(lat: 0.02, lon: 0),  // 0
            Coordinate(lat: 0.00, lon: 0),  // 1
            Coordinate(lat: 0.04, lon: 0),  // 2
            Coordinate(lat: 0.01, lon: 0),  // 3
            Coordinate(lat: 0.03, lon: 0),  // 4
        ]
        let result = seq(coords)
        #expect(result == [1, 3, 0, 4, 2] || result == [2, 4, 0, 3, 1])
    }

    /// The open path never costs more than the input order it replaced.
    @Test func neverWorseThanInputOrder() {
        let coords = [
            Coordinate(lat: 41.8902, lon: 12.4922),
            Coordinate(lat: 41.9022, lon: 12.4539),
            Coordinate(lat: 41.8896, lon: 12.4769),
            Coordinate(lat: 41.9029, lon: 12.4534),
            Coordinate(lat: 41.8986, lon: 12.4768),
            Coordinate(lat: 41.8902, lon: 12.4823),
        ]
        let result = seq(coords)
        #expect(cost(result, coords) <= cost(Array(0..<coords.count), coords) + 0.001)
    }

    @Test func resultIsAlwaysAPermutation() {
        let coords = (0..<10).map { Coordinate(lat: Double($0) * 0.013,
                                               lon: Double(($0 * 7) % 10) * 0.011) }
        #expect(Set(seq(coords)) == Set(0..<10))
        #expect(seq(coords).count == 10)
    }

    /// Eight points in Rome where nearest-neighbour + 2-opt gets stuck 2.2%
    /// above the true optimum. The exact solver must find the optimum, so this
    /// fails if `sequence` ever silently degrades to the heuristic path — the
    /// one regression the rest of this suite cannot detect.
    @Test func exactSolverBeatsWhatTheHeuristicWouldFind() {
        let coords = [
            Coordinate(lat: 41.898, lon: 12.504),
            Coordinate(lat: 41.928, lon: 12.468),
            Coordinate(lat: 41.889, lon: 12.472),
            Coordinate(lat: 41.892, lon: 12.484),
            Coordinate(lat: 41.909, lon: 12.473),
            Coordinate(lat: 41.880, lon: 12.481),
            Coordinate(lat: 41.898, lon: 12.488),
            Coordinate(lat: 41.928, lon: 12.495),
        ]
        let result = seq(coords)
        // Exhaustively verified optimum: 11737.30 s, achieved only by this
        // path (or its reverse). Nearest-neighbour + 2-opt yields 11995.07 s.
        #expect(result == [0, 6, 3, 5, 2, 4, 1, 7] || result == [7, 1, 4, 2, 5, 3, 6, 0])
        #expect(abs(cost(result, coords) - 11_737.30) < 1.0)
        #expect(cost(result, coords) < 11_900.0)   // strictly better than the heuristic's 11995.07
    }

    // MARK: closed tours

    /// Four corners of a square: the optimal cycle is the perimeter, so the
    /// tour cost equals four edge lengths and never a diagonal.
    @Test func closedTourOfASquareIsThePerimeter() {
        let coords = [
            Coordinate(lat: 0.00, lon: 0.00),
            Coordinate(lat: 0.02, lon: 0.02),   // diagonal neighbour of 0
            Coordinate(lat: 0.00, lon: 0.02),
            Coordinate(lat: 0.02, lon: 0.00),
        ]
        let order = seq(coords, closed: true)
        let edge = StopSequencer.totalSeconds(order: [0, 2], coordinates: coords,
                                              mode: .walking, estimator: estimator)
        #expect(abs(cost(order, coords, closed: true) - edge * 4) < 1.0)
    }

    @Test func closedTourStartsAtIndexZero() {
        let coords = (0..<6).map { Coordinate(lat: Double($0) * 0.01,
                                              lon: Double(($0 * 3) % 6) * 0.01) }
        #expect(seq(coords, closed: true).first == 0)
    }

    // MARK: the exact/heuristic boundary

    @Test func exactLimitIsTwelve() {
        #expect(StopSequencer.exactLimit == 12)
    }

    /// Twelve stops is the largest exact case and must stay fast.
    @Test func twelveStopsStillReturnsAPermutation() {
        let coords = (0..<12).map { Coordinate(lat: Double($0) * 0.009,
                                               lon: Double(($0 * 5) % 12) * 0.008) }
        let result = seq(coords)
        #expect(Set(result) == Set(0..<12))
    }
}
