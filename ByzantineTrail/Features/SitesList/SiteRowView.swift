import SwiftUI

struct SiteRowView: View {
    let site: Site
    let cityName: String?
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            iconTile
            VStack(alignment: .leading, spacing: 3) {
                Text(site.name)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                HStack(spacing: 6) {
                    Label(site.type.displayLabel, systemImage: site.type.iconName)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    importanceBadge
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(site.name), \(site.type.displayLabel), \(site.importance.displayLabel) tier, \(subtitle)")
    }

    private var subtitle: String {
        let country = CountryName.localized(site.country)
        if let cityName, !cityName.isEmpty { return "\(cityName) · \(country)" }
        return country
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.bgCardAlt)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: site.type.iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.accentPrimary)
            )
    }

    private var importanceBadge: some View {
        Text(site.importance.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(site.importance.tierColor(theme).opacity(0.18), in: Capsule())
            .foregroundStyle(theme.textPrimary)
    }
}
