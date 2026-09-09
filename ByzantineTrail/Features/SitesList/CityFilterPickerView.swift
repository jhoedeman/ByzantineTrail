import SwiftUI

/// Pushed multi-select City picker. Defaults to the catalog's center cities;
/// a search field reveals ALL cities so any town (including single-site ones)
/// can be filtered to. Below-threshold selections stay pinned in "Selected".
struct CityFilterPickerView: View {
    @Binding var selectedCityIds: Set<String>
    let cities: [City]
    let centerCityIds: Set<String>
    @State private var searchText = ""

    init(selectedCityIds: Binding<Set<String>>, cities: [City], centerCityIds: Set<String>) {
        self._selectedCityIds = selectedCityIds
        self.cities = cities
        self.centerCityIds = centerCityIds
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                let pinned = CityCenters.selectedNonCenters(
                    selected: selectedCityIds, centers: centerCityIds)
                if !pinned.isEmpty {
                    Section("Selected") {
                        ForEach(sortedCities(withIDs: pinned)) { cityToggle($0) }
                    }
                }
                Section("Centers") {
                    ForEach(centerCities) { cityToggle($0) }
                }
            } else {
                ForEach(searchResults) { cityToggle($0) }
            }
        }
        .navigationTitle("City")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search all cities")
        .overlay {
            if !searchText.isEmpty && searchResults.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    private var centerCities: [City] {
        sortedCities(withIDs: centerCityIds)
    }

    private var searchResults: [City] {
        let q = SiteQuery.fold(searchText)
        return cities
            .filter { SiteQuery.fold($0.name).contains(q) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func sortedCities(withIDs ids: Set<String>) -> [City] {
        cities
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func cityToggle(_ city: City) -> some View {
        Toggle(city.name, isOn: Binding(
            get: { selectedCityIds.contains(city.id) },
            set: { isOn in
                if isOn { selectedCityIds.insert(city.id) }
                else { selectedCityIds.remove(city.id) }
            }
        ))
    }
}
