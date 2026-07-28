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

/// Controllable SuggestionSubmitting for store tests: captures submissions and
/// can force a failure. (The plain `MockSuggestionService` above always succeeds.)
actor StubSuggestionService: SuggestionSubmitting {
    private let failSubmit: Bool
    private(set) var submitted: [SiteSuggestion] = []
    struct StubError: Error {}
    init(failSubmit: Bool = false) { self.failSubmit = failSubmit }
    func submit(_ suggestion: SiteSuggestion) async throws {
        if failSubmit { throw StubError() }
        submitted.append(suggestion)
    }
}

/// Controllable RemoteSyncProvider for coordinator tests: seed the pull result,
/// capture pushes, and force failures.
actor StubSyncProvider: RemoteSyncProvider {
    private let pullChanges: [UserSiteChange]
    private let pullToken: SyncToken
    private let failPush: Bool
    private let failPull: Bool
    private var pushedBatches: [[UserSiteChange]] = []
    private var pullTokens: [SyncToken?] = []

    init(pullChanges: [UserSiteChange] = [], pullToken: SyncToken = SyncToken(raw: "t1"),
         failPush: Bool = false, failPull: Bool = false) {
        self.pullChanges = pullChanges
        self.pullToken = pullToken
        self.failPush = failPush
        self.failPull = failPull
    }

    struct StubError: Error {}

    func push(_ changes: [UserSiteChange]) async throws {
        if failPush { throw StubError() }
        pushedBatches.append(changes)
    }

    func pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken) {
        pullTokens.append(token)
        if failPull { throw StubError() }
        return (pullChanges, pullToken)
    }

    func pushed() -> [[UserSiteChange]] { pushedBatches }
    func pullCalls() -> [SyncToken?] { pullTokens }
}
