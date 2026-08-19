import SwiftUI

struct FilterSheetView: View {
    @Binding var filter: SiteFilter
    let allCountryCodes: [String]
    let cities: [City]
    let theme: Theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    ForEach(SiteType.allCases, id: \.self) { type in
                        Toggle(type.displayLabel, isOn: membership(type, in: \.types))
                    }
                }
                Section("Importance") {
                    ForEach(Importance.allCases, id: \.self) { imp in
                        Toggle(imp.displayLabel, isOn: membership(imp, in: \.importances))
                    }
                }
                Section("Country") {
                    ForEach(sortedCountryCodes, id: \.self) { code in
                        Toggle(CountryName.localized(code), isOn: membership(code, in: \.countries))
                    }
                }
                Section("City") {
                    ForEach(sortedCities) { city in
                        Toggle(city.name, isOn: membership(city.id, in: \.cityIds))
                    }
                }
                Section("My Sites") {
                    Toggle("Favorites", isOn: $filter.favoritesOnly)
                    Toggle("Want to Visit", isOn: $filter.wantOnly)
                    Toggle("Visited", isOn: $filter.visitedOnly)
                }
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

    /// Countries alphabetized by localized display name (not ISO code, which
    /// only looks alphabetical by coincidence — the UK's "GB" would otherwise
    /// sort under G).
    private var sortedCountryCodes: [String] {
        allCountryCodes.sorted {
            CountryName.localized($0).localizedStandardCompare(CountryName.localized($1)) == .orderedAscending
        }
    }

    /// Cities alphabetized by name; localizedStandardCompare sorts accents and
    /// case the way Finder does ("Vall de Boí" lands with the V's).
    private var sortedCities: [City] {
        cities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
