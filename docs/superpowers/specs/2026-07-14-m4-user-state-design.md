# M4 — Local User State Design

**Status:** Approved for planning (2026-07-14)
**Milestone gate (master spec §326):** SwiftData favorites / want-to-visit / visited, Profile activity + progress stats — local only, no sync yet.
**Parent spec:** `docs/superpowers/specs/2026-07-12-byzantine-trail-design.md` (§0.1 sync seam, §4 CloudKit, §5.1–5.4, §6).

## Goal

Add per-user site state — **favorite**, **want-to-visit**, **visited** — persisted locally in SwiftData, surfaced on list rows, site detail, and the map, filterable on both tabs, with a Profile activity + progress screen.

## Scope decisions (locked during brainstorming)

1. **No ratings in M4.** `myRating` is declared in the model (schema-ready) but unused: no rating control, no my-rating chip, no my-rating sort. All rating UI + aggregation lands in M5 with CloudKit.
2. **State filtering is in M4.** `SiteFilter.matches` / `SiteQuery.apply` grow their signatures now to accept user-state; three filter toggles reach list + map via the shared `SiteFilterModel`.
3. **Local-only, single choke point.** `UserStateStore` writes SwiftData only — no `RemoteSyncProvider` dependency yet. Every mutation funnels through one private `apply(...)` method so M5 hooks `push`/`pull` there without reshaping the store's public API.
4. **No undo toast.** iOS has no native toast; the "undo toast" wording in master spec §276 is deliberately superseded by **direct manipulation** — the action-row toggles are idempotent and self-reversing (see §4 below).
5. **Profile = activity + progress only.** Account/iCloud, Appearance picker, Suggest-a-site, and About are deferred to M5/polish.

## Global constraints (inherited, verbatim where exact)

- iOS 17+, Swift 6.2, SwiftUI. Swift Testing (`import Testing` / `@Test` / `#expect`) — **not** XCTest.
- XcodeGen: regenerate with the real binary `~/bin/xcodegen_dist/bin/xcodegen generate` (the `xcodegen` symlink silently fails). `.xcodeproj` is git-ignored; path-based sources.
- **SwiftData is the local source of truth, always** (master spec §20).
- No hardcoded hex in feature code — colors come from `Theme` semantic tokens (§5.5). Visited uses the existing `theme.visitedCheck` token (Jade `#2A7A4E` light / `#4AC480` dark, per `docs/COLOR_SYSTEM.md`).
- No CloudKit container, no `NSLocationWhenInUseUsageDescription`, no analytics.
- Accessibility: Dynamic Type, VoiceOver labels on the new controls, `accessibilityIdentifier`s for UI tests.
- Owner privacy: commit author uses the GitHub no-reply address; no owner identity in UI or data.

## Architecture

New module `Core/UserState/`, local SwiftData only. Two primary units plus small value types:

```
Core/UserState/
  UserSiteState.swift       @Model — one row per touched site
  UserStateStore.swift      @Observable — ModelContext wrapper, single apply() choke point
  SiteUserFlags.swift       value struct (isFavorite/wantsToVisit/visited) for one site
  UserStateSnapshot.swift   value struct (three Set<String>) for pure filtering
  VisitedProgress.swift     pure computation for Profile progress stats
```

`UserStateStore` is created at app root and injected into the environment beside `CatalogStore`. The SwiftData `ModelContainer` for `UserSiteState` is configured in `ByzantineTrailApp` (local store, no CloudKit).

### Data model — `UserSiteState`

SwiftData `@Model`, **one row per touched site** (lazy: no row exists until the first flag is set):

| Field | Type | Notes |
|---|---|---|
| `siteId` | `String` | `.unique` attribute |
| `isFavorite` | `Bool` | |
| `wantsToVisit` | `Bool` | |
| `visited` | `Bool` | |
| `myRating` | `Int?` | declared, **unused in M4** (M5) |
| `updatedAt` | `Date` | set on every mutation |

**Prune-on-empty:** a mutation that leaves a row with all three flags `false` and `myRating == nil` deletes the row, so the store holds only meaningful state (no orphan rows).

### `UserStateStore` API

`@Observable final class UserStateStore`:

- **Reads (in-memory, rebuilt on load from SwiftData):**
  - `favoriteIDs`, `wantIDs`, `visitedIDs` : `Set<String>`
  - `flags(for siteId: String) -> SiteUserFlags`
  - `snapshot() -> UserStateSnapshot` (the three sets, for `SiteQuery`)
- **Mutations (all route through private `apply`):**
  - `toggleFavorite(_ siteId: String)`
  - `toggleWant(_ siteId: String)`
  - `toggleVisited(_ siteId: String)` — sets `visited`; **when turning on, also clears `wantsToVisit`**. Returns `Void` (no undo token — see §4).
  - `private func apply(_ mutation: (inout UserSiteState) -> Void, for siteId: String)` — upserts the row, applies the mutation, sets `updatedAt`, prunes if empty, saves the context, and refreshes the in-memory sets. **This is the sole write path; M5 adds sync here.**
- **Aggregates for Profile:**
  - `visitedCount`, `favoriteCount`, `wantCount`
  - `VisitedProgress` breakdowns (see §7)

`SiteUserFlags`: `struct SiteUserFlags: Equatable { var isFavorite, wantsToVisit, visited: Bool }` — the store-free value `SiteFilter` needs.
`UserStateSnapshot`: `struct UserStateSnapshot { let favorites, want, visited: Set<String>; func flags(for:) -> SiteUserFlags }`.

## §4. Behavior: visited clears want — direct manipulation (no toast)

Marking a site visited clears its want-to-visit flag (a visited place is no longer "want to visit"). The reversal is the controls themselves:

- Tapping **Visited** animates the **Want** (bookmark) button de-filling in the same view — that visible state change *is* the feedback.
- If the user didn't want it cleared, they tap the bookmark again to restore it. Toggles are idempotent and directly reversible.

No transient overlay, no undo token, nothing to time out. This is the iOS-native paradigm (direct manipulation) and supersedes the "undo toast" wording in master spec §276.

## §5. Filter growth (the flagged signature change)

- **`SiteFilter`** gains `var favoritesOnly = false`, `var wantOnly = false`, `var visitedOnly = false`. `isEmpty`, `activeCount`, and `clear()` account for them.
- **`matches` grows:** `func matches(_ site: Site, flags: SiteUserFlags) -> Bool`. New clauses AND with the existing type/country/city/importance clauses:
  - `(!favoritesOnly || flags.isFavorite)`
  - `(!wantOnly || flags.wantsToVisit)`
  - `(!visitedOnly || flags.visited)`
  `SiteFilter` stays pure and store-free (takes flags, not the store).
- **`SiteQuery.apply` grows:** `func apply(to sites:, cityNames:, userState: UserStateSnapshot) -> [Site]`, passing `userState.flags(for: site.id)` into `filter.matches`. Still a pure transform; sort pipeline unchanged (no new `SortField` in M4).
- **`FilterSheetView`** gains a **"My Sites"** section with three `Toggle`s bound to the new flags. `SiteFilterModel` is unchanged (it holds a `SiteFilter`); because both tabs read it, the toggles reach list + map together.

Call sites (`SitesListView`, `MapTabView`) read the injected `UserStateStore.snapshot()` and pass it into `apply`.

## §6. UI surfaces

- **Detail action row** (`SiteDetailView`): replace `shareRow` with an HStack — **Favorite** (heart / heart.fill) · **Want** (bookmark / bookmark.fill) · **Visited** (checkmark.circle / checkmark.circle.fill, `theme.visitedCheck` when on) · **Share** (existing `ShareLink`, unchanged). Each button toggles via the store; Visited also clears Want (§4). VoiceOver labels reflect on/off; `accessibilityIdentifier`s on each.
- **Row glyphs** (`SiteRowView`): a trailing glyph cluster showing only the *set* flags — favorite heart, want bookmark, visited Jade check. The row's combined accessibility label appends active state (e.g. "…, favorite, visited").
- **Map badge** (`SiteMarkerView`, `SiteMapView.swift`): when the annotation's site is visited, composite a small Jade `visited-check` badge onto the marker. The visited flag is passed through `SiteAnnotation`; the marker refreshes on state change via the existing per-view refresh path (`SiteMapView.swift:52`), same mechanism as selection.

## §7. Profile — activity + progress only

`ProfileView` (currently a stub) rebuilt as a `NavigationStack` `List`/`Form`:

- **Activity:** three `NavigationLink`s → `FavoritesView` / `WantToVisitView` / `VisitedView`. Each is a filtered site list reusing `SiteRowView` with row→`SiteDetailView` navigation and an **empty state** ("No favorites yet", etc.). Lists derive from `UserStateStore` sets intersected with the catalog.
- **Progress stats** (`ProgressStatsView` + `VisitedProgress`): overall **visited / total** with a Gilded progress bar, plus **per-country** and **per-tier** visited breakdowns. `VisitedProgress` is a pure struct computed from the visited set + catalog (`func compute(visited: Set<String>, sites: [Site]) -> VisitedProgress`), independently testable.

Deferred (not in M4): Account/iCloud status, Appearance picker, Suggest-a-site, About.

## §8. Data flow

```
User taps action → UserStateStore.toggle*  → apply() upserts/prunes UserSiteState, saves,
                                              refreshes favoriteIDs/wantIDs/visitedIDs
   @Observable change →  SiteDetailView action row, SiteRowView glyphs, SiteMarkerView badge,
                         ProfileView activity + progress all update
   SitesListView / MapTabView → SiteQuery.apply(..., userState: store.snapshot())
```

## §9. Error handling

SwiftData save failures are surfaced as a non-blocking inline state and logged; the in-memory sets are only updated after a successful save so UI never diverges from the store. No blocking alerts (master spec §6). Missing catalog (offline first-launch edge) simply yields empty activity lists and 0/0 progress.

## §10. Testing

Swift Testing throughout; store tests use an **in-memory `ModelContainer`**.

- `UserStateStoreTests`: toggle each flag; visited-on clears want; visited-off leaves want cleared; prune-on-empty deletes the row; set maintenance (`favoriteIDs` etc.) matches SwiftData; `updatedAt` advances; snapshot correctness.
- `SiteFilterTests` (extended): each state flag alone and AND-ed with catalog dimensions; `isEmpty`/`activeCount`/`clear` with the new flags.
- `SiteQueryTests` (extended): `apply(..., userState:)` returns the correct subset; empty snapshot = no state constraint.
- `VisitedProgressTests`: zero visited, all visited, per-country and per-tier tallies, unknown-country resilience.
- Accessibility identifiers present on action-row buttons and row glyphs (checked in a lightweight view/UI test).

## §11. Files

**Create**
- `Core/UserState/UserSiteState.swift`
- `Core/UserState/UserStateStore.swift`
- `Core/UserState/SiteUserFlags.swift`
- `Core/UserState/UserStateSnapshot.swift`
- `Core/UserState/VisitedProgress.swift`
- `Features/Profile/FavoritesView.swift`
- `Features/Profile/WantToVisitView.swift`
- `Features/Profile/VisitedView.swift`
- `Features/Profile/ProgressStatsView.swift`
- Tests: `UserStateStoreTests.swift`, `VisitedProgressTests.swift` (+ extensions to `SiteFilterTests`, `SiteQueryTests`)

**Modify**
- `Core/Catalog/SiteFilter.swift` — three flags + `matches(_:flags:)`
- `Core/Catalog/SiteQuery.swift` — `apply(..., userState:)`
- `Features/SitesList/FilterSheetView.swift` — "My Sites" section
- `Features/SitesList/SitesListView.swift` — pass `snapshot()` into `apply`
- `Features/SitesList/SiteRowView.swift` — trailing glyph cluster
- `Features/Map/MapTabView.swift` — pass `snapshot()` into `apply`
- `Features/Map/SiteMapView.swift` — visited badge on `SiteMarkerView`; `SiteAnnotation` carries the visited flag
- `Features/SiteDetail/SiteDetailView.swift` — action row replaces `shareRow`
- `Features/Profile/ProfileView.swift` — activity + progress
- `App/ByzantineTrailApp.swift` — `ModelContainer` for `UserSiteState`, inject `UserStateStore`

## Non-goals (M4)

Ratings (control, chip, sort, aggregation), any CloudKit / sync, Account/iCloud UI, Appearance picker, Suggest-a-site, About, distance-from-me sort. All tracked for M5 or later per the master spec.
