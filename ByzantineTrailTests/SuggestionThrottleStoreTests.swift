import Testing
import Foundation
@testable import ByzantineTrail

struct SuggestionThrottleStoreTests {
    @Test func userDefaultsRoundTrips() {
        let defaults = UserDefaults(suiteName: "m5c.throttle.test")!
        defaults.removePersistentDomain(forName: "m5c.throttle.test")
        let store = UserDefaultsSuggestionThrottleStore(defaults: defaults)
        #expect(store.load().isEmpty)
        let ts = [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)]
        store.save(ts)
        #expect(store.load() == ts)
    }

    @Test func inMemoryRoundTrips() {
        let store = InMemorySuggestionThrottleStore()
        #expect(store.load().isEmpty)
        let ts = [Date(timeIntervalSince1970: 1)]
        store.save(ts)
        #expect(store.load() == ts)
    }
}
