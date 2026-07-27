import CloudKit

/// Maps `CKAccountStatus` to the app's `AccountStatus`. Activated by the owner
/// (needs the iCloud entitlement + a signed-in account). All CloudKit stays here.
struct CloudKitAccountStatusProvider: AccountStatusProviding {
    private let container: CKContainer

    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        container = CKContainer(identifier: containerID)
    }

    func currentStatus() async -> AccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine, .temporarilyUnavailable: return .unknown
            @unknown default: return .unknown
            }
        } catch { return .unknown }
    }
}
