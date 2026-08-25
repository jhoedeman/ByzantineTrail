import Testing
@testable import ByzantineTrail

struct GreatCircleTests {
    private func c(_ lat: Double, _ lon: Double) -> Coordinate {
        Coordinate(lat: lat, lon: lon)
    }

    @Test func zeroDistanceForIdenticalCoordinates() {
        #expect(GreatCircle.metres(from: c(41.0086, 28.9802),
                                   to: c(41.0086, 28.9802)) == 0)
    }

    /// One degree of latitude is R * pi / 180 with R = 6_371_000.
    @Test func oneDegreeOfLatitude() {
        let d = GreatCircle.metres(from: c(0, 0), to: c(1, 0))
        #expect(abs(d - 111_194.93) < 1.0)
    }

    /// At the equator one degree of longitude equals one degree of latitude.
    @Test func oneDegreeOfLongitudeAtEquator() {
        let d = GreatCircle.metres(from: c(0, 0), to: c(0, 1))
        #expect(abs(d - 111_194.93) < 1.0)
    }

    @Test func symmetric() {
        let a = c(41.8902, 12.4922)
        let b = c(41.9022, 12.4539)
        #expect(abs(GreatCircle.metres(from: a, to: b)
                    - GreatCircle.metres(from: b, to: a)) < 0.001)
    }

    /// Colosseum to St Peter's, ~3.44 km.
    @Test func knownRomePair() {
        let d = GreatCircle.metres(from: c(41.8902, 12.4922), to: c(41.9022, 12.4539))
        #expect(abs(d - 3_439.42) < 1.0)
    }

    /// Hagia Sophia to Chora, ~4.24 km.
    @Test func knownIstanbulPair() {
        let d = GreatCircle.metres(from: c(41.0086, 28.9802), to: c(41.0311, 28.9394))
        #expect(abs(d - 4_239.77) < 1.0)
    }

    /// Acropolis to the Rotunda in Thessaloniki, ~303 km.
    @Test func longDistancePair() {
        let d = GreatCircle.metres(from: c(37.9715, 23.7267), to: c(40.6333, 22.9528))
        #expect(abs(d - 303_372.89) < 10.0)
    }
}
