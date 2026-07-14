import SwiftUI
import SwiftData

@main
struct ByzantineTrailApp: App {
    @State private var catalogStore = CatalogStore()
    @State private var themeManager = ThemeManager()
    @State private var filterModel = SiteFilterModel()
    @State private var userState: UserStateStore

    init() {
        // Local SwiftData store for per-site user state (no CloudKit in M4).
        // Fall back to an in-memory store if the on-disk store can't open, so
        // the app still launches (favorites just won't persist that session).
        let container = (try? UserStateStore.makeContainer())
            ?? (try! UserStateStore.makeContainer(inMemory: true))
        // The store retains this container (see Task 2) — safe to let the local go.
        _userState = State(initialValue: UserStateStore(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalogStore)
                .environment(themeManager)
                .environment(filterModel)
                .environment(userState)
                .environment(\.entitlements, FreeEntitlementManager())
                .task {
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
