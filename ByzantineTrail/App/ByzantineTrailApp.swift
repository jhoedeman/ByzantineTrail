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
                    if catalogStore.catalog == nil {
                        try? catalogStore.loadBundled()
                    }
                }
        }
    }
}
