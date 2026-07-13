import SwiftUI

struct SitesListView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.theme(for: colorScheme)
        NavigationStack {
            List(catalogStore.sites) { site in
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                        .foregroundStyle(theme.textPrimary)
                    Text(site.country)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .navigationTitle("Sites")
        }
    }
}
