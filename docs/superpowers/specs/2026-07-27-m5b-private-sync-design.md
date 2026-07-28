# M5b — Private User-State Sync (CloudKit) Design

**Status:** Approved design (2026-07-27). Supersedes nothing; builds on M4 (local user state) and M5a (public ratings + live CloudKit).

**Goal:** Sync a user's *private* per-site state — favorites, want-to-visit, visited — across their own devices, through the existing `RemoteSyncProvider` seam backed by the CloudKit **private** database. `myRating` is intentionally out of scope (it already syncs via the M5a public-ratings path).

## 0. Context & prior decisions this builds on

- **The seam already exists** (`ByzantineTrail/Core/Sync/RemoteSyncProvider.swift`): `push(_ changes: [UserSiteChange]) async throws` and `pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken)`, plus `UserSiteChange { siteId, isFavorite, wantsToVisit, visited, myRating: Int?, updatedAt }` and `SyncToken { raw: String }`. A `MockRemoteSyncProvider` conforming to it lives in the test target.
- **Prior architectural decision (kept):** custom push/pull, **NOT** `CKSyncEngine`, **NOT** SwiftData/`NSPersistentCloudKitContainer` mirroring. The local SwiftData store stays local-only.
- **M5a decision (kept):** `UserStateStore.makeContainer` uses `ModelConfiguration(cloudKitDatabase: .none)`. M5b does **not** change this — the local store is never CloudKit-mirrored. `UserSiteState` keeps `@Attribute(.unique) var siteId` and its non-optional attributes; **no CloudKit-compatibility surgery is performed**.
- **M5a is live:** the iCloud entitlement, `DEVELOPMENT_TEAM`, and container `iCloud.com.byzantinetrail.app` are all active; the public ratings DB works end-to-end. M5b reuses the same container's **private** database.

## 1. Scope

**In scope:** cross-device sync of `isFavorite`, `wantsToVisit`, `visited`.

**Out of scope (deliberate):**
- **`myRating`** — already syncs across devices via the M5a public ratings DB (rate on device A → public `Rating` record → device B's `RatingsStore.refresh` reconciles it into the local cache on detail-open). Adding it to private sync would create a second, divergent path for the same value. The private sync ignores `myRating` entirely. Accepted trade-off: device B's list "me N" chips fill lazily on detail-open, not immediately.
- **Real-time sync** (CKSubscription / silent push). Sync runs on launch + foreground only. Subscriptions are a possible later enhancement.
- **Field-level conflict merge.** Conflict resolution is per-record (per-site) last-writer-wins.

## 2. Architecture

Sync is a **separate explicit layer** over the unchanged local store:

```
UserStateStore (local SwiftData, source of truth for the UI)
      │  apply(markPending:)         ▲ mergeRemote (LWW)
      ▼                               │
SyncCoordinator ── pull/merge/push ──► RemoteSyncProvider
   (@MainActor @Observable)              ├─ MockRemoteSyncProvider (tests/offline-dev)
   lastToken (persisted)                 └─ CloudKitSyncProvider (private DB; CloudKit confined here)
```

- The UI and the rest of the app are unchanged; they read `UserStateStore` as before.
- `CloudKit` import appears only in `CloudKitSyncProvider.swift` (same discipline as M5a's `CloudKitRatingsService`).

## 3. The sync cycle

1. **Local change.** `UserStateStore.apply` marks the touched row `pendingSync = true` — **only** for the three synced flags. `setRating` calls `apply(markPending: false)` (myRating is not synced).
2. **`SyncCoordinator.sync()`** (on launch and on `scenePhase → .active`):
   1. `pull(since: lastToken)` → `(changes, newToken)`.
   2. **Merge** each remote change by **last-writer-wins on `updatedAt`**: apply the remote flags to the local row only if the remote `updatedAt` is newer than the local row's (or the local row is absent and the remote carries any true flag). Merge sets the local `updatedAt` to the remote's and **does not** set `pendingSync`.
   3. Persist `newToken` as `lastToken`.
   4. `push(pendingChanges())` — all rows still `pendingSync == true`, mapped to `[UserSiteChange]`.
   5. On push success, `clearPending(theirSiteIds)`.
3. **Offline / failure.** Any thrown error aborts the cycle as a silent no-op; pending rows persist and flush on the next successful sync. `lastToken` only advances on a successful pull.

**"Delete" without tombstones.** Clearing all flags on a site is represented as an **all-false record**, never a CloudKit record deletion. A pulled all-false change clears the flags on the other device. The CloudKit record for a touched site is durable.

**Order rationale.** Pull-then-push: a local row that is genuinely newer than the pulled remote survives the LWW merge (its `updatedAt` is later) and is then pushed in step 4.

## 4. Local model & store changes

### 4.1 `UserSiteState` (`Core/UserState/UserSiteState.swift`)
- Add `var pendingSync: Bool = false`.
- `isEmpty` is unchanged (`!isFavorite && !wantsToVisit && !visited && myRating == nil`).
- Pruning rule (in `apply`) relaxes from `if isEmpty` to **`if isEmpty && !pendingSync`**. Rationale:
  - A flag toggled off → all-false but `pendingSync == true` → **not** pruned (the cleared state must be pushed).
  - A `myRating` set then cleared → all-false, `pendingSync == false` (setRating never marks pending) → pruned, exactly as in M4 (the M4 test `clearingRatingOnBareRowPrunesIt` stays green).
  - After a cleared row is pushed and `pendingSync` cleared, the empty row becomes prune-eligible again; it lingers harmlessly (invisible to the UI — projections ignore all-false rows) until a future `apply` prunes it. No re-prune pass is required.

### 4.2 `UserStateStore` (`Core/UserState/UserStateStore.swift`)
- `apply` gains a `markPending: Bool = true` parameter; it sets `row.pendingSync = true` when `markPending` and (after the mutation) when the row still exists. Flag mutations (`toggleFavorite`/`toggleWant`/`toggleVisited`) use the default `true`; `setRating` passes `markPending: false`.
- New methods:
  - `func pendingChanges() -> [UserSiteChange]` — fetch rows where `pendingSync == true`, map to `UserSiteChange` (flags + `updatedAt`; `myRating` set to `nil` in the change — the provider ignores it regardless).
  - `func clearPending(_ siteIds: [String])` — set `pendingSync = false` on those rows, save, reload.
  - `func mergeRemote(_ change: UserSiteChange)` — LWW apply: find/insert the row; if the row is absent and the change is all-false, **no-op** (nothing to represent); otherwise if the local `updatedAt` is older than `change.updatedAt`, set the three flags from the change, set `updatedAt = change.updatedAt`, leave `pendingSync = false`; if the local row is newer, skip. Then prune per §4.1 and reload.
  - `func mergeRemote(_ changes: [UserSiteChange])` — batch convenience.
- `reload()` is unchanged (projections already ignore all-false rows; `pendingSync` is not projected).

## 5. `SyncMerge` (pure) — `Core/Sync/SyncMerge.swift`

Pure, fully unit-tested resolution used by `mergeRemote`:

```
enum SyncMerge {
    enum Decision: Equatable { case apply, skip }
    /// `localUpdatedAt == nil` means the local row is absent.
    static func resolve(localUpdatedAt: Date?, remote: UserSiteChange) -> Decision
}
```
Rules:
- local absent (`nil`) + all-false remote → `.skip` (nothing to represent);
- local absent (`nil`) + any-true remote → `.apply`;
- local present + `remote.updatedAt > localUpdatedAt` → `.apply`;
- otherwise (older-or-equal remote) → `.skip` — equal timestamps skip, so a record the app just pushed and re-pulls is a harmless no-op.

(Keeping this pure isolates the LWW logic from SwiftData for testing.)

## 6. `SyncCoordinator` — `Core/Sync/SyncCoordinator.swift`

`@MainActor @Observable final class SyncCoordinator`:
- `init(provider: any RemoteSyncProvider, userState: UserStateStore, tokenStore: SyncTokenStoring)`.
- `private(set) var lastSyncedAt: Date?` (for optional UI/debug; not required by any screen in M5b).
- `func sync() async` — the §3 cycle; all provider calls wrapped so a throw is a silent no-op that leaves `lastToken` and pending intact (except a successful pull advances the token).
- `SyncTokenStoring` seam: `func load() -> SyncToken?` / `func save(_ token: SyncToken?)`. Real impl `UserDefaultsSyncTokenStore` (single key); an in-memory impl for tests. This keeps token persistence injectable and the coordinator unit-testable with no I/O.

## 7. `CloudKitSyncProvider` — `Core/Sync/CloudKitSyncProvider.swift`

Real implementation, all CloudKit confined here:
- `init(containerID: String = "iCloud.com.byzantinetrail.app")`; uses `container.privateCloudDatabase`.
- Record type **`UserSiteState`**, `recordName == siteId` (unique within the user's private DB). Fields: `isFavorite`, `wantsToVisit`, `visited` (Int 0/1 or Bool), `updatedAt` (Date). **No `myRating`.**
- `push(_ changes:)` — upsert one record per change (fetch-or-create by recordName, set fields incl. all-false, save). Never deletes.
- `pull(since token:)` — **query by timestamp**: `CKQuery(recordType: "UserSiteState", predicate: updatedAt > since)` (or `TRUEPREDICATE` when `token == nil`), paginated via the query cursor (same `allRecords(matching:)` helper pattern as `CloudKitRatingsService`). Map records → `[UserSiteChange]` (myRating = nil). New `SyncToken.raw` = the max `updatedAt` seen, else the prior token (ISO-8601 string). Records the app itself just pushed may return on the next pull; the LWW merge makes that a harmless no-op.
- Errors propagate to `SyncCoordinator`, which swallows them.

**Why query-by-timestamp, not custom-zone change tokens:** simpler (no custom `CKRecordZone`, no `CKServerChangeToken` archiving), and it fits the no-delete/all-false model. The cost — it cannot detect record deletions — does not apply because M5b never deletes records.

## 8. App wiring — `App/ByzantineTrailApp.swift`

- Construct a `SyncCoordinator` with the real `CloudKitSyncProvider` and a `UserDefaultsSyncTokenStore`, sharing the existing `UserStateStore` instance. The `MockRemoteSyncProvider` remains the documented offline-dev fallback (swap one line, mirroring the M5a mock/CloudKit toggle).
- Inject nothing new into the environment unless a view needs it (no M5b screen requires it); the coordinator is driven by app lifecycle only.
- Trigger `await syncCoordinator.sync()` from the existing launch `.task` (after account/catalog setup) and again on `scenePhase` transitions to `.active` (add a `.onChange(of: scenePhase)`).

## 9. CloudKit Dashboard (Development, private DB)

- Record type **`UserSiteState`** — auto-created on first write, or add explicitly (fields per §7).
- **One Queryable index on `updatedAt`** (required for the pull query). Optionally a Queryable index on `recordName` if a `TRUEPREDICATE` first-sync query needs it.
- **No security roles** — the private database is inherently scoped to the signed-in user.
- Do **not** deploy Development → Production until app release.

## 10. Testing

- **`SyncMerge`** (pure): absent+all-false → skip; absent+any-true → apply; newer-remote → apply; older-or-equal-remote → skip.
- **`UserStateStore`** (in-memory container): `apply(markPending:)` sets/omits `pendingSync` correctly for flags vs `setRating`; `pendingChanges()` returns exactly the dirty rows as `UserSiteChange`; `clearPending` clears them; `mergeRemote` applies/skips per LWW and prunes correctly; a flag toggled off is retained while pending and pruned after clear; the M4 `clearingRatingOnBareRowPrunesIt` behavior is preserved.
- **`SyncCoordinator`** (with `MockRemoteSyncProvider` + in-memory token store): full cycle pushes pending and clears it; pull merges by LWW; token advances on success and is persisted; a provider throw is a no-op that leaves pending + token intact; all-false remote clears a local flag.
- **`CloudKitSyncProvider`**: written + build-checked (compiles with `import CloudKit`, no new entitlement — already active). Because CloudKit is live and the simulator is iCloud-signed-in, integration-test in-session: make a change on one device, run `sync()`, confirm the record in the CloudKit Console (and, if feasible, that a second simulator signed into the same iCloud account pulls it).

## 11. Global constraints (carried into the plan)

- iOS 17+, Swift 6.2, SwiftUI. Tests use **Swift Testing** (`import Testing` / `@Test` / `#expect`) — never XCTest.
- All CloudKit code confined to `CloudKitSyncProvider.swift`.
- The local SwiftData store keeps `cloudKitDatabase: .none` and `@Attribute(.unique)`; **no** model CloudKit-compatibility changes.
- `myRating` is never read or written by the private-sync path.
- Every local mutation still routes through `UserStateStore.apply`; sync reads/writes go through the new store methods, not a parallel write path.
- XcodeGen: regenerate with the real binary `~/bin/xcodegen_dist/bin/xcodegen generate`. Build/test destination `platform=iOS Simulator,name=iPhone 16`. Commit author is already the GitHub no-reply address.

## 12. Rollout order (for the plan)

1. `UserSiteState.pendingSync` + relaxed prune.
2. `UserStateStore` sync methods (`apply(markPending:)`, `pendingChanges`, `clearPending`, `mergeRemote`).
3. `SyncMerge` (pure).
4. `SyncTokenStoring` + `UserDefaultsSyncTokenStore` + in-memory test store.
5. `SyncCoordinator` (mock-driven, full unit tests).
6. App wiring (mock provider) + launch/foreground triggers — build + full suite.
7. `CloudKitSyncProvider` (write + build-check).
8. Flip wiring to `CloudKitSyncProvider`; CloudKit Dashboard schema + `updatedAt` index; in-session integration test.
9. `docs/CLOUDKIT_SETUP.md` addendum for the private-DB record type + index.
