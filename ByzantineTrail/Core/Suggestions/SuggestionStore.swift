import Observation
import Foundation

/// Observable orchestration for site suggestions (M5c). Validates the form,
/// enforces the client rate limit, calls the `SuggestionSubmitting` seam, and
/// records a timestamp on success. Never throws; returns a `SubmitResult`.
@MainActor
@Observable
final class SuggestionStore {
    enum SubmitResult: Equatable {
        case success
        case invalid([SuggestionValidator.Problem])
        case rateLimited
        case failed
    }

    private let service: any SuggestionSubmitting
    private let throttle: any SuggestionThrottleStoring
    private let now: () -> Date

    private(set) var isSubmitting = false
    private(set) var remaining: Int

    init(service: any SuggestionSubmitting,
         throttle: any SuggestionThrottleStoring,
         now: @escaping () -> Date = Date.init) {
        self.service = service
        self.throttle = throttle
        self.now = now
        self.remaining = SuggestionRateLimiter.decide(recent: throttle.load(), now: now()).remaining
    }

    /// Recompute `remaining` from the throttle store (call when the form appears).
    func refreshRemaining() {
        remaining = SuggestionRateLimiter.decide(recent: throttle.load(), now: now()).remaining
    }

    func submit(name: String, location: String,
                whyInclude: String, linksText: String) async -> SubmitResult {
        let suggestion: SiteSuggestion
        switch SuggestionValidator.validate(name: name, location: location,
                                            whyInclude: whyInclude, linksText: linksText) {
        case .invalid(let problems): return .invalid(problems)
        case .valid(let value): suggestion = value
        }

        let current = now()
        let recent = SuggestionRateLimiter.pruned(throttle.load(), now: current)
        guard SuggestionRateLimiter.decide(recent: recent, now: current).allowed else {
            remaining = 0
            return .rateLimited
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.submit(suggestion)
        } catch {
            return .failed
        }

        let updated = recent + [current]
        throttle.save(updated)
        remaining = SuggestionRateLimiter.decide(recent: updated, now: current).remaining
        return .success
    }
}
