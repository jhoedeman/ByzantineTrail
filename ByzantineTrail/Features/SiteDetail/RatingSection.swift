import SwiftUI

/// Average + your 1–10 rating bar + remove + a gated explainer (spec §5.2).
struct RatingSection: View {
    let site: Site
    let theme: Theme

    @Environment(RatingsStore.self) private var ratingsStore
    @Environment(UserStateStore.self) private var userState
    @Environment(AccountStore.self) private var accountStore
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        let gate = RatingGate.evaluate(status: accountStore.status, isOnline: network.isOnline)
        let mine = userState.myRating(for: site.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rating").font(.headline).foregroundStyle(theme.textPrimary)
                Spacer()
                averageLabel
            }
            RatingBar(value: mine, isEnabled: gate.isEnabled, theme: theme) { rating in
                Task { await ratingsStore.submit(rating, for: site.id) }
            }
            HStack {
                if let explainer = gate.explainer {
                    Text(explainer).font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if mine != nil, gate.isEnabled {
                    Button("Remove my rating") {
                        Task { await ratingsStore.remove(for: site.id) }
                    }
                    .font(.caption)
                    .tint(theme.accentPrimary)
                    .accessibilityIdentifier("detail.removeRating")
                }
            }
        }
        .task(id: site.id) { await ratingsStore.refresh(site.id) }
    }

    @ViewBuilder private var averageLabel: some View {
        if let summary = ratingsStore.summary(for: site.id), summary.count > 0 {
            Text("\(summary.average, specifier: "%.1f") ★ (\(summary.count))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ratingDisplay)
        } else {
            Text("No ratings yet").font(.caption).foregroundStyle(theme.textSecondary)
        }
    }
}
