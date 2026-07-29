import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var themeManager = themeManager
        let theme = themeManager.theme(for: colorScheme)
        let presentation = AccountStatusPresentation.make(for: accountStore.status)

        List {
            Section("Appearance") {
                Picker("Theme", selection: $themeManager.preference) {
                    ForEach(ThemePreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance")
            }

            Section("Account") {
                HStack(alignment: .top) {
                    Image(systemName: presentation.symbolName)
                        .foregroundStyle(theme.accentPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                        if let explainer = presentation.explainer {
                            Text(explainer)
                                .font(.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                .accessibilityIdentifier("settings.account.status")

                if presentation.showsOpenSettings {
                    Button("Open Settings") { openAppSettings() }
                        .accessibilityIdentifier("settings.account.openSettings")
                }
            }

            Section {
                NavigationLink("About") { AboutView() }
                    .accessibilityIdentifier("settings.about")
            }
        }
        .navigationTitle("Settings")
        .background(theme.bgApp)
        .task { await accountStore.refresh() }
    }

    /// iOS only permits deep-linking to the app's OWN Settings page, not the
    /// iCloud account pane. This is the standard iOS pattern.
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
