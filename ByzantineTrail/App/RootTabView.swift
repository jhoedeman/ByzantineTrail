import SwiftUI

struct RootTabView: View {
    var body: some View {
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
    }
}
