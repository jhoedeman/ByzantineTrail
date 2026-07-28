import Testing
import Foundation
@testable import ByzantineTrail

@MainActor
struct SuggestionStoreTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func make(service: any SuggestionSubmitting, seed: [Date] = [])
        -> (SuggestionStore, InMemorySuggestionThrottleStore) {
        let throttle = InMemorySuggestionThrottleStore(seed)
        let store = SuggestionStore(service: service, throttle: throttle, now: { self.now })
        return (store, throttle)
    }

    @Test func validSubmitCallsServiceAndRecordsTimestamp() async {
        let stub = StubSuggestionService()
        let (store, throttle) = make(service: stub)
        let result = await store.submit(name: "Hagia Sophia", location: "Istanbul",
                                        whyInclude: "", linksText: "")
        #expect(result == .success)
        let submitted = await stub.submitted
        #expect(submitted == [SiteSuggestion(name: "Hagia Sophia", location: "Istanbul",
                                             whyInclude: nil, linksText: nil)])
        #expect(throttle.load() == [now])
        #expect(store.remaining == SuggestionRateLimiter.maxPerWindow - 1)
    }

    @Test func invalidSubmitSkipsServiceAndRecordsNothing() async {
        let stub = StubSuggestionService()
        let (store, throttle) = make(service: stub)
        let result = await store.submit(name: "   ", location: "", whyInclude: "", linksText: "")
        #expect(result == .invalid([.nameRequired]))
        let submitted = await stub.submitted
        #expect(submitted.isEmpty)
        #expect(throttle.load().isEmpty)
    }

    @Test func rateLimitedSubmitSkipsService() async {
        let stub = StubSuggestionService()
        let seed = Array(repeating: now.addingTimeInterval(-10),
                         count: SuggestionRateLimiter.maxPerWindow)
        let (store, _) = make(service: stub, seed: seed)
        let result = await store.submit(name: "Valid", location: "", whyInclude: "", linksText: "")
        #expect(result == .rateLimited)
        let submitted = await stub.submitted
        #expect(submitted.isEmpty)
    }

    @Test func failedServiceRecordsNoTimestamp() async {
        let stub = StubSuggestionService(failSubmit: true)
        let (store, throttle) = make(service: stub)
        let result = await store.submit(name: "Valid", location: "", whyInclude: "", linksText: "")
        #expect(result == .failed)
        #expect(throttle.load().isEmpty)
        #expect(store.remaining == SuggestionRateLimiter.maxPerWindow)
    }
}
