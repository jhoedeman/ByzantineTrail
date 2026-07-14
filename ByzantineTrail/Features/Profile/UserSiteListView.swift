import SwiftUI

/// Reusable list of catalog sites filtered to a set of site ids (favorites,
/// want-to-visit, or visited). Reuses SiteRowView + row→detail navigation.
struct UserSiteListView: View {
    let title: String
    let emptyTitle: String
    let emptySymbol: String
    let siteIDs: Set<String>

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(UserStateStore.self) private var userState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.theme(for: colorScheme)
        let cityNames = catalogStore.cityNamesByID
        let sites = catalogStore.sites
            .filter { siteIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        List(sites) { site in
            NavigationLink {
                SiteDetailView(site: site)
            } label: {
                SiteRowView(site: site,
                            cityName: site.cityId.flatMap { cityNames[$0] },
                            theme: theme,
                            flags: userState.flags(for: site.id))
            }
        }
        .listStyle(.plain)
        .overlay {
            if sites.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
            }
        }
        .navigationTitle(title)
        .background(theme.bgApp)
    }
}
