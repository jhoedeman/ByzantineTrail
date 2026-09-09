# Filter Redesign: Collapsible Sheet + Curated City Picker — Design

**Date:** 2026-09-08
**Status:** Approved design, pending spec review
**Scope:** Sites list filter sheet UX only. No sort changes, no catalog content edits.

## Problem

The filter sheet (`FilterSheetView`) renders every dimension's full option set in
one long scrolling `Form`. The worst offender is **City**: the catalog has 281
cities, and **222 of them (79%) have exactly one site**. Scrolling 281 toggles to
find a filter is poor UX, and most of those toggles are single-site towns nobody
deliberately filters to.

Two independent fixes:

1. **The whole sheet scrolls too much.** Collapse each dimension into a tappable
   row that unrolls its options on demand, so the sheet opens as a handful of
   short rows.
2. **The City list is unusably long.** Show only "true centers" by default, but
   let the user search-and-select *any* town, including single-site ones.

Only City is curated. Country (31, all real, a closed memorable set), Type (17
used kinds, a fixed vocabulary), Importance (3), and My Sites (3) are short enough
that collapsing alone makes them immediately usable — they render their full
option set exactly as today, just inside a collapsible row. This decision is
deliberate: curation is only worth it when the honest list is unusably long;
collapse handles everything else.

## Goals

- Filter sheet opens as ~5 short collapsible rows, each showing a one-line
  summary of its current selection.
- City filtering defaults to the ~31 cities with 3+ catalogued sites.
- The user can search all 281 cities and toggle any of them.
- A below-threshold city, once selected, stays visible and removable.
- Zero catalog content changes; the center list is derived at runtime and
  self-maintains as sites are added.

## Non-Goals

- No changes to `SortMenu` or `SiteQuery` sorting.
- No curation/threshold on Country, Type, Importance, or My Sites.
- No country-by-frequency reordering; Country stays alphabetical by localized
  name, as today.
- No removal of unused/empty option toggles (e.g. a `SiteType` with zero sites) —
  out of scope for "just the cities change."
- No change to the main list's `.searchable`, which already matches sites by city
  name and must keep working unchanged.

## The "center" definition

A city is a **center** iff it has **3 or more** sites in the loaded catalog.
Threshold = 3 yields 31 of 281 cities. Derived at runtime; no stored flag.

### New pure helper: `CityCenters`

```swift
enum CityCenters {
    /// IDs of cities with at least `threshold` sites in `sites`.
    /// Pure and synchronous so it is trivially unit-testable.
    static func centerIds(sites: [Site], threshold: Int = 3) -> Set<String>
}
```

Implementation: count `site.cityId` occurrences (ignoring nil), keep keys whose
count `>= threshold`.

### CatalogStore surface

Add one computed property so the sheet and picker share a single source:

```swift
/// City IDs that qualify as "centers" (3+ sites) — the default City filter list.
var centerCityIds: Set<String> { CityCenters.centerIds(sites: sites) }
```

## UI structure

### `FilterSheetView` (rewritten)

Same inputs as today (`@Binding var filter`, `allCountryCodes`, `cities`,
`theme`), plus it needs `centerCityIds` and `cityNamesByID` (pass in from the
call site, which already has `CatalogStore`). A `Form` of collapsible rows:

- **Type** — `DisclosureGroup`, collapsed. Unrolls the existing `SiteType.allCases`
  toggles (unchanged content). Header trailing text = selection summary.
- **Importance** — `DisclosureGroup`. Unrolls Major / Notable / Minor.
- **Country** — `DisclosureGroup`. Unrolls the alphabetical-by-localized-name
  country toggles (unchanged from today).
- **City** — **not** a `DisclosureGroup`. A `NavigationLink` (label + summary)
  pushing `CityFilterPickerView`.
- **My Sites** — `DisclosureGroup`. Unrolls Favorites / Want to Visit / Visited.

All groups collapsed by default on each presentation (no persistence of
expansion state). Toolbar keeps "Clear all" (leading, disabled when
`filter.isEmpty`) and "Done" (trailing).

**Selection summary** (one helper): given the selected values for a dimension and
a display-name closure, produce e.g. `"Church, Monastery +2"` (first one or two
names, then `+N`), or empty string when nothing is selected. Shown as secondary
text in each row's header / link.

### `CityFilterPickerView` (new)

A `.searchable` multi-select screen pushed from the City row.

Inputs: `@Binding var selectedCityIds: Set<String>` (bound to `filter.cityIds`),
`cities: [City]`, `centerCityIds: Set<String>`, `theme`. Local
`@State searchText`.

Body — a `List` whose contents depend on `searchText`:

- **Search empty (default view):**
  - Section **"Selected"** — only shown when at least one selected city is *not*
    a center. Lists those below-threshold selected cities (checked), so they are
    always visible and removable. (Selected centers already appear checked in the
    Centers section, so they are not duplicated here.)
  - Section **"Centers"** — the `centerCityIds` cities, alphabetical by name,
    each a checkable row.
- **Search non-empty:** a single flat list of all `cities` whose name matches,
  using `SiteQuery.fold` (diacritic/case-insensitive) `contains`, alphabetical by
  name, each checkable. No section split while searching.

Rows toggle membership in `selectedCityIds` (reuse the same add/remove-from-Set
binding pattern as today's `membership(_:in:)`). A checkmark (or the existing
`Toggle` style) indicates selection.

Navigation title "City". The pushed screen inherits the sheet's `NavigationStack`.

## Data flow

Unchanged pipeline. `SiteFilter.cityIds` still holds whatever is selected; a
below-threshold ID sits in the set identically to a center ID. `SiteFilter`,
`SiteFilter.matches`, `SiteQuery`, `activeCount`, and the filter badge need **no**
changes — the badge already counts City as one active dimension when `cityIds`
is non-empty.

## Testing

- `CityCentersTests`:
  - `centerIds` with a synthetic `[Site]` returns exactly the cities at/above the
    threshold; excludes below-threshold and nil-cityId sites.
  - Default threshold is 3.
- A view-model-level or logic test for the summary helper (`[]` → "", one → name,
  three+ → `"A, B +1"`).
- Below-threshold-preservation is covered by the picker's "Selected" section
  logic; if extracted into a small pure function
  (`belowThresholdSelected(selected:centers:) -> [String]`), unit-test that it
  returns only selected IDs absent from `centers`.

Existing filter/query tests must continue to pass unchanged.

## Files

- **Create:** `ByzantineTrail/Core/Catalog/CityCenters.swift`
- **Create:** `ByzantineTrail/Features/SitesList/CityFilterPickerView.swift`
- **Create:** `ByzantineTrailTests/CityCentersTests.swift`
- **Modify:** `ByzantineTrail/Features/SitesList/FilterSheetView.swift` (rewrite
  as collapsible rows; City → NavigationLink)
- **Modify:** `ByzantineTrail/Core/Catalog/CatalogStore.swift` (add
  `centerCityIds`)
- **Modify:** `ByzantineTrail/Features/SitesList/SitesListView.swift` (pass
  `centerCityIds` / `cityNamesByID` into `FilterSheetView`)
- **Unchanged:** `SiteFilter.swift`, `SiteQuery.swift`, `SortMenu.swift`,
  `catalog.json`
