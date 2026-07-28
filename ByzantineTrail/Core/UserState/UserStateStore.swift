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
    private(set) var myRatings: [String: Int] = [:]

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        reload()
    }

    /// Build the production (on-disk) or an in-memory (test) container.
    ///
    /// `cloudKitDatabase: .none` keeps this LOCAL store off CloudKit even once the
    /// iCloud entitlement is present (M5a public ratings use the CloudKit *public*
    /// DB directly via CKContainer, not SwiftData). Without this, SwiftData's
    /// `.automatic` default would try to mirror `UserSiteState` to a private
    /// CloudKit DB and fail (CloudKit requires every attribute optional/defaulted).
    /// Private user-state sync is deferred to M5b.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory,
                                        cloudKitDatabase: .none)
        return try ModelContainer(for: UserSiteState.self, configurations: config)
    }

    // MARK: Reads

    func flags(for siteId: String) -> SiteUserFlags {
        SiteUserFlags(isFavorite: favoriteIDs.contains(siteId),
                      wantsToVisit: wantIDs.contains(siteId),
                      visited: visitedIDs.contains(siteId))
    }

    func myRating(for siteId: String) -> Int? { myRatings[siteId] }

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

    /// The user's own rating for a site. Not synced by M5b (the public Rating is
    /// the cross-device source of truth), so it does not mark the row pending or
    /// bump `updatedAt` (which keys flag last-writer-wins).
    func setRating(_ value: Int?, for siteId: String) {
        apply(siteId, markPending: false) { $0.myRating = value }
    }

    // MARK: The single write path

    private func apply(_ siteId: String, markPending: Bool = true,
                       _ mutate: (UserSiteState) -> Void) {
        let row: UserSiteState
        if let found = existing(siteId) {
            row = found
        } else {
            row = UserSiteState(siteId: siteId)
            context.insert(row)
        }
        mutate(row)
        if markPending {
            row.updatedAt = .now
            row.pendingSync = true
        }
        if row.isEmpty && !row.pendingSync { context.delete(row) }
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
        myRatings = Dictionary(uniqueKeysWithValues:
            rows.compactMap { row in row.myRating.map { (row.siteId, $0) } })
    }

    // MARK: Sync (M5b)

    /// Rows changed locally and not yet pushed, as wire changes. `myRating` is
    /// never synced by M5b, so it is always nil here.
    func pendingChanges() -> [UserSiteChange] {
        let rows = (try? context.fetch(FetchDescriptor<UserSiteState>())) ?? []
        return rows.filter(\.pendingSync).map {
            UserSiteChange(siteId: $0.siteId, isFavorite: $0.isFavorite,
                           wantsToVisit: $0.wantsToVisit, visited: $0.visited,
                           myRating: nil, updatedAt: $0.updatedAt)
        }
    }

    /// Clear the pending flag on pushed rows; prune any that are now empty.
    func clearPending(_ siteIds: [String]) {
        let set = Set(siteIds)
        let rows = (try? context.fetch(FetchDescriptor<UserSiteState>())) ?? []
        for row in rows where set.contains(row.siteId) { row.pendingSync = false }
        for row in rows where row.isEmpty && !row.pendingSync { context.delete(row) }
        try? context.save()
        reload()
    }

    /// Apply a batch of remote changes via last-writer-wins, then persist once.
    func mergeRemote(_ changes: [UserSiteChange]) {
        for change in changes { mergeOne(change) }
        for row in (try? context.fetch(FetchDescriptor<UserSiteState>())) ?? []
        where row.isEmpty && !row.pendingSync { context.delete(row) }
        try? context.save()
        reload()
    }

    func mergeRemote(_ change: UserSiteChange) { mergeRemote([change]) }

    /// LWW-apply a single remote change in-place (no save/reload — caller batches).
    private func mergeOne(_ change: UserSiteChange) {
        let local = existing(change.siteId)
        guard SyncMerge.resolve(localUpdatedAt: local?.updatedAt, remote: change) == .apply
        else { return }
        let row: UserSiteState
        if let local { row = local } else {
            row = UserSiteState(siteId: change.siteId)
            context.insert(row)
        }
        row.isFavorite = change.isFavorite
        row.wantsToVisit = change.wantsToVisit
        row.visited = change.visited
        row.updatedAt = change.updatedAt
        row.pendingSync = false   // remote won; drop any superseded local pending
    }
}
