import SwiftUI

struct SitesListView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SiteFilterModel.self) private var filterModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var query = SiteQuery()
    @State private var showingFilter = false
    @AppStorage("sites.sortField") private var storedSortField = SortField.name.rawValue
    @AppStorage("sites.sortAscending") private var storedAscending = true

    var body: some View {
        @Bindable var filterModel = filterModel
        let theme = themeManager.theme(for: colorScheme)
        let cityNames = catalogStore.cityNamesByID
        let activeQuery: SiteQuery = {
            var q = query
            q.filter = filterModel.filter
            return q
        }()
        let results = activeQuery.apply(to: catalogStore.sites, cityNames: cityNames)

        NavigationStack {
            List(results) { site in
                NavigationLink {
                    SiteDetailView(site: site)
                } label: {
                    SiteRowView(site: site,
                                cityName: site.cityId.flatMap { cityNames[$0] },
                                theme: theme)
                }
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
                FilterSheetView(filter: $filterModel.filter,
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
