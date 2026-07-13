import Foundation
@testable import ByzantineTrail

actor MockRemoteSyncProvider: RemoteSyncProvider {
    private(set) var pushed: [UserSiteChange] = []
    func push(_ changes: [UserSiteChange]) async throws { pushed.append(contentsOf: changes) }
    func pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken) {
        (pushed, SyncToken(raw: "mock"))
    }
}

actor MockRatingsService: RatingsServicing {
    private var summaries: [String: RatingSummary] = [:]
    func summary(for siteId: String) async throws -> RatingSummary? { summaries[siteId] }
    func submit(rating: Int, for siteId: String) async throws {
        let existing = summaries[siteId]
        summaries[siteId] = RatingSummary(
            siteId: siteId,
            count: (existing?.count ?? 0) + 1,
            total: (existing?.total ?? 0) + rating
        )
    }
}

actor MockSuggestionService: SuggestionSubmitting {
    private(set) var submitted: [SiteSuggestion] = []
    func submit(_ suggestion: SiteSuggestion) async throws { submitted.append(suggestion) }
}
