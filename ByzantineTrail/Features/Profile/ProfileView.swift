import SwiftUI

struct ProfileView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(UserStateStore.self) private var userState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.theme(for: colorScheme)
        NavigationStack {
            List {
                Section("My Activity") {
                    activityLink("Favorites", systemImage: "heart.fill",
                                 count: userState.favoriteCount, ids: userState.favoriteIDs,
                                 emptyTitle: "No favorites yet", emptySymbol: "heart", theme: theme)
                    activityLink("Want to Visit", systemImage: "bookmark.fill",
                                 count: userState.wantCount, ids: userState.wantIDs,
                                 emptyTitle: "Nothing saved yet", emptySymbol: "bookmark", theme: theme)
                    activityLink("Visited", systemImage: "checkmark.circle.fill",
                                 count: userState.visitedCount, ids: userState.visitedIDs,
                                 emptyTitle: "No visits logged yet", emptySymbol: "checkmark.circle",
                                 theme: theme)
                }

                Section("Progress") {
                    ProgressStatsView(
                        progress: VisitedProgress.compute(visited: userState.visitedIDs,
                                                          sites: catalogStore.sites),
                        theme: theme)
                }
            }
            .navigationTitle("Profile")
            .background(theme.bgApp)
        }
    }

    private func activityLink(_ title: String, systemImage: String, count: Int,
                              ids: Set<String>, emptyTitle: String, emptySymbol: String,
                              theme: Theme) -> some View {
        NavigationLink {
            UserSiteListView(title: title, emptyTitle: emptyTitle,
                             emptySymbol: emptySymbol, siteIDs: ids)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text("\(count)").foregroundStyle(theme.textSecondary)
            }
        }
    }
}
