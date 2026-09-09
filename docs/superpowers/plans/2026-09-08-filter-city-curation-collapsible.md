# Filter Redesign: Collapsible Sheet + Curated City Picker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the long-scrolling filter sheet with collapsible rows, and give City a curated-by-default, searchable multi-select picker so 281 cities stop cluttering the sheet.

**Architecture:** A pure `CityCenters` helper derives the ~31 "center" cities (3+ sites) at runtime from the loaded catalog. `FilterSheetView` becomes a `Form` of `DisclosureGroup` rows (Type, Importance, Country, My Sites) plus a `NavigationLink` City row that pushes a new `.searchable` `CityFilterPickerView`. A pure `FilterSummary` helper renders each collapsed row's selection summary. No changes to `SiteFilter`, `SiteQuery`, sorting, or catalog content.

**Tech Stack:** SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), XcodeGen-managed project.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-08-filter-city-curation-collapsible-design.md`.
- Center threshold is **3** (a city with 3+ sites is a center). Default parameter value.
- **New source files must be registered via XcodeGen** before they build. Sources are folder-based, so after creating any file run: `~/bin/xcodegen_dist/bin/xcodegen generate` (use this REAL path, not the `~/bin/xcodegen` symlink).
- Tests use Swift Testing, not XCTest. `Site` fixtures are decoded from JSON (see existing `ByzantineTrailTests/SiteFilterTests.swift`).
- `SiteFilter`, `SiteFilter.matches`, `SiteQuery`, `SortMenu`, and `catalog.json` MUST remain unchanged.
- Commit author for every commit: `git -c user.email="6411536+jhoedeman@users.noreply.github.com" -c user.name="John Hoedeman" commit`. The real gmail must never enter the repo.
- Work happens on branch `filter-city-curation` (already checked out; holds the spec commit).
- Test command (single suite):
  `xcodebuild test -project ByzantineTrail.xcodeproj -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ByzantineTrailTests/<SuiteName> 2>&1 | tail -25`
- Build command (view verification):
  `xcodebuild build -project ByzantineTrail.xcodeproj -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -8`

---

## File Structure

- **Create** `ByzantineTrail/Core/Catalog/CityCenters.swift` — pure center-derivation logic (`centerIds`, `selectedNonCenters`).
- **Create** `ByzantineTrail/Features/SitesList/FilterSummary.swift` — pure selection-summary string builder.
- **Create** `ByzantineTrail/Features/SitesList/CityFilterPickerView.swift` — the pushed searchable multi-select City screen.
- **Create** `ByzantineTrailTests/CityCentersTests.swift`, `ByzantineTrailTests/FilterSummaryTests.swift`.
- **Modify** `ByzantineTrail/Core/Catalog/CatalogStore.swift` — add `centerCityIds`.
- **Modify** `ByzantineTrail/Features/SitesList/FilterSheetView.swift` — rewrite as collapsible rows + City NavigationLink.
- **Modify** `ByzantineTrail/Features/SitesList/SitesListView.swift` — pass `centerCityIds` + `cityNamesByID` into the sheet.

---

## Task 1: CityCenters helper + CatalogStore.centerCityIds

**Files:**
- Create: `ByzantineTrail/Core/Catalog/CityCenters.swift`
- Create: `ByzantineTrailTests/CityCentersTests.swift`
- Modify: `ByzantineTrail/Core/Catalog/CatalogStore.swift` (add computed property after `cityNamesByID`, ~line 15)

**Interfaces:**
- Produces:
  - `enum CityCenters { static func centerIds(sites: [Site], threshold: Int = 3) -> Set<String>; static func selectedNonCenters(selected: Set<String>, centers: Set<String>) -> Set<String> }`
  - `CatalogStore.centerCityIds: Set<String>` (computed)

- [ ] **Step 1: Write the failing tests**

Create `ByzantineTrailTests/CityCentersTests.swift`:

```swift
import Testing
import Foundation
@testable import ByzantineTrail

struct CityCentersTests {
    private func site(_ id: String, cityId: String?) -> Site {
        let json = """
        {"id":"\(id)","name":"\(id)","type":"church","country":"TR",
         \(cityId.map { "\"cityId\":\"\($0)\"," } ?? "")
         "coordinate":{"lat":0,"lon":0},"importance":"minor"}
        """
        return try! JSONDecoder().decode(Site.self, from: Data(json.utf8))
    }

    @Test func centerIdsKeepsOnlyCitiesAtOrAboveThreshold() {
        let sites = [
            site("1", cityId: "rome"), site("2", cityId: "rome"), site("3", cityId: "rome"),
            site("4", cityId: "pisa"), site("5", cityId: "pisa"),
            site("6", cityId: "areopoli"),
            site("7", cityId: nil),
        ]
        #expect(CityCenters.centerIds(sites: sites) == ["rome"])
    }

    @Test func centerIdsThresholdIsConfigurable() {
        let sites = [site("1", cityId: "pisa"), site("2", cityId: "pisa")]
        #expect(CityCenters.centerIds(sites: sites, threshold: 2) == ["pisa"])
        #expect(CityCenters.centerIds(sites: sites, threshold: 3).isEmpty)
    }

    @Test func selectedNonCentersReturnsBelowThresholdSelections() {
        let centers: Set<String> = ["rome", "ravenna"]
        let selected: Set<String> = ["rome", "areopoli", "mistra"]
        #expect(CityCenters.selectedNonCenters(selected: selected, centers: centers)
                == ["areopoli", "mistra"])
    }

    @Test func selectedNonCentersEmptyWhenAllSelectedAreCenters() {
        #expect(CityCenters.selectedNonCenters(selected: ["rome"],
                                               centers: ["rome", "ravenna"]).isEmpty)
    }
}
```

- [ ] **Step 2: Create the implementation file**

Create `ByzantineTrail/Core/Catalog/CityCenters.swift`:

```swift
import Foundation

/// Derives the catalog's "center" cities — those with enough sites to be worth
/// surfacing as ready-made City filter options. Pure and synchronous so it is
/// trivially testable and cheap to recompute from the loaded catalog.
enum CityCenters {
    /// IDs of cities with at least `threshold` sites in `sites` (nil cityIds ignored).
    static func centerIds(sites: [Site], threshold: Int = 3) -> Set<String> {
        var counts: [String: Int] = [:]
        for site in sites {
            if let cityId = site.cityId { counts[cityId, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value >= threshold }.keys)
    }

    /// Selected city IDs that are NOT centers. The picker pins these in a
    /// "Selected" section so a below-threshold town stays visible and removable.
    static func selectedNonCenters(selected: Set<String>,
                                   centers: Set<String>) -> Set<String> {
        selected.subtracting(centers)
    }
}
```

- [ ] **Step 3: Add `centerCityIds` to CatalogStore**

In `ByzantineTrail/Core/Catalog/CatalogStore.swift`, immediately after the
`cityNamesByID` computed property (currently ending ~line 15), insert:

```swift

    /// City IDs that qualify as "centers" (3+ sites) — the default City filter list.
    var centerCityIds: Set<String> { CityCenters.centerIds(sites: sites) }
```

- [ ] **Step 4: Regenerate the project so new files are in the target**

Run: `~/bin/xcodegen_dist/bin/xcodegen generate`
Expected: `Created project at ByzantineTrail.xcodeproj`

- [ ] **Step 5: Run the tests and verify they pass**

Run: `xcodebuild test -project ByzantineTrail.xcodeproj -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ByzantineTrailTests/CityCentersTests 2>&1 | tail -25`
Expected: `** TEST SUCCEEDED **`, 4 tests passing.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/Catalog/CityCenters.swift ByzantineTrailTests/CityCentersTests.swift ByzantineTrail/Core/Catalog/CatalogStore.swift ByzantineTrail.xcodeproj/project.pbxproj
git -c user.email="6411536+jhoedeman@users.noreply.github.com" -c user.name="John Hoedeman" commit -m "feat(filter): derive center cities (3+ sites) from catalog

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: FilterSummary helper

**Files:**
- Create: `ByzantineTrail/Features/SitesList/FilterSummary.swift`
- Create: `ByzantineTrailTests/FilterSummaryTests.swift`

**Interfaces:**
- Produces: `enum FilterSummary { static func summarize(_ names: [String]) -> String }`
  - `[]` → `""`; `["A"]` → `"A"`; `["A","B"]` → `"A, B"`; 3+ → `"A, B +N"` where N = count − 2.
  - Caller passes names already sorted, so overflow count is deterministic.

- [ ] **Step 1: Write the failing tests**

Create `ByzantineTrailTests/FilterSummaryTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct FilterSummaryTests {
    @Test func emptyGivesEmptyString() {
        #expect(FilterSummary.summarize([]) == "")
    }

    @Test func oneName() {
        #expect(FilterSummary.summarize(["Church"]) == "Church")
    }

    @Test func twoNames() {
        #expect(FilterSummary.summarize(["Church", "Monastery"]) == "Church, Monastery")
    }

    @Test func threeOrMoreAppendsOverflowCount() {
        #expect(FilterSummary.summarize(["Church", "Monastery", "Fortress"])
                == "Church, Monastery +1")
        #expect(FilterSummary.summarize(["A", "B", "C", "D"]) == "A, B +2")
    }
}
```

- [ ] **Step 2: Create the implementation file**

Create `ByzantineTrail/Features/SitesList/FilterSummary.swift`:

```swift
import Foundation

/// One-line summary of a filter dimension's current selection, shown as
/// secondary text on a collapsed filter row. Names are expected pre-sorted so
/// the "+N" overflow is stable.
enum FilterSummary {
    static func summarize(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]), \(names[1])"
        default: return "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }
}
```

- [ ] **Step 3: Regenerate the project**

Run: `~/bin/xcodegen_dist/bin/xcodegen generate`
Expected: `Created project at ByzantineTrail.xcodeproj`

- [ ] **Step 4: Run the tests and verify they pass**

Run: `xcodebuild test -project ByzantineTrail.xcodeproj -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ByzantineTrailTests/FilterSummaryTests 2>&1 | tail -25`
Expected: `** TEST SUCCEEDED **`, 4 tests passing.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Features/SitesList/FilterSummary.swift ByzantineTrailTests/FilterSummaryTests.swift ByzantineTrail.xcodeproj/project.pbxproj
git -c user.email="6411536+jhoedeman@users.noreply.github.com" -c user.name="John Hoedeman" commit -m "feat(filter): selection-summary helper for collapsed rows

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: CityFilterPickerView (pushed searchable picker)

**Files:**
- Create: `ByzantineTrail/Features/SitesList/CityFilterPickerView.swift`

**Interfaces:**
- Consumes: `CityCenters.selectedNonCenters(selected:centers:)` (Task 1); `City` (`id`, `name`); `SiteQuery.fold(_:)` (static, existing).
- Produces: `struct CityFilterPickerView: View` with initializer
  `init(selectedCityIds: Binding<Set<String>>, cities: [City], centerCityIds: Set<String>)`.

This task is a SwiftUI view; it is verified by a successful build (the pure
logic it depends on is already tested in Task 1).

- [ ] **Step 1: Create the view**

Create `ByzantineTrail/Features/SitesList/CityFilterPickerView.swift`:

```swift
import SwiftUI

/// Pushed multi-select City picker. Defaults to the catalog's center cities;
/// a search field reveals ALL cities so any town (including single-site ones)
/// can be filtered to. Below-threshold selections stay pinned in "Selected".
struct CityFilterPickerView: View {
    @Binding var selectedCityIds: Set<String>
    let cities: [City]
    let centerCityIds: Set<String>
    @State private var searchText = ""

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
```

- [ ] **Step 2: Regenerate the project**

Run: `~/bin/xcodegen_dist/bin/xcodegen generate`
Expected: `Created project at ByzantineTrail.xcodeproj`

- [ ] **Step 3: Build and verify it compiles**

Run: `xcodebuild build -project ByzantineTrail.xcodeproj -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ByzantineTrail/Features/SitesList/CityFilterPickerView.swift ByzantineTrail.xcodeproj/project.pbxproj
git -c user.email="6411536+jhoedeman@users.noreply.github.com" -c user.name="John Hoedeman" commit -m "feat(filter): searchable City picker (centers + search all)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Rewrite FilterSheetView as collapsible rows + wire it up

**Files:**
- Modify: `ByzantineTrail/Features/SitesList/FilterSheetView.swift` (full rewrite)
- Modify: `ByzantineTrail/Features/SitesList/SitesListView.swift` (the `.sheet` call, ~lines 61-66)

**Interfaces:**
- Consumes: `FilterSummary.summarize(_:)` (Task 2); `CityFilterPickerView(selectedCityIds:cities:centerCityIds:)` (Task 3); `CatalogStore.centerCityIds` and `CatalogStore.cityNamesByID` (Task 1 / existing).
- Produces: `FilterSheetView` initializer gains two parameters —
  `init(filter: Binding<SiteFilter>, allCountryCodes: [String], cities: [City], centerCityIds: Set<String>, cityNamesByID: [String: String], theme: Theme)`.

SwiftUI view integration; verified by a successful build.

- [ ] **Step 1: Rewrite FilterSheetView**

Replace the entire contents of `ByzantineTrail/Features/SitesList/FilterSheetView.swift` with:

```swift
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
        FilterSummary.summarize(filter.types.map(\.displayLabel).sorted())
    }
    private var importanceSummary: String {
        FilterSummary.summarize(filter.importances.map(\.displayLabel).sorted())
    }
    private var countrySummary: String {
        FilterSummary.summarize(filter.countries.map { CountryName.localized($0) }.sorted())
    }
    private var citySummary: String {
        FilterSummary.summarize(filter.cityIds.compactMap { cityNamesByID[$0] }.sorted())
    }
    private var mySitesSummary: String {
        var parts: [String] = []
        if filter.favoritesOnly { parts.append("Favorites") }
        if filter.wantOnly { parts.append("Want to Visit") }
        if filter.visitedOnly { parts.append("Visited") }
        return FilterSummary.summarize(parts)
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
```

- [ ] **Step 2: Update the SitesListView call site**

In `ByzantineTrail/Features/SitesList/SitesListView.swift`, replace the
`.sheet(isPresented: $showingFilter)` block (currently passing
`filter`/`allCountryCodes`/`cities`/`theme`) with:

```swift
            .sheet(isPresented: $showingFilter) {
                FilterSheetView(filter: $filterModel.filter,
                                allCountryCodes: catalogStore.countryCodes,
                                cities: catalogStore.cities,
                                centerCityIds: catalogStore.centerCityIds,
                                cityNamesByID: cityNames,
                                theme: theme)
            }
```

(`cityNames` is already bound earlier in `body` as `catalogStore.cityNamesByID`.)

- [ ] **Step 3: Regenerate the project**

Run: `~/bin/xcodegen_dist/bin/xcodegen generate`
Expected: `Created project at ByzantineTrail.xcodeproj`

- [ ] **Step 4: Build and verify the whole app compiles**

Run: `xcodebuild build -project ByzantineTrail.xcodeproj -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Run the full test suite (nothing regressed)**

Run: `xcodebuild test -project ByzantineTrail.xcodeproj -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25`
Expected: `** TEST SUCCEEDED **` (all existing suites + the two new ones).

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Features/SitesList/FilterSheetView.swift ByzantineTrail/Features/SitesList/SitesListView.swift ByzantineTrail.xcodeproj/project.pbxproj
git -c user.email="6411536+jhoedeman@users.noreply.github.com" -c user.name="John Hoedeman" commit -m "feat(filter): collapsible filter sheet with curated City picker

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Manual verification (after Task 4)

Run the app in the simulator and confirm:
- Filter sheet opens as five short rows; each shows its selection summary when set.
- Type / Importance / Country / My Sites unroll their options in place.
- Tapping City pushes the picker: Centers section lists ~31 cities; searching "areopoli" (or any Mani town) finds it; toggling a searched town, clearing search, shows it under "Selected"; unchecking removes it.
- "Clear all" resets everything; the filter badge count on the Sites toolbar still matches selections.
