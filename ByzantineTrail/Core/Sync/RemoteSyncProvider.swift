import Foundation

struct UserSiteChange: Equatable, Sendable {
    let siteId: String
    let isFavorite, wantsToVisit, visited: Bool
    let myRating: Int?
    let updatedAt: Date
}

struct SyncToken: Equatable, Sendable { let raw: String }

protocol RemoteSyncProvider: Sendable {
    func push(_ changes: [UserSiteChange]) async throws
    func pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken)
}
