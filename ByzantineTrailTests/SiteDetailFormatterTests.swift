import Testing
import Foundation
import MapKit
@testable import ByzantineTrail

struct SiteDetailFormatterTests {
    @Test func mapsURLHasCoordinateAndName() {
        let url = SiteDetailFormatter.mapsURL(latitude: 41.0086, longitude: 28.9802, name: "Hagia Sophia")
        #expect(url.host == "maps.apple.com")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains { $0.name == "ll" && $0.value == "41.0086,28.9802" })
        #expect(items.contains { $0.name == "q" && $0.value == "Hagia Sophia" })
    }

    @Test func googleMapsURLHasCoordinateQuery() {
        let url = SiteDetailFormatter.googleMapsURL(latitude: 41.0086, longitude: 28.9802)
        #expect(url.host == "www.google.com")
        #expect(url.absoluteString.hasPrefix("https://www.google.com/maps/search/?"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // Universal cross-platform link: query is the exact coordinate, so the
        // pin lands precisely instead of relying on Google's name geocoding.
        #expect(items.contains { $0.name == "api" && $0.value == "1" })
        #expect(items.contains { $0.name == "query" && $0.value == "41.0086,28.9802" })
    }

    @Test func mapItemCarriesNameAndCoordinate() {
        let item = SiteDetailFormatter.mapItem(latitude: 1, longitude: 2, name: "X")
        #expect(item.name == "X")
        let coord = Self.coordinate(of: item)
        #expect(abs(coord.latitude - 1) < 0.0001)
        #expect(abs(coord.longitude - 2) < 0.0001)
    }

    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return item.location.coordinate
        } else {
            return Self.legacyCoordinate(of: item)
        }
    }

    @available(iOS, introduced: 17.0, deprecated: 26.0)
    static func legacyCoordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        item.placemark.coordinate
    }

    @Test func shareMessageIncludesSummaryWhenPresent() {
        #expect(SiteDetailFormatter.shareMessage(name: "A", summary: "teaser") == "A — teaser")
        #expect(SiteDetailFormatter.shareMessage(name: "A", summary: nil) == "A")
        #expect(SiteDetailFormatter.shareMessage(name: "A", summary: "") == "A")
    }

    @Test func descriptionSplitsParagraphsAndParsesMarkdown() {
        let paras = SiteDetailFormatter.descriptionParagraphs("First **bold**.\n\nSecond line.")
        #expect(paras.count == 2)
        #expect(String(paras[0].characters) == "First bold.")
        #expect(String(paras[1].characters) == "Second line.")
    }

    @Test func descriptionEmptyForNilOrBlank() {
        #expect(SiteDetailFormatter.descriptionParagraphs(nil).isEmpty)
        #expect(SiteDetailFormatter.descriptionParagraphs("   ").isEmpty)
    }

    @MainActor
    @Test func storePhotoResolverResolvesAgainstBase() throws {
        let store = CatalogStore()
        store.setCatalogForTesting(try CatalogStore.decode(Data(#"""
        {"schemaVersion":2,"catalogVersion":1,"photoBaseURL":"https://host/","cities":[],"sites":[]}
        """#.utf8)))
        let photo = Photo(id: "p", thumb: "thumbs/p.jpg", full: "photos/p.jpg", caption: nil, credit: nil)
        #expect(store.photoResolver?.fullURL(for: photo) == URL(string: "https://host/photos/p.jpg"))
    }
}
