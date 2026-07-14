# M5a — Public Ratings Design

**Status:** Approved for planning (2026-07-14)
**Milestone gate (master spec §326):** M5 = CloudKit sync + public ratings. **M5 is decomposed** into M5a (public ratings — this spec), M5b (private-state sync), M5c (suggestions). This spec is M5a only.
**Parent spec:** `docs/superpowers/specs/2026-07-12-byzantine-trail-design.md` (§0.2 self-healing ratings, §0.4 seams, §4 CloudKit, §5.1–5.2, §6).
**Builds on:** M4 (`docs/superpowers/specs/2026-07-14-m4-user-state-design.md`) — `UserStateStore` single `apply` write path, `UserSiteState.myRating` (declared unused in M4, activated here).

## Goal

Let a signed-in user rate any site 1–10, see the community average + count, edit or remove their rating, and scan/sort sites by rating — backed by **real CloudKit** (public database) behind the existing `RatingsServicing` seam, gated on iCloud account availability and connectivity.

## Scope decisions (locked during brainstorming)

1. **Real CloudKit now.** The owner has an Apple Developer account, so M5a builds and integration-tests against the real CloudKit **Development** environment. Mock seams still drive fast, network-free unit tests.
2. **M5 is split; ratings first.** M5b (private-state sync via `CloudKitSyncProvider` + `pendingSync`) and M5c (suggestions) are separate specs/plans.
3. **My-rating dual-write.** On submit, the user's rating is written to the public `Rating` record (shared source of truth) **and** cached locally in `UserSiteState.myRating` via the M4 `apply` choke point (instant/offline display; syncs across devices in M5b).
4. **Batch summary cache.** `RatingsStore` loads all `RatingSummary` records once (≤500) so list rows and rating-sort read synchronously.
5. **Online-only ratings (no outbox in M5a).** Per §5.2 the rating control is disabled with an explainer when signed-out or offline. The §6 queue-and-replay concern belongs to M5b private-state sync, not M5a ratings.
6. **Account-status seam.** A small `AccountStatusProviding` protocol (Mock + CloudKit impl) keeps rating-gating testable without CloudKit. This is a pragmatic addition scoped to M5; the master spec's "four seams" (§0.4) become five.
7. **Deferred out of M5a.** Private sync (M5b), suggestions (M5c), the standalone `Tools/rebuild_summaries.swift` owner rebuild script (the in-app recompute reconcile is the practical self-healer), any rating offline-queue, entitlements/paywall (the §0.3 seam already exists — nothing to build).

## Global constraints (inherited, exact where noted)

- iOS 17+, Swift 6.2, SwiftUI. Swift Testing (`import Testing` / `@Test` / `#expect`) — **not** XCTest.
- XcodeGen: regenerate with the real binary `~/bin/xcodegen_dist/bin/xcodegen generate` (the `xcodegen` symlink silently fails). `.xcodeproj` is git-ignored; path-based sources.
- **All CloudKit code confined to its service classes** (`Core/Ratings/CloudKit*`, `Core/Account/CloudKit*`) — feature/UI code talks only to the protocols and `@Observable` stores.
- **No hardcoded hex in feature code** — colors come from `Theme` semantic tokens. Average uses `theme.ratingDisplay` (Gold); the pip control fills with `theme.ratingDisplay`, empty track `theme.bgCardAlt`.
- CloudKit container `iCloud.com.byzantinetrail.app`; bundle id `com.byzantinetrail.app` (already set). Development environment for M5a.
- **`Rating` records are source of truth; `RatingSummary` is a rebuildable derived cache** (master spec §0.2) — never trusted as authoritative.
- Ratings scale: **integer 1–10**, one editable rating per user per site (master spec §1).
- Owner privacy: commit author uses the GitHub no-reply address; no owner identity in UI or data. No submitter identity beyond the CloudKit `userRecordID` implied by creator-write.
- Accessibility: Dynamic Type; VoiceOver on the rating control (value = current rating, actions to set); `accessibilityIdentifier`s on the control.

## Architecture

```
Core/Ratings/
  RatingsServicing.swift    (existing seam — GROWN, see below)
  RatingMath.swift          pure delta / recompute / reconcile logic (fully unit-tested)
  RatingsStore.swift        @Observable @MainActor — summary + my-rating caches, batch load
  CloudKitRatingsService.swift   real impl (public DB); all CloudKit here
  MockRatingsService.swift  in-memory impl for tests + previews
Core/Account/
  AccountStatus.swift       enum + AccountStatusProviding protocol
  AccountStore.swift        @Observable @MainActor — current status, gates rating control
  CloudKitAccountStatusProvider.swift   CKContainer.accountStatus() + CKAccountChanged
Core/Networking/
  NetworkMonitor.swift      @Observable — NWPathMonitor → isOnline
Features/SiteDetail/
  RatingSection.swift       average + RatingBar + remove + gated explainer
  RatingBar.swift           10-segment pip control (pure pip↔value mapping)
```

Stores (`RatingsStore`, `AccountStore`, `NetworkMonitor`) are created at app root and injected into the environment beside `CatalogStore` / `UserStateStore`. `RatingsStore` is constructed with a `RatingsServicing` (production: `CloudKitRatingsService`; tests/previews: `MockRatingsService`). `AccountStore` with an `AccountStatusProviding`.

### Data model — CloudKit public database

Per master spec §4:

- **`Rating`** — recordName `"<siteId>|<userRecordID>"` (deterministic upsert). Fields: `siteId` (String, queryable/indexed), `value` (Int 1–10). Security: **world read, creator write.** Source of truth.
- **`RatingSummary`** — recordName `"summary-<siteId>"`. Fields: `siteId` (String), `count` (Int), `total` (Int). Security: **world read, authenticated write.** Rebuildable derived cache (`average = total / count`).

Record types auto-create on first write in the Development environment; the Dashboard config (indexes, security roles) is documented in `docs/CLOUDKIT_SETUP.md` (§ below) and performed by the owner.

### `RatingsServicing` (grown)

Current seam: `summary(for:)`, `submit(rating:for:)`. Grown to:

```swift
struct SiteRatingState: Equatable, Sendable {
    let summary: RatingSummary?   // aggregate (nil = no ratings yet)
    let mine: Int?                // the caller's own rating, if any
}

protocol RatingsServicing: Sendable {
    /// Aggregate + caller's own rating for one site (one round-trip; reconciles
    /// my-rating cross-device). The summary read also runs the §0.2 reconcile.
    func load(for siteId: String) async throws -> SiteRatingState
    /// Batch-load all summaries for list rows + rating sort.
    func allSummaries() async throws -> [String: RatingSummary]
    /// Upsert the caller's Rating and update the summary; returns the updated summary.
    func submit(rating: Int, for siteId: String) async throws -> RatingSummary
    /// Delete the caller's Rating and update the summary; returns the updated summary.
    func removeRating(for siteId: String) async throws -> RatingSummary
}
```

`RatingSummary` (existing, unchanged): `siteId`, `count`, `total`, computed `average`.

### `RatingMath` (pure)

All correctness logic, no CloudKit:

```swift
enum RatingMath {
    /// Apply a rating change to a summary. old == nil means a new rating.
    static func applyDelta(to summary: RatingSummary, old: Int?, new: Int?) -> RatingSummary
    /// Rebuild a summary from the actual Rating values (the reconcile / self-heal path).
    static func recompute(siteId: String, values: [Int]) -> RatingSummary
    /// True when the delta-maintained summary disagrees with a recompute and
    /// should be overwritten.
    static func needsReconcile(cached: RatingSummary, recomputed: RatingSummary) -> Bool
}
```

`submit`: `applyDelta(old: myOld, new: rating)`; `removeRating`: `applyDelta(old: myOld, new: nil)`. `CloudKitRatingsService` uses `applyDelta` for the fast path (with `CKRecord` change-tag retry) and `recompute` when the change-tag retry is exhausted or `needsReconcile` fires on a `load`.

### `RatingsStore` (`@Observable @MainActor`)

- Caches: `summaries: [String: RatingSummary]`, `myRatings: [String: Int]`.
- `func loadAll()` — calls `service.allSummaries()`, populates `summaries` (best-effort; failure leaves cache empty, rows show no rating). Invoked on first Sites-tab appearance / app launch.
- `func state(for siteId:) -> SiteRatingState` — sync read from cache (drives rows).
- `func refresh(_ siteId:) async` — calls `service.load(for:)`, updates both caches (the detail-open reconcile).
- `func submit(_ rating: Int, for siteId:) async` / `func remove(for siteId:) async` — call the service, update `summaries` + `myRatings` optimistically, and write local myRating via `UserStateStore.setRating(_:for:)` (injected).
- Exposes `summary(for:) -> RatingSummary?` and `myRating(for:) -> Int?` for the row/sort snapshot.

### `UserStateStore.setRating(_:for:)` (M4 store, grown)

New mutation routed through the existing private `apply` choke point:

```swift
func setRating(_ value: Int?, for siteId: String)  // sets myRating; prune-on-empty still applies
```

`UserSiteState.isEmpty` already accounts for `myRating == nil`, so clearing a rating on a site with no other flags prunes the row. `updatedAt` bumps (so M5b will sync it).

### Account + connectivity

- `AccountStatus`: `.available`, `.noAccount`, `.restricted`, `.unknown`.
- `AccountStatusProviding.currentStatus() async -> AccountStatus` + a change stream/notification. `CloudKitAccountStatusProvider` maps `CKAccountStatus` and observes `CKAccountChanged`. `AccountStore` (`@Observable`) refreshes on launch + on change.
- `NetworkMonitor` (`@Observable`, `NWPathMonitor`) → `isOnline`.
- **Rating control enabled iff `accountStore.status == .available` AND `networkMonitor.isOnline`.** Otherwise the control is disabled and a one-line explainer shows ("Sign in to iCloud to rate" / "Connect to the internet to rate"). The average/count still display from cache.

## UI

- **`RatingBar`** — a horizontal row of 10 tappable segments (pips). Filled up to the selected value with `theme.ratingDisplay`; empty track `theme.bgCardAlt`. Tap segment N → rating N. Pure `pipIndex ↔ ratingValue` mapping is unit-tested. Disabled state dims and ignores taps. `accessibilityValue` = "N of 10"; adjustable action increments/decrements.
- **`RatingSection`** (in `SiteDetailView`, above the description) — average `8.4 ★ (127)` using `theme.ratingDisplay`; the `RatingBar`; a "Remove my rating" button when `mine != nil`; the gated explainer when disabled. Writes via `RatingsStore`. On appear, calls `ratingsStore.refresh(site.id)`.
- **Rows** (`SiteRowView`) — append average `8.4 ★ (n)` and a my-rating chip, read from `RatingsStore` (nothing shown when the site has no cached summary / no my-rating). Folded into the row's accessibility label.
- **Sort** (`SortField`) — add `.averageRating` and `.myRating` (display labels "Rating" / "My rating"). `SiteQuery.apply(...)` and its `sorted(...)` grow to accept a **ratings snapshot** (`RatingsSnapshot { summaries: [String: RatingSummary]; myRatings: [String: Int] }`) with a defaulted `.empty`, exactly like the M4 `userState` growth. Sites lacking a summary sort last (descending) / as 0. `SitesListView` passes `ratingsStore`'s snapshot.

## Data flow

```
Launch / Sites tab → RatingsStore.loadAll() → summaries cache
Detail appears → RatingsStore.refresh(siteId) → service.load → summary + mine (reconcile)
User taps pip N → RatingsStore.submit(N, siteId)
    → CloudKitRatingsService.submit → upsert Rating + applyDelta summary (retry/recompute)
    → optimistic cache update + UserStateStore.setRating(N, siteId) (local myRating, updatedAt)
Rows / sort read RatingsStore snapshot (sync)
Account/offline change → AccountStore / NetworkMonitor → RatingSection re-gates
```

## Error handling

- CloudKit failures surface as **non-blocking inline states** (master spec §6): a submit failure reverts the optimistic cache update and shows a brief inline "Couldn't save rating" note; no blocking alert. `CloudKit` retryable errors (`.zoneBusy`, `.requestRateLimited`, change-tag conflicts) retry with backoff inside `CloudKitRatingsService`.
- `loadAll()` / `refresh` failures are silent no-ops that leave the cache as-is (rows simply show no rating) — consistent with the offline-tolerant posture.
- Signed-out / offline is a **gated disabled state**, not an error.

## Testing

- **`RatingMathTests`** — `applyDelta` (new rating, changed rating, removal), `recompute` (0/1/many values, average), `needsReconcile` (agree / disagree). Pure, exhaustive.
- **`RatingsStoreTests`** (vs `MockRatingsService`) — `loadAll` populates cache; `submit` updates summary + myRating optimistically and calls `UserStateStore.setRating`; `remove` clears; `refresh` reconciles; snapshot correctness.
- **`SiteQueryTests`** (extended) — `.averageRating` / `.myRating` sort with a ratings snapshot; empty snapshot leaves order unchanged; no-summary sites sort last.
- **`RatingBarTests`** — pip index ↔ rating value mapping; clamping.
- **Gating logic** — `AccountStore` + `NetworkMonitor` (injected/mock) → control enabled only when available + online.
- **`CloudKitRatingsService`** — integration-verified in the simulator signed into an iCloud (sandbox) account against the Development environment: rate a site → average/count update; change rating → average adjusts; remove → count drops; second run reads persisted values. Its correctness logic is `RatingMath` (unit-tested); the CloudKit I/O wrapper is thin.

## CloudKit setup (`docs/CLOUDKIT_SETUP.md`, owner-manual + doc)

Owner-performed, clearly flagged as manual (not code):

1. Xcode: add the **iCloud** capability with **CloudKit**, container `iCloud.com.byzantinetrail.app`; commit the entitlements file to the target.
2. CloudKit Dashboard (Development): the `Rating` and `RatingSummary` record types (auto-created on first write, or defined explicitly), with `Rating.siteId` **queryable** index; security roles — `Rating`: world read + creator write; `RatingSummary`: world read + authenticated write.
3. Sign the simulator/device into an iCloud sandbox account for integration testing.

The doc mirrors `docs/CATALOG_HOSTING.md`'s owner-guide style. Promotion to Production and the standalone rebuild script are out of scope (later).

## Files

**Create**
- `Core/Ratings/RatingMath.swift`, `Core/Ratings/RatingsStore.swift`, `Core/Ratings/CloudKitRatingsService.swift`, `Core/Ratings/MockRatingsService.swift`
- `Core/Account/AccountStatus.swift`, `Core/Account/AccountStore.swift`, `Core/Account/CloudKitAccountStatusProvider.swift`
- `Core/Networking/NetworkMonitor.swift`
- `Features/SiteDetail/RatingSection.swift`, `Features/SiteDetail/RatingBar.swift`
- `docs/CLOUDKIT_SETUP.md`
- Tests: `RatingMathTests.swift`, `RatingsStoreTests.swift`, `RatingBarTests.swift`, gating tests (+ extend `SiteQueryTests`)
- The app entitlements file (iCloud/CloudKit)

**Modify**
- `Core/Ratings/RatingsServicing.swift` — grow the protocol (`load`, `allSummaries`, `submit -> RatingSummary`, `removeRating`) + `SiteRatingState`
- `Core/UserState/UserStateStore.swift` — add `setRating(_:for:)` via `apply`
- `Core/Catalog/SiteQuery.swift` + `SortField` — `.averageRating` / `.myRating`, ratings-snapshot param (defaulted)
- `Features/SitesList/SiteRowView.swift` — average + my-rating chip
- `Features/SitesList/SitesListView.swift` — pass the ratings snapshot into `apply`; add the two sort cases to the menu
- `Features/SiteDetail/SiteDetailView.swift` — insert `RatingSection`
- `App/ByzantineTrailApp.swift` — construct + inject `RatingsStore`, `AccountStore`, `NetworkMonitor`; wire `CloudKitRatingsService` + `CloudKitAccountStatusProvider`
- `project.yml` — attach the entitlements file (regenerate)

## Non-goals (M5a)

Private-state sync / `CloudKitSyncProvider` / `pendingSync` (M5b), suggestions (M5c), the standalone `Tools/rebuild_summaries.swift` script, rating offline-queue, StoreKit/paywall, Production CloudKit environment, half-point or non-integer ratings.
