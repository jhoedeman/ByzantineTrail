import SwiftUI

/// Profile → Contribute → Suggest a site (M5c). A gated form that submits a
/// `SiteSuggestion` via `SuggestionStore`. Reads account/network from the
/// environment (like `RatingSection`); Submit is disabled when signed out,
/// offline, over the daily limit, or the name is empty.
struct SuggestSiteForm: View {
    let theme: Theme

    @Environment(SuggestionStore.self) private var store
    @Environment(AccountStore.self) private var accountStore
    @Environment(NetworkMonitor.self) private var network

    @State private var name = ""
    @State private var location = ""
    @State private var whyInclude = ""
    @State private var linksText = ""
    @State private var status: SuggestionStore.SubmitResult?

    var body: some View {
        let gate = SuggestionGate.evaluate(status: accountStore.status,
                                           isOnline: network.isOnline,
                                           remaining: store.remaining)
        let nameEntered = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canSubmit = gate.isEnabled && nameEntered && !store.isSubmitting

        Form {
            Section("Site") {
                TextField("Name (required)", text: $name)
                    .accessibilityIdentifier("suggest.name")
                TextField("Location", text: $location)
                    .accessibilityIdentifier("suggest.location")
            }
            Section("Details (optional)") {
                TextField("Why should it be included?", text: $whyInclude, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("suggest.why")
                TextField("Links", text: $linksText, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("suggest.links")
            }
            Section {
                Button {
                    Task { await performSubmit() }
                } label: {
                    if store.isSubmitting { ProgressView() } else { Text("Submit suggestion") }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("suggest.submit")

                if let message = statusMessage(gate: gate) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(status == .success ? theme.accentPrimary : theme.textSecondary)
                        .accessibilityIdentifier("suggest.status")
                }
            }
        }
        .navigationTitle("Suggest a Site")
        .navigationBarTitleDisplayMode(.inline)
        .background(theme.bgApp)
        .task { store.refreshRemaining() }
    }

    private func performSubmit() async {
        let result = await store.submit(name: name, location: location,
                                        whyInclude: whyInclude, linksText: linksText)
        status = result
        if result == .success { name = ""; location = ""; whyInclude = ""; linksText = "" }
    }

    /// Post-submit status wins over the pre-submit gate explainer.
    private func statusMessage(gate: SuggestionGate.State) -> String? {
        switch status {
        case .success: return "Thanks — your suggestion was sent."
        case .invalid(let problems):
            return problems.contains(.nameRequired)
                ? "Please enter a site name."
                : "One of your entries is too long."
        case .rateLimited: return "You've reached today's suggestion limit (10)."
        case .failed: return "Couldn't send right now. Please try again."
        case .none: return gate.explainer
        }
    }
}
