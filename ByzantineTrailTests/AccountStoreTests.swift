import Testing
import CloudKit
@testable import ByzantineTrail

struct CloudKitAccountStatusMappingTests {
    @Test func availableMapsToAvailable() {
        #expect(CloudKitAccountStatusProvider.map(.available) == .available)
    }

    @Test func noAccountMapsToNoAccount() {
        #expect(CloudKitAccountStatusProvider.map(.noAccount) == .noAccount)
    }

    @Test func restrictedMapsToRestricted() {
        #expect(CloudKitAccountStatusProvider.map(.restricted) == .restricted)
    }

    @Test func couldNotDetermineMapsToUnknown() {
        #expect(CloudKitAccountStatusProvider.map(.couldNotDetermine) == .unknown)
    }

    /// The signed-in iCloud simulator persistently reports `.temporarilyUnavailable`
    /// (rawValue 4) even though CloudKit reads/writes succeed. Treating it as
    /// available keeps Settings showing "Signed in to iCloud" and keeps the
    /// rating/suggestion gates open, matching the account's real usability.
    @Test func temporarilyUnavailableMapsToAvailable() {
        #expect(CloudKitAccountStatusProvider.map(.temporarilyUnavailable) == .available)
    }
}

@MainActor
struct AccountStoreTests {
    @Test func startsUnknownThenRefreshes() async {
        let store = AccountStore(provider: MockAccountStatusProvider(status: .available))
        #expect(store.status == .unknown)
        await store.refresh()
        #expect(store.status == .available)
    }

    @Test func reflectsNoAccount() async {
        let store = AccountStore(provider: MockAccountStatusProvider(status: .noAccount))
        await store.refresh()
        #expect(store.status == .noAccount)
    }
}
