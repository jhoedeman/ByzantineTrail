/// Pure gating for the rating control (spec §5.2): account must be available AND
/// online. Account check takes precedence over connectivity.
enum RatingGate {
    struct RatingGateState: Equatable {
        let isEnabled: Bool
        let explainer: String?
    }

    static func evaluate(status: AccountStatus, isOnline: Bool) -> RatingGateState {
        guard status == .available else {
            return .init(isEnabled: false, explainer: "Sign in to iCloud to rate.")
        }
        guard isOnline else {
            return .init(isEnabled: false, explainer: "Connect to the internet to rate.")
        }
        return .init(isEnabled: true, explainer: nil)
    }
}
