# M5b — Private User-State Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync a user's private per-site flags (favorite / want-to-visit / visited) across their own devices through the existing `RemoteSyncProvider` seam, backed by the CloudKit **private** database, on launch + foreground.

**Architecture:** A pure `SyncMerge` (last-writer-wins) + `UserStateStore` sync methods (dirty-flag `pendingSync`, `mergeRemote`) drive a `SyncCoordinator` that runs pull→merge→push against a `RemoteSyncProvider`. The real `CloudKitSyncProvider` (private DB, query-by-timestamp) is one impl; a mock drives all unit tests. The local SwiftData store is unchanged (`@Attribute(.unique)`, `cloudKitDatabase: .none`) — sync is a separate explicit layer, not SwiftData mirroring.

**Tech Stack:** SwiftUI, SwiftData, CloudKit (private DB, already active from M5a), Swift Testing, XcodeGen, iOS 17+.

**Spec:** `docs/superpowers/specs/2026-07-27-m5b-private-sync-design.md`.

## Global Constraints

- iOS 17+, Swift 6.2, SwiftUI. Tests use **Swift Testing** (`import Testing` / `@Test` / `#expect`) — **never** XCTest.
- **All CloudKit code confined to `CloudKitSyncProvider.swift`.** Feature/store code talks only to the `RemoteSyncProvider` protocol.
- **Sync scope is flags only:** `isFavorite`, `wantsToVisit`, `visited`. `myRating` is **never** read or written by the private-sync path (it stays on the M5a public-ratings path).
- **Local store unchanged:** keep `ModelConfiguration(cloudKitDatabase: .none)` and `@Attribute(.unique) var siteId`. No CloudKit-compatibility surgery on `UserSiteState`.
- **Every local mutation still routes through `UserStateStore.apply`.** Sync reads/writes go through the new store methods, not a parallel write path.
- **Conflict resolution:** per-record (per-site) last-writer-wins on `updatedAt`.
- **"Delete" = an all-false record**, never a CloudKit record deletion (no tombstones).
- CloudKit container `iCloud.com.byzantinetrail.app`, **private** database, Development environment.
- XcodeGen: regenerate with the **real binary** `~/bin/xcodegen_dist/bin/xcodegen generate` (NOT the `xcodegen` symlink) after adding files.
- Build/test destination: `platform=iOS Simulator,name=iPhone 16`.
- Commit author is already the GitHub no-reply address — do not change git identity.

## File Structure

- `ByzantineTrail/Core/Sync/RemoteSyncProvider.swift` — **exists**; `UserSiteChange`, `SyncToken`, `RemoteSyncProvider`. Unchanged.
- `ByzantineTrail/Core/Sync/SyncMerge.swift` — **new**; pure LWW decision.
- `ByzantineTrail/Core/Sync/SyncTokenStore.swift` — **new**; `SyncTokenStoring` + `UserDefaultsSyncTokenStore`.
- `ByzantineTrail/Core/Sync/SyncCoordinator.swift` — **new**; the pull/merge/push orchestrator.
- `ByzantineTrail/Core/Sync/CloudKitSyncProvider.swift` — **new**; real private-DB provider (CloudKit confined here).
- `ByzantineTrail/Core/UserState/UserSiteState.swift` — **modify**; add `pendingSync`.
- `ByzantineTrail/Core/UserState/UserStateStore.swift` — **modify**; `apply(markPending:)`, relaxed prune, `pendingChanges`, `clearPending`, `mergeRemote`.
- `ByzantineTrail/App/ByzantineTrailApp.swift` — **modify**; construct `SyncCoordinator`, trigger on launch + `scenePhase`.
- `ByzantineTrailTests/Mocks/MockProviders.swift` — **modify**; add a controllable `StubSyncProvider` (keep `MockRemoteSyncProvider`).
- Test files: `SyncMergeTests.swift`, `UserStateSyncTests.swift`, `SyncCoordinatorTests.swift`.
- `docs/CLOUDKIT_SETUP.md` — **modify**; private-DB addendum.

---

### Task 1: `SyncMerge` — pure last-writer-wins

**Files:**
- Create: `ByzantineTrail/Core/Sync/SyncMerge.swift`
- Test: `ByzantineTrailTests/SyncMergeTests.swift`

**Interfaces:**
- Consumes: `UserSiteChange` (existing, in `Core/Sync/RemoteSyncProvider.swift`).
- Produces: `enum SyncMerge` with `enum Decision: Equatable { case apply, skip }` and `static func resolve(localUpdatedAt: Date?, remote: UserSiteChange) -> Decision`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/SyncMergeTests.swift`:
```swift
import Testing
import Foundation
@testable import ByzantineTrail

struct SyncMergeTests {
    private func change(_ fav: Bool, at t: TimeInterval) -> UserSiteChange {
        UserSiteChange(siteId: "s", isFavorite: fav, wantsToVisit: false,
                       visited: false, myRating: nil,
                       updatedAt: Date(timeIntervalSince1970: t))
    }

    @Test func absentLocalAllFalseRemoteSkips() {
        let remote = UserSiteChange(siteId: "s", isFavorite: false, wantsToVisit: false,
                                    visited: false, myRating: nil, updatedAt: Date(timeIntervalSince1970: 5))
        #expect(SyncMerge.resolve(localUpdatedAt: nil, remote: remote) == .skip)
    }

    @Test func absentLocalAnyTrueRemoteApplies() {
        #expect(SyncMerge.resolve(localUpdatedAt: nil, remote: change(true, at: 5)) == .apply)
    }

    @Test func newerRemoteApplies() {
        #expect(SyncMerge.resolve(localUpdatedAt: Date(timeIntervalSince1970: 3),
                                  remote: change(true, at: 5)) == .apply)
    }

    @Test func olderRemoteSkips() {
        #expect(SyncMerge.resolve(localUpdatedAt: Date(timeIntervalSince1970: 9),
                                  remote: change(true, at: 5)) == .skip)
    }

    @Test func equalTimestampSkips() {
        #expect(SyncMerge.resolve(localUpdatedAt: Date(timeIntervalSince1970: 5),
                                  remote: change(true, at: 5)) == .skip)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `SyncMerge` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Core/Sync/SyncMerge.swift`:
```swift
import Foundation

/// Pure conflict resolution for private-state sync (spec §5). Per-record
/// last-writer-wins on `updatedAt`. `localUpdatedAt == nil` means the local row
/// is absent; an all-false remote change for an absent row is nothing to
/// represent, so it is skipped (the "delete" is already the local absence).
enum SyncMerge {
    enum Decision: Equatable { case apply, skip }

    static func resolve(localUpdatedAt: Date?, remote: UserSiteChange) -> Decision {
        let remoteAllFalse = !remote.isFavorite && !remote.wantsToVisit && !remote.visited
        guard let local = localUpdatedAt else {
            return remoteAllFalse ? .skip : .apply
        }
        return remote.updatedAt > local ? .apply : .skip
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/SyncMergeTests 2>&1 | tail -20`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Sync/SyncMerge.swift ByzantineTrailTests/SyncMergeTests.swift
git commit -m "$(cat <<'EOF'
M5b Task 1: SyncMerge pure last-writer-wins resolution

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `UserSiteState.pendingSync` + `apply(markPending:)` + relaxed prune

**Files:**
- Modify: `ByzantineTrail/Core/UserState/UserSiteState.swift`
- Modify: `ByzantineTrail/Core/UserState/UserStateStore.swift`
- Test: `ByzantineTrailTests/UserStateSyncTests.swift` (new)

**Interfaces:**
- Consumes: existing `UserSiteState`, `UserStateStore.apply`.
- Produces: `UserSiteState.pendingSync: Bool`; `UserStateStore.apply(_ siteId:, markPending: Bool = true, _ mutate:)`. Flag mutations mark pending + bump `updatedAt`; `setRating` passes `markPending: false` (no pending, no `updatedAt` bump). Prune rule becomes `isEmpty && !pendingSync`.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/UserStateSyncTests.swift`:
```swift
import Testing
import SwiftData
import Foundation
@testable import ByzantineTrail

@MainActor
struct UserStateSyncTests {
    func make() throws -> (UserStateStore, ModelContainer) {
        let container = try UserStateStore.makeContainer(inMemory: true)
        return (UserStateStore(container: container), container)
    }

    @Test func flagToggleMarksPending() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.first?.pendingSync == true)
    }

    @Test func setRatingDoesNotMarkPending() throws {
        let (store, container) = try make()
        store.setRating(8, for: "a")
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.count == 1)
        #expect(rows.first?.pendingSync == false)
    }

    @Test func clearedFlagRowIsRetainedWhilePending() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")   // favorite on  (pending)
        store.toggleFavorite("a")   // favorite off (all-false but still pending)
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.count == 1)                 // NOT pruned — cleared state must sync
        #expect(rows.first?.isFavorite == false)
        #expect(rows.first?.pendingSync == true)
    }

    @Test func bareRatingRowStillPrunesOnClear() throws {
        let (store, container) = try make()
        store.setRating(7, for: "a")
        store.setRating(nil, for: "a")           // all-false, never pending
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.isEmpty)                     // M4 behavior preserved
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `pendingSync` unresolved.

- [ ] **Step 3: Add `pendingSync` to the model**

In `ByzantineTrail/Core/UserState/UserSiteState.swift`, add the stored property (after `var updatedAt: Date`) and the init parameter:
```swift
    var updatedAt: Date
    /// True when a synced flag changed locally and has not yet been pushed
    /// (M5b). Not part of `isEmpty` — a cleared-but-unpushed row must survive.
    /// Property-level default `= false` so SwiftData lightweight migration can
    /// add this attribute to existing on-disk stores without a load failure.
    var pendingSync: Bool = false

    init(siteId: String, isFavorite: Bool = false, wantsToVisit: Bool = false,
         visited: Bool = false, myRating: Int? = nil, updatedAt: Date = .now,
         pendingSync: Bool = false) {
        self.siteId = siteId
        self.isFavorite = isFavorite
        self.wantsToVisit = wantsToVisit
        self.visited = visited
        self.myRating = myRating
        self.updatedAt = updatedAt
        self.pendingSync = pendingSync
    }
```
Leave `isEmpty` unchanged (it must NOT consider `pendingSync`).

- [ ] **Step 4: Change `apply` in `UserStateStore`**

In `ByzantineTrail/Core/UserState/UserStateStore.swift`, replace the `apply` method with a `markPending`-aware version, and change `setRating` to opt out:
```swift
    /// The user's own rating for a site. Not synced by M5b (the public Rating is
    /// the cross-device source of truth), so it does not mark the row pending.
    func setRating(_ value: Int?, for siteId: String) {
        apply(siteId, markPending: false) { $0.myRating = value }
    }

    // MARK: The single write path

    private func apply(_ siteId: String, markPending: Bool = true,
                       _ mutate: (UserSiteState) -> Void) {
        let row: UserSiteState
        if let found = existing(siteId) {
            row = found
        } else {
            row = UserSiteState(siteId: siteId)
            context.insert(row)
        }
        mutate(row)
        if markPending {
            row.updatedAt = .now
            row.pendingSync = true
        }
        if row.isEmpty && !row.pendingSync { context.delete(row) }
        try? context.save()
        reload()
    }
```
(The flag mutations `toggleFavorite` / `toggleWant` / `toggleVisited` are unchanged — they call `apply(siteId) { ... }` and get the default `markPending: true`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/UserStateSyncTests -only-testing:ByzantineTrailTests/UserStateStoreTests 2>&1 | tail -20`
Expected: PASS — the 4 new tests plus all existing `UserStateStoreTests` pass (M4 pruning behavior preserved).

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/UserState/UserSiteState.swift ByzantineTrail/Core/UserState/UserStateStore.swift ByzantineTrailTests/UserStateSyncTests.swift
git commit -m "$(cat <<'EOF'
M5b Task 2: UserSiteState.pendingSync + apply(markPending:) + prune-when-not-pending

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `UserStateStore` sync methods — `pendingChanges` / `clearPending` / `mergeRemote`

**Files:**
- Modify: `ByzantineTrail/Core/UserState/UserStateStore.swift`
- Test: `ByzantineTrailTests/UserStateSyncTests.swift` (extend)

**Interfaces:**
- Consumes: `SyncMerge` (Task 1), `UserSiteChange`, `UserSiteState.pendingSync` (Task 2).
- Produces:
  - `func pendingChanges() -> [UserSiteChange]` (rows where `pendingSync`, mapped; `myRating` always `nil`).
  - `func clearPending(_ siteIds: [String])` (clear the flag on those rows, prune newly-empty non-pending rows, save, reload).
  - `func mergeRemote(_ change: UserSiteChange)` and `func mergeRemote(_ changes: [UserSiteChange])` (LWW via `SyncMerge`; applies remote flags + remote `updatedAt`, leaves `pendingSync == false`).

- [ ] **Step 1: Write the failing test**

Add to `ByzantineTrailTests/UserStateSyncTests.swift`:
```swift
    private func remote(_ site: String, fav: Bool = false, want: Bool = false,
                        visited: Bool = false, at t: TimeInterval) -> UserSiteChange {
        UserSiteChange(siteId: site, isFavorite: fav, wantsToVisit: want,
                       visited: visited, myRating: nil, updatedAt: Date(timeIntervalSince1970: t))
    }

    @Test func pendingChangesReturnsDirtyRowsWithoutRating() throws {
        let (store, _) = try make()
        store.toggleFavorite("a")
        store.setRating(9, for: "a")     // rating change must not un-dirty or leak into the change
        let pending = store.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending.first?.siteId == "a")
        #expect(pending.first?.isFavorite == true)
        #expect(pending.first?.myRating == nil)
    }

    @Test func clearPendingClearsFlag() throws {
        let (store, container) = try make()
        store.toggleFavorite("a")
        store.clearPending(["a"])
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.first?.pendingSync == false)
        #expect(store.pendingChanges().isEmpty)
    }

    @Test func mergeRemoteAppliesNewerAndKeepsNotPending() throws {
        let (store, container) = try make()
        store.mergeRemote(remote("a", fav: true, at: 100))
        #expect(store.favoriteIDs == ["a"])
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.first?.pendingSync == false)   // received, not dirty
    }

    @Test func mergeRemoteSkipsOlderThanLocal() throws {
        let (store, _) = try make()
        store.toggleVisited("a")                      // local updatedAt ~= now (newer than epoch)
        store.mergeRemote(remote("a", visited: false, at: 1))   // stale remote
        #expect(store.visitedIDs == ["a"])            // local wins
    }

    @Test func mergeRemoteAllFalseClearsAndPrunes() throws {
        let (store, container) = try make()
        store.mergeRemote(remote("a", fav: true, at: 100))
        store.mergeRemote(remote("a", fav: false, at: 200))     // newer all-false = cleared
        #expect(store.favoriteIDs.isEmpty)
        let rows = try container.mainContext.fetch(FetchDescriptor<UserSiteState>())
        #expect(rows.isEmpty)                          // pruned (empty, not pending)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `pendingChanges` / `clearPending` / `mergeRemote` unresolved.

- [ ] **Step 3: Add the sync methods**

In `ByzantineTrail/Core/UserState/UserStateStore.swift`, add a `MARK: Sync (M5b)` section (e.g. after `reload()`):
```swift
    // MARK: Sync (M5b)

    /// Rows changed locally and not yet pushed, as wire changes. `myRating` is
    /// never synced by M5b, so it is always nil here.
    func pendingChanges() -> [UserSiteChange] {
        let rows = (try? context.fetch(FetchDescriptor<UserSiteState>())) ?? []
        return rows.filter(\.pendingSync).map {
            UserSiteChange(siteId: $0.siteId, isFavorite: $0.isFavorite,
                           wantsToVisit: $0.wantsToVisit, visited: $0.visited,
                           myRating: nil, updatedAt: $0.updatedAt)
        }
    }

    /// Clear the pending flag on pushed rows; prune any that are now empty.
    func clearPending(_ siteIds: [String]) {
        let set = Set(siteIds)
        let rows = (try? context.fetch(FetchDescriptor<UserSiteState>())) ?? []
        for row in rows where set.contains(row.siteId) { row.pendingSync = false }
        for row in rows where row.isEmpty && !row.pendingSync { context.delete(row) }
        try? context.save()
        reload()
    }

    /// Apply a batch of remote changes via last-writer-wins, then persist once.
    func mergeRemote(_ changes: [UserSiteChange]) {
        for change in changes { mergeOne(change) }
        for row in (try? context.fetch(FetchDescriptor<UserSiteState>())) ?? []
        where row.isEmpty && !row.pendingSync { context.delete(row) }
        try? context.save()
        reload()
    }

    func mergeRemote(_ change: UserSiteChange) { mergeRemote([change]) }

    /// LWW-apply a single remote change in-place (no save/reload — caller batches).
    private func mergeOne(_ change: UserSiteChange) {
        let local = existing(change.siteId)
        guard SyncMerge.resolve(localUpdatedAt: local?.updatedAt, remote: change) == .apply
        else { return }
        let row: UserSiteState
        if let local { row = local } else {
            row = UserSiteState(siteId: change.siteId)
            context.insert(row)
        }
        row.isFavorite = change.isFavorite
        row.wantsToVisit = change.wantsToVisit
        row.visited = change.visited
        row.updatedAt = change.updatedAt
        row.pendingSync = false   // remote won; drop any superseded local pending
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/UserStateSyncTests 2>&1 | tail -20`
Expected: PASS — all `UserStateSyncTests` (Task 2 + Task 3) pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/UserState/UserStateStore.swift ByzantineTrailTests/UserStateSyncTests.swift
git commit -m "$(cat <<'EOF'
M5b Task 3: UserStateStore pendingChanges/clearPending/mergeRemote (LWW)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `SyncTokenStoring` + `UserDefaultsSyncTokenStore`

**Files:**
- Create: `ByzantineTrail/Core/Sync/SyncTokenStore.swift`
- Test: `ByzantineTrailTests/SyncTokenStoreTests.swift`

**Interfaces:**
- Consumes: `SyncToken` (existing).
- Produces: `protocol SyncTokenStoring { func load() -> SyncToken?; func save(_ token: SyncToken?) }`; `struct UserDefaultsSyncTokenStore: SyncTokenStoring` (init `defaults: UserDefaults = .standard`); `final class InMemorySyncTokenStore: SyncTokenStoring` for tests.

- [ ] **Step 1: Write the failing test**

`ByzantineTrailTests/SyncTokenStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import ByzantineTrail

struct SyncTokenStoreTests {
    @Test func userDefaultsRoundTrips() {
        let defaults = UserDefaults(suiteName: "m5b.token.test")!
        defaults.removePersistentDomain(forName: "m5b.token.test")
        let store = UserDefaultsSyncTokenStore(defaults: defaults)
        #expect(store.load() == nil)
        store.save(SyncToken(raw: "2026-07-27T00:00:00Z"))
        #expect(store.load() == SyncToken(raw: "2026-07-27T00:00:00Z"))
        store.save(nil)
        #expect(store.load() == nil)
    }

    @Test func inMemoryRoundTrips() {
        let store = InMemorySyncTokenStore()
        #expect(store.load() == nil)
        store.save(SyncToken(raw: "t1"))
        #expect(store.load() == SyncToken(raw: "t1"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `SyncTokenStoring` / `UserDefaultsSyncTokenStore` / `InMemorySyncTokenStore` unresolved.

- [ ] **Step 3: Write the implementation**

`ByzantineTrail/Core/Sync/SyncTokenStore.swift`:
```swift
import Foundation

/// Persistence seam for the pull sync token. Injected so `SyncCoordinator` is
/// testable with no I/O. Used only on the main actor (no Sendable needed).
protocol SyncTokenStoring {
    func load() -> SyncToken?
    func save(_ token: SyncToken?)
}

struct UserDefaultsSyncTokenStore: SyncTokenStoring {
    private let key = "byzantinetrail.sync.token"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> SyncToken? { defaults.string(forKey: key).map(SyncToken.init(raw:)) }
    func save(_ token: SyncToken?) {
        if let token { defaults.set(token.raw, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}

/// In-memory token store for tests.
final class InMemorySyncTokenStore: SyncTokenStoring {
    private var token: SyncToken?
    init(_ token: SyncToken? = nil) { self.token = token }
    func load() -> SyncToken? { token }
    func save(_ token: SyncToken?) { self.token = token }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/SyncTokenStoreTests 2>&1 | tail -20`
Expected: PASS — 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Sync/SyncTokenStore.swift ByzantineTrailTests/SyncTokenStoreTests.swift
git commit -m "$(cat <<'EOF'
M5b Task 4: SyncTokenStoring seam + UserDefaults/in-memory stores

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `SyncCoordinator` + controllable `StubSyncProvider`

**Files:**
- Create: `ByzantineTrail/Core/Sync/SyncCoordinator.swift`
- Modify: `ByzantineTrailTests/Mocks/MockProviders.swift` (add `StubSyncProvider`; keep `MockRemoteSyncProvider`)
- Test: `ByzantineTrailTests/SyncCoordinatorTests.swift`

**Interfaces:**
- Consumes: `RemoteSyncProvider`, `UserStateStore` (Tasks 2–3), `SyncTokenStoring` + `InMemorySyncTokenStore` (Task 4), `UserSiteChange`, `SyncToken`.
- Produces: `@MainActor @Observable final class SyncCoordinator` with `init(provider: any RemoteSyncProvider, userState: UserStateStore, tokenStore: any SyncTokenStoring)`, `private(set) var lastSyncedAt: Date?`, `func sync() async`.
- Test double `actor StubSyncProvider: RemoteSyncProvider` with `init(pullChanges: [UserSiteChange] = [], pullToken: SyncToken = SyncToken(raw: "t1"), failPush: Bool = false, failPull: Bool = false)`, `func pushed() -> [[UserSiteChange]]`, `func pullCalls() -> [SyncToken?]`.

- [ ] **Step 1: Add the controllable stub provider**

Append to `ByzantineTrailTests/Mocks/MockProviders.swift` (leave the existing `MockRemoteSyncProvider` and `MockSuggestionService` intact):
```swift
/// Controllable RemoteSyncProvider for coordinator tests: seed the pull result,
/// capture pushes, and force failures.
actor StubSyncProvider: RemoteSyncProvider {
    private let pullChanges: [UserSiteChange]
    private let pullToken: SyncToken
    private let failPush: Bool
    private let failPull: Bool
    private var pushedBatches: [[UserSiteChange]] = []
    private var pullTokens: [SyncToken?] = []

    init(pullChanges: [UserSiteChange] = [], pullToken: SyncToken = SyncToken(raw: "t1"),
         failPush: Bool = false, failPull: Bool = false) {
        self.pullChanges = pullChanges
        self.pullToken = pullToken
        self.failPush = failPush
        self.failPull = failPull
    }

    struct StubError: Error {}

    func push(_ changes: [UserSiteChange]) async throws {
        if failPush { throw StubError() }
        pushedBatches.append(changes)
    }

    func pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken) {
        pullTokens.append(token)
        if failPull { throw StubError() }
        return (pullChanges, pullToken)
    }

    func pushed() -> [[UserSiteChange]] { pushedBatches }
    func pullCalls() -> [SyncToken?] { pullTokens }
}
```

- [ ] **Step 2: Write the failing test**

`ByzantineTrailTests/SyncCoordinatorTests.swift`:
```swift
import Testing
import SwiftData
import Foundation
@testable import ByzantineTrail

@MainActor
struct SyncCoordinatorTests {
    private func userState() throws -> UserStateStore {
        UserStateStore(container: try UserStateStore.makeContainer(inMemory: true))
    }
    private func change(_ site: String, fav: Bool, at t: TimeInterval) -> UserSiteChange {
        UserSiteChange(siteId: site, isFavorite: fav, wantsToVisit: false,
                       visited: false, myRating: nil, updatedAt: Date(timeIntervalSince1970: t))
    }

    @Test func pushesPendingAndClearsIt() async throws {
        let state = try userState()
        state.toggleFavorite("a")
        let provider = StubSyncProvider()
        let coord = SyncCoordinator(provider: provider, userState: state,
                                    tokenStore: InMemorySyncTokenStore())
        await coord.sync()
        let batches = await provider.pushed()
        #expect(batches.count == 1)
        #expect(batches.first?.first?.siteId == "a")
        #expect(state.pendingChanges().isEmpty)   // cleared after successful push
    }

    @Test func pullMergesRemoteAndPersistsToken() async throws {
        let state = try userState()
        let tokenStore = InMemorySyncTokenStore()
        let provider = StubSyncProvider(pullChanges: [change("b", fav: true, at: 100)],
                                        pullToken: SyncToken(raw: "t2"))
        let coord = SyncCoordinator(provider: provider, userState: state, tokenStore: tokenStore)
        await coord.sync()
        #expect(state.favoriteIDs == ["b"])
        #expect(tokenStore.load() == SyncToken(raw: "t2"))
    }

    @Test func pushFailureKeepsPending() async throws {
        let state = try userState()
        state.toggleFavorite("a")
        let provider = StubSyncProvider(failPush: true)
        let coord = SyncCoordinator(provider: provider, userState: state,
                                    tokenStore: InMemorySyncTokenStore())
        await coord.sync()
        #expect(state.pendingChanges().count == 1)   // retained for next sync
    }

    @Test func pullFailureLeavesTokenUnchanged() async throws {
        let state = try userState()
        let tokenStore = InMemorySyncTokenStore(SyncToken(raw: "t0"))
        let provider = StubSyncProvider(failPull: true)
        let coord = SyncCoordinator(provider: provider, userState: state, tokenStore: tokenStore)
        await coord.sync()
        #expect(tokenStore.load() == SyncToken(raw: "t0"))
        #expect(await provider.pullCalls() == [SyncToken(raw: "t0")])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing 2>&1 | tail -20`
Expected: FAIL — `SyncCoordinator` unresolved.

- [ ] **Step 4: Write the implementation**

`ByzantineTrail/Core/Sync/SyncCoordinator.swift`:
```swift
import Foundation
import Observation

/// Orchestrates the private-state sync cycle (spec §3): pull + merge (LWW),
/// persist the token, then push still-pending local changes. Any provider throw
/// is a silent no-op — offline just defers work to the next sync. Driven by app
/// lifecycle (launch + foreground); no screen depends on it.
@MainActor
@Observable
final class SyncCoordinator {
    private let provider: any RemoteSyncProvider
    private let userState: UserStateStore
    private let tokenStore: any SyncTokenStoring
    private(set) var lastSyncedAt: Date?

    init(provider: any RemoteSyncProvider, userState: UserStateStore,
         tokenStore: any SyncTokenStoring) {
        self.provider = provider
        self.userState = userState
        self.tokenStore = tokenStore
    }

    func sync() async {
        // 1. Pull + merge (LWW). Token only advances on a successful pull.
        if let result = try? await provider.pull(since: tokenStore.load()) {
            userState.mergeRemote(result.changes)
            tokenStore.save(result.token)
        }
        // 2. Push still-pending local changes; clear them only on success.
        let pending = userState.pendingChanges()
        if !pending.isEmpty {
            do {
                try await provider.push(pending)
                userState.clearPending(pending.map(\.siteId))
            } catch {
                // Keep pending for the next sync.
            }
        }
        lastSyncedAt = .now
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/SyncCoordinatorTests 2>&1 | tail -20`
Expected: PASS — 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/Sync/SyncCoordinator.swift ByzantineTrailTests/Mocks/MockProviders.swift ByzantineTrailTests/SyncCoordinatorTests.swift
git commit -m "$(cat <<'EOF'
M5b Task 5: SyncCoordinator pull/merge/push cycle + StubSyncProvider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `CloudKitSyncProvider` (write + build-check)

**Files:**
- Create: `ByzantineTrail/Core/Sync/CloudKitSyncProvider.swift`

**Interfaces:**
- Consumes: `RemoteSyncProvider`, `UserSiteChange`, `SyncToken`.
- Produces: `final class CloudKitSyncProvider: RemoteSyncProvider`.

**No unit test** — the CloudKit I/O is integration-verified in Task 8; the merge/LWW logic it feeds is already unit-tested. Gate: **compiles clean** (`import CloudKit`, no new entitlement — already active from M5a).

- [ ] **Step 1: Write the implementation**

`ByzantineTrail/Core/Sync/CloudKitSyncProvider.swift`:
```swift
import CloudKit

/// Real private-database sync backend (spec §7). Record type `UserSiteState`,
/// recordName == siteId, in the user's private DB. Sync scope is the three flags
/// only — `myRating` is never read or written here. All CloudKit is confined to
/// this file. Pull is query-by-`updatedAt` (no custom zone; fits the no-delete /
/// all-false model). Activated by the owner (docs/CLOUDKIT_SETUP.md).
final class CloudKitSyncProvider: RemoteSyncProvider {
    private let db: CKDatabase
    private static let recordType = "UserSiteState"

    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        db = CKContainer(identifier: containerID).privateCloudDatabase
    }

    private func iso() -> ISO8601DateFormatter { ISO8601DateFormatter() }

    func push(_ changes: [UserSiteChange]) async throws {
        for change in changes {
            let id = CKRecord.ID(recordName: change.siteId)
            let rec = (try? await db.record(for: id))
                ?? CKRecord(recordType: Self.recordType, recordID: id)
            rec["isFavorite"] = (change.isFavorite ? 1 : 0) as CKRecordValue
            rec["wantsToVisit"] = (change.wantsToVisit ? 1 : 0) as CKRecordValue
            rec["visited"] = (change.visited ? 1 : 0) as CKRecordValue
            rec["updatedAt"] = change.updatedAt as CKRecordValue
            _ = try await db.save(rec)
        }
    }

    func pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken) {
        let sinceDate = token?.raw.flatMap { iso().date(from: $0) }
        let predicate: NSPredicate = sinceDate.map {
            NSPredicate(format: "updatedAt > %@", $0 as NSDate)
        } ?? NSPredicate(value: true)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)

        var changes: [UserSiteChange] = []
        var maxDate = sinceDate ?? .distantPast
        for rec in try await allRecords(matching: query) {
            guard let updatedAt = rec["updatedAt"] as? Date else { continue }
            changes.append(UserSiteChange(
                siteId: rec.recordID.recordName,
                isFavorite: (rec["isFavorite"] as? Int ?? 0) != 0,
                wantsToVisit: (rec["wantsToVisit"] as? Int ?? 0) != 0,
                visited: (rec["visited"] as? Int ?? 0) != 0,
                myRating: nil, updatedAt: updatedAt))
            if updatedAt > maxDate { maxDate = updatedAt }
        }
        return (changes, SyncToken(raw: iso().string(from: maxDate)))
    }

    /// All records matching a query, following the cursor across every page.
    private func allRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var out: [CKRecord] = []
        var response = try await db.records(matching: query)
        while true {
            for (_, result) in response.matchResults {
                if let rec = try? result.get() { out.append(rec) }
            }
            guard let cursor = response.queryCursor else { break }
            response = try await db.records(continuingMatchFrom: cursor)
        }
        return out
    }
}
```

- [ ] **Step 2: Regenerate + build**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ByzantineTrail/Core/Sync/CloudKitSyncProvider.swift
git commit -m "$(cat <<'EOF'
M5b Task 6: CloudKitSyncProvider (private DB, query-by-updatedAt pull)

Written and build-checked; integration-tested with the schema in Task 8.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: App wiring + launch/foreground triggers

**Files:**
- Modify: `ByzantineTrail/App/ByzantineTrailApp.swift`

**Interfaces:**
- Consumes: `SyncCoordinator` (Task 5), `CloudKitSyncProvider` (Task 6), `UserDefaultsSyncTokenStore` (Task 4), the existing shared `UserStateStore`.
- Produces: a `SyncCoordinator` driven on launch and on `scenePhase → .active`.

**No new unit test** — integration verified by build + full suite (mock-backed unit tests already cover the logic) and the Task 8 device test. The real sync runs against CloudKit only on a real launch.

- [ ] **Step 1: Construct the coordinator**

In `ByzantineTrail/App/ByzantineTrailApp.swift`, add the stored property and scene-phase environment beside the others:
```swift
    @State private var syncCoordinator: SyncCoordinator
    @Environment(\.scenePhase) private var scenePhase
```
In `init()`, after `let store = UserStateStore(container: container)` and `_userState = State(initialValue: store)`, construct the coordinator with the real provider (the mock stays a test-only double; sync simply no-ops when offline, so no app-side fallback is needed):
```swift
        _syncCoordinator = State(initialValue: SyncCoordinator(
            provider: CloudKitSyncProvider(),
            userState: store,
            tokenStore: UserDefaultsSyncTokenStore()))
```

- [ ] **Step 2: Trigger sync on launch + foreground**

Add a sync call at the **end** of the existing launch `.task { ... }` block (after the catalog refresh), and an `.onChange(of: scenePhase)` on the same `RootTabView()`:
```swift
                    // 3. Sync private user-state across the user's devices (M5b).
                    await syncCoordinator.sync()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await syncCoordinator.sync() }
                    }
                }
```

- [ ] **Step 3: Regenerate + build + full suite**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` (the test host launches with the real provider; its background `sync()` does not block or fail the suite, matching the M5a live-wiring behavior).

- [ ] **Step 4: Commit**

```bash
git add ByzantineTrail/App/ByzantineTrailApp.swift
git commit -m "$(cat <<'EOF'
M5b Task 7: wire SyncCoordinator (CloudKitSyncProvider) on launch + foreground

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: CloudKit Dashboard schema + `updatedAt` index + integration test

**Files:** none (CloudKit Console + in-session simulator verification).

**This task's deliverable is a working private-DB round-trip.** CloudKit is already live (M5a) and the iPhone 16 simulator is signed into iCloud, so this is done in-session, not deferred.

- [ ] **Step 1: Auto-create the record type**

Regenerate + build + launch the app on the booted iPhone 16 simulator, open a site, and toggle **Favorite**. The launch/foreground `sync()` pushes a `UserSiteState` record to the **private** database, auto-creating the record type in Development.
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```
(Install/launch via the simulator tooling; sign-in persists from M5a.)

- [ ] **Step 2: Add the index (CloudKit Console → Development → Private DB)**

- Open the CloudKit Console → container `iCloud.com.byzantinetrail.app` → **Development** → the record type `UserSiteState` now exists.
- Under **Indexes**, add a **Queryable** index on **`updatedAt`** (required for the `updatedAt > since` pull query), and a **Queryable** index on **`recordName`** (for the first-sync `TRUEPREDICATE` query).
- No security roles — the private database is scoped to the signed-in user.

- [ ] **Step 3: Verify the round-trip**

- **Push:** in the Console → Data → Records → Private DB → query `UserSiteState`; confirm the favorited site's record is present with `isFavorite = 1`.
- **Pull/merge:** toggle the favorite **off** in the app, foreground-sync, and confirm the record updates to `isFavorite = 0` (the all-false "delete" representation).
- **Cross-device (if a second simulator is available):** sign a second simulator into the same iCloud account, launch the app, and confirm the favorite state matches after its launch sync.
- If a pull query errors with "Field 'updatedAt' is not marked queryable," the index from Step 2 hasn't finished — re-check it.

- [ ] **Step 4: Record the outcome**

No code commit (Console-side). Note the verified round-trip in the execution ledger / PR description.

---

### Task 9: `docs/CLOUDKIT_SETUP.md` private-DB addendum

**Files:**
- Modify: `docs/CLOUDKIT_SETUP.md`

- [ ] **Step 1: Append the M5b section**

Add to the end of `docs/CLOUDKIT_SETUP.md`:
```markdown
## M5b — private user-state sync (private database)

Favorites / want-to-visit / visited sync across a user's own devices via the
**private** CloudKit database (separate from the public ratings DB).

### Schema (Development, Private DB)
- Record type **`UserSiteState`** — `recordName` = the site id. Fields:
  `isFavorite` (Int 0/1), `wantsToVisit` (Int 0/1), `visited` (Int 0/1),
  `updatedAt` (Date). **No `myRating`** — that stays on the public ratings path.
  Auto-created on the first sync write.
- **Indexes:** Queryable on **`updatedAt`** (the pull query is `updatedAt > since`)
  and Queryable on **`recordName`** (first-sync fetch-all).
- **No security roles** — the private database is inherently per-user.

### Wiring
`ByzantineTrailApp.init()` constructs `SyncCoordinator(provider:
CloudKitSyncProvider(), …)`, which syncs on launch and on foreground. To run
offline / without iCloud during development, sync simply no-ops; no code change
is needed. `MockRemoteSyncProvider` / `StubSyncProvider` are test-only.

### Notes
- Conflict resolution is per-record last-writer-wins on `updatedAt`.
- "Delete" is represented as an all-false record (no tombstones); the record is
  never deleted from CloudKit.
- Do not deploy the schema Development → Production until app release.
```

- [ ] **Step 2: Commit**

```bash
git add docs/CLOUDKIT_SETUP.md
git commit -m "$(cat <<'EOF'
M5b Task 9: CLOUDKIT_SETUP addendum for private-DB user-state sync

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Final verification (after all tasks)

- [ ] Full suite green: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -25` → `** TEST SUCCEEDED **`.
- [ ] `import CloudKit` appears only in `CloudKitSyncProvider.swift` (`grep -rn "import CloudKit" ByzantineTrail/` shows it plus M5a's two files).
- [ ] Local store still uses `cloudKitDatabase: .none` and `@Attribute(.unique) var siteId` (unchanged).
- [ ] `myRating` is never referenced in the Sync layer (`grep -rn myRating ByzantineTrail/Core/Sync/` returns nothing but `nil`-valued `UserSiteChange` fields).
- [ ] Task 8 private-DB round-trip verified in the Console (push + all-false clear).

## Notes for the executor

- **The local SwiftData model is intentionally not made CloudKit-compatible** — M5b syncs through the seam, not SwiftData mirroring. Do not remove `@Attribute(.unique)` or flip `cloudKitDatabase`.
- **`updatedAt` is bumped only on flag changes** (`apply(markPending:)`), not on `setRating` — this keeps LWW keyed to synced-flag recency.
- **Pruning is `isEmpty && !pendingSync`** — a cleared flag row survives until pushed; a bare-rating row still prunes (M4 behavior).
- **Query-by-timestamp pull** needs the `updatedAt` Queryable index (Task 8); the app no-ops gracefully until it exists.
