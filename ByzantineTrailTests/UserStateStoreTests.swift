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

    @Test func emptyRowIsPruned() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")   // creates the row
        store.toggleFavorite("a")   // back to empty → pruned
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
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
}
