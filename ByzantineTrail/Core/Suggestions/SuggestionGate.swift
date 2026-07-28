/// Pure gating for the Suggest-a-Site Submit control (M5c). Precedence:
/// account availability, then connectivity, then the client rate limit.
/// Mirrors `RatingGate`.
enum SuggestionGate {
    struct State: Equatable {
        let isEnabled: Bool
        let explainer: String?
    }

    static func evaluate(status: AccountStatus, isOnline: Bool, remaining: Int) -> State {
        guard status == .available else {
            return .init(isEnabled: false, explainer: "Sign in to iCloud to suggest a site.")
        }
        guard isOnline else {
            return .init(isEnabled: false, explainer: "Connect to the internet to suggest a site.")
        }
        guard remaining > 0 else {
            return .init(isEnabled: false, explainer: "You've reached today's suggestion limit (10).")
        }
        return .init(isEnabled: true, explainer: nil)
    }
}
