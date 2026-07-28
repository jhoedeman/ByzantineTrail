# CloudKit setup (M5a — public ratings)

Ratings use a **CloudKit public database**. Until you complete this one-time
setup, the app runs against an in-memory mock service (averages are demo data).
These steps require your Apple Developer account and are done in Xcode + the
CloudKit Dashboard — not by an automated agent.

## 1. Enable the capability
The **entitlement is already wired** — `project.yml` has an `entitlements:` block
that XcodeGen uses to generate `ByzantineTrail/ByzantineTrail.entitlements`
(container `iCloud.com.byzantinetrail.app`, service `CloudKit`). You do **not**
re-add the capability by hand in Xcode; XcodeGen owns that file. What's left:

1. Set your **signing Team**. With XcodeGen, a Team set in Xcode's UI is wiped on
   the next `xcodegen generate`, so put it in `project.yml` under the app target's
   `settings.base` as `DEVELOPMENT_TEAM: <YOUR_TEAM_ID>` — **or**, to keep your
   Team ID out of this public repo, in a gitignored local xcconfig. Then
   regenerate: `~/bin/xcodegen_dist/bin/xcodegen generate`.
2. On developer.apple.com, ensure the App ID has **iCloud** enabled and the
   **container `iCloud.com.byzantinetrail.app`** exists (Xcode's automatic signing
   will offer to create it once a Team is set).

> **Note — the local SwiftData store stays off CloudKit.**
> `UserStateStore.makeContainer` sets `ModelConfiguration(cloudKitDatabase: .none)`
> on purpose: the entitlement powers only the **public-DB ratings** (via
> `CKContainer` in `CloudKitRatingsService`), not SwiftData sync. Without `.none`,
> SwiftData's `.automatic` default would try to CloudKit-mirror `UserSiteState` and
> crash at launch (CloudKit requires every attribute optional/defaulted). When you
> build **M5b** (private user-state sync), that's where you flip this back and make
> `UserSiteState` CloudKit-compatible.

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
1. In the simulator: Settings → **"Sign in to your iPhone"** with any real iCloud
   account (your own is fine — there is **no** separate "CloudKit sandbox"
   account; that's a StoreKit concept). Debug builds automatically use the
   CloudKit **Development** environment, isolated from Production; the record's
   `userRecordID` is an opaque per-container id, not your email. You can wipe dev
   data anytime via the Console → **Reset Development Environment**.
2. Run the app; open a site; rate it → the average/count update; change it → the
   average adjusts; remove → the count drops; relaunch → the value persists.
3. Sign out of iCloud → the rating control disables with "Sign in to iCloud to rate."
4. Turn off networking → the control disables with "Connect to the internet to rate."

## Notes
- The in-app recompute reconcile (on detail open / on retry exhaustion) is the
  self-healer. A standalone "rebuild all summaries" owner script is deferred.
- **CloudKit robustness:** The service is hardened for three cases:
  - **Pagination** — `allSummaries`/`reconcile` follow query cursors across
    all pages (no undercount overwrite on large result sets).
  - **Failed deletes** — propagated in `removeRating` (not silently swallowed).
  - **Transient errors** — `submit` distinguishes `CKError.unknownItem`
    (no prior rating) from a transient fetch error, so an edit isn't
    double-counted.

  Exercise these in integration testing: rate a site across a page boundary,
  and verify persistence after rate/edit/remove/relaunch.
- Promotion to the Production CloudKit environment is a later step.

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

## M5c — site suggestions (public database, create-only)

Users can propose a site from **Profile → Contribute → Suggest a site**. The
form writes to the **public** CloudKit database via `CloudKitSuggestionService`.

### Schema (Development, Public DB)
- Record type **`SiteSuggestion`** — fields `name` (String), `location`
  (String), `whyInclude` (String), `linksText` (String), `submittedAt` (Date).
  Auto-created on the first submit.
- **No submitter identity** is stored (random UUID recordName; no `userRecordID`).

### Security role (Dashboard-only)
- Set the `_icloud` (authenticated users) role on `SiteSuggestion` to
  **create-only** — create allowed, **no read, no write**. Authenticated users
  can submit but cannot read anyone's suggestions (including their own). The
  **owner reads submissions in the CloudKit Dashboard**.
- No indexes are required — the app never queries this type.

### Notes
- The client rate limit (10 submissions / rolling 24 h, in `SuggestionRateLimiter`)
  is a soft UX guardrail only — **not** a security control.
- Offline / signed-out, the form's Submit is disabled with an explainer
  (`SuggestionGate`); submissions are **not** queued for later replay.
- Do not deploy the schema Development → Production until app release.
