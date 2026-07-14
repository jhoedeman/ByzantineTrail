import Observation

/// Observable iCloud account status. Starts `.unknown`; `refresh()` queries the
/// provider (call on launch and on CloudKit's account-changed notification).
@MainActor
@Observable
final class AccountStore {
    private let provider: any AccountStatusProviding
    private(set) var status: AccountStatus = .unknown

    init(provider: any AccountStatusProviding) { self.provider = provider }

    func refresh() async { status = await provider.currentStatus() }
}
