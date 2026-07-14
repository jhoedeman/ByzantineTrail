import SwiftUI

struct SiteStateGlyph: Identifiable, Equatable {
    enum ColorRole { case accent, visited }
    let id: String
    let symbol: String
    let colorRole: ColorRole
}

extension SiteUserFlags {
    /// Glyphs for the *set* flags only, in a stable favorite→want→visited order.
    var rowGlyphs: [SiteStateGlyph] {
        var out: [SiteStateGlyph] = []
        if isFavorite { out.append(.init(id: "favorite", symbol: "heart.fill", colorRole: .accent)) }
        if wantsToVisit { out.append(.init(id: "want", symbol: "bookmark.fill", colorRole: .accent)) }
        if visited { out.append(.init(id: "visited", symbol: "checkmark.circle.fill", colorRole: .visited)) }
        return out
    }
}

struct SiteRowView: View {
    let site: Site
    let cityName: String?
    let theme: Theme
    var flags: SiteUserFlags = SiteUserFlags()

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
            if !flags.rowGlyphs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(flags.rowGlyphs) { g in
                        Image(systemName: g.symbol)
                            .font(.caption)
                            .foregroundStyle(g.colorRole == .visited ? theme.visitedCheck
                                                                      : theme.accentPrimary)
                    }
                }
                .accessibilityHidden(true)   // state is folded into the row's a11y label
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(site.name), \(site.type.displayLabel), \(site.importance.displayLabel) tier, \(subtitle)\(stateA11y)")
    }

    private var subtitle: String {
        let country = CountryName.localized(site.country)
        if let cityName, !cityName.isEmpty { return "\(cityName) · \(country)" }
        return country
    }

    private var stateA11y: String {
        var parts: [String] = []
        if flags.isFavorite { parts.append("favorite") }
        if flags.wantsToVisit { parts.append("want to visit") }
        if flags.visited { parts.append("visited") }
        return parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
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
