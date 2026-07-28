import Foundation

/// Pure conflict resolution for private-state sync (spec §5). Per-record
/// last-writer-wins on `updatedAt`. `localUpdatedAt == nil` means the local row
/// is absent; an all-false remote change for an absent row is nothing to
/// represent, so it is skipped (the "delete" is already the local absence).
enum SyncMerge {
    enum Decision: Equatable { case apply, skip }

    static func resolve(localUpdatedAt: Date?, remote: UserSiteChange) -> Decision {
        let remoteAllFalse = !remote.isFavorite && !remote.wantsToVisit && !remote.visited
        guard let local = localUpdatedAt else {
            return remoteAllFalse ? .skip : .apply
        }
        return remote.updatedAt > local ? .apply : .skip
    }
}
