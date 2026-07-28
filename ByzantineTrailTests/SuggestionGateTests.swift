import Testing
@testable import ByzantineTrail

struct SuggestionGateTests {
    @Test func signedOutBeatsEverything() {
        let s = SuggestionGate.evaluate(status: .noAccount, isOnline: false, remaining: 0)
        #expect(s == .init(isEnabled: false, explainer: "Sign in to iCloud to suggest a site."))
    }

    @Test func offlineBeatsRateLimit() {
        let s = SuggestionGate.evaluate(status: .available, isOnline: false, remaining: 0)
        #expect(s == .init(isEnabled: false, explainer: "Connect to the internet to suggest a site."))
    }

    @Test func rateLimitedWhenNoneRemain() {
        let s = SuggestionGate.evaluate(status: .available, isOnline: true, remaining: 0)
        #expect(s == .init(isEnabled: false, explainer: "You've reached today's suggestion limit (10)."))
    }

    @Test func enabledWhenAllPass() {
        let s = SuggestionGate.evaluate(status: .available, isOnline: true, remaining: 3)
        #expect(s == .init(isEnabled: true, explainer: nil))
    }
}
