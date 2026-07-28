import Testing
import SwiftData
import Foundation
@testable import ByzantineTrail

@MainActor
struct SyncCoordinatorTests {
    private func userState() throws -> UserStateStore {
        UserStateStore(container: try UserStateStore.makeContainer(inMemory: true))
    }
    private func change(_ site: String, fav: Bool, at t: TimeInterval) -> UserSiteChange {
        UserSiteChange(siteId: site, isFavorite: fav, wantsToVisit: false,
                       visited: false, myRating: nil, updatedAt: Date(timeIntervalSince1970: t))
    }

    @Test func pushesPendingAndClearsIt() async throws {
        let state = try userState()
        state.toggleFavorite("a")
        let provider = StubSyncProvider()
        let coord = SyncCoordinator(provider: provider, userState: state,
                                    tokenStore: InMemorySyncTokenStore())
        await coord.sync()
        let batches = await provider.pushed()
        #expect(batches.count == 1)
        #expect(batches.first?.first?.siteId == "a")
        #expect(state.pendingChanges().isEmpty)   // cleared after successful push
    }

    @Test func pullMergesRemoteAndPersistsToken() async throws {
        let state = try userState()
        let tokenStore = InMemorySyncTokenStore()
        let provider = StubSyncProvider(pullChanges: [change("b", fav: true, at: 100)],
                                        pullToken: SyncToken(raw: "t2"))
        let coord = SyncCoordinator(provider: provider, userState: state, tokenStore: tokenStore)
        await coord.sync()
        #expect(state.favoriteIDs == ["b"])
        #expect(tokenStore.load() == SyncToken(raw: "t2"))
    }

    @Test func pushFailureKeepsPending() async throws {
        let state = try userState()
        state.toggleFavorite("a")
        let provider = StubSyncProvider(failPush: true)
        let coord = SyncCoordinator(provider: provider, userState: state,
                                    tokenStore: InMemorySyncTokenStore())
        await coord.sync()
        #expect(state.pendingChanges().count == 1)   // retained for next sync
    }

    @Test func pullFailureLeavesTokenUnchanged() async throws {
        let state = try userState()
        let tokenStore = InMemorySyncTokenStore(SyncToken(raw: "t0"))
        let provider = StubSyncProvider(failPull: true)
        let coord = SyncCoordinator(provider: provider, userState: state, tokenStore: tokenStore)
        await coord.sync()
        #expect(tokenStore.load() == SyncToken(raw: "t0"))
        #expect(await provider.pullCalls() == [SyncToken(raw: "t0")])
    }
}
