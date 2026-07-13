import SwiftUI

struct RootTabView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.theme(for: colorScheme)
        TabView {
            SitesListView()
                .tabItem { Label("Sites", systemImage: "list.bullet") }
                .tag("sites")
            MapTabView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag("map")
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag("profile")
        }
        .tint(theme.accentPrimary)
    }
}
