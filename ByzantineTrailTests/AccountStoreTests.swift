import Testing
@testable import ByzantineTrail

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
