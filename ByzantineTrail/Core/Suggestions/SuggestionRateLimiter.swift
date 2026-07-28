import Foundation

/// Pure rolling-window rate limit for site suggestions (M5c): at most
/// `maxPerWindow` submissions per `window`. Operates on stored timestamps;
/// persistence lives in `SuggestionThrottleStore`. No I/O — unit-tested alone.
enum SuggestionRateLimiter {
    static let maxPerWindow = 10
    static let window: TimeInterval = 24 * 60 * 60

    struct Decision: Equatable { let allowed: Bool; let remaining: Int }

    /// Timestamps strictly newer than `now - window` (edge and older are dropped).
    static func pruned(_ timestamps: [Date], now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-window)
        return timestamps.filter { $0 > cutoff }
    }

    static func decide(recent: [Date], now: Date) -> Decision {
        let remaining = max(0, maxPerWindow - pruned(recent, now: now).count)
        return Decision(allowed: remaining > 0, remaining: remaining)
    }
}
