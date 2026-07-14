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
                    ForEach(allCountryCodes, id: \.self) { code in
                        Toggle(CountryName.localized(code), isOn: membership(code, in: \.countries))
                    }
                }
                Section("City") {
                    ForEach(cities) { city in
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
