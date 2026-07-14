import SwiftUI

/// Renders a VisitedProgress: overall gilded bar + per-tier and per-country bars.
struct ProgressStatsView: View {
    let progress: VisitedProgress
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            overall
            if progress.byTier.contains(where: { $0.total > 0 }) {
                bucketGroup("By Tier", progress.byTier.filter { $0.total > 0 })
            }
            if !progress.byCountry.isEmpty {
                bucketGroup("By Country", progress.byCountry)
            }
        }
        .padding(.vertical, 4)
    }

    private var overall: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Visited").font(.headline).foregroundStyle(theme.textPrimary)
                Spacer()
                Text("\(progress.visited) / \(progress.total)")
                    .font(.subheadline).foregroundStyle(theme.textSecondary)
            }
            GildedBar(fraction: progress.fraction, theme: theme)
        }
    }

    private func bucketGroup(_ title: String, _ buckets: [ProgressBucket]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textSecondary)
            ForEach(buckets) { b in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(b.label).font(.footnote).foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text("\(b.visited)/\(b.total)").font(.footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                    GildedBar(fraction: b.fraction, theme: theme)
                }
            }
        }
    }
}

/// Thin rounded progress bar in the gilded (gold) accent.
struct GildedBar: View {
    let fraction: Double
    let theme: Theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.bgCardAlt)
                Capsule().fill(theme.accentPrimary)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

#Preview {
    let sample = VisitedProgress(
        visited: 3, total: 10,
        byCountry: [ProgressBucket(id: "TR", label: "Türkiye", visited: 2, total: 5),
                    ProgressBucket(id: "IT", label: "Italy", visited: 1, total: 5)],
        byTier: [ProgressBucket(id: "major", label: "Major", visited: 2, total: 4),
                 ProgressBucket(id: "notable", label: "Notable", visited: 1, total: 3),
                 ProgressBucket(id: "minor", label: "Minor", visited: 0, total: 3)])
    return ProgressStatsView(progress: sample, theme: .chrysos(.dark))
        .padding()
        .background(Theme.chrysos(.dark).bgApp)
}
