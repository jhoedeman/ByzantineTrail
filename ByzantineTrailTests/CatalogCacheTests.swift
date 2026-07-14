import Testing
import Foundation
@testable import ByzantineTrail

struct CatalogCacheTests {
    private func tempCache() -> CatalogCache {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return CatalogCache(directory: dir)
    }

    @Test func loadReturnsNilWhenAbsent() {
        #expect(tempCache().load() == nil)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let cache = tempCache()
        let bytes = Data("hello".utf8)
        try cache.save(bytes)
        #expect(cache.load() == bytes)
    }

    @Test func saveOverwrites() throws {
        let cache = tempCache()
        try cache.save(Data("one".utf8))
        try cache.save(Data("two".utf8))
        #expect(cache.load() == Data("two".utf8))
    }
}
