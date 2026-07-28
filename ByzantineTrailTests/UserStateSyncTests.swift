import Testing
import SwiftData
import Foundation
@testable import ByzantineTrail

@MainActor
struct UserStateSyncTests {
    func make() throws -> (UserStateStore, ModelContainer) {
        let container = try UserStateStore.makeContainer(inMemory: true)
        return (UserStateStore(container: container), container)
    }

    private func remote(_ site: String, fav: Bool = false, want: Bool = false,
                        visited: Bool = false, at t: TimeInterval) -> UserSiteChange {
        UserSiteChange(siteId: site, isFavorite: fav, wantsToVisit: want,
                       visited: visited, myRating: nil, updatedAt: Date(timeIntervalSince1970: t))
    }

    // MARK: Task 2 — pendingSync + apply(markPending:) + prune

    @Test func flagToggleMarksPending() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.first?.pendingSync == true)
    }

    @Test func setRatingDoesNotMarkPending() throws {
        let (store, container) = try make()
        store.setRating(8, for: "a")
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.count == 1)
        #expect(rows.first?.pendingSync == false)
    }

    @Test func clearedFlagRowIsRetainedWhilePending() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")   // favorite on  (pending)
        store.toggleFavorite("a")   // favorite off (all-false but still pending)
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.count == 1)                 // NOT pruned — cleared state must sync
        #expect(rows.first?.isFavorite == false)
        #expect(rows.first?.pendingSync == true)
    }

    @Test func bareRatingRowStillPrunesOnClear() throws {
        let (store, container) = try make()
        store.setRating(7, for: "a")
        store.setRating(nil, for: "a")           // all-false, never pending
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.isEmpty)                     // M4 behavior preserved
    }

    // MARK: Task 3 — pendingChanges / clearPending / mergeRemote

    @Test func pendingChangesReturnsDirtyRowsWithoutRating() throws {
        let (store, _) = try make()
        store.toggleFavorite("a")
        store.setRating(9, for: "a")     // rating change must not un-dirty or leak into the change
        let pending = store.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending.first?.siteId == "a")
        #expect(pending.first?.isFavorite == true)
        #expect(pending.first?.myRating == nil)
    }

    @Test func clearPendingClearsFlag() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")
        store.clearPending(["a"])
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.first?.pendingSync == false)
        #expect(store.pendingChanges().isEmpty)
    }

    @Test func mergeRemoteAppliesNewerAndKeepsNotPending() throws {
        let (store, container) = try make()
        store.mergeRemote(remote("a", fav: true, at: 100))
        #expect(store.favoriteIDs == ["a"])
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.first?.pendingSync == false)   // received, not dirty
    }

    @Test func mergeRemoteSkipsOlderThanLocal() throws {
        let (store, _) = try make()
        store.toggleVisited("a")                      // local updatedAt ~= now (newer than epoch)
        store.mergeRemote(remote("a", visited: false, at: 1))   // stale remote
        #expect(store.visitedIDs == ["a"])            // local wins
    }

    @Test func mergeRemoteAllFalseClearsAndPrunes() throws {
        let (store, container) = try make()
        store.mergeRemote(remote("a", fav: true, at: 100))
        store.mergeRemote(remote("a", fav: false, at: 200))     // newer all-false = cleared
        #expect(store.favoriteIDs.isEmpty)
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.isEmpty)                          // pruned (empty, not pending)
    }
}
