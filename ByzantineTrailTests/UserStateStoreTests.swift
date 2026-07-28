import Testing
import SwiftData
@testable import ByzantineTrail

@MainActor
struct UserStateStoreTests {
    private func make() throws -> (UserStateStore, ModelContainer) {
        let container = try UserStateStore.makeContainer(inMemory: true)
        return (UserStateStore(container: container), container)
    }

    @Test func toggleFavoriteAddsAndRemoves() throws {
        let (store, _) = try make()
        store.toggleFavorite("a")
        #expect(store.favoriteIDs == ["a"])
        #expect(store.flags(for: "a").isFavorite)
        store.toggleFavorite("a")
        #expect(store.favoriteIDs.isEmpty)
    }

    @Test func markingVisitedClearsWant() throws {
        let (store, _) = try make()
        store.toggleWant("a")
        #expect(store.wantIDs == ["a"])
        store.toggleVisited("a")
        #expect(store.visitedIDs == ["a"])
        #expect(store.wantIDs.isEmpty)   // want cleared by visiting
    }

    @Test func emptyRowIsPrunedOnceSynced() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")   // creates the row (pending)
        store.toggleFavorite("a")   // back to all-false, but still pending → retained (M5b)
        var rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.count == 1)    // cleared state must survive to sync the clear
        store.clearPending(["a"])   // clear pushed → now truly empty → pruned
        rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.isEmpty)
    }

    @Test func snapshotReflectsAllSets() throws {
        let (store, _) = try make()
        store.toggleFavorite("a"); store.toggleWant("b"); store.toggleVisited("c")
        let snap = store.snapshot()
        #expect(snap.favorites == ["a"])
        #expect(snap.want == ["b"])
        #expect(snap.visited == ["c"])
    }

    @Test func stateSurvivesReloadOnSameContainer() throws {
        let container = try UserStateStore.makeContainer(inMemory: true)
        let store1 = UserStateStore(container: container)
        store1.toggleVisited("a")
        let store2 = UserStateStore(container: container)
        #expect(store2.visitedIDs == ["a"])
    }

    @Test func counts() throws {
        let (store, _) = try make()
        store.toggleFavorite("a"); store.toggleFavorite("b"); store.toggleVisited("a")
        #expect(store.favoriteCount == 2)
        #expect(store.visitedCount == 1)
        #expect(store.wantCount == 0)
    }

    @Test func setRatingStoresAndClears() throws {
        let (store, _) = try make()
        store.setRating(8, for: "s")
        #expect(store.myRating(for: "s") == 8)
        #expect(store.myRatings == ["s": 8])
        store.setRating(nil, for: "s")
        #expect(store.myRating(for: "s") == nil)
        #expect(store.myRatings.isEmpty)
    }

    @Test func clearingRatingOnBareRowPrunesIt() throws {
        let (store, container) = try make()
        store.setRating(7, for: "s")   // creates a row with only a rating
        store.setRating(nil, for: "s") // row now empty → pruned
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.isEmpty)
    }

    @Test func ratingCoexistsWithFlags() throws {
        let (store, _) = try make()
        store.toggleFavorite("s")
        store.setRating(9, for: "s")
        #expect(store.favoriteIDs == ["s"])
        #expect(store.myRating(for: "s") == 9)
    }
}
