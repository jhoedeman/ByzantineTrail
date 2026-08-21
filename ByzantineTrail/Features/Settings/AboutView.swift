import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                Text("Byzantine Trail")
                    .font(.headline)
            }
            Section("Version") {
                Text(AppVersionInfo.current.displayString)
                    .accessibilityIdentifier("about.version")
            }
            Section {
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    .accessibilityIdentifier("about.privacy")
                NavigationLink("Image Credits") { ImageCreditsView() }
                    .accessibilityIdentifier("about.credits")
            }
        }
        .navigationTitle("About")
    }
}
