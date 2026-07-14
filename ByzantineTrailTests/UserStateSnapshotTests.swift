import Testing
@testable import ByzantineTrail

struct UserStateSnapshotTests {
    @Test func emptySnapshotYieldsAllFalseFlags() {
        let flags = UserStateSnapshot.empty.flags(for: "any")
        #expect(flags == SiteUserFlags())
    }

    @Test func flagsReflectMembership() {
        let snap = UserStateSnapshot(favorites: ["a"], want: ["a", "b"], visited: ["c"])
        #expect(snap.flags(for: "a") == SiteUserFlags(isFavorite: true, wantsToVisit: true, visited: false))
        #expect(snap.flags(for: "b") == SiteUserFlags(isFavorite: false, wantsToVisit: true, visited: false))
        #expect(snap.flags(for: "c") == SiteUserFlags(isFavorite: false, wantsToVisit: false, visited: true))
        #expect(snap.flags(for: "z") == SiteUserFlags())
    }
}
