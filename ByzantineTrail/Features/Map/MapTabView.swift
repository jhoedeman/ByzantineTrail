import SwiftUI

struct MapTabView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SiteFilterModel.self) private var filterModel
    @Environment(UserStateStore.self) private var userState
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingFilter = false
    @State private var selectedSite: Site?
    @State private var fitToken = 0

    var body: some View {
        @Bindable var filterModel = filterModel
        let theme = themeManager.theme(for: colorScheme)
        let snapshot = userState.snapshot()
        let filtered = catalogStore.sites.filter {
            filterModel.filter.matches($0, flags: snapshot.flags(for: $0.id))
        }
        let annotations = SiteAnnotation.annotations(from: filtered, visited: snapshot.visited)

        NavigationStack {
            SiteMapView(annotations: annotations,
                        theme: theme,
                        fitToken: fitToken,
                        onSelectSite: { selectedSite = $0 })
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView("No sites match", systemImage: "map")
                    }
                }
                .navigationTitle("Map")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        filterButton(theme)
                    }
                }
                .sheet(isPresented: $showingFilter) {
                    FilterSheetView(filter: $filterModel.filter,
                                    allCountryCodes: catalogStore.countryCodes,
                                    cities: catalogStore.cities,
                                    theme: theme)
                }
                .sheet(item: $selectedSite) { site in
                    SiteDetailView(site: site)
                        .presentationDetents([.medium, .large])
                }
        }
        .onChange(of: filterModel.filter) { _, _ in fitToken += 1 }
    }

    private func filterButton(_ theme: Theme) -> some View {
        Button { showingFilter = true } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .overlay(alignment: .topTrailing) {
                    if filterModel.filter.activeCount > 0 {
                        Text("\(filterModel.filter.activeCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(theme.interactiveCtaText)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(theme.accentPrimary, in: Circle())
                            .offset(x: 10, y: -10)
                    }
                }
        }
        .accessibilityLabel(filterModel.filter.activeCount > 0
            ? "Filter, \(filterModel.filter.activeCount) active"
            : "Filter")
    }
}
