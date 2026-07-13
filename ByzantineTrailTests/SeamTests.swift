import Testing
import Foundation
@testable import ByzantineTrail

struct SeamTests {
    @Test func freeEntitlementUnlocksEverything() {
        let e = FreeEntitlementManager()
        for gate in FeatureGate.allCases {
            #expect(e.isUnlocked(gate))
        }
    }

    @Test func ratingSummaryComputesAverage() {
        let s = RatingSummary(siteId: "x", count: 4, total: 34)
        #expect(s.average == 8.5)
    }

    @Test func ratingSummaryZeroCountIsZeroAverage() {
        let s = RatingSummary(siteId: "x", count: 0, total: 0)
        #expect(s.average == 0)
    }

    @Test func mockSyncRoundTrips() async throws {
        let provider = MockRemoteSyncProvider()
        let change = UserSiteChange(siteId: "hagia-sophia", isFavorite: true,
                                    wantsToVisit: false, visited: false,
                                    myRating: 9, updatedAt: Date(timeIntervalSince1970: 1))
        try await provider.push([change])
        let result = try await provider.pull(since: nil)
        #expect(result.changes == [change])
    }

    @Test func mockRatingsRecordsSubmission() async throws {
        let svc = MockRatingsService()
        try await svc.submit(rating: 7, for: "chora-church")
        let summary = try await svc.summary(for: "chora-church")
        #expect(summary?.total == 7)
        #expect(summary?.count == 1)
    }

    @Test func mockSuggestionRecords() async throws {
        let svc = MockSuggestionService()
        try await svc.submit(SiteSuggestion(name: "New Site", location: nil,
                                            whyInclude: nil, linksText: nil))
        let count = await svc.submitted.count
        #expect(count == 1)
    }
}
