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
    var average: Double? = nil
    var myRating: Int? = nil
    var resolver: PhotoResolver? = nil

    var body: some View {
        HStack(spacing: 12) {
            leadingTile
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
                if average != nil || myRating != nil {
                    HStack(spacing: 6) {
                        if let average {
                            Text("\(average, specifier: "%.1f") ★")
                                .font(.caption)
                                .foregroundStyle(theme.ratingDisplay)
                        }
                        if let myRating {
                            Text("me \(myRating)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(theme.ratingDisplay.opacity(0.18), in: Capsule())
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
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
        .accessibilityLabel("\(site.name), \(site.type.displayLabel), \(site.importance.displayLabel) tier, \(subtitle)\(stateA11y)\(ratingA11y)")
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

    private var ratingA11y: String {
        var parts: [String] = []
        if let average { parts.append("average \(String(format: "%.1f", average))") }
        if let myRating { parts.append("your rating \(myRating)") }
        return parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
    }

    /// A real photo thumbnail when the site has one (bundled thumbs resolve to
    /// local file URLs, so no network fetch on first paint); the type icon
    /// otherwise. The icon also fills in while the image loads or if it fails.
    @ViewBuilder private var leadingTile: some View {
        if let photo = site.photos.first, let url = resolver?.thumbURL(for: photo) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.bgCardAlt)
                .frame(width: 44, height: 44)
                .overlay(
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            iconGlyph
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        } else {
            iconTile
        }
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.bgCardAlt)
            .frame(width: 44, height: 44)
            .overlay(iconGlyph)
    }

    private var iconGlyph: some View {
        Image(systemName: site.type.iconName)
            .font(.system(size: 20))
            .foregroundStyle(theme.accentPrimary)
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
