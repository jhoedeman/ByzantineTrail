import SwiftUI

struct FilterSheetView: View {
    @Binding var filter: SiteFilter
    let allCountryCodes: [String]
    let cities: [City]
    let centerCityIds: Set<String>
    let cityNamesByID: [String: String]
    let theme: Theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DisclosureGroup {
                    ForEach(SiteType.allCases, id: \.self) { type in
                        Toggle(type.displayLabel, isOn: membership(type, in: \.types))
                    }
                } label: { rowLabel("Type", summary: typeSummary) }

                DisclosureGroup {
                    ForEach(Importance.allCases, id: \.self) { imp in
                        Toggle(imp.displayLabel, isOn: membership(imp, in: \.importances))
                    }
                } label: { rowLabel("Importance", summary: importanceSummary) }

                DisclosureGroup {
                    ForEach(sortedCountryCodes, id: \.self) { code in
                        Toggle(CountryName.localized(code), isOn: membership(code, in: \.countries))
                    }
                } label: { rowLabel("Country", summary: countrySummary) }

                NavigationLink {
                    CityFilterPickerView(selectedCityIds: $filter.cityIds,
                                         cities: cities,
                                         centerCityIds: centerCityIds)
                } label: { rowLabel("City", summary: citySummary) }

                DisclosureGroup {
                    Toggle("Favorites", isOn: $filter.favoritesOnly)
                    Toggle("Want to Visit", isOn: $filter.wantOnly)
                    Toggle("Visited", isOn: $filter.visitedOnly)
                } label: { rowLabel("My Sites", summary: mySitesSummary) }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear all") { filter.clear() }
                        .disabled(filter.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Row label (title + one-line selection summary)

    private func rowLabel(_ title: String, summary: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Summaries

    private var typeSummary: String {
        FilterSummary.summarize(localizedSorted(filter.types.map(\.displayLabel)))
    }
    private var importanceSummary: String {
        FilterSummary.summarize(localizedSorted(filter.importances.map(\.displayLabel)))
    }
    private var countrySummary: String {
        FilterSummary.summarize(localizedSorted(filter.countries.map { CountryName.localized($0) }))
    }
    private var citySummary: String {
        FilterSummary.summarize(localizedSorted(filter.cityIds.compactMap { cityNamesByID[$0] }))
    }
    private var mySitesSummary: String {
        // Intentionally fixed order (Favorites, Want to Visit, Visited) to match
        // the toggle order in the row — NOT alphabetized like the other summaries.
        var parts: [String] = []
        if filter.favoritesOnly { parts.append("Favorites") }
        if filter.wantOnly { parts.append("Want to Visit") }
        if filter.visitedOnly { parts.append("Visited") }
        return FilterSummary.summarize(parts)
    }

    /// Sort display names the way the rows themselves sort (accents/case like
    /// Finder), so a collapsed summary's first two names match the expanded order.
    private func localizedSorted(_ names: [String]) -> [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Helpers

    /// Countries alphabetized by localized display name (not ISO code).
    private var sortedCountryCodes: [String] {
        allCountryCodes.sorted {
            CountryName.localized($0).localizedStandardCompare(CountryName.localized($1)) == .orderedAscending
        }
    }

    /// Binding that adds/removes `value` from one of SiteFilter's Set members.
    private func membership<T: Hashable>(
        _ value: T, in keyPath: WritableKeyPath<SiteFilter, Set<T>>
    ) -> Binding<Bool> {
        Binding(
            get: { filter[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn { filter[keyPath: keyPath].insert(value) }
                else { filter[keyPath: keyPath].remove(value) }
            }
        )
    }
}
