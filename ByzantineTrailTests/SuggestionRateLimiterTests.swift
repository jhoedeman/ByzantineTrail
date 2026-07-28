import Testing
import Foundation
@testable import ByzantineTrail

struct SuggestionRateLimiterTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func allowsUnderLimit() {
        let d = SuggestionRateLimiter.decide(recent: Array(repeating: now, count: 9), now: now)
        #expect(d == .init(allowed: true, remaining: 1))
    }

    @Test func deniesAtLimit() {
        let d = SuggestionRateLimiter.decide(recent: Array(repeating: now, count: 10), now: now)
        #expect(d == .init(allowed: false, remaining: 0))
    }

    @Test func prunesAtAndBeforeWindowEdge() {
        let old = now.addingTimeInterval(-SuggestionRateLimiter.window - 1)
        let edge = now.addingTimeInterval(-SuggestionRateLimiter.window) // exactly at cutoff → pruned
        let fresh = now.addingTimeInterval(-1)
        #expect(SuggestionRateLimiter.pruned([old, edge, fresh], now: now) == [fresh])
    }

    @Test func remainingCountsOnlyRecent() {
        let old = now.addingTimeInterval(-SuggestionRateLimiter.window - 1)
        let recent = Array(repeating: now.addingTimeInterval(-10), count: 3)
        #expect(SuggestionRateLimiter.decide(recent: [old] + recent, now: now).remaining == 7)
    }
}
