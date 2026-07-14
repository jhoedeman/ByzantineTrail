import SwiftUI

@main
struct ByzantineTrailApp: App {
    @State private var catalogStore = CatalogStore()
    @State private var themeManager = ThemeManager()
    @State private var filterModel = SiteFilterModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalogStore)
                .environment(themeManager)
                .environment(filterModel)
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
