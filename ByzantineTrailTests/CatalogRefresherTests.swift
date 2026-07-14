import Testing
import Foundation
@testable import ByzantineTrail

struct CatalogRefresherTests {
    // A full, valid catalog JSON at the given version.
    private func catalogJSON(version: Int) -> Data {
        Data(#"""
        {"schemaVersion":2,"catalogVersion":\#(version),"photoBaseURL":"https://x/","cities":[],
         "sites":[{"id":"a","name":"A","type":"church","country":"TR",
         "coordinate":{"lat":0,"lon":0},"importance":"major"}]}
        """#.utf8)
    }

    private let base = URL(string: "https://host.example/cat/")!
    private var manifestURL: URL { base.appendingPathComponent("catalog-manifest.json") }
    private var catalogURL: URL { base.appendingPathComponent("catalog.json") }

    private func manifestJSON(version: Int, url: String, sha256: String) -> Data {
        Data(#"{"catalogVersion":\#(version),"url":"\#(url)","sha256":"\#(sha256)"}"#.utf8)
    }

    // Build a fetch closure that serves canned bytes per URL and records hits.
    private final class Recorder: @unchecked Sendable {
        var fetched: [URL] = []
    }
    private func fetcher(_ responses: [URL: Data], recorder: Recorder) -> CatalogRefresher.Fetch {
        { url in
            recorder.fetched.append(url)
            guard let data = responses[url] else { throw URLError(.fileDoesNotExist) }
            return data
        }
    }
    private func tempCache() -> CatalogCache {
        CatalogCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    @Test func happyPathDownloadsVerifiesCachesAndReturns() async throws {
        let catalog = catalogJSON(version: 2)
        let sha = CatalogHash.sha256Hex(catalog)
        let cache = tempCache()
        let rec = Recorder()
        let responses = [
            manifestURL: manifestJSON(version: 2, url: "catalog.json", sha256: sha),
            catalogURL: catalog,
        ]
        let refresher = CatalogRefresher(baseURL: base, cache: cache, fetch: fetcher(responses, recorder: rec))

        let result = await refresher.refresh(currentVersion: 1)
        #expect(result?.catalogVersion == 2)
        #expect(cache.load() == catalog)          // cached the new bytes
    }

    @Test func versionGateSkipsDownloadWhenNotNewer() async throws {
        let cache = tempCache()
        let rec = Recorder()
        let responses = [manifestURL: manifestJSON(version: 2, url: "catalog.json", sha256: "x")]
        let refresher = CatalogRefresher(baseURL: base, cache: cache, fetch: fetcher(responses, recorder: rec))

        let result = await refresher.refresh(currentVersion: 2)   // equal → skip
        #expect(result == nil)
        #expect(!rec.fetched.contains(catalogURL))                // never downloaded the catalog
        #expect(cache.load() == nil)
    }

    @Test func sha256MismatchAborts() async throws {
        let catalog = catalogJSON(version: 2)
        let cache = tempCache()
        let rec = Recorder()
        let responses = [
            manifestURL: manifestJSON(version: 2, url: "catalog.json", sha256: "deadbeef"),
            catalogURL: catalog,
        ]
        let refresher = CatalogRefresher(baseURL: base, cache: cache, fetch: fetcher(responses, recorder: rec))

        let result = await refresher.refresh(currentVersion: 1)
        #expect(result == nil)
        #expect(cache.load() == nil)              // did not cache unverified bytes
    }

    @Test func versionMismatchBetweenManifestAndCatalogAborts() async throws {
        let catalog = catalogJSON(version: 3)     // decodes to 3
        let sha = CatalogHash.sha256Hex(catalog)
        let cache = tempCache()
        let rec = Recorder()
        let responses = [
            manifestURL: manifestJSON(version: 2, url: "catalog.json", sha256: sha),  // claims 2
            catalogURL: catalog,
        ]
        let refresher = CatalogRefresher(baseURL: base, cache: cache, fetch: fetcher(responses, recorder: rec))

        let result = await refresher.refresh(currentVersion: 1)
        #expect(result == nil)
        #expect(cache.load() == nil)
    }

    @Test func nonHTTPSCatalogURLRejectedBeforeDownload() async throws {
        // An absolute, attacker-supplied http:// catalog URL must be refused by the
        // scheme guard BEFORE any bytes are fetched — even if those bytes would
        // otherwise hash-match and decode. Defends the fetch against a manifest
        // that points off-host or downgrades the transport.
        let catalog = catalogJSON(version: 2)
        let sha = CatalogHash.sha256Hex(catalog)
        let httpURL = URL(string: "http://host.example/cat/catalog.json")!
        let cache = tempCache()
        let rec = Recorder()
        let responses = [
            manifestURL: manifestJSON(version: 2, url: httpURL.absoluteString, sha256: sha),
            httpURL: catalog,   // bytes ARE available + valid, yet must not be used
        ]
        let refresher = CatalogRefresher(baseURL: base, cache: cache, fetch: fetcher(responses, recorder: rec))

        let result = await refresher.refresh(currentVersion: 1)
        #expect(result == nil)
        #expect(!rec.fetched.contains(httpURL))   // guarded before the download
        #expect(cache.load() == nil)
    }

    @Test func offlineFetchThrowsIsSilentNoOp() async throws {
        let cache = tempCache()
        let rec = Recorder()
        let refresher = CatalogRefresher(baseURL: base, cache: cache, fetch: fetcher([:], recorder: rec))

        let result = await refresher.refresh(currentVersion: 1)   // manifest fetch throws
        #expect(result == nil)
        #expect(cache.load() == nil)
    }
}
