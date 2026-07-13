import SwiftUI

struct SitesListView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var query = SiteQuery()
    @State private var showingFilter = false
    @AppStorage("sites.sortField") private var storedSortField = SortField.name.rawValue
    @AppStorage("sites.sortAscending") private var storedAscending = true

    var body: some View {
        let theme = themeManager.theme(for: colorScheme)
        let cityNames = catalogStore.cityNamesByID
        let results = query.apply(to: catalogStore.sites, cityNames: cityNames)

        NavigationStack {
            List(results) { site in
                SiteRowView(site: site,
                            cityName: site.cityId.flatMap { cityNames[$0] },
                            theme: theme)
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("No sites match", systemImage: "magnifyingglass")
                }
            }
            .navigationTitle("Sites")
            .searchable(text: $query.searchText, prompt: "Search sites")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SortMenu(sortField: $query.sortField, ascending: $query.ascending)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterButton(theme)
                }
            }
            .sheet(isPresented: $showingFilter) {
                FilterSheetView(filter: $query.filter,
                                allCountryCodes: catalogStore.countryCodes,
                                cities: catalogStore.cities,
                                theme: theme)
            }
        }
        .onAppear {
            query.sortField = SortField(rawValue: storedSortField) ?? .name
            query.ascending = storedAscending
        }
        .onChange(of: query.sortField) { _, new in storedSortField = new.rawValue }
        .onChange(of: query.ascending) { _, new in storedAscending = new }
    }

    private func filterButton(_ theme: Theme) -> some View {
        Button { showingFilter = true } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .overlay(alignment: .topTrailing) {
                    if query.filter.activeCount > 0 {
                        Text("\(query.filter.activeCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(theme.interactiveCtaText)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(theme.accentPrimary, in: Circle())
                            .offset(x: 10, y: -10)
                    }
                }
        }
        .accessibilityLabel(query.filter.activeCount > 0
            ? "Filter, \(query.filter.activeCount) active"
            : "Filter")
    }
}
