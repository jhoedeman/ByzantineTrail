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
            return Self.map(try await container.accountStatus())
        } catch { return .unknown }
    }

    /// Pure mapping seam (unit-testable without CloudKit).
    ///
    /// `.temporarilyUnavailable` denotes a real, signed-in account whose token
    /// merely wants a refresh — CloudKit reads/writes still succeed (and the
    /// iCloud-signed-in simulator reports it persistently). Treating it as
    /// available keeps Settings and the rating/suggestion gates in sync with the
    /// account's actual usability, rather than stranding the UI in `.unknown`
    /// ("Checking iCloud status…") forever.
    static func map(_ status: CKAccountStatus) -> AccountStatus {
        switch status {
        case .available, .temporarilyUnavailable: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .couldNotDetermine: return .unknown
        @unknown default: return .unknown
        }
    }
}
