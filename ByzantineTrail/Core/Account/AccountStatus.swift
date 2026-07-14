/// iCloud account availability for gating ratings (spec §5.2). CloudKit is one
/// provider; a mock drives tests without an Apple Developer account.
enum AccountStatus: Equatable, Sendable {
    case available, noAccount, restricted, unknown
}

protocol AccountStatusProviding: Sendable {
    func currentStatus() async -> AccountStatus
}

struct MockAccountStatusProvider: AccountStatusProviding {
    let status: AccountStatus
    func currentStatus() async -> AccountStatus { status }
}
