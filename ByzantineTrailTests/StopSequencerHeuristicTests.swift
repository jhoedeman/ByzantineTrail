import Testing
@testable import ByzantineTrail

struct StopSequencerHeuristicTests {
    private let estimator = HaversineEstimator()

    private func seq(_ coords: [Coordinate],
                     pinned: Set<Int> = [],
                     closed: Bool = false) -> [Int] {
        StopSequencer.sequence(coordinates: coords, mode: .walking,
                               estimator: estimator,
                               pinnedPositions: pinned, closed: closed)
    }

    private func cost(_ order: [Int], _ coords: [Coordinate]) -> Double {
        StopSequencer.totalSeconds(order: order, coordinates: coords,
                                   mode: .walking, estimator: estimator)
    }

    /// Scrambled collinear points, above the exact limit. The heuristic should
    /// still find the walk-the-line answer on an input this easy.
    private var scrambledLine: [Coordinate] {
        let latitudes = [0.07, 0.00, 0.13, 0.02, 0.11, 0.04, 0.09,
                         0.01, 0.12, 0.05, 0.08, 0.03, 0.10, 0.06]
        return latitudes.map { Coordinate(lat: $0, lon: 0) }
    }

    // MARK: above the exact limit

    @Test func fourteenStopsReturnsAPermutation() {
        let result = seq(scrambledLine)
        #expect(result.count == 14)
        #expect(Set(result) == Set(0..<14))
    }

    @Test func heuristicWalksTheLine() {
        let coords = scrambledLine
        let sorted = (0..<coords.count).sorted { coords[$0].lat < coords[$1].lat }
        let result = seq(coords)
        #expect(result == sorted || result == sorted.reversed())
    }

    @Test func heuristicBeatsTheInputOrder() {
        let coords = scrambledLine
        #expect(cost(seq(coords), coords) < cost(Array(0..<coords.count), coords))
    }

    /// The heuristic must land close to the exact answer on a case both can do.
    @Test func heuristicIsCloseToExactOnATenStopDay() {
        let coords = (0..<10).map {
            Coordinate(lat: 41.89 + Double(($0 * 7) % 10) * 0.004,
                       lon: 12.47 + Double(($0 * 3) % 10) * 0.005)
        }
        let exact = seq(coords)                       // n <= 12, exact path
        let heuristic = seq(coords, pinned: [0])      // forces the heuristic
        #expect(cost(heuristic, coords) <= cost(exact, coords) * 1.25)
    }

    // MARK: pinning

    @Test func pinnedPositionKeepsItsStop() {
        let coords = scrambledLine
        let result = seq(coords, pinned: [3])
        #expect(result[3] == 3)
    }

    @Test func severalPinnedPositionsAllHold() {
        let coords = scrambledLine
        let result = seq(coords, pinned: [0, 5, 13])
        #expect(result[0] == 0)
        #expect(result[5] == 5)
        #expect(result[13] == 13)
        #expect(Set(result) == Set(0..<14))
    }

    @Test func pinningEveryPositionReturnsTheInputOrder() {
        let coords = scrambledLine
        #expect(seq(coords, pinned: Set(0..<14)) == Array(0..<14))
    }

    @Test func pinnedSmallDayStillHonoursPins() {
        let coords = (0..<6).map { Coordinate(lat: Double($0) * 0.01,
                                              lon: Double(($0 * 5) % 6) * 0.01) }
        let result = seq(coords, pinned: [2])
        #expect(result[2] == 2)
        #expect(Set(result) == Set(0..<6))
    }

    @Test func outOfRangePinsAreIgnoredRatherThanCrashing() {
        let coords = scrambledLine
        let result = seq(coords, pinned: [99, -4])
        #expect(Set(result) == Set(0..<14))
    }

    // MARK: closed tours above the limit

    @Test func closedHeuristicTourStartsAtIndexZero() {
        let coords = (0..<14).map { Coordinate(lat: Double($0) * 0.01,
                                               lon: Double(($0 * 5) % 14) * 0.01) }
        #expect(seq(coords, closed: true).first == 0)
    }
}
