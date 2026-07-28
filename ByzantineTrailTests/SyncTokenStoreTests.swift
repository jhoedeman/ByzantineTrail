import Testing
import Foundation
@testable import ByzantineTrail

struct SyncTokenStoreTests {
    @Test func userDefaultsRoundTrips() {
        let defaults = UserDefaults(suiteName: "m5b.token.test")!
        defaults.removePersistentDomain(forName: "m5b.token.test")
        let store = UserDefaultsSyncTokenStore(defaults: defaults)
        #expect(store.load() == nil)
        store.save(SyncToken(raw: "2026-07-27T00:00:00Z"))
        #expect(store.load() == SyncToken(raw: "2026-07-27T00:00:00Z"))
        store.save(nil)
        #expect(store.load() == nil)
    }

    @Test func inMemoryRoundTrips() {
        let store = InMemorySyncTokenStore()
        #expect(store.load() == nil)
        store.save(SyncToken(raw: "t1"))
        #expect(store.load() == SyncToken(raw: "t1"))
    }
}
