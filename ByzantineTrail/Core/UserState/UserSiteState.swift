import Foundation
import SwiftData

/// Local per-site user state (one row per *touched* site). Rows are created
/// lazily on first flag set and pruned when they carry no state. `myRating` is
/// declared for M5 (ratings) but unused in M4.
@Model
final class UserSiteState {
    @Attribute(.unique) var siteId: String
    var isFavorite: Bool
    var wantsToVisit: Bool
    var visited: Bool
    var myRating: Int?
    var updatedAt: Date

    init(siteId: String, isFavorite: Bool = false, wantsToVisit: Bool = false,
         visited: Bool = false, myRating: Int? = nil, updatedAt: Date = .now) {
        self.siteId = siteId
        self.isFavorite = isFavorite
        self.wantsToVisit = wantsToVisit
        self.visited = visited
        self.myRating = myRating
        self.updatedAt = updatedAt
    }

    /// A row carrying no user state should not persist.
    var isEmpty: Bool { !isFavorite && !wantsToVisit && !visited && myRating == nil }
}
