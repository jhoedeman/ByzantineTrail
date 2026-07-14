import Foundation
@testable import ByzantineTrail

actor MockRemoteSyncProvider: RemoteSyncProvider {
    private(set) var pushed: [UserSiteChange] = []
    func push(_ changes: [UserSiteChange]) async throws { pushed.append(contentsOf: changes) }
    func pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken) {
        (pushed, SyncToken(raw: "mock"))
    }
}

actor MockSuggestionService: SuggestionSubmitting {
    private(set) var submitted: [SiteSuggestion] = []
    func submit(_ suggestion: SiteSuggestion) async throws { submitted.append(suggestion) }
}
