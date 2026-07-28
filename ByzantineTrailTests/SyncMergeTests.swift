import Testing
import Foundation
@testable import ByzantineTrail

struct SyncMergeTests {
    private func change(_ fav: Bool, at t: TimeInterval) -> UserSiteChange {
        UserSiteChange(siteId: "s", isFavorite: fav, wantsToVisit: false,
                       visited: false, myRating: nil,
                       updatedAt: Date(timeIntervalSince1970: t))
    }

    @Test func absentLocalAllFalseRemoteSkips() {
        let remote = UserSiteChange(siteId: "s", isFavorite: false, wantsToVisit: false,
                                    visited: false, myRating: nil, updatedAt: Date(timeIntervalSince1970: 5))
        #expect(SyncMerge.resolve(localUpdatedAt: nil, remote: remote) == .skip)
    }

    @Test func absentLocalAnyTrueRemoteApplies() {
        #expect(SyncMerge.resolve(localUpdatedAt: nil, remote: change(true, at: 5)) == .apply)
    }

    @Test func newerRemoteApplies() {
        #expect(SyncMerge.resolve(localUpdatedAt: Date(timeIntervalSince1970: 3),
                                  remote: change(true, at: 5)) == .apply)
    }

    @Test func olderRemoteSkips() {
        #expect(SyncMerge.resolve(localUpdatedAt: Date(timeIntervalSince1970: 9),
                                  remote: change(true, at: 5)) == .skip)
    }

    @Test func equalTimestampSkips() {
        #expect(SyncMerge.resolve(localUpdatedAt: Date(timeIntervalSince1970: 5),
                                  remote: change(true, at: 5)) == .skip)
    }
}
