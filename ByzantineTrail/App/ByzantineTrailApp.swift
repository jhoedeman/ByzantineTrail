import SwiftUI
import SwiftData

@main
struct ByzantineTrailApp: App {
    @State private var catalogStore = CatalogStore()
    @State private var themeManager = ThemeManager()
    @State private var filterModel = SiteFilterModel()
    @State private var userState: UserStateStore
    @State private var ratingsStore: RatingsStore
    @State private var accountStore: AccountStore
    @State private var network = NetworkMonitor()

    init() {
        // Local SwiftData store for per-site user state (no CloudKit in M4).
        // Fall back to an in-memory store if the on-disk store can't open, so
        // the app still launches (favorites just won't persist that session).
        let container = (try? UserStateStore.makeContainer())
            ?? (try! UserStateStore.makeContainer(inMemory: true))
        // The store retains this container (see Task 2) — safe to let the local go.
        let store = UserStateStore(container: container)
        _userState = State(initialValue: store)

        // Pre-CloudKit wiring (owner flips to CloudKit in Task 14 / CLOUDKIT_SETUP.md).
        let ratingsService = MockRatingsService(seed: MockRatingsSeed.demo)
        _ratingsStore = State(initialValue: RatingsStore(service: ratingsService, userState: store))
        _accountStore = State(initialValue: AccountStore(
            provider: MockAccountStatusProvider(status: .available)))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalogStore)
                .environment(themeManager)
                .environment(filterModel)
                .environment(userState)
                .environment(ratingsStore)
                .environment(accountStore)
                .environment(network)
                .environment(\.entitlements, FreeEntitlementManager())
                .task {
                    await accountStore.refresh()
                    // 1. Load the newest valid catalog synchronously (offline-safe):
                    //    cached copy if newer, else the bundled one.
                    let cache = try? CatalogCache.makeDefault()
                    if catalogStore.catalog == nil {
                        if let cache {
                            try? catalogStore.loadNewestValid(cache: cache)
                        } else {
                            try? catalogStore.loadBundled()
                        }
                    }
                    // 2. Kick a background refresh. Any failure (incl. offline, or a
                    //    not-yet-created content repo) is a silent no-op.
                    if let cache {
                        let refresher = CatalogRefresher(
                            baseURL: RemoteConfig.catalogBaseURL,
                            cache: cache,
                            fetch: CatalogRefresher.urlSessionFetch)
                        if let fresh = await refresher.refresh(
                            currentVersion: catalogStore.catalog?.catalogVersion ?? 0) {
                            catalogStore.apply(fresh)
                        }
                    }
                }
        }
    }
}
