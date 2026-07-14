import Testing
import MapKit
@testable import ByzantineTrail

struct MapRegionMathTests {
    @Test func emptyReturnsNil() {
        #expect(MapRegionMath.boundingRegion(for: []) == nil)
    }

    @Test func singleCoordinateCentersWithMinimumSpan() throws {
        let c = CLLocationCoordinate2D(latitude: 41.0086, longitude: 28.9802) // Hagia Sophia
        let region = try #require(MapRegionMath.boundingRegion(for: [c]))
        #expect(abs(region.center.latitude - c.latitude) < 0.0001)
        #expect(abs(region.center.longitude - c.longitude) < 0.0001)
        #expect(region.span.latitudeDelta >= 0.02)
        #expect(region.span.longitudeDelta >= 0.02)
    }

    @Test func multipleCoordinatesCoverExtremesWithPadding() throws {
        let coords = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 28.0),
            CLLocationCoordinate2D(latitude: 44.0, longitude: 12.0), // Ravenna-ish
        ]
        let region = try #require(MapRegionMath.boundingRegion(for: coords))
        #expect(abs(region.center.latitude - 42.5) < 0.0001)
        #expect(abs(region.center.longitude - 20.0) < 0.0001)
        // raw lat span = 3.0, padded by 1.3 → ~3.9, must exceed the raw extent
        #expect(region.span.latitudeDelta > 3.0)
        #expect(region.span.longitudeDelta > 16.0)
    }
}
