import Testing
@testable import ByzantineTrail

struct RatingGateTests {
    @Test func enabledWhenAvailableAndOnline() {
        let g = RatingGate.evaluate(status: .available, isOnline: true)
        #expect(g.isEnabled)
        #expect(g.explainer == nil)
    }

    @Test func signedOutExplainer() {
        for status in [AccountStatus.noAccount, .restricted, .unknown] {
            let g = RatingGate.evaluate(status: status, isOnline: true)
            #expect(!g.isEnabled)
            #expect(g.explainer == "Sign in to iCloud to rate.")
        }
    }

    @Test func offlineExplainerWhenAvailable() {
        let g = RatingGate.evaluate(status: .available, isOnline: false)
        #expect(!g.isEnabled)
        #expect(g.explainer == "Connect to the internet to rate.")
    }
}
