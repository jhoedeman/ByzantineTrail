import Testing
import Foundation
@testable import ByzantineTrail

struct CatalogManifestTests {
    @Test func decodesManifest() throws {
        let json = #"{"catalogVersion":42,"url":"catalog-v42.json","sha256":"abc123"}"#
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: Data(json.utf8))
        #expect(manifest.catalogVersion == 42)
        #expect(manifest.url == "catalog-v42.json")
        #expect(manifest.sha256 == "abc123")
    }

    @Test func toleratesUnknownKeys() throws {
        // Extra keys in the manifest must not break older apps.
        let json = #"{"catalogVersion":7,"url":"c.json","sha256":"x","note":"ignored"}"#
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: Data(json.utf8))
        #expect(manifest.catalogVersion == 7)
    }

    @Test func baseURLEndsWithSlash() {
        // Trailing slash is required for relative manifest.url resolution.
        #expect(RemoteConfig.catalogBaseURL.absoluteString.hasSuffix("/"))
    }
}
