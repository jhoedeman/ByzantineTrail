# M5a — Public Ratings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rate sites 1–10, see the community average + count, edit/remove your rating, and sort by rating — behind the `RatingsServicing` seam, wired to an in-memory mock backend for the buildable/testable milestone, with real `CloudKit` provider code written and an owner-performed activation step.

**Architecture:** Pure `RatingMath` holds all summary delta/recompute logic (fully unit-tested). `RatingsStore` (@Observable) caches summaries and drives the UI via a `RatingsServicing`; `UserStateStore` gains `setRating` (the local my-rating cache, on the M4 `apply` choke point). Account/offline gating goes through a small `AccountStatusProviding` seam + `NetworkMonitor` + pure `RatingGate`. Everything a subagent builds is wired to mocks (no CloudKit entitlement); the real `CloudKitRatingsService`/`CloudKitAccountStatusProvider` are written and build-checked, and activated by the owner.

**Tech Stack:** SwiftUI, SwiftData, CloudKit (owner-activated), Network framework, Swift Testing, XcodeGen, iOS 17+.

**Spec:** `docs/superpowers/specs/2026-07-14-m5a-public-ratings-design.md`.

## Global Constraints

- iOS 17+, Swift 6.2, SwiftUI. Tests use **Swift Testing** (`import Testing` / `@Test` / `#expect`) — **never** XCTest.
- **All CloudKit code confined to `CloudKitRatingsService` / `CloudKitAccountStatusProvider`.** Feature/UI code talks only to protocols and `@Observable` stores.
- **No CloudKit entitlement is added by any subagent task.** Adding the iCloud capability requires the owner's Developer signing team; it is Task 14 (owner-performed). Subagent-built app wires **mock** providers and must build + run in the simulator with no entitlement.
- **`Rating` records are source of truth; `RatingSummary` is a rebuildable derived cache** (spec §0.2) — never trusted as authoritative.
- Ratings scale: **integer 1–10**, one editable rating per user per site.
- **No hardcoded hex** in feature code. Average + filled pips use `theme.ratingDisplay`; empty pip track uses `theme.bgCardAlt`.
- **My-rating is local state:** row chips + rating-sort read the user's own rating from `UserStateStore.myRatings` (all sites, offline); `RatingsStore.refresh` reconciles it from the cloud on detail open. Averages come from `RatingsStore.summaries`.
- CloudKit container `iCloud.com.byzantinetrail.app`; Development environment.
- XcodeGen: regenerate with the **real binary** `~/bin/xcodegen_dist/bin/xcodegen generate` (NOT the `xcodegen` symlink) after adding files.
- Build/test destination: `platform=iOS Simulator,name=iPhone 16`.
- Commit author is already the GitHub no-reply address — do not change git identity.

---

### Task 1: `RatingMath` — pure summary logic

**Files:**
- Create: `ByzantineTrail/Core/Ratings/RatingMath.swift`
- Test: `ByzantineTrailTests/RatingMathTests.swift`

**Interfaces:**
- Consumes: `RatingSummary` (existing, in `Core/Ratings/RatingsServicing.swift`).
- Produces: `enum RatingMath` with `applyDelta(to:old:new:) -> RatingSummary`, `recompute(siteId:values:) -> RatingSummary`, `needsReconcile(cached:recomputed:) -> Bool`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/RatingMathTests.swift`:
```swift
import Testing
@testable import ByzantineTrail

struct RatingMathTests {
    private func summary(_ count: Int, _ total: Int) -> RatingSummary {
        RatingSummary(siteId: "s", count: count, total: total)
    }

    @Test func applyDeltaNewRating() {
        let out = RatingMath.applyDelta(to: summary(2, 14), old: nil, new: 8)
        #expect(out.count == 3)
        #expect(out.total == 22)
    }

    @Test func applyDeltaChangedRating() {
        let out = RatingMath.applyDelta(to: summary(3, 22), old: 8, new: 5)
        #expect(out.count == 3)      // count unchanged when editing
        #expect(out.total == 19)     // 22 - 8 + 5
    }

    @Test func applyDeltaRemoval() {
        let out = RatingMath.applyDelta(to: summary(3, 22), old: 8, new: nil)
        #expect(out.count == 2)
        #expect(out.total == 14)
    }

    @Test func applyDeltaRemovalNeverGoesNegative() {
        let out = RatingMath.applyDelta(to: summary(0, 0), old: 8, new: nil)
        #expect(out.count == 0)
        #expect(out.total == 0)
    }

    @Test func recomputeFromValues() {
        let out = RatingMath.recompute(siteId: "s", values: [8, 6, 10])
        #expect(out.count == 3)
        #expect(out.total == 24)
        #expect(out.average == 8.0)
    }

    @Test func recomputeEmpty() {
        let out = RatingMath.recompute(siteId: "s", values: [])
        #expect(out.count == 0)
        #expect(out.average == 0)
    }

    @Test func needsReconcileDetectsDrift() {
        #expect(RatingMath.needsReconcile(cached: summary(3, 22), recomputed: summary(3, 24)))
        #expect(!RatingMath.needsReconcile(cached: summary(3, 24), recomputed: summary(3, 24)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `RatingMath` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Core/Ratings/RatingMath.swift`:
```swift
/// Pure summary arithmetic for public ratings (spec §0.2). `Rating` records are
/// the source of truth; `RatingSummary` is this rebuildable derived cache.
enum RatingMath {
    /// Apply a rating change to a summary. `old == nil` = a brand-new rating;
    /// `new == nil` = a removal. Editing (both non-nil) leaves `count` unchanged.
    static func applyDelta(to summary: RatingSummary, old: Int?, new: Int?) -> RatingSummary {
        var count = summary.count
        var total = summary.total
        if old == nil, let new { count += 1; total += new }          // new rating
        else if let old, new == nil { count -= 1; total -= old }      // removal
        else if let old, let new { total += new - old }               // edit
        return RatingSummary(siteId: summary.siteId,
                             count: max(0, count), total: max(0, total))
    }

    /// Rebuild a summary from the actual rating values (self-heal / reconcile).
    static func recompute(siteId: String, values: [Int]) -> RatingSummary {
        RatingSummary(siteId: siteId, count: values.count, total: values.reduce(0, +))
    }

    /// True when the delta-maintained cache disagrees with a fresh recompute.
    static func needsReconcile(cached: RatingSummary, recomputed: RatingSummary) -> Bool {
        cached.count != recomputed.count || cached.total != recomputed.total
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/RatingMathTests 2>&1 | tail -20`
Expected: PASS — 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Ratings/RatingMath.swift ByzantineTrailTests/RatingMathTests.swift
git commit -m "$(cat <<'EOF'
M5a Task 1: RatingMath pure summary delta/recompute/reconcile logic

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Grow `RatingsServicing` + `SiteRatingState` + `MockRatingsService`

**Files:**
- Modify: `ByzantineTrail/Core/Ratings/RatingsServicing.swift`
- Create: `ByzantineTrail/Core/Ratings/MockRatingsService.swift`
- Test: `ByzantineTrailTests/MockRatingsServiceTests.swift`

**Interfaces:**
- Consumes: `RatingMath` (Task 1), `RatingSummary` (existing).
- Produces:
  - `struct SiteRatingState: Equatable, Sendable { let summary: RatingSummary?; let mine: Int? }`
  - `RatingsServicing` reshaped: `load(for:) async throws -> SiteRatingState`, `allSummaries() async throws -> [String: RatingSummary]`, `submit(rating:for:) async throws -> RatingSummary`, `removeRating(for:) async throws -> RatingSummary`.
  - `actor MockRatingsService: RatingsServicing` with `init(seed: [String: RatingSummary] = [:])`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/MockRatingsServiceTests.swift`:
```swift
import Testing
@testable import ByzantineTrail

struct MockRatingsServiceTests {
    @Test func submitFromEmptyCreatesRating() async throws {
        let svc = MockRatingsService()
        let summary = try await svc.submit(rating: 8, for: "s")
        #expect(summary.count == 1)
        #expect(summary.total == 8)
        let state = try await svc.load(for: "s")
        #expect(state.mine == 8)
        #expect(state.summary?.count == 1)
    }

    @Test func resubmitEditsWithoutInflatingCount() async throws {
        let svc = MockRatingsService()
        _ = try await svc.submit(rating: 8, for: "s")
        let summary = try await svc.submit(rating: 5, for: "s")
        #expect(summary.count == 1)
        #expect(summary.total == 5)
        #expect(try await svc.load(for: "s").mine == 5)
    }

    @Test func removeClearsMineAndDecrements() async throws {
        let svc = MockRatingsService()
        _ = try await svc.submit(rating: 8, for: "s")
        let summary = try await svc.removeRating(for: "s")
        #expect(summary.count == 0)
        #expect(try await svc.load(for: "s").mine == nil)
    }

    @Test func submitStacksOnSeededOthers() async throws {
        let svc = MockRatingsService(seed: ["s": RatingSummary(siteId: "s", count: 2, total: 14)])
        let summary = try await svc.submit(rating: 10, for: "s")
        #expect(summary.count == 3)     // 2 seeded others + me
        #expect(summary.total == 24)
    }

    @Test func allSummariesReturnsSeeded() async throws {
        let svc = MockRatingsService(seed: ["a": RatingSummary(siteId: "a", count: 1, total: 9)])
        let all = try await svc.allSummaries()
        #expect(all["a"]?.total == 9)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — new protocol methods / `MockRatingsService` / `SiteRatingState` unresolved.

- [ ] **Step 3: Grow the protocol**

Replace `ByzantineTrail/Core/Ratings/RatingsServicing.swift` with:
```swift
struct RatingSummary: Equatable, Sendable {
    let siteId: String
    let count, total: Int
    var average: Double { count == 0 ? 0 : Double(total) / Double(count) }
}

/// Aggregate + the caller's own rating for one site.
struct SiteRatingState: Equatable, Sendable {
    let summary: RatingSummary?
    let mine: Int?
}

/// Public-ratings backend seam. `Rating` records are source of truth;
/// `RatingSummary` is a rebuildable derived cache (spec §0.2).
protocol RatingsServicing: Sendable {
    /// Aggregate + the caller's own rating (one round-trip; runs the reconcile).
    func load(for siteId: String) async throws -> SiteRatingState
    /// All summaries for list rows + rating sort.
    func allSummaries() async throws -> [String: RatingSummary]
    /// Upsert the caller's rating; returns the updated summary.
    func submit(rating: Int, for siteId: String) async throws -> RatingSummary
    /// Delete the caller's rating; returns the updated summary.
    func removeRating(for siteId: String) async throws -> RatingSummary
}
```

- [ ] **Step 4: Write the mock**

`ByzantineTrail/Core/Ratings/MockRatingsService.swift`:
```swift
/// In-memory `RatingsServicing` for tests, previews, and the pre-CloudKit app
/// wiring. `seed` models *other users'* ratings so averages look realistic;
/// the caller's own rating is tracked separately and layered on via RatingMath.
actor MockRatingsService: RatingsServicing {
    private var others: [String: RatingSummary]
    private var mine: [String: Int] = [:]

    init(seed: [String: RatingSummary] = [:]) { self.others = seed }

    private func base(_ siteId: String) -> RatingSummary {
        others[siteId] ?? RatingSummary(siteId: siteId, count: 0, total: 0)
    }

    private func combined(_ siteId: String) -> RatingSummary {
        RatingMath.applyDelta(to: base(siteId), old: nil, new: mine[siteId])
    }

    func load(for siteId: String) async throws -> SiteRatingState {
        let s = combined(siteId)
        return SiteRatingState(summary: s.count == 0 ? nil : s, mine: mine[siteId])
    }

    func allSummaries() async throws -> [String: RatingSummary] {
        var out: [String: RatingSummary] = [:]
        for id in Set(others.keys).union(mine.keys) { out[id] = combined(id) }
        return out
    }

    func submit(rating: Int, for siteId: String) async throws -> RatingSummary {
        mine[siteId] = rating
        return combined(siteId)
    }

    func removeRating(for siteId: String) async throws -> RatingSummary {
        mine[siteId] = nil
        return combined(siteId)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/MockRatingsServiceTests 2>&1 | tail -20`
Expected: PASS — 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/Ratings/RatingsServicing.swift ByzantineTrail/Core/Ratings/MockRatingsService.swift ByzantineTrailTests/MockRatingsServiceTests.swift
git commit -m "$(cat <<'EOF'
M5a Task 2: grow RatingsServicing seam + SiteRatingState + MockRatingsService

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `UserStateStore.setRating` + local my-rating cache

**Files:**
- Modify: `ByzantineTrail/Core/UserState/UserStateStore.swift`
- Test: `ByzantineTrailTests/UserStateStoreTests.swift` (extend)

**Interfaces:**
- Consumes: `UserSiteState` (existing; `myRating: Int?` already declared, `isEmpty` already checks `myRating == nil`).
- Produces: `UserStateStore.setRating(_ value: Int?, for siteId: String)`, `private(set) var myRatings: [String: Int]`, `func myRating(for siteId: String) -> Int?`.

- [ ] **Step 1: Write the failing test**

Add to `ByzantineTrailTests/UserStateStoreTests.swift` (reuse its `make()` helper):
```swift
    @Test func setRatingStoresAndClears() throws {
        let (store, _) = try make()
        store.setRating(8, for: "s")
        #expect(store.myRating(for: "s") == 8)
        #expect(store.myRatings == ["s": 8])
        store.setRating(nil, for: "s")
        #expect(store.myRating(for: "s") == nil)
        #expect(store.myRatings.isEmpty)
    }

    @Test func clearingRatingOnBareRowPrunesIt() throws {
        let (store, container) = try make()
        store.setRating(7, for: "s")   // creates a row with only a rating
        store.setRating(nil, for: "s") // row now empty → pruned
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.isEmpty)
    }

    @Test func ratingCoexistsWithFlags() throws {
        let (store, _) = try make()
        store.toggleFavorite("s")
        store.setRating(9, for: "s")
        #expect(store.favoriteIDs == ["s"])
        #expect(store.myRating(for: "s") == 9)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `setRating` / `myRatings` / `myRating(for:)` unresolved.

- [ ] **Step 3: Add the my-rating cache + mutation**

In `ByzantineTrail/Core/UserState/UserStateStore.swift`, add a stored property beside the id sets:
```swift
    private(set) var myRatings: [String: Int] = [:]
```
Add a read below `flags(for:)`:
```swift
    func myRating(for siteId: String) -> Int? { myRatings[siteId] }
```
Add a mutation in the "Mutations (all via `apply`)" section:
```swift
    /// The user's own rating for a site (the public Rating is the shared source
    /// of truth; this is the local cache — instant, offline, synced in M5b).
    func setRating(_ value: Int?, for siteId: String) {
        apply(siteId) { $0.myRating = value }
    }
```
In `reload()`, populate `myRatings` alongside the id sets:
```swift
        myRatings = Dictionary(uniqueKeysWithValues:
            rows.compactMap { row in row.myRating.map { (row.siteId, $0) } })
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/UserStateStoreTests 2>&1 | tail -20`
Expected: PASS — existing + 3 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/UserState/UserStateStore.swift ByzantineTrailTests/UserStateStoreTests.swift
git commit -m "$(cat <<'EOF'
M5a Task 3: UserStateStore.setRating + local my-rating cache (via apply)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `RatingsStore`

**Files:**
- Create: `ByzantineTrail/Core/Ratings/RatingsStore.swift`
- Test: `ByzantineTrailTests/RatingsStoreTests.swift`

**Interfaces:**
- Consumes: `RatingsServicing` + `MockRatingsService` (Task 2), `UserStateStore` (Task 3), `RatingSummary`.
- Produces: `@MainActor @Observable final class RatingsStore` with `init(service: any RatingsServicing, userState: UserStateStore)`, `private(set) var summaries: [String: RatingSummary]`, `func loadAll() async`, `func summary(for:) -> RatingSummary?`, `func refresh(_:) async`, `func submit(_:for:) async`, `func remove(for:) async`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/RatingsStoreTests.swift`:
```swift
import Testing
import SwiftData
@testable import ByzantineTrail

@MainActor
struct RatingsStoreTests {
    private func make(seed: [String: RatingSummary] = [:]) throws -> (RatingsStore, UserStateStore) {
        let container = try UserStateStore.makeContainer(inMemory: true)
        let userState = UserStateStore(container: container)
        let store = RatingsStore(service: MockRatingsService(seed: seed), userState: userState)
        return (store, userState)
    }

    @Test func loadAllPopulatesSummaries() async throws {
        let (store, _) = try make(seed: ["a": RatingSummary(siteId: "a", count: 2, total: 16)])
        await store.loadAll()
        #expect(store.summary(for: "a")?.average == 8.0)
    }

    @Test func submitUpdatesSummaryAndLocalMyRating() async throws {
        let (store, userState) = try make()
        await store.submit(8, for: "s")
        #expect(store.summary(for: "s")?.total == 8)
        #expect(userState.myRating(for: "s") == 8)   // dual-write to local cache
    }

    @Test func removeClearsSummaryAndLocalMyRating() async throws {
        let (store, userState) = try make()
        await store.submit(8, for: "s")
        await store.remove(for: "s")
        #expect(userState.myRating(for: "s") == nil)
        #expect(store.summary(for: "s")?.count == 0)
    }

    @Test func refreshReconcilesLocalMyRatingFromCloud() async throws {
        // Service already has a rating for the site (e.g. from another device);
        // local cache is empty until refresh pulls it.
        let (store, userState) = try make()
        await store.submit(6, for: "s")           // now service.mine[s] = 6
        userState.setRating(nil, for: "s")        // simulate local drift
        await store.refresh("s")
        #expect(userState.myRating(for: "s") == 6) // reconciled from cloud
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `RatingsStore` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Core/Ratings/RatingsStore.swift`:
```swift
import Observation

/// Observable cache over a `RatingsServicing`. Holds community summaries for
/// rows/sort; the user's own rating lives in `UserStateStore` (local, all sites),
/// which this store writes on submit and reconciles from the cloud on refresh.
@MainActor
@Observable
final class RatingsStore {
    private let service: any RatingsServicing
    private let userState: UserStateStore

    private(set) var summaries: [String: RatingSummary] = [:]

    init(service: any RatingsServicing, userState: UserStateStore) {
        self.service = service
        self.userState = userState
    }

    func summary(for siteId: String) -> RatingSummary? { summaries[siteId] }

    /// Batch-load every summary (rows + sort). Failure leaves the cache as-is.
    func loadAll() async {
        if let all = try? await service.allSummaries() { summaries = all }
    }

    /// Detail-open reconcile: refresh one site's summary and pull my cloud rating
    /// into the local cache (covers a rating made on another device).
    func refresh(_ siteId: String) async {
        guard let state = try? await service.load(for: siteId) else { return }
        if let summary = state.summary { summaries[siteId] = summary }
        if userState.myRating(for: siteId) != state.mine {
            userState.setRating(state.mine, for: siteId)
        }
    }

    func submit(_ rating: Int, for siteId: String) async {
        guard let summary = try? await service.submit(rating: rating, for: siteId) else { return }
        summaries[siteId] = summary
        userState.setRating(rating, for: siteId)
    }

    func remove(for siteId: String) async {
        guard let summary = try? await service.removeRating(for: siteId) else { return }
        summaries[siteId] = summary
        userState.setRating(nil, for: siteId)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/RatingsStoreTests 2>&1 | tail -20`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Ratings/RatingsStore.swift ByzantineTrailTests/RatingsStoreTests.swift
git commit -m "$(cat <<'EOF'
M5a Task 4: RatingsStore (summary cache + dual-write + cloud reconcile)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Account status — seam, mock, store

**Files:**
- Create: `ByzantineTrail/Core/Account/AccountStatus.swift`
- Create: `ByzantineTrail/Core/Account/AccountStore.swift`
- Test: `ByzantineTrailTests/AccountStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum AccountStatus: Equatable, Sendable { case available, noAccount, restricted, unknown }`
  - `protocol AccountStatusProviding: Sendable { func currentStatus() async -> AccountStatus }`
  - `struct MockAccountStatusProvider: AccountStatusProviding { let status: AccountStatus }`
  - `@MainActor @Observable final class AccountStore` with `init(provider:)`, `private(set) var status: AccountStatus`, `func refresh() async`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/AccountStoreTests.swift`:
```swift
import Testing
@testable import ByzantineTrail

@MainActor
struct AccountStoreTests {
    @Test func startsUnknownThenRefreshes() async {
        let store = AccountStore(provider: MockAccountStatusProvider(status: .available))
        #expect(store.status == .unknown)
        await store.refresh()
        #expect(store.status == .available)
    }

    @Test func reflectsNoAccount() async {
        let store = AccountStore(provider: MockAccountStatusProvider(status: .noAccount))
        await store.refresh()
        #expect(store.status == .noAccount)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `AccountStatus` / `AccountStore` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Core/Account/AccountStatus.swift`:
```swift
/// iCloud account availability for gating ratings (spec §5.2). CloudKit is one
/// provider; a mock drives tests without an Apple Developer account.
enum AccountStatus: Equatable, Sendable {
    case available, noAccount, restricted, unknown
}

protocol AccountStatusProviding: Sendable {
    func currentStatus() async -> AccountStatus
}

struct MockAccountStatusProvider: AccountStatusProviding {
    let status: AccountStatus
    func currentStatus() async -> AccountStatus { status }
}
```

`ByzantineTrail/Core/Account/AccountStore.swift`:
```swift
import Observation

/// Observable iCloud account status. Starts `.unknown`; `refresh()` queries the
/// provider (call on launch and on CloudKit's account-changed notification).
@MainActor
@Observable
final class AccountStore {
    private let provider: any AccountStatusProviding
    private(set) var status: AccountStatus = .unknown

    init(provider: any AccountStatusProviding) { self.provider = provider }

    func refresh() async { status = await provider.currentStatus() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/AccountStoreTests 2>&1 | tail -20`
Expected: PASS — 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Account/AccountStatus.swift ByzantineTrail/Core/Account/AccountStore.swift ByzantineTrailTests/AccountStoreTests.swift
git commit -m "$(cat <<'EOF'
M5a Task 5: account-status seam + AccountStore (mock-driven, testable)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `NetworkMonitor` + `RatingGate`

**Files:**
- Create: `ByzantineTrail/Core/Networking/NetworkMonitor.swift`
- Create: `ByzantineTrail/Core/Ratings/RatingGate.swift`
- Test: `ByzantineTrailTests/RatingGateTests.swift`

**Interfaces:**
- Consumes: `AccountStatus` (Task 5).
- Produces:
  - `@MainActor @Observable final class NetworkMonitor` with `private(set) var isOnline: Bool` (starts `true`).
  - `enum RatingGate` with `static func evaluate(status: AccountStatus, isOnline: Bool) -> RatingGateState`, and `struct RatingGateState: Equatable { let isEnabled: Bool; let explainer: String? }`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/RatingGateTests.swift`:
```swift
import Testing
@testable import ByzantineTrail

struct RatingGateTests {
    @Test func enabledWhenAvailableAndOnline() {
        let g = RatingGate.evaluate(status: .available, isOnline: true)
        #expect(g.isEnabled)
        #expect(g.explainer == nil)
    }

    @Test func signedOutExplainer() {
        for status in [AccountStatus.noAccount, .restricted, .unknown] {
            let g = RatingGate.evaluate(status: status, isOnline: true)
            #expect(!g.isEnabled)
            #expect(g.explainer == "Sign in to iCloud to rate.")
        }
    }

    @Test func offlineExplainerWhenAvailable() {
        let g = RatingGate.evaluate(status: .available, isOnline: false)
        #expect(!g.isEnabled)
        #expect(g.explainer == "Connect to the internet to rate.")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `RatingGate` / `NetworkMonitor` unresolved.

- [ ] **Step 3: Write `RatingGate`**

`ByzantineTrail/Core/Ratings/RatingGate.swift`:
```swift
/// Pure gating for the rating control (spec §5.2): account must be available AND
/// online. Account check takes precedence over connectivity.
enum RatingGate {
    struct RatingGateState: Equatable {
        let isEnabled: Bool
        let explainer: String?
    }

    static func evaluate(status: AccountStatus, isOnline: Bool) -> RatingGateState {
        guard status == .available else {
            return .init(isEnabled: false, explainer: "Sign in to iCloud to rate.")
        }
        guard isOnline else {
            return .init(isEnabled: false, explainer: "Connect to the internet to rate.")
        }
        return .init(isEnabled: true, explainer: nil)
    }
}
```

- [ ] **Step 4: Write `NetworkMonitor`**

`ByzantineTrail/Core/Networking/NetworkMonitor.swift`:
```swift
import Observation
import Network

/// Observable connectivity. Starts optimistic (`isOnline == true`) so the UI
/// isn't briefly gated before the first path update arrives.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/RatingGateTests 2>&1 | tail -20`
Expected: PASS — 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/Networking/NetworkMonitor.swift ByzantineTrail/Core/Ratings/RatingGate.swift ByzantineTrailTests/RatingGateTests.swift
git commit -m "$(cat <<'EOF'
M5a Task 6: NetworkMonitor + pure RatingGate (account+online gating)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `RatingBar` pip control

**Files:**
- Create: `ByzantineTrail/Features/SiteDetail/RatingBar.swift`
- Test: `ByzantineTrailTests/RatingBarTests.swift`

**Interfaces:**
- Consumes: `Theme`.
- Produces: `struct RatingBar: View` (`value: Int?`, `isEnabled: Bool`, `theme: Theme`, `onSelect: (Int) -> Void`), plus a pure `enum RatingScale` with `count = 10`, `func isFilled(segment:for:) -> Bool`, `func rating(forSegment:) -> Int`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/RatingBarTests.swift`:
```swift
import Testing
@testable import ByzantineTrail

struct RatingBarTests {
    @Test func tenSegments() { #expect(RatingScale.count == 10) }

    @Test func segmentMapsToOneBasedRating() {
        #expect(RatingScale.rating(forSegment: 0) == 1)
        #expect(RatingScale.rating(forSegment: 9) == 10)
    }

    @Test func fillsUpToValue() {
        #expect(RatingScale.isFilled(segment: 0, for: 3))   // rating 1 ≤ 3
        #expect(RatingScale.isFilled(segment: 2, for: 3))   // rating 3 ≤ 3
        #expect(!RatingScale.isFilled(segment: 3, for: 3))  // rating 4 > 3
    }

    @Test func nothingFilledForNil() {
        #expect(!RatingScale.isFilled(segment: 0, for: nil))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `RatingScale` / `RatingBar` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Features/SiteDetail/RatingBar.swift`:
```swift
import SwiftUI

/// Pure pip↔value mapping for the 1–10 rating bar.
enum RatingScale {
    static let count = 10
    static func rating(forSegment index: Int) -> Int { index + 1 }
    static func isFilled(segment index: Int, for value: Int?) -> Bool {
        guard let value else { return false }
        return rating(forSegment: index) <= value
    }
}

/// A row of 10 tappable segments; filled up to `value`. Disabled state dims and
/// ignores taps. Colors are theme tokens (no hardcoded hex).
struct RatingBar: View {
    let value: Int?
    let isEnabled: Bool
    let theme: Theme
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<RatingScale.count, id: \.self) { index in
                let filled = RatingScale.isFilled(segment: index, for: value)
                Capsule()
                    .fill(filled ? theme.ratingDisplay : theme.bgCardAlt)
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { if isEnabled { onSelect(RatingScale.rating(forSegment: index)) } }
                    .accessibilityHidden(true)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel("Your rating")
        .accessibilityValue(value.map { "\($0) of 10" } ?? "Not rated")
        .accessibilityIdentifier("detail.ratingBar")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let current = value ?? 0
            switch direction {
            case .increment: onSelect(min(RatingScale.count, current + 1))
            case .decrement: onSelect(max(1, current - 1))
            @unknown default: break
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/RatingBarTests 2>&1 | tail -20`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Features/SiteDetail/RatingBar.swift ByzantineTrailTests/RatingBarTests.swift
git commit -m "$(cat <<'EOF'
M5a Task 7: RatingBar 10-segment pip control + pure RatingScale mapping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `RatingSection` on site detail

**Files:**
- Create: `ByzantineTrail/Features/SiteDetail/RatingSection.swift`
- Modify: `ByzantineTrail/Features/SiteDetail/SiteDetailView.swift`

**Interfaces:**
- Consumes: `RatingsStore`, `AccountStore`, `NetworkMonitor`, `UserStateStore` (environment), `RatingBar` (Task 7), `RatingGate` (Task 6).
- Produces: `struct RatingSection: View` (`site: Site`, `theme: Theme`).

**No new unit test** — SwiftUI over already-tested stores/gate; gate = build + simulator (against the mock service wired in Task 11). Accessibility identifiers added for later UI tests.

- [ ] **Step 1: Create `RatingSection`**

`ByzantineTrail/Features/SiteDetail/RatingSection.swift`:
```swift
import SwiftUI

/// Average + your 1–10 rating bar + remove + a gated explainer (spec §5.2).
struct RatingSection: View {
    let site: Site
    let theme: Theme

    @Environment(RatingsStore.self) private var ratingsStore
    @Environment(UserStateStore.self) private var userState
    @Environment(AccountStore.self) private var accountStore
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        let gate = RatingGate.evaluate(status: accountStore.status, isOnline: network.isOnline)
        let mine = userState.myRating(for: site.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rating").font(.headline).foregroundStyle(theme.textPrimary)
                Spacer()
                averageLabel
            }
            RatingBar(value: mine, isEnabled: gate.isEnabled, theme: theme) { rating in
                Task { await ratingsStore.submit(rating, for: site.id) }
            }
            HStack {
                if let explainer = gate.explainer {
                    Text(explainer).font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if mine != nil, gate.isEnabled {
                    Button("Remove my rating") {
                        Task { await ratingsStore.remove(for: site.id) }
                    }
                    .font(.caption)
                    .tint(theme.accentPrimary)
                    .accessibilityIdentifier("detail.removeRating")
                }
            }
        }
        .task(id: site.id) { await ratingsStore.refresh(site.id) }
    }

    @ViewBuilder private var averageLabel: some View {
        if let summary = ratingsStore.summary(for: site.id), summary.count > 0 {
            Text("\(summary.average, specifier: "%.1f") ★ (\(summary.count))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ratingDisplay)
        } else {
            Text("No ratings yet").font(.caption).foregroundStyle(theme.textSecondary)
        }
    }
}
```

- [ ] **Step 2: Insert into `SiteDetailView`**

In `ByzantineTrail/Features/SiteDetail/SiteDetailView.swift`, add `RatingSection` between `actionRow(theme)` and the `Divider()`:
```swift
                    header(theme)
                    actionRow(theme)
                    RatingSection(site: site, theme: theme)
                    Divider()
```

- [ ] **Step 3: Regenerate + build**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (Full app run happens in Task 11 once the stores are injected; this task only needs to compile.)

- [ ] **Step 4: Commit**

```bash
git add ByzantineTrail/Features/SiteDetail/RatingSection.swift ByzantineTrail/Features/SiteDetail/SiteDetailView.swift
git commit -m "$(cat <<'EOF'
M5a Task 8: RatingSection (average + rating bar + remove + gated explainer)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: `RatingsSnapshot` + rating sort in `SiteQuery`

**Files:**
- Create: `ByzantineTrail/Core/Ratings/RatingsSnapshot.swift`
- Modify: `ByzantineTrail/Core/Catalog/SiteQuery.swift`
- Test: `ByzantineTrailTests/SiteQueryTests.swift` (extend)

**Interfaces:**
- Consumes: `RatingSummary`.
- Produces:
  - `struct RatingsSnapshot: Equatable { let summaries: [String: RatingSummary]; let myRatings: [String: Int]; static let empty; func average(for:) -> Double?; func mine(for:) -> Int? }`
  - `SortField` gains `.averageRating`, `.myRating`.
  - `SiteQuery.apply(to:cityNames:userState:ratings:)` with `ratings: RatingsSnapshot = .empty`.

- [ ] **Step 1: Write the failing tests**

Add to `ByzantineTrailTests/SiteQueryTests.swift` (reuse the `catalog` fixture + `cityNames`):
```swift
    @Test func sortByAverageRatingDescendingPutsHighestFirst() {
        var q = SiteQuery(); q.sortField = .averageRating; q.ascending = false
        let ratings = RatingsSnapshot(
            summaries: ["hagia-sophia": RatingSummary(siteId: "hagia-sophia", count: 1, total: 9),
                        "san-vitale": RatingSummary(siteId: "san-vitale", count: 1, total: 6)],
            myRatings: [:])
        let out = q.apply(to: catalog.sites, cityNames: cityNames, ratings: ratings)
        #expect(out.first?.id == "hagia-sophia")     // 9.0 before 6.0
        #expect(out.last?.id != "hagia-sophia")       // unrated sites sort after rated
    }

    @Test func sortByMyRatingUsesSnapshotMyRatings() {
        var q = SiteQuery(); q.sortField = .myRating; q.ascending = false
        let ratings = RatingsSnapshot(summaries: [:], myRatings: ["mystras": 10])
        let out = q.apply(to: catalog.sites, cityNames: cityNames, ratings: ratings)
        #expect(out.first?.id == "mystras")
    }

    @Test func ratingSortWithEmptySnapshotIsStableByName() {
        var q = SiteQuery(); q.sortField = .averageRating; q.ascending = false
        let out = q.apply(to: catalog.sites, cityNames: cityNames)   // ratings defaults to .empty
        #expect(out.count == catalog.sites.count)   // no crash; all unrated → name tie-break
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `.averageRating` / `ratings:` unresolved.

- [ ] **Step 3: Write `RatingsSnapshot`**

`ByzantineTrail/Core/Ratings/RatingsSnapshot.swift`:
```swift
/// Immutable rating data for the pure `SiteQuery` sort — community averages plus
/// the user's own ratings. Assembled by the view from RatingsStore + UserStateStore.
struct RatingsSnapshot: Equatable {
    let summaries: [String: RatingSummary]
    let myRatings: [String: Int]

    static let empty = RatingsSnapshot(summaries: [:], myRatings: [:])

    func average(for siteId: String) -> Double? {
        guard let s = summaries[siteId], s.count > 0 else { return nil }
        return s.average
    }
    func mine(for siteId: String) -> Int? { myRatings[siteId] }
}
```

- [ ] **Step 4: Grow `SortField` + `SiteQuery`**

In `ByzantineTrail/Core/Catalog/SiteQuery.swift`, add the two cases and labels:
```swift
enum SortField: String, CaseIterable, Identifiable {
    case name, importance, country, city, averageRating, myRating
    var id: String { rawValue }
    var displayLabel: String {
        switch self {
        case .name: "Name"
        case .importance: "Importance"
        case .country: "Country"
        case .city: "City"
        case .averageRating: "Rating"
        case .myRating: "My rating"
        }
    }
}
```
Change `apply` to take the ratings snapshot and pass it into `sorted`:
```swift
    func apply(to sites: [Site], cityNames: [String: String],
               userState: UserStateSnapshot = .empty,
               ratings: RatingsSnapshot = .empty) -> [Site] {
        let searched = sites.filter { matchesSearch($0, cityNames: cityNames) }
        let filtered = searched.filter { filter.matches($0, flags: userState.flags(for: $0.id)) }
        return sorted(filtered, cityNames: cityNames, ratings: ratings)
    }
```
Change `sorted`'s signature and add the two cases (unrated sorts as -1 so it lands last when descending):
```swift
    private func sorted(_ sites: [Site], cityNames: [String: String],
                        ratings: RatingsSnapshot) -> [Site] {
        let asc = sites.sorted { a, b in
            switch sortField {
            case .name:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .importance:
                return a.importance.rank != b.importance.rank
                    ? a.importance.rank < b.importance.rank
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .country:
                let ca = CountryName.localized(a.country), cb = CountryName.localized(b.country)
                return ca != cb
                    ? ca.localizedCaseInsensitiveCompare(cb) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .city:
                let ca = a.cityId.flatMap { cityNames[$0] } ?? ""
                let cb = b.cityId.flatMap { cityNames[$0] } ?? ""
                return ca != cb
                    ? ca.localizedCaseInsensitiveCompare(cb) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .averageRating:
                let ra = ratings.average(for: a.id) ?? -1, rb = ratings.average(for: b.id) ?? -1
                return ra != rb ? ra < rb
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .myRating:
                let ra = ratings.mine(for: a.id) ?? -1, rb = ratings.mine(for: b.id) ?? -1
                return ra != rb ? ra < rb
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
        return ascending ? asc : asc.reversed()
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/SiteQueryTests 2>&1 | tail -20`
Expected: PASS — existing + 3 new tests pass.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/Ratings/RatingsSnapshot.swift ByzantineTrail/Core/Catalog/SiteQuery.swift ByzantineTrailTests/SiteQueryTests.swift
git commit -m "$(cat <<'EOF'
M5a Task 9: RatingsSnapshot + averageRating/myRating sort in SiteQuery

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Row average + my-rating chip; list wiring

**Files:**
- Modify: `ByzantineTrail/Features/SitesList/SiteRowView.swift`
- Modify: `ByzantineTrail/Features/SitesList/SitesListView.swift`

**Interfaces:**
- Consumes: `RatingSummary`, `RatingsStore` + `UserStateStore` (environment), `RatingsSnapshot` (Task 9).
- Produces: `SiteRowView` gains `var average: Double? = nil` and `var myRating: Int? = nil` (defaulted so nothing else breaks); `SitesListView` passes the ratings snapshot into `apply` and per-row values.

**No new unit test** — the sort/query logic is covered by Task 9; this is view wiring, verified by build + simulator (Task 11 runs the full app).

- [ ] **Step 1: Add rating display to `SiteRowView`**

In `ByzantineTrail/Features/SitesList/SiteRowView.swift`, add two defaulted properties after `var flags`:
```swift
    var average: Double? = nil
    var myRating: Int? = nil
```
Insert a rating line into the row's inner `VStack` — after the existing type/importance `HStack` (the one containing `importanceBadge`), still inside that `VStack(alignment: .leading, spacing: 3)`:
```swift
                if average != nil || myRating != nil {
                    HStack(spacing: 6) {
                        if let average {
                            Text("\(average, specifier: "%.1f") ★")
                                .font(.caption)
                                .foregroundStyle(theme.ratingDisplay)
                        }
                        if let myRating {
                            Text("me \(myRating)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(theme.ratingDisplay.opacity(0.18), in: Capsule())
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                }
```
(Rows show the average glyph only; the rating *count* lives on the detail screen.)

Append rating state to the accessibility label — change the `.accessibilityLabel(...)` to include a rating clause by extending `stateA11y` usage; add a computed `ratingA11y`:
```swift
    private var ratingA11y: String {
        var parts: [String] = []
        if let average { parts.append("average \(String(format: "%.1f", average))") }
        if let myRating { parts.append("your rating \(myRating)") }
        return parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
    }
```
and append `\(ratingA11y)` at the end of the existing `.accessibilityLabel("…\(stateA11y)")` string → `"…\(stateA11y)\(ratingA11y)"`.

- [ ] **Step 2: Wire `SitesListView`**

In `ByzantineTrail/Features/SitesList/SitesListView.swift`, add the store dependency (beside the others):
```swift
    @Environment(RatingsStore.self) private var ratingsStore
```
Build the ratings snapshot and pass it into `apply`, and pass per-row values. Replace the `results` line:
```swift
        let ratingsSnapshot = RatingsSnapshot(summaries: ratingsStore.summaries,
                                              myRatings: userState.myRatings)
        let results = activeQuery.apply(to: catalogStore.sites, cityNames: cityNames,
                                        userState: userState.snapshot(),
                                        ratings: ratingsSnapshot)
```
Update the `SiteRowView(...)` construction to pass rating values:
```swift
                    SiteRowView(site: site,
                                cityName: site.cityId.flatMap { cityNames[$0] },
                                theme: theme,
                                flags: userState.flags(for: site.id),
                                average: ratingsSnapshot.average(for: site.id),
                                myRating: ratingsSnapshot.mine(for: site.id))
```
Kick a batch load once when the list appears — add to the `.onAppear` block (which already sets sort fields):
```swift
        .task { await ratingsStore.loadAll() }
```

- [ ] **Step 3: Regenerate + build**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ByzantineTrail/Features/SitesList/SiteRowView.swift ByzantineTrail/Features/SitesList/SitesListView.swift
git commit -m "$(cat <<'EOF'
M5a Task 10: row average + my-rating chip; list passes ratings snapshot

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: App wiring (mock providers) + inject stores

**Files:**
- Modify: `ByzantineTrail/App/ByzantineTrailApp.swift`

**Interfaces:**
- Consumes: `RatingsStore` (Task 4), `AccountStore` (Task 5), `NetworkMonitor` (Task 6), `MockRatingsService` (Task 2), `MockAccountStatusProvider` (Task 5).
- Produces: the three stores injected into the environment; ratings fully functional against the mock service in the simulator.

**No new unit test** — integration verified by build + full suite + simulator (ratings against the mock). This is the milestone's end-to-end checkpoint.

- [ ] **Step 1: Construct + inject the stores**

In `ByzantineTrail/App/ByzantineTrailApp.swift`, add the three stored properties beside `userState`:
```swift
    @State private var ratingsStore: RatingsStore
    @State private var accountStore: AccountStore
    @State private var network = NetworkMonitor()
```
In `init()`, after building `userState`'s container/store, construct the ratings + account stores. **CloudKit is activated by the owner in Task 14 — until then the app wires the mock service** (with a seed so averages look real), and a mock account provider reporting `.available` so the control is usable in the sim:
```swift
        let store = UserStateStore(container: container)
        _userState = State(initialValue: store)

        // Pre-CloudKit wiring (owner flips to CloudKit in Task 14 / CLOUDKIT_SETUP.md).
        let ratingsService = MockRatingsService(seed: MockRatingsSeed.demo)
        _ratingsStore = State(initialValue: RatingsStore(service: ratingsService, userState: store))
        _accountStore = State(initialValue: AccountStore(
            provider: MockAccountStatusProvider(status: .available)))
```
Add the three `.environment(...)` calls to the `RootTabView()` chain:
```swift
                .environment(userState)
                .environment(ratingsStore)
                .environment(accountStore)
                .environment(network)
```
Refresh the account store on launch — add to the existing `.task { ... }`, at the top:
```swift
                    await accountStore.refresh()
```

- [ ] **Step 2: Add the demo seed**

Create the seed used above — append to `ByzantineTrail/Core/Ratings/MockRatingsService.swift`:
```swift
/// Deterministic seed of "other users'" ratings so the mock-backed app shows
/// realistic averages before CloudKit is activated. Keyed by the bundled sites.
enum MockRatingsSeed {
    static let demo: [String: RatingSummary] = [
        "hagia-sophia": RatingSummary(siteId: "hagia-sophia", count: 128, total: 1180),
        "basilica-cistern": RatingSummary(siteId: "basilica-cistern", count: 74, total: 651),
        "san-vitale": RatingSummary(siteId: "san-vitale", count: 53, total: 489),
        "mystras": RatingSummary(siteId: "mystras", count: 27, total: 232),
    ]
}
```
(These ids match the bundled catalog; sites not listed simply show "No ratings yet" until rated.)

- [ ] **Step 3: Regenerate + build + full suite**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Simulator check**

Boot the app. Open a bundled site's detail: confirm the average shows (e.g. Hagia Sophia ≈ 9.2 ★ (128)), tap a pip to rate → the bar fills, the count/average update, and a "Remove my rating" button appears; remove → clears. Back in the Sites list: the average glyph + "me N" chip show on rated rows; Sort → "Rating" / "My rating" reorder the list. (Account is mock-`.available`, so the control is enabled.)

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/App/ByzantineTrailApp.swift ByzantineTrail/Core/Ratings/MockRatingsService.swift
git commit -m "$(cat <<'EOF'
M5a Task 11: wire RatingsStore/AccountStore/NetworkMonitor (mock backend)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: `CloudKitRatingsService` (write + build-check)

**Files:**
- Create: `ByzantineTrail/Core/Ratings/CloudKitRatingsService.swift`

**Interfaces:**
- Consumes: `RatingsServicing`, `RatingMath`, `RatingSummary`, `SiteRatingState`.
- Produces: `final class CloudKitRatingsService: RatingsServicing`.

**No unit test** — its correctness logic is `RatingMath` (already unit-tested); the CloudKit I/O is thin and integration-verified by the owner in Task 14. Gate for this task: **compiles clean** (`import CloudKit` needs no entitlement to build).

- [ ] **Step 1: Write the implementation**

`ByzantineTrail/Core/Ratings/CloudKitRatingsService.swift`:
```swift
import CloudKit

/// Real public-database ratings backend (spec §0.2, §4). `Rating` records are the
/// source of truth; `RatingSummary` is a delta-maintained, recomputable cache.
/// All CloudKit is confined to this file. Activated by the owner (CLOUDKIT_SETUP.md).
final class CloudKitRatingsService: RatingsServicing {
    private let db: CKDatabase
    private let container: CKContainer

    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        container = CKContainer(identifier: containerID)
        db = container.publicCloudDatabase
    }

    private func summaryRecordID(_ siteId: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "summary-\(siteId)")
    }
    private func ratingRecordID(_ siteId: String, _ user: CKRecord.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(siteId)|\(user.recordName)")
    }

    private func summary(from record: CKRecord?, siteId: String) -> RatingSummary {
        RatingSummary(siteId: siteId,
                      count: (record?["count"] as? Int) ?? 0,
                      total: (record?["total"] as? Int) ?? 0)
    }

    // MARK: RatingsServicing

    func load(for siteId: String) async throws -> SiteRatingState {
        let userID = try await container.userRecordID()
        async let summaryRec = try? db.record(for: summaryRecordID(siteId))
        async let mineRec = try? db.record(for: ratingRecordID(siteId, userID))
        let cached = summary(from: await summaryRec, siteId: siteId)
        let mine = (await mineRec)?["value"] as? Int
        // Reconcile: recompute from the actual Rating records; overwrite on drift.
        let reconciled = try await reconcile(siteId: siteId, cached: cached)
        return SiteRatingState(summary: reconciled.count == 0 ? nil : reconciled, mine: mine)
    }

    func allSummaries() async throws -> [String: RatingSummary] {
        let query = CKQuery(recordType: "RatingSummary", predicate: NSPredicate(value: true))
        let (results, _) = try await db.records(matching: query)
        var out: [String: RatingSummary] = [:]
        for (_, result) in results {
            if let rec = try? result.get(), let siteId = rec["siteId"] as? String {
                out[siteId] = summary(from: rec, siteId: siteId)
            }
        }
        return out
    }

    func submit(rating: Int, for siteId: String) async throws -> RatingSummary {
        let userID = try await container.userRecordID()
        let ratingID = ratingRecordID(siteId, userID)
        let old = (try? await db.record(for: ratingID))?["value"] as? Int
        let ratingRec = CKRecord(recordType: "Rating", recordID: ratingID)
        ratingRec["siteId"] = siteId as CKRecordValue
        ratingRec["value"] = rating as CKRecordValue
        _ = try await db.save(ratingRec)
        return try await updateSummary(siteId: siteId, old: old, new: rating)
    }

    func removeRating(for siteId: String) async throws -> RatingSummary {
        let userID = try await container.userRecordID()
        let ratingID = ratingRecordID(siteId, userID)
        let old = (try? await db.record(for: ratingID))?["value"] as? Int
        if old != nil { _ = try? await db.deleteRecord(withID: ratingID) }
        return try await updateSummary(siteId: siteId, old: old, new: nil)
    }

    // MARK: Summary maintenance (delta fast-path + change-tag retry + recompute)

    private func updateSummary(siteId: String, old: Int?, new: Int?) async throws -> RatingSummary {
        for _ in 0..<3 {
            let existing = try? await db.record(for: summaryRecordID(siteId))
            let current = summary(from: existing, siteId: siteId)
            let next = RatingMath.applyDelta(to: current, old: old, new: new)
            let rec = existing ?? CKRecord(recordType: "RatingSummary", recordID: summaryRecordID(siteId))
            rec["siteId"] = siteId as CKRecordValue
            rec["count"] = next.count as CKRecordValue
            rec["total"] = next.total as CKRecordValue
            do { _ = try await db.save(rec); return next }
            catch let error as CKError where error.code == .serverRecordChanged { continue }
        }
        // Retry exhausted → authoritative recompute from Rating records.
        return try await reconcile(siteId: siteId, cached: summary(from: nil, siteId: siteId), force: true)
    }

    /// Recompute the summary from the actual Rating records and overwrite the cache
    /// when it has drifted (self-heal, spec §0.2). Returns the trustworthy summary.
    private func reconcile(siteId: String, cached: RatingSummary, force: Bool = false) async throws -> RatingSummary {
        let query = CKQuery(recordType: "Rating",
                            predicate: NSPredicate(format: "siteId == %@", siteId))
        let (results, _) = try await db.records(matching: query)
        let values = results.compactMap { try? $0.1.get()["value"] as? Int }.compactMap { $0 }
        let recomputed = RatingMath.recompute(siteId: siteId, values: values)
        if force || RatingMath.needsReconcile(cached: cached, recomputed: recomputed) {
            let rec = (try? await db.record(for: summaryRecordID(siteId)))
                ?? CKRecord(recordType: "RatingSummary", recordID: summaryRecordID(siteId))
            rec["siteId"] = siteId as CKRecordValue
            rec["count"] = recomputed.count as CKRecordValue
            rec["total"] = recomputed.total as CKRecordValue
            _ = try? await db.save(rec)
        }
        return recomputed
    }
}
```

- [ ] **Step 2: Regenerate + build**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **` (CloudKit compiles without the entitlement; it's unused until Task 14).

- [ ] **Step 3: Commit**

```bash
git add ByzantineTrail/Core/Ratings/CloudKitRatingsService.swift
git commit -m "$(cat <<'EOF'
M5a Task 12: CloudKitRatingsService (public DB, delta + recompute reconcile)

Written and build-checked; owner activates + integration-tests in Task 14.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: `CloudKitAccountStatusProvider` (write + build-check)

**Files:**
- Create: `ByzantineTrail/Core/Account/CloudKitAccountStatusProvider.swift`

**Interfaces:**
- Consumes: `AccountStatus`, `AccountStatusProviding` (Task 5).
- Produces: `struct CloudKitAccountStatusProvider: AccountStatusProviding`.

**No unit test** — thin `CKContainer` wrapper; integration-verified by the owner in Task 14. Gate: compiles clean.

- [ ] **Step 1: Write the implementation**

`ByzantineTrail/Core/Account/CloudKitAccountStatusProvider.swift`:
```swift
import CloudKit

/// Maps `CKAccountStatus` to the app's `AccountStatus`. Activated by the owner
/// (needs the iCloud entitlement + a signed-in account). All CloudKit stays here.
struct CloudKitAccountStatusProvider: AccountStatusProviding {
    private let container: CKContainer

    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        container = CKContainer(identifier: containerID)
    }

    func currentStatus() async -> AccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine, .temporarilyUnavailable: return .unknown
            @unknown default: return .unknown
            }
        } catch { return .unknown }
    }
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
git add ByzantineTrail/Core/Account/CloudKitAccountStatusProvider.swift
git commit -m "$(cat <<'EOF'
M5a Task 13: CloudKitAccountStatusProvider (CKAccountStatus mapping)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: `CLOUDKIT_SETUP.md` + owner activation guide

**Files:**
- Create: `docs/CLOUDKIT_SETUP.md`

**Interfaces:** none (documentation + a documented, owner-performed wiring flip).

**This task's deliverable is the doc.** The CloudKit *activation* (adding the iCloud capability/entitlement, setting the signing team, Dashboard schema, signing the sim into iCloud, flipping the app wiring from mock to CloudKit, and the end-to-end integration test) **is performed by the owner** — a subagent cannot configure the Developer signing team or sign into the owner's iCloud. Write the doc so the owner can do it in one sitting.

- [ ] **Step 1: Write `docs/CLOUDKIT_SETUP.md`**

Content (owner guide, mirroring `docs/CATALOG_HOSTING.md`'s style):
```markdown
# CloudKit setup (M5a — public ratings)

Ratings use a **CloudKit public database**. Until you complete this one-time
setup, the app runs against an in-memory mock service (averages are demo data).
These steps require your Apple Developer account and are done in Xcode + the
CloudKit Dashboard — not by an automated agent.

## 1. Enable the capability (Xcode)
1. Open the project, select the **ByzantineTrail** target → Signing & Capabilities.
2. Set your **Team** (Developer account).
3. **+ Capability → iCloud**; check **CloudKit**; add the container
   `iCloud.com.byzantinetrail.app`.
4. This writes `ByzantineTrail/ByzantineTrail.entitlements`. Add it to the target
   in `project.yml` under the app target's `settings.base`:
   `CODE_SIGN_ENTITLEMENTS: ByzantineTrail/ByzantineTrail.entitlements`, then
   regenerate: `~/bin/xcodegen_dist/bin/xcodegen generate`.

## 2. Define the schema (CloudKit Dashboard → Development)
Record types (auto-create on first write, or add explicitly):
- **Rating** — `siteId` (String, **Queryable** index), `value` (Int).
  Security: **world read, creator write.**
- **RatingSummary** — `siteId` (String), `count` (Int), `total` (Int).
  Security: **world read, authenticated write.**

## 3. Flip the app wiring to CloudKit
In `ByzantineTrail/App/ByzantineTrailApp.swift` `init()`, replace the two mock
lines with the real providers:
```swift
let ratingsService = CloudKitRatingsService()
_ratingsStore = State(initialValue: RatingsStore(service: ratingsService, userState: store))
_accountStore = State(initialValue: AccountStore(provider: CloudKitAccountStatusProvider()))
```

## 4. Integration test (simulator or device signed into iCloud)
1. In the simulator: Settings → sign into an **iCloud sandbox** account.
2. Run the app; open a site; rate it → the average/count update; change it → the
   average adjusts; remove → the count drops; relaunch → the value persists.
3. Sign out of iCloud → the rating control disables with "Sign in to iCloud to rate."
4. Turn off networking → the control disables with "Connect to the internet to rate."

## Notes
- The in-app recompute reconcile (on detail open / on retry exhaustion) is the
  self-healer. A standalone "rebuild all summaries" owner script is deferred.
- Promotion to the Production CloudKit environment is a later step.
```

- [ ] **Step 2: Commit**

```bash
git add docs/CLOUDKIT_SETUP.md
git commit -m "$(cat <<'EOF'
M5a Task 14: CLOUDKIT_SETUP.md owner activation guide

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Final verification (after all tasks)

- [ ] Full suite green: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -25` → `** TEST SUCCEEDED **`.
- [ ] Simulator smoke test (mock backend): rate/edit/remove on detail; average + my-rating chip on rows; Rating / My-rating sort; the control is enabled (mock account `.available`).
- [ ] Confirm the CloudKit provider files compile and are confined to their service classes; no entitlement was added by any subagent task.
- [ ] Hand off `docs/CLOUDKIT_SETUP.md` to the owner for CloudKit activation (Task 14 owner steps).

## Notes for the executor

- **No subagent task adds the iCloud entitlement or sets a signing team** — that is owner-only (Task 14). Every subagent task must build/run in the simulator with no entitlement, wired to mocks.
- **Defaulted parameters** on `SiteQuery.apply` (`userState`, `ratings`) and on `SiteRowView` (`flags`, `average`, `myRating`) are intentional — they keep the build green as wiring lands incrementally. Do not remove them.
- **My-rating is sourced from `UserStateStore`** (local, all sites) for rows/sort; `RatingsStore` only reconciles it on detail open. Do not move row my-rating reads to `RatingsStore`.
- View tasks (8, 10, 11) are simulator-verified; their underlying logic is unit-tested in the math/store/query/gate tasks.
