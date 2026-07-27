import Observation

/// Observable cache over a `RatingsServicing`. Holds community summaries for
/// rows/sort; the user's own rating lives in `UserStateStore` (local, all sites),
/// which this store writes on submit and reconciles from the cloud on refresh.
@MainActor
@Observable
final class RatingsStore {
    private let service: any RatingsServicing
    private let userState: UserStateStore

    private(set) var summaries: [String: RatingSummary] = [:]

    init(service: any RatingsServicing, userState: UserStateStore) {
        self.service = service
        self.userState = userState
    }

    func summary(for siteId: String) -> RatingSummary? { summaries[siteId] }

    /// Batch-load every summary (rows + sort). Failure leaves the cache as-is.
    func loadAll() async {
        if let all = try? await service.allSummaries() { summaries = all }
    }

    /// Detail-open reconcile: refresh one site's summary and pull my cloud rating
    /// into the local cache (covers a rating made on another device).
    func refresh(_ siteId: String) async {
        guard let state = try? await service.load(for: siteId) else { return }
        if let summary = state.summary { summaries[siteId] = summary }
        if userState.myRating(for: siteId) != state.mine {
            userState.setRating(state.mine, for: siteId)
        }
    }

    func submit(_ rating: Int, for siteId: String) async {
        guard let summary = try? await service.submit(rating: rating, for: siteId) else { return }
        summaries[siteId] = summary
        userState.setRating(rating, for: siteId)
    }

    func remove(for siteId: String) async {
        guard let summary = try? await service.removeRating(for: siteId) else { return }
        summaries[siteId] = summary
        userState.setRating(nil, for: siteId)
    }
}
