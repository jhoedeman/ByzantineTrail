# M4 — Local User State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local (SwiftData) favorite / want-to-visit / visited state, surfaced on rows, detail, and map, filterable across both tabs, with a Profile activity + progress screen.

**Architecture:** A new `Core/UserState/` module owns a SwiftData `@Model` (`UserSiteState`) and an `@Observable @MainActor UserStateStore` whose every mutation routes through one private `apply` choke point (M5 hooks sync there). Pure value types (`SiteUserFlags`, `UserStateSnapshot`, `VisitedProgress`) keep filtering and progress computation store-free and unit-testable. `SiteFilter`/`SiteQuery` grow (with defaulted params) to filter by user state; the shared `SiteFilterModel` carries the toggles to list + map at once. UI is thin SwiftUI over the store, verified in the simulator.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`import Testing`), XcodeGen, iOS 17+.

**Spec:** `docs/superpowers/specs/2026-07-14-m4-user-state-design.md`.

## Global Constraints

- iOS deployment floor **17.0**; Swift 6.2; SwiftUI. Universal (iPhone + iPad).
- Tests use **Swift Testing** (`import Testing` / `@Test` / `#expect`) — **never** XCTest.
- **SwiftData is the local source of truth.** M4 is **local only** — no CloudKit container, no `RemoteSyncProvider` dependency, no sync path built.
- **All mutations route through `UserStateStore.apply`** — the single write path (M5 adds sync there).
- **No ratings in M4.** `UserSiteState.myRating` is declared (schema-ready for M5) but never read or written by any M4 code.
- **No hardcoded hex in feature code.** Colors come from `Theme` semantic tokens. Visited uses `theme.visitedCheck`; the gilded progress bar uses `theme.accentPrimary`.
- Accessibility: Dynamic Type, VoiceOver labels/values on the new controls, `accessibilityIdentifier`s on the detail action buttons.
- XcodeGen: after adding any file, regenerate with the **real binary** `~/bin/xcodegen_dist/bin/xcodegen generate` (NOT the `xcodegen` symlink, which silently fails). Sources are path-based, so files under `ByzantineTrail/` and `ByzantineTrailTests/` are auto-included on regen.
- Build/test destination: `platform=iOS Simulator,name=iPhone 16`.
- Commit author is already the GitHub no-reply address (owner privacy) — do not change git identity.

---

### Task 1: User-state value types

**Files:**
- Create: `ByzantineTrail/Core/UserState/SiteUserFlags.swift`
- Create: `ByzantineTrail/Core/UserState/UserStateSnapshot.swift`
- Test: `ByzantineTrailTests/UserStateSnapshotTests.swift`

**Interfaces:**
- Produces:
  - `struct SiteUserFlags: Equatable { var isFavorite = false; var wantsToVisit = false; var visited = false }`
  - `struct UserStateSnapshot: Equatable` with `let favorites/want/visited: Set<String>`, `static let empty`, `func flags(for siteId: String) -> SiteUserFlags`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/UserStateSnapshotTests.swift`:
```swift
import Testing
@testable import ByzantineTrail

struct UserStateSnapshotTests {
    @Test func emptySnapshotYieldsAllFalseFlags() {
        let flags = UserStateSnapshot.empty.flags(for: "any")
        #expect(flags == SiteUserFlags())
    }

    @Test func flagsReflectMembership() {
        let snap = UserStateSnapshot(favorites: ["a"], want: ["a", "b"], visited: ["c"])
        #expect(snap.flags(for: "a") == SiteUserFlags(isFavorite: true, wantsToVisit: true, visited: false))
        #expect(snap.flags(for: "b") == SiteUserFlags(isFavorite: false, wantsToVisit: true, visited: false))
        #expect(snap.flags(for: "c") == SiteUserFlags(isFavorite: false, wantsToVisit: false, visited: true))
        #expect(snap.flags(for: "z") == SiteUserFlags())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — compile error, `SiteUserFlags` / `UserStateSnapshot` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Core/UserState/SiteUserFlags.swift`:
```swift
/// Per-site user flags for one site. Store-free value type so `SiteFilter` can
/// filter by user state without importing the persistence layer.
struct SiteUserFlags: Equatable {
    var isFavorite = false
    var wantsToVisit = false
    var visited = false
}
```

`ByzantineTrail/Core/UserState/UserStateSnapshot.swift`:
```swift
/// Immutable snapshot of user state across all touched sites, as three id sets.
/// `SiteQuery` takes one of these so filtering stays a pure transform.
struct UserStateSnapshot: Equatable {
    let favorites: Set<String>
    let want: Set<String>
    let visited: Set<String>

    static let empty = UserStateSnapshot(favorites: [], want: [], visited: [])

    func flags(for siteId: String) -> SiteUserFlags {
        SiteUserFlags(isFavorite: favorites.contains(siteId),
                      wantsToVisit: want.contains(siteId),
                      visited: visited.contains(siteId))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/UserStateSnapshotTests 2>&1 | tail -20`
Expected: PASS — 2 tests pass, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/UserState/SiteUserFlags.swift ByzantineTrail/Core/UserState/UserStateSnapshot.swift ByzantineTrailTests/UserStateSnapshotTests.swift
git commit -m "$(cat <<'EOF'
M4 Task 1: user-state value types (SiteUserFlags, UserStateSnapshot)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `UserSiteState` model + `UserStateStore`

**Files:**
- Create: `ByzantineTrail/Core/UserState/UserSiteState.swift`
- Create: `ByzantineTrail/Core/UserState/UserStateStore.swift`
- Test: `ByzantineTrailTests/UserStateStoreTests.swift`

**Interfaces:**
- Consumes: `SiteUserFlags`, `UserStateSnapshot` (Task 1).
- Produces:
  - `@Model final class UserSiteState` with `@Attribute(.unique) var siteId`, `isFavorite/wantsToVisit/visited: Bool`, `myRating: Int?`, `updatedAt: Date`, `var isEmpty: Bool`.
  - `@MainActor @Observable final class UserStateStore`:
    - `init(container: ModelContainer)` — **the store retains the container** (its `mainContext` alone does not keep an in-memory container alive; a discarded container deallocates asynchronously and crashes SwiftData mid-use).
    - `static func makeContainer(inMemory: Bool = false) throws -> ModelContainer`
    - `private(set) var favoriteIDs/wantIDs/visitedIDs: Set<String>`
    - `func flags(for: String) -> SiteUserFlags`, `func snapshot() -> UserStateSnapshot`, `func reload()`
    - `var favoriteCount/wantCount/visitedCount: Int`
    - `func toggleFavorite(_:) / toggleWant(_:) / toggleVisited(_:)`

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/UserStateStoreTests.swift`:
```swift
import Testing
import SwiftData
@testable import ByzantineTrail

@MainActor
struct UserStateStoreTests {
    private func make() throws -> (UserStateStore, ModelContainer) {
        let container = try UserStateStore.makeContainer(inMemory: true)
        return (UserStateStore(container: container), container)
    }

    @Test func toggleFavoriteAddsAndRemoves() throws {
        let (store, _) = try make()
        store.toggleFavorite("a")
        #expect(store.favoriteIDs == ["a"])
        #expect(store.flags(for: "a").isFavorite)
        store.toggleFavorite("a")
        #expect(store.favoriteIDs.isEmpty)
    }

    @Test func markingVisitedClearsWant() throws {
        let (store, _) = try make()
        store.toggleWant("a")
        #expect(store.wantIDs == ["a"])
        store.toggleVisited("a")
        #expect(store.visitedIDs == ["a"])
        #expect(store.wantIDs.isEmpty)   // want cleared by visiting
    }

    @Test func emptyRowIsPruned() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")   // creates the row
        store.toggleFavorite("a")   // back to empty → pruned
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.isEmpty)
    }

    @Test func snapshotReflectsAllSets() throws {
        let (store, _) = try make()
        store.toggleFavorite("a"); store.toggleWant("b"); store.toggleVisited("c")
        let snap = store.snapshot()
        #expect(snap.favorites == ["a"])
        #expect(snap.want == ["b"])
        #expect(snap.visited == ["c"])
    }

    @Test func stateSurvivesReloadOnSameContainer() throws {
        let container = try UserStateStore.makeContainer(inMemory: true)
        let store1 = UserStateStore(container: container)
        store1.toggleVisited("a")
        let store2 = UserStateStore(container: container)
        #expect(store2.visitedIDs == ["a"])
    }

    @Test func counts() throws {
        let (store, _) = try make()
        store.toggleFavorite("a"); store.toggleFavorite("b"); store.toggleVisited("a")
        #expect(store.favoriteCount == 2)
        #expect(store.visitedCount == 1)
        #expect(store.wantCount == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `UserSiteState` / `UserStateStore` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Core/UserState/UserSiteState.swift`:
```swift
import Foundation
import SwiftData

/// Local per-site user state (one row per *touched* site). Rows are created
/// lazily on first flag set and pruned when they carry no state. `myRating` is
/// declared for M5 (ratings) but unused in M4.
@Model
final class UserSiteState {
    @Attribute(.unique) var siteId: String
    var isFavorite: Bool
    var wantsToVisit: Bool
    var visited: Bool
    var myRating: Int?
    var updatedAt: Date

    init(siteId: String, isFavorite: Bool = false, wantsToVisit: Bool = false,
         visited: Bool = false, myRating: Int? = nil, updatedAt: Date = .now) {
        self.siteId = siteId
        self.isFavorite = isFavorite
        self.wantsToVisit = wantsToVisit
        self.visited = visited
        self.myRating = myRating
        self.updatedAt = updatedAt
    }

    /// A row carrying no user state should not persist.
    var isEmpty: Bool { !isFavorite && !wantsToVisit && !visited && myRating == nil }
}
```

`ByzantineTrail/Core/UserState/UserStateStore.swift`:
```swift
import Foundation
import SwiftData
import Observation

/// Local source of truth for per-site user state (favorites / want / visited).
/// Every mutation routes through the single `apply` choke point — M5 hooks
/// `RemoteSyncProvider.push` there without reshaping this API. SwiftData only in M4.
@MainActor
@Observable
final class UserStateStore {
    // Retain the container: its `mainContext` alone does NOT keep an in-memory
    // ModelContainer alive — a dropped container deallocates on a background
    // thread (SQLite teardown) and crashes SwiftData while the context is in use.
    private let container: ModelContainer
    private let context: ModelContext

    // In-memory projections rebuilt from SwiftData; drive @Observable UI updates.
    private(set) var favoriteIDs: Set<String> = []
    private(set) var wantIDs: Set<String> = []
    private(set) var visitedIDs: Set<String> = []

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        reload()
    }

    /// Build the production (on-disk) or an in-memory (test) container.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: UserSiteState.self, configurations: config)
    }

    // MARK: Reads

    func flags(for siteId: String) -> SiteUserFlags {
        SiteUserFlags(isFavorite: favoriteIDs.contains(siteId),
                      wantsToVisit: wantIDs.contains(siteId),
                      visited: visitedIDs.contains(siteId))
    }

    func snapshot() -> UserStateSnapshot {
        UserStateSnapshot(favorites: favoriteIDs, want: wantIDs, visited: visitedIDs)
    }

    var favoriteCount: Int { favoriteIDs.count }
    var wantCount: Int { wantIDs.count }
    var visitedCount: Int { visitedIDs.count }

    // MARK: Mutations (all via `apply`)

    func toggleFavorite(_ siteId: String) { apply(siteId) { $0.isFavorite.toggle() } }
    func toggleWant(_ siteId: String) { apply(siteId) { $0.wantsToVisit.toggle() } }

    /// Marking visited clears want-to-visit (spec §4). Reversal is direct
    /// manipulation — re-tapping the controls — so nothing is returned.
    func toggleVisited(_ siteId: String) {
        apply(siteId) { row in
            row.visited.toggle()
            if row.visited { row.wantsToVisit = false }
        }
    }

    // MARK: The single write path

    private func apply(_ siteId: String, _ mutate: (UserSiteState) -> Void) {
        let row: UserSiteState
        if let found = existing(siteId) {
            row = found
        } else {
            row = UserSiteState(siteId: siteId)
            context.insert(row)
        }
        mutate(row)
        row.updatedAt = .now
        if row.isEmpty { context.delete(row) }
        try? context.save()
        reload()
    }

    private func existing(_ siteId: String) -> UserSiteState? {
        let descriptor = FetchDescriptor<UserSiteState>(
            predicate: #Predicate { $0.siteId == siteId })
        return try? context.fetch(descriptor).first
    }

    /// Rebuild the in-memory id sets from SwiftData.
    func reload() {
        let rows = (try? context.fetch(FetchDescriptor<UserSiteState>())) ?? []
        favoriteIDs = Set(rows.filter(\.isFavorite).map(\.siteId))
        wantIDs = Set(rows.filter(\.wantsToVisit).map(\.siteId))
        visitedIDs = Set(rows.filter(\.visited).map(\.siteId))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/UserStateStoreTests 2>&1 | tail -20`
Expected: PASS — 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/UserState/UserSiteState.swift ByzantineTrail/Core/UserState/UserStateStore.swift ByzantineTrailTests/UserStateStoreTests.swift
git commit -m "$(cat <<'EOF'
M4 Task 2: UserSiteState model + UserStateStore (single apply choke point)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `VisitedProgress` pure computation

**Files:**
- Create: `ByzantineTrail/Core/UserState/VisitedProgress.swift`
- Test: `ByzantineTrailTests/VisitedProgressTests.swift`

**Interfaces:**
- Consumes: `Site`, `Importance` (existing catalog types); `CountryName.localized` (existing).
- Produces:
  - `struct ProgressBucket: Identifiable, Equatable { let id, label: String; let visited, total: Int; var fraction: Double }`
  - `struct VisitedProgress: Equatable { let visited, total: Int; let byCountry, byTier: [ProgressBucket]; var fraction: Double; static func compute(visited: Set<String>, sites: [Site]) -> VisitedProgress }`

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/VisitedProgressTests.swift`:
```swift
import Testing
import Foundation
@testable import ByzantineTrail

struct VisitedProgressTests {
    func site(_ id: String, country: String = "TR", importance: Importance = .major) -> Site {
        let json = """
        {"id":"\(id)","name":"\(id)","type":"church","country":"\(country)",
         "coordinate":{"lat":0,"lon":0},"importance":"\(importance.rawValue)"}
        """
        return try! JSONDecoder().decode(Site.self, from: Data(json.utf8))
    }

    @Test func zeroVisited() {
        let p = VisitedProgress.compute(visited: [], sites: [site("a"), site("b")])
        #expect(p.visited == 0)
        #expect(p.total == 2)
        #expect(p.fraction == 0)
    }

    @Test func allVisited() {
        let sites = [site("a"), site("b")]
        let p = VisitedProgress.compute(visited: ["a", "b"], sites: sites)
        #expect(p.visited == 2)
        #expect(p.fraction == 1)
    }

    @Test func perCountryTally() {
        let sites = [site("a", country: "TR"), site("b", country: "TR"), site("c", country: "IT")]
        let p = VisitedProgress.compute(visited: ["a"], sites: sites)
        #expect(p.byCountry.first { $0.id == "TR" }?.visited == 1)
        #expect(p.byCountry.first { $0.id == "TR" }?.total == 2)
        #expect(p.byCountry.first { $0.id == "IT" }?.visited == 0)
        #expect(p.byCountry.first { $0.id == "IT" }?.total == 1)
    }

    @Test func perTierTallyInFixedOrder() {
        let sites = [site("a", importance: .major), site("b", importance: .minor)]
        let p = VisitedProgress.compute(visited: ["b"], sites: sites)
        #expect(p.byTier.map(\.id) == ["major", "notable", "minor"])
        #expect(p.byTier.first { $0.id == "minor" }?.visited == 1)
        #expect(p.byTier.first { $0.id == "notable" }?.total == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `VisitedProgress` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Core/UserState/VisitedProgress.swift`:
```swift
import Foundation

/// One progress row: how many sites in a bucket are visited.
struct ProgressBucket: Identifiable, Equatable {
    let id: String        // stable key (country code or tier rawValue)
    let label: String     // display label
    let visited: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(visited) / Double(total) }
}

/// Pure visited-progress computation for the Profile screen: overall plus
/// per-country and per-tier breakdowns, from the visited id set + catalog.
struct VisitedProgress: Equatable {
    let visited: Int
    let total: Int
    let byCountry: [ProgressBucket]
    let byTier: [ProgressBucket]

    var fraction: Double { total == 0 ? 0 : Double(visited) / Double(total) }

    static func compute(visited visitedIDs: Set<String>, sites: [Site]) -> VisitedProgress {
        let visitedCount = sites.reduce(into: 0) { $0 += visitedIDs.contains($1.id) ? 1 : 0 }

        // Per country, sorted by localized country name.
        var countryTotals: [String: (visited: Int, total: Int)] = [:]
        for site in sites {
            var e = countryTotals[site.country] ?? (0, 0)
            e.total += 1
            if visitedIDs.contains(site.id) { e.visited += 1 }
            countryTotals[site.country] = e
        }
        let byCountry = countryTotals
            .map { ProgressBucket(id: $0.key, label: CountryName.localized($0.key),
                                  visited: $0.value.visited, total: $0.value.total) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        // Per tier, fixed major → notable → minor order.
        let byTier: [ProgressBucket] = Importance.allCases.map { imp in
            let inTier = sites.filter { $0.importance == imp }
            let v = inTier.reduce(into: 0) { $0 += visitedIDs.contains($1.id) ? 1 : 0 }
            return ProgressBucket(id: imp.rawValue, label: imp.displayLabel,
                                  visited: v, total: inTier.count)
        }

        return VisitedProgress(visited: visitedCount, total: sites.count,
                               byCountry: byCountry, byTier: byTier)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/VisitedProgressTests 2>&1 | tail -20`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/UserState/VisitedProgress.swift ByzantineTrailTests/VisitedProgressTests.swift
git commit -m "$(cat <<'EOF'
M4 Task 3: VisitedProgress pure computation (overall + per country/tier)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Grow `SiteFilter` + `SiteQuery` for state filtering

**Files:**
- Modify: `ByzantineTrail/Core/Catalog/SiteFilter.swift`
- Modify: `ByzantineTrail/Core/Catalog/SiteQuery.swift`
- Test: `ByzantineTrailTests/SiteFilterTests.swift` (extend), `ByzantineTrailTests/SiteQueryTests.swift` (extend)

**Interfaces:**
- Consumes: `SiteUserFlags`, `UserStateSnapshot` (Task 1).
- Produces:
  - `SiteFilter` gains `var favoritesOnly/wantOnly/visitedOnly = false`; `matches(_ site: Site, flags: SiteUserFlags = SiteUserFlags()) -> Bool`.
  - `SiteQuery.apply(to:cityNames:userState: UserStateSnapshot = .empty) -> [Site]`.
- **Defaulted params keep existing call sites (`SitesListView`, `MapTabView`) compiling** until Task 8 wires real state.

- [ ] **Step 1: Write the failing tests**

Add to `ByzantineTrailTests/SiteFilterTests.swift` (reuse the existing `site(_:...)` helper in that struct):
```swift
    @Test func favoritesOnlyMatchesOnlyFavorites() {
        var f = SiteFilter(); f.favoritesOnly = true
        #expect(f.activeCount == 1)
        #expect(!f.isEmpty)
        #expect(f.matches(site("a"), flags: SiteUserFlags(isFavorite: true)))
        #expect(!f.matches(site("b"), flags: SiteUserFlags(isFavorite: false)))
    }

    @Test func stateFlagsAreANDedWithCatalogDimensions() {
        var f = SiteFilter(); f.visitedOnly = true; f.importances = [.major]
        #expect(f.activeCount == 2)
        #expect(f.matches(site("a", importance: .major), flags: SiteUserFlags(visited: true)))
        #expect(!f.matches(site("b", importance: .major), flags: SiteUserFlags(visited: false)))
        #expect(!f.matches(site("c", importance: .minor), flags: SiteUserFlags(visited: true)))
    }

    @Test func defaultFlagsRejectWhenStateFilterActive() {
        var f = SiteFilter(); f.wantOnly = true
        #expect(!f.matches(site("a")))   // default flags = not wanted
    }

    @Test func clearResetsStateFlags() {
        var f = SiteFilter(); f.favoritesOnly = true; f.visitedOnly = true
        f.clear()
        #expect(f.isEmpty)
        #expect(f.activeCount == 0)
    }
```

Add to `ByzantineTrailTests/SiteQueryTests.swift` (reuse the struct's `catalog` fixture + `cityNames`):
```swift
    @Test func applyFiltersByUserState() {
        var q = SiteQuery(); q.filter.favoritesOnly = true
        let snap = UserStateSnapshot(favorites: ["san-vitale"], want: [], visited: [])
        let out = q.apply(to: catalog.sites, cityNames: cityNames, userState: snap)
        #expect(out.map(\.id) == ["san-vitale"])
    }

    @Test func applyWithoutUserStateIgnoresStateFilter() {
        let q = SiteQuery()
        let out = q.apply(to: catalog.sites, cityNames: cityNames)
        #expect(out.count == catalog.sites.count)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `favoritesOnly` / `userState:` unresolved.

- [ ] **Step 3: Grow `SiteFilter`**

Replace the body of `ByzantineTrail/Core/Catalog/SiteFilter.swift` (keep the doc comment) with:
```swift
struct SiteFilter: Equatable {
    var types: Set<SiteType> = []
    var countries: Set<String> = []
    var cityIds: Set<String> = []
    var importances: Set<Importance> = []
    var favoritesOnly = false
    var wantOnly = false
    var visitedOnly = false

    var isEmpty: Bool {
        types.isEmpty && countries.isEmpty && cityIds.isEmpty && importances.isEmpty
        && !favoritesOnly && !wantOnly && !visitedOnly
    }

    /// Number of dimensions with at least one selection (drives the badge count).
    var activeCount: Int {
        (types.isEmpty ? 0 : 1)
        + (countries.isEmpty ? 0 : 1)
        + (cityIds.isEmpty ? 0 : 1)
        + (importances.isEmpty ? 0 : 1)
        + (favoritesOnly ? 1 : 0)
        + (wantOnly ? 1 : 0)
        + (visitedOnly ? 1 : 0)
    }

    mutating func clear() { self = SiteFilter() }

    func matches(_ site: Site, flags: SiteUserFlags = SiteUserFlags()) -> Bool {
        (types.isEmpty || types.contains(site.type))
        && (countries.isEmpty || countries.contains(site.country))
        && (cityIds.isEmpty || (site.cityId.map { cityIds.contains($0) } ?? false))
        && (importances.isEmpty || importances.contains(site.importance))
        && (!favoritesOnly || flags.isFavorite)
        && (!wantOnly || flags.wantsToVisit)
        && (!visitedOnly || flags.visited)
    }
}
```

- [ ] **Step 4: Grow `SiteQuery.apply`**

In `ByzantineTrail/Core/Catalog/SiteQuery.swift`, replace the `apply` method:
```swift
    func apply(to sites: [Site], cityNames: [String: String],
               userState: UserStateSnapshot = .empty) -> [Site] {
        let searched = sites.filter { matchesSearch($0, cityNames: cityNames) }
        let filtered = searched.filter { filter.matches($0, flags: userState.flags(for: $0.id)) }
        return sorted(filtered, cityNames: cityNames)
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/SiteFilterTests -only-testing:ByzantineTrailTests/SiteQueryTests 2>&1 | tail -20`
Expected: PASS — all existing + new tests pass (existing `matches(site("a"))` calls still compile via the default flags).

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/Catalog/SiteFilter.swift ByzantineTrail/Core/Catalog/SiteQuery.swift ByzantineTrailTests/SiteFilterTests.swift ByzantineTrailTests/SiteQueryTests.swift
git commit -m "$(cat <<'EOF'
M4 Task 4: grow SiteFilter/SiteQuery for favorite/want/visited filtering

Defaulted params keep existing call sites compiling; Task 8 wires real state.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: App wiring — SwiftData container + inject `UserStateStore`

**Files:**
- Modify: `ByzantineTrail/App/ByzantineTrailApp.swift`

**Interfaces:**
- Consumes: `UserStateStore.makeContainer()`, `UserStateStore(context:)` (Task 2).
- Produces: `UserStateStore` available in the environment for all views (`@Environment(UserStateStore.self)`).

**No new unit test** — this is app-level integration verified by build + simulator launch (SwiftData's `App`/`Scene` are `@MainActor`, so constructing the `@MainActor` store in `App.init()` is valid). The store's behavior is already covered by Task 2.

- [ ] **Step 1: Add the container + store to the App**

In `ByzantineTrail/App/ByzantineTrailApp.swift`, add `import SwiftData` at the top, and replace the property declarations + add an `init()`:
```swift
import SwiftUI
import SwiftData

@main
struct ByzantineTrailApp: App {
    @State private var catalogStore = CatalogStore()
    @State private var themeManager = ThemeManager()
    @State private var filterModel = SiteFilterModel()
    @State private var userState: UserStateStore

    init() {
        // Local SwiftData store for per-site user state (no CloudKit in M4).
        // Fall back to an in-memory store if the on-disk store can't open, so
        // the app still launches (favorites just won't persist that session).
        let container = (try? UserStateStore.makeContainer())
            ?? (try! UserStateStore.makeContainer(inMemory: true))
        // The store retains this container (see Task 2) — safe to let the local go.
        _userState = State(initialValue: UserStateStore(container: container))
    }
```

- [ ] **Step 2: Inject the store into the environment**

In the same file, add one line to the `RootTabView()` environment chain (next to the other `.environment(...)` calls):
```swift
                .environment(userState)
```
Leave the existing `.task { ... }` catalog-loading block unchanged.

- [ ] **Step 3: Regenerate + build**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full suite to confirm nothing regressed**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/App/ByzantineTrailApp.swift
git commit -m "$(cat <<'EOF'
M4 Task 5: SwiftData container for UserSiteState + inject UserStateStore

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Site detail action row (Favorite / Want / Visited / Share)

**Files:**
- Modify: `ByzantineTrail/Features/SiteDetail/SiteDetailView.swift`

**Interfaces:**
- Consumes: `UserStateStore` from environment (Task 5); `theme.visitedCheck`, `theme.accentPrimary`.
- Produces: an action row replacing the M2 share-only row.

**No new unit test** — SwiftUI glue over already-tested store methods; verified by build + simulator. Accessibility identifiers (`detail.favorite`/`detail.want`/`detail.visited`) are added for future UI tests.

- [ ] **Step 1: Add the store dependency**

In `SiteDetailView`, add below the existing `@Environment` lines:
```swift
    @Environment(UserStateStore.self) private var userState
```

- [ ] **Step 2: Swap the row call**

Change line `shareRow(theme)` (inside `body`) to:
```swift
                    actionRow(theme)
```

- [ ] **Step 3: Replace `shareRow` with the action row**

Delete the existing `shareRow(_:)` method (the one commented "Favorite / Want-to-visit / Visited arrive in M4") and add:
```swift
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
```

- [ ] **Step 4: Regenerate + build**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Simulator check**

Boot the app, open any site's detail. Confirm: Favorite/Want/Visited toggle and stay lit (Visited in Jade); tapping Visited while Want is on clears Want in the same view; Share still opens the share sheet.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Features/SiteDetail/SiteDetailView.swift
git commit -m "$(cat <<'EOF'
M4 Task 6: site detail action row (favorite/want/visited + share)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Row state glyphs

**Files:**
- Modify: `ByzantineTrail/Features/SitesList/SiteRowView.swift`
- Test: `ByzantineTrailTests/SiteRowGlyphTests.swift`

**Interfaces:**
- Consumes: `SiteUserFlags` (Task 1).
- Produces:
  - `struct SiteStateGlyph: Identifiable, Equatable { let id, symbol: String; let colorRole: SiteStateGlyph.ColorRole }` with `enum ColorRole { case accent, visited }`.
  - `extension SiteUserFlags { var rowGlyphs: [SiteStateGlyph] }`.
  - `SiteRowView` gains `var flags: SiteUserFlags = SiteUserFlags()` (defaulted so `SitesListView` still compiles until Task 8).

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/SiteRowGlyphTests.swift`:
```swift
import Testing
@testable import ByzantineTrail

struct SiteRowGlyphTests {
    @Test func noGlyphsWhenNoState() {
        #expect(SiteUserFlags().rowGlyphs.isEmpty)
    }

    @Test func oneGlyphPerActiveFlagInOrder() {
        let all = SiteUserFlags(isFavorite: true, wantsToVisit: true, visited: true)
        #expect(all.rowGlyphs.map(\.id) == ["favorite", "want", "visited"])
    }

    @Test func visitedGlyphUsesVisitedRole() {
        let f = SiteUserFlags(isFavorite: false, wantsToVisit: false, visited: true)
        #expect(f.rowGlyphs.count == 1)
        #expect(f.rowGlyphs[0].colorRole == .visited)
        #expect(f.rowGlyphs[0].symbol == "checkmark.circle.fill")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `rowGlyphs` / `SiteStateGlyph` unresolved.

- [ ] **Step 3: Add the glyph model + row changes**

At the top of `ByzantineTrail/Features/SitesList/SiteRowView.swift` (below `import SwiftUI`), add:
```swift
struct SiteStateGlyph: Identifiable, Equatable {
    enum ColorRole { case accent, visited }
    let id: String
    let symbol: String
    let colorRole: ColorRole
}

extension SiteUserFlags {
    /// Glyphs for the *set* flags only, in a stable favorite→want→visited order.
    var rowGlyphs: [SiteStateGlyph] {
        var out: [SiteStateGlyph] = []
        if isFavorite { out.append(.init(id: "favorite", symbol: "heart.fill", colorRole: .accent)) }
        if wantsToVisit { out.append(.init(id: "want", symbol: "bookmark.fill", colorRole: .accent)) }
        if visited { out.append(.init(id: "visited", symbol: "checkmark.circle.fill", colorRole: .visited)) }
        return out
    }
}
```

Add the property to `SiteRowView` (after `let theme: Theme`):
```swift
    var flags: SiteUserFlags = SiteUserFlags()
```

Replace the trailing `Spacer(minLength: 0)` in `body` with:
```swift
            Spacer(minLength: 0)
            if !flags.rowGlyphs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(flags.rowGlyphs) { g in
                        Image(systemName: g.symbol)
                            .font(.caption)
                            .foregroundStyle(g.colorRole == .visited ? theme.visitedCheck
                                                                      : theme.accentPrimary)
                    }
                }
                .accessibilityHidden(true)   // state is folded into the row's a11y label
            }
```

Add a computed state string (below the `subtitle` property):
```swift
    private var stateA11y: String {
        var parts: [String] = []
        if flags.isFavorite { parts.append("favorite") }
        if flags.wantsToVisit { parts.append("want to visit") }
        if flags.visited { parts.append("visited") }
        return parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
    }
```

Extend the existing `.accessibilityLabel(...)` to append `stateA11y`:
```swift
        .accessibilityLabel("\(site.name), \(site.type.displayLabel), \(site.importance.displayLabel) tier, \(subtitle)\(stateA11y)")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/SiteRowGlyphTests 2>&1 | tail -20`
Expected: PASS — 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Features/SitesList/SiteRowView.swift ByzantineTrailTests/SiteRowGlyphTests.swift
git commit -m "$(cat <<'EOF'
M4 Task 7: row state glyphs (favorite/want/visited) + a11y

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Filter-sheet "My Sites" toggles + wire list & map to user state

**Files:**
- Modify: `ByzantineTrail/Features/SitesList/FilterSheetView.swift`
- Modify: `ByzantineTrail/Features/SitesList/SitesListView.swift`
- Modify: `ByzantineTrail/Features/Map/MapTabView.swift`

**Interfaces:**
- Consumes: `SiteFilter.favoritesOnly/wantOnly/visitedOnly` (Task 4), `UserStateStore.snapshot()/flags(for:)` (Task 2), `SiteRowView(flags:)` (Task 7).
- Produces: state filtering live end-to-end on both tabs (shared `SiteFilterModel`).

**No new unit test** — the filtering logic is covered by Task 4; this task is view wiring, verified by build + simulator.

- [ ] **Step 1: Add the "My Sites" section to the filter sheet**

In `FilterSheetView.body`'s `Form`, add after the existing `Section("City") { ... }`:
```swift
                Section("My Sites") {
                    Toggle("Favorites", isOn: $filter.favoritesOnly)
                    Toggle("Want to Visit", isOn: $filter.wantOnly)
                    Toggle("Visited", isOn: $filter.visitedOnly)
                }
```

- [ ] **Step 2: Wire `SitesListView`**

Add the store dependency (below the other `@Environment` lines):
```swift
    @Environment(UserStateStore.self) private var userState
```
Change the results line to pass the snapshot:
```swift
        let results = activeQuery.apply(to: catalogStore.sites, cityNames: cityNames,
                                        userState: userState.snapshot())
```
Pass flags into the row:
```swift
                    SiteRowView(site: site,
                                cityName: site.cityId.flatMap { cityNames[$0] },
                                theme: theme,
                                flags: userState.flags(for: site.id))
```

- [ ] **Step 3: Wire `MapTabView`**

Add the store dependency (below the other `@Environment` lines):
```swift
    @Environment(UserStateStore.self) private var userState
```
Replace the `filtered`/`annotations` lines with a snapshot-aware version:
```swift
        let snapshot = userState.snapshot()
        let filtered = catalogStore.sites.filter {
            filterModel.filter.matches($0, flags: snapshot.flags(for: $0.id))
        }
        let annotations = SiteAnnotation.annotations(from: filtered)
```

- [ ] **Step 4: Regenerate + build + full suite**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Simulator check**

Favorite a couple of sites. Open Filter → "My Sites" → toggle **Favorites**. Confirm the Sites list narrows to favorites AND the Map narrows to the same set (shared filter), and the filter badge count reflects the toggle.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Features/SitesList/FilterSheetView.swift ByzantineTrail/Features/SitesList/SitesListView.swift ByzantineTrail/Features/Map/MapTabView.swift
git commit -m "$(cat <<'EOF'
M4 Task 8: My Sites filter toggles + wire list/map to user state

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Visited badge on map pins

**Files:**
- Modify: `ByzantineTrail/Features/Map/SiteAnnotation.swift`
- Modify: `ByzantineTrail/Features/Map/SiteMapView.swift`
- Modify: `ByzantineTrail/Features/Map/MapTabView.swift`
- Test: `ByzantineTrailTests/SiteAnnotationTests.swift` (extend)

**Interfaces:**
- Consumes: `UserStateSnapshot.visited` via `MapTabView` (Task 8); `theme.visitedCheck`.
- Produces: `SiteAnnotation.visited` (mutable, so on-screen pins can be updated in place); a Jade check badge on visited markers.

**Note (why the extra sync):** `updateUIView` diffs annotations by `site.id` and keeps existing annotation *objects* for unchanged ids — those hold a stale `visited` value when the flag toggles while the pin stays on-screen. So we make `visited` a `var` and refresh persisted annotations from the fresh data before re-applying the marker style.

- [ ] **Step 1: Write the failing test**

Add to `ByzantineTrailTests/SiteAnnotationTests.swift` (reuse its existing `site(_:)` helper):
```swift
    @Test func annotationsCarryVisitedFlag() {
        let sites = [site("a"), site("b")]
        let anns = SiteAnnotation.annotations(from: sites, visited: ["a"])
        #expect(anns.first { $0.site.id == "a" }?.visited == true)
        #expect(anns.first { $0.site.id == "b" }?.visited == false)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `annotations(from:visited:)` / `.visited` unresolved.

- [ ] **Step 3: Add `visited` to `SiteAnnotation`**

Replace `ByzantineTrail/Features/Map/SiteAnnotation.swift` contents (keep the header doc comment) with:
```swift
import MapKit

/// Map annotation backing one catalog `Site`. Reference type as `MKAnnotation`
/// requires; carries the whole `Site` plus the user's `visited` flag so the
/// delegate can style the marker (tier color + visited badge) and open detail.
final class SiteAnnotation: NSObject, MKAnnotation {
    let site: Site
    /// Mutable so `updateUIView` can refresh a persisted pin when the user
    /// toggles visited while it stays on-screen.
    var visited: Bool
    var coordinate: CLLocationCoordinate2D
    var title: String?

    init(site: Site, visited: Bool = false) {
        self.site = site
        self.visited = visited
        self.coordinate = CLLocationCoordinate2D(latitude: site.coordinate.lat,
                                                 longitude: site.coordinate.lon)
        self.title = site.name
    }

    static func annotations(from sites: [Site], visited: Set<String> = []) -> [SiteAnnotation] {
        sites.map { SiteAnnotation(site: $0, visited: visited.contains($0.id)) }
    }
}
```

- [ ] **Step 4: Pass the visited set from `MapTabView`**

In `MapTabView`, change the annotations line (from Task 8) to:
```swift
        let annotations = SiteAnnotation.annotations(from: filtered, visited: snapshot.visited)
```

- [ ] **Step 5: Render + refresh the badge in `SiteMapView`**

In `SiteMapView.updateUIView`, replace the theme-reapply loop (the `for annotation in map.annotations { ... markerView.apply(theme:) ... }` block) with a version that first syncs `visited` on persisted annotations:
```swift
        // Sync each on-screen annotation's `visited` from the fresh data (its
        // object persists across filter updates), then repaint markers so a
        // theme switch or a visited toggle both take effect.
        let freshByID = Dictionary(annotations.map { ($0.site.id, $0.visited) },
                                   uniquingKeysWith: { a, _ in a })
        for annotation in map.annotations {
            if let existing = annotation as? SiteAnnotation,
               let freshVisited = freshByID[existing.site.id] {
                existing.visited = freshVisited
            }
            if let markerView = map.view(for: annotation) as? SiteMarkerView {
                markerView.apply(theme: theme)
            }
        }
```

In `SiteMarkerView`, add a badge image view and show it when visited. Add the property + init setup and update `apply(theme:)`:
```swift
    private let visitedBadge = UIImageView()
```
At the end of `init(annotation:reuseIdentifier:)` (after `displayPriority = .defaultHigh`):
```swift
        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        visitedBadge.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: cfg)
        visitedBadge.backgroundColor = .white
        visitedBadge.layer.cornerRadius = 8
        visitedBadge.layer.masksToBounds = true
        visitedBadge.isHidden = true
        addSubview(visitedBadge)
```
Replace `apply(theme:)` with:
```swift
    func apply(theme: Theme?) {
        guard let theme, let annotation = annotation as? SiteAnnotation else { return }
        markerTintColor = UIColor(annotation.site.importance.tierColor(theme))
        glyphTintColor = UIColor(Color(hex: Palette.stone950))
        visitedBadge.tintColor = UIColor(theme.visitedCheck)
        visitedBadge.isHidden = !annotation.visited
        visitedBadge.sizeToFit()
        visitedBadge.bounds.size = CGSize(width: 16, height: 16)
        visitedBadge.center = CGPoint(x: bounds.maxX, y: bounds.minY + 2)
    }
```
Also hide the badge on reuse — in `prepareForReuse()` add:
```swift
        visitedBadge.isHidden = true
```

- [ ] **Step 6: Run the annotation test + build**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/SiteAnnotationTests 2>&1 | tail -20
```
Expected: PASS — annotation tests (existing + new) pass.

- [ ] **Step 7: Simulator check**

On the Map, mark a visible site visited (via its detail sheet) and confirm a Jade check badge appears on that pin without re-centering the map; un-visit it and the badge disappears. (Badge offset may need small tuning — adjust the `center` in `apply(theme:)` if it sits off the balloon.)

- [ ] **Step 8: Commit**

```bash
git add ByzantineTrail/Features/Map/SiteAnnotation.swift ByzantineTrail/Features/Map/SiteMapView.swift ByzantineTrail/Features/Map/MapTabView.swift ByzantineTrailTests/SiteAnnotationTests.swift
git commit -m "$(cat <<'EOF'
M4 Task 9: visited badge on map pins (in-place refresh on toggle)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: `ProgressStatsView` + `GildedBar`

**Files:**
- Create: `ByzantineTrail/Features/Profile/ProgressStatsView.swift`

**Interfaces:**
- Consumes: `VisitedProgress`, `ProgressBucket` (Task 3); `theme.accentPrimary`, `theme.bgCardAlt`.
- Produces: `struct ProgressStatsView: View { let progress: VisitedProgress; let theme: Theme }` and `struct GildedBar: View { let fraction: Double; let theme: Theme }`.

**No new unit test** — pure layout over the already-tested `VisitedProgress`; verified by the `#Preview` and in-app in Task 11.

- [ ] **Step 1: Create the view**

`ByzantineTrail/Features/Profile/ProgressStatsView.swift`:
```swift
import SwiftUI

/// Renders a VisitedProgress: overall gilded bar + per-tier and per-country bars.
struct ProgressStatsView: View {
    let progress: VisitedProgress
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            overall
            if progress.byTier.contains(where: { $0.total > 0 }) {
                bucketGroup("By Tier", progress.byTier.filter { $0.total > 0 })
            }
            if !progress.byCountry.isEmpty {
                bucketGroup("By Country", progress.byCountry)
            }
        }
        .padding(.vertical, 4)
    }

    private var overall: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Visited").font(.headline).foregroundStyle(theme.textPrimary)
                Spacer()
                Text("\(progress.visited) / \(progress.total)")
                    .font(.subheadline).foregroundStyle(theme.textSecondary)
            }
            GildedBar(fraction: progress.fraction, theme: theme)
        }
    }

    private func bucketGroup(_ title: String, _ buckets: [ProgressBucket]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textSecondary)
            ForEach(buckets) { b in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(b.label).font(.footnote).foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text("\(b.visited)/\(b.total)").font(.footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                    GildedBar(fraction: b.fraction, theme: theme)
                }
            }
        }
    }
}

/// Thin rounded progress bar in the gilded (gold) accent.
struct GildedBar: View {
    let fraction: Double
    let theme: Theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.bgCardAlt)
                Capsule().fill(theme.accentPrimary)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

#Preview {
    let sample = VisitedProgress(
        visited: 3, total: 10,
        byCountry: [ProgressBucket(id: "TR", label: "Türkiye", visited: 2, total: 5),
                    ProgressBucket(id: "IT", label: "Italy", visited: 1, total: 5)],
        byTier: [ProgressBucket(id: "major", label: "Major", visited: 2, total: 4),
                 ProgressBucket(id: "notable", label: "Notable", visited: 1, total: 3),
                 ProgressBucket(id: "minor", label: "Minor", visited: 0, total: 3)])
    return ProgressStatsView(progress: sample, theme: .chrysos(.dark))
        .padding()
        .background(Theme.chrysos(.dark).bgApp)
}
```

- [ ] **Step 2: Regenerate + build**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ByzantineTrail/Features/Profile/ProgressStatsView.swift
git commit -m "$(cat <<'EOF'
M4 Task 10: ProgressStatsView + GildedBar (overall + per tier/country)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: `UserSiteListView` + Profile rebuild (activity + progress)

**Files:**
- Create: `ByzantineTrail/Features/Profile/UserSiteListView.swift`
- Modify: `ByzantineTrail/Features/Profile/ProfileView.swift`

**Interfaces:**
- Consumes: `UserStateStore` (favorite/want/visited ids + counts), `CatalogStore`, `SiteRowView(flags:)`, `SiteDetailView`, `ProgressStatsView` (Task 10), `VisitedProgress.compute` (Task 3).
- Produces: the M4 Profile screen.

**Design note:** the spec named three near-identical screens (`FavoritesView`/`WantToVisitView`/`VisitedView`). They are DRYed into one reusable `UserSiteListView` parameterized by title/empty-state/id-set — one focused file instead of three duplicates.

**No new unit test** — SwiftUI over already-tested store + progress; verified by build + simulator.

- [ ] **Step 1: Create the reusable list**

`ByzantineTrail/Features/Profile/UserSiteListView.swift`:
```swift
import SwiftUI

/// Reusable list of catalog sites filtered to a set of site ids (favorites,
/// want-to-visit, or visited). Reuses SiteRowView + row→detail navigation.
struct UserSiteListView: View {
    let title: String
    let emptyTitle: String
    let emptySymbol: String
    let siteIDs: Set<String>

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(UserStateStore.self) private var userState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.theme(for: colorScheme)
        let cityNames = catalogStore.cityNamesByID
        let sites = catalogStore.sites
            .filter { siteIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        List(sites) { site in
            NavigationLink {
                SiteDetailView(site: site)
            } label: {
                SiteRowView(site: site,
                            cityName: site.cityId.flatMap { cityNames[$0] },
                            theme: theme,
                            flags: userState.flags(for: site.id))
            }
        }
        .listStyle(.plain)
        .overlay {
            if sites.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
            }
        }
        .navigationTitle(title)
        .background(theme.bgApp)
    }
}
```

- [ ] **Step 2: Rebuild `ProfileView`**

Replace `ByzantineTrail/Features/Profile/ProfileView.swift` with:
```swift
import SwiftUI

struct ProfileView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(UserStateStore.self) private var userState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeManager.theme(for: colorScheme)
        NavigationStack {
            List {
                Section("My Activity") {
                    activityLink("Favorites", systemImage: "heart.fill",
                                 count: userState.favoriteCount, ids: userState.favoriteIDs,
                                 emptyTitle: "No favorites yet", emptySymbol: "heart", theme: theme)
                    activityLink("Want to Visit", systemImage: "bookmark.fill",
                                 count: userState.wantCount, ids: userState.wantIDs,
                                 emptyTitle: "Nothing saved yet", emptySymbol: "bookmark", theme: theme)
                    activityLink("Visited", systemImage: "checkmark.circle.fill",
                                 count: userState.visitedCount, ids: userState.visitedIDs,
                                 emptyTitle: "No visits logged yet", emptySymbol: "checkmark.circle",
                                 theme: theme)
                }

                Section("Progress") {
                    ProgressStatsView(
                        progress: VisitedProgress.compute(visited: userState.visitedIDs,
                                                          sites: catalogStore.sites),
                        theme: theme)
                }
            }
            .navigationTitle("Profile")
            .background(theme.bgApp)
        }
    }

    private func activityLink(_ title: String, systemImage: String, count: Int,
                              ids: Set<String>, emptyTitle: String, emptySymbol: String,
                              theme: Theme) -> some View {
        NavigationLink {
            UserSiteListView(title: title, emptyTitle: emptyTitle,
                             emptySymbol: emptySymbol, siteIDs: ids)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text("\(count)").foregroundStyle(theme.textSecondary)
            }
        }
    }
}
```

- [ ] **Step 3: Regenerate + build + full suite**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Simulator check**

Open Profile. Confirm: the three activity rows show counts; tapping each opens a filtered list (empty state when zero); the Progress section shows overall + per-tier + per-country bars, and marking a site visited elsewhere updates the counts and bars on return.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Features/Profile/UserSiteListView.swift ByzantineTrail/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
M4 Task 11: Profile activity lists + progress (UserSiteListView, ProfileView)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Final verification (after all tasks)

- [ ] Full suite green: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -25` → `** TEST SUCCEEDED **`.
- [ ] Simulator smoke test end-to-end: favorite/want/visited from detail persist across an app relaunch; visited clears want; row glyphs + map badge reflect state; "My Sites" filters narrow both tabs; Profile activity + progress accurate.
- [ ] Confirm no ratings surfaced anywhere (M5), no CloudKit, no location prompt.

## Notes for the executor

- **Build-green discipline:** Tasks 4 and 7 use defaulted parameters so intermediate tasks compile before Task 8 wires real state — do not "clean these up" by removing the defaults; `.empty` / default flags are also used by previews and tests.
- **`myRating` is intentionally unused** in M4 — leave it in the model, do not add UI for it.
- **View tasks (5, 6, 8, 9, 10, 11)** are verified in the simulator, matching the M3 pattern; their underlying logic is unit-tested in the value/store/filter/progress tasks.
