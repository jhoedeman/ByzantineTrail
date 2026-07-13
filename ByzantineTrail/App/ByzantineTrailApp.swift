import SwiftUI

@main
struct ByzantineTrailApp: App {
    @State private var catalogStore = CatalogStore()
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalogStore)
                .environment(themeManager)
                .environment(\.entitlements, FreeEntitlementManager())
                .task {
                    if catalogStore.catalog == nil {
                        try? catalogStore.loadBundled()
                    }
                }
        }
    }
}
