import SwiftUI

struct SiteDetailView: View {
    let site: Site
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(UserStateStore.self) private var userState

    var body: some View {
        let theme = themeManager.theme(for: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PhotoCarousel(site: site, resolver: catalogStore.photoResolver, theme: theme)

                VStack(alignment: .leading, spacing: 14) {
                    header(theme)
                    actionRow(theme)
                    Divider()
                    descriptionSection(theme)
                    infoSection("Hours", text: site.hours, theme: theme)
                    infoSection("Entry", text: site.entryInfo, theme: theme)
                    linksSection(theme)
                    SiteLocationSection(site: site, theme: theme)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(theme.bgApp)
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cityName: String? { site.cityId.flatMap { catalogStore.cityNamesByID[$0] } }

    private var subtitle: String {
        let country = CountryName.localized(site.country)
        if let cityName, !cityName.isEmpty { return "\(cityName) · \(country)" }
        return country
    }

    private func header(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(site.name)
                .font(.title.bold())
                .foregroundStyle(theme.textPrimary)
            HStack(spacing: 8) {
                Label(site.type.displayLabel, systemImage: site.type.iconName)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                Text(site.importance.displayLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(site.importance.tierColor(theme).opacity(0.18), in: Capsule())
                    .foregroundStyle(theme.textPrimary)
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func actionRow(_ theme: Theme) -> some View {
        let flags = userState.flags(for: site.id)
        return HStack(alignment: .top, spacing: 20) {
            actionButton(title: "Favorite",
                         symbol: flags.isFavorite ? "heart.fill" : "heart",
                         on: flags.isFavorite, tint: theme.accentPrimary, theme: theme,
                         id: "detail.favorite") { userState.toggleFavorite(site.id) }

            actionButton(title: "Want to visit",
                         symbol: flags.wantsToVisit ? "bookmark.fill" : "bookmark",
                         on: flags.wantsToVisit, tint: theme.accentPrimary, theme: theme,
                         id: "detail.want") { userState.toggleWant(site.id) }

            actionButton(title: "Visited",
                         symbol: flags.visited ? "checkmark.circle.fill" : "checkmark.circle",
                         on: flags.visited, tint: theme.visitedCheck, theme: theme,
                         id: "detail.visited") { withAnimation { userState.toggleVisited(site.id) } }

            Spacer(minLength: 0)
            shareButton(theme)
        }
    }

    private func actionButton(title: String, symbol: String, on: Bool, tint: Color,
                              theme: Theme, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2)
            }
            .foregroundStyle(on ? tint : theme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "on" : "off")
        .accessibilityIdentifier(id)
    }

    private func shareButton(_ theme: Theme) -> some View {
        ShareLink(
            item: SiteDetailFormatter.mapsURL(latitude: site.coordinate.lat,
                                              longitude: site.coordinate.lon, name: site.name),
            subject: Text(site.name),
            message: Text(SiteDetailFormatter.shareMessage(name: site.name, summary: site.summary))
        ) {
            VStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up").font(.title3)
                Text("Share").font(.caption2)
            }
            .foregroundStyle(theme.accentPrimary)
        }
    }

    @ViewBuilder
    private func descriptionSection(_ theme: Theme) -> some View {
        let paragraphs = SiteDetailFormatter.descriptionParagraphs(site.description)
        if !paragraphs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                    Text(para)
                        .font(.body)
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func infoSection(_ title: String, text: String?, theme: Theme) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func linksSection(_ theme: Theme) -> some View {
        if !site.links.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Links")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                ForEach(site.links, id: \.url) { link in
                    if let url = URL(string: link.url) {
                        Link(link.title, destination: url)
                            .tint(theme.accentPrimary)
                    }
                }
            }
        }
    }
}
