import Testing
import Foundation
@testable import ByzantineTrail

struct PhotoResolverTests {
    let base = URL(string: "https://host.example/")!
    let photo = Photo(id: "p1", thumb: "thumbs/p1.jpg", full: "photos/p1.jpg",
                      caption: nil, credit: nil)

    @Test func thumbUsesBundleWhenPresent() {
        let r = PhotoResolver(photoBaseURL: base, thumbExistsInBundle: { _ in true })
        #expect(r.thumbURL(for: photo).isFileURL)
    }

    @Test func thumbFallsBackToRemote() {
        let r = PhotoResolver(photoBaseURL: base, thumbExistsInBundle: { _ in false })
        #expect(r.thumbURL(for: photo) == URL(string: "https://host.example/thumbs/p1.jpg"))
    }

    @Test func fullAlwaysResolvesAgainstBase() {
        let r = PhotoResolver(photoBaseURL: base, thumbExistsInBundle: { _ in true })
        #expect(r.fullURL(for: photo) == URL(string: "https://host.example/photos/p1.jpg"))
    }
}
