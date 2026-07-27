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
- **CloudKit robustness:** The service is hardened for pagination (`allSummaries`/`reconcile` follow query cursors across all pages), failed deletes (propagated in `removeRating`), and transient errors (distinguishes `CKError.unknownItem` — no prior rating — from fetch errors in `submit`). Exercise these in integration testing: rate a site across a page boundary, and verify persistence after rate/edit/remove/relaunch.
- Promotion to the Production CloudKit environment is a later step.
