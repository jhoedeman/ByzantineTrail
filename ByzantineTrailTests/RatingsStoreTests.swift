import Testing
import SwiftData
@testable import ByzantineTrail

@MainActor
struct RatingsStoreTests {
    private func make(seed: [String: RatingSummary] = [:]) throws -> (RatingsStore, UserStateStore) {
        let container = try UserStateStore.makeContainer(inMemory: true)
        let userState = UserStateStore(container: container)
        let store = RatingsStore(service: MockRatingsService(seed: seed), userState: userState)
        return (store, userState)
    }

    @Test func loadAllPopulatesSummaries() async throws {
        let (store, _) = try make(seed: ["a": RatingSummary(siteId: "a", count: 2, total: 16)])
        await store.loadAll()
        #expect(store.summary(for: "a")?.average == 8.0)
    }

    @Test func submitUpdatesSummaryAndLocalMyRating() async throws {
        let (store, userState) = try make()
        await store.submit(8, for: "s")
        #expect(store.summary(for: "s")?.total == 8)
        #expect(userState.myRating(for: "s") == 8)   // dual-write to local cache
    }

    @Test func removeClearsSummaryAndLocalMyRating() async throws {
        let (store, userState) = try make()
        await store.submit(8, for: "s")
        await store.remove(for: "s")
        #expect(userState.myRating(for: "s") == nil)
        #expect(store.summary(for: "s")?.count == 0)
    }

    @Test func refreshReconcilesLocalMyRatingFromCloud() async throws {
        // Service already has a rating for the site (e.g. from another device);
        // local cache is empty until refresh pulls it.
        let (store, userState) = try make()
        await store.submit(6, for: "s")           // now service.mine[s] = 6
        userState.setRating(nil, for: "s")        // simulate local drift
        await store.refresh("s")
        #expect(userState.myRating(for: "s") == 6) // reconciled from cloud
    }
}
