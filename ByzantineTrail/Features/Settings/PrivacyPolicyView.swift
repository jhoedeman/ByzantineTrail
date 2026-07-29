import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(Self.policyText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityIdentifier("privacy.body")
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// In-app source of truth for the privacy policy. No personal email — the
    /// Contact line points at the App Store listing (hard privacy rule).
    private static let policyText = """
    Byzantine Trail — Privacy Policy
    Last updated: July 2026

    Byzantine Trail is designed to collect as little as possible.

    No tracking. The app contains no advertising, no third-party analytics, and no tracking of any kind. It does not use the Advertising Identifier and never shares data with data brokers.

    Ratings you submit are public. When you rate a site (1–10), that rating and its site are stored in Apple's CloudKit public database so other users can see the community average. Ratings are not shown next to your name.

    Site suggestions. If you suggest a site, the details you type are stored in Apple's CloudKit database. Suggestions carry no identifying information about you.

    Your favorites, want-to-visit, and visited lists are private. These sync across your own devices through your personal iCloud account. They are stored in your private iCloud database, which the developer cannot read.

    Where your data lives. All data stays within Apple's CloudKit. Apple's handling of it is governed by Apple's Privacy Policy. The app has no separate servers and no separate account system.

    Contact. Questions about this policy can be raised through the app's App Store listing.
    """
}
