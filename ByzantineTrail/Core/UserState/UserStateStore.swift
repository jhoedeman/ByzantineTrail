import Foundation
import SwiftData
import Observation

/// Local source of truth for per-site user state (favorites / want / visited).
/// Every mutation routes through the single `apply` choke point — M5 hooks
/// `RemoteSyncProvider.push` there without reshaping this API. SwiftData only in M4.
@MainActor
@Observable
final class UserStateStore {
    // Retain the container: its `mainContext` alone does NOT keep an in-memory
    // ModelContainer alive — a dropped container deallocates on a background
    // thread (SQLite teardown) and crashes SwiftData while the context is in use.
    private let container: ModelContainer
    private let context: ModelContext

    // In-memory projections rebuilt from SwiftData; drive @Observable UI updates.
    private(set) var favoriteIDs: Set<String> = []
    private(set) var wantIDs: Set<String> = []
    private(set) var visitedIDs: Set<String> = []

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        reload()
    }

    /// Build the production (on-disk) or an in-memory (test) container.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: UserSiteState.self, configurations: config)
    }

    // MARK: Reads

    func flags(for siteId: String) -> SiteUserFlags {
        SiteUserFlags(isFavorite: favoriteIDs.contains(siteId),
                      wantsToVisit: wantIDs.contains(siteId),
                      visited: visitedIDs.contains(siteId))
    }

    func snapshot() -> UserStateSnapshot {
        UserStateSnapshot(favorites: favoriteIDs, want: wantIDs, visited: visitedIDs)
    }

    var favoriteCount: Int { favoriteIDs.count }
    var wantCount: Int { wantIDs.count }
    var visitedCount: Int { visitedIDs.count }

    // MARK: Mutations (all via `apply`)

    func toggleFavorite(_ siteId: String) { apply(siteId) { $0.isFavorite.toggle() } }
    func toggleWant(_ siteId: String) { apply(siteId) { $0.wantsToVisit.toggle() } }

    /// Marking visited clears want-to-visit (spec §4). Reversal is direct
    /// manipulation — re-tapping the controls — so nothing is returned.
    func toggleVisited(_ siteId: String) {
        apply(siteId) { row in
            row.visited.toggle()
            if row.visited { row.wantsToVisit = false }
        }
    }

    // MARK: The single write path

    private func apply(_ siteId: String, _ mutate: (UserSiteState) -> Void) {
        let row: UserSiteState
        if let found = existing(siteId) {
            row = found
        } else {
            row = UserSiteState(siteId: siteId)
            context.insert(row)
        }
        mutate(row)
        row.updatedAt = .now
        if row.isEmpty { context.delete(row) }
        try? context.save()
        reload()
    }

    private func existing(_ siteId: String) -> UserSiteState? {
        let descriptor = FetchDescriptor<UserSiteState>(
            predicate: #Predicate { $0.siteId == siteId })
        return try? context.fetch(descriptor).first
    }

    /// Rebuild the in-memory id sets from SwiftData.
    func reload() {
        let rows = (try? context.fetch(FetchDescriptor<UserSiteState>())) ?? []
        favoriteIDs = Set(rows.filter(\.isFavorite).map(\.siteId))
        wantIDs = Set(rows.filter(\.wantsToVisit).map(\.siteId))
        visitedIDs = Set(rows.filter(\.visited).map(\.siteId))
    }
}
