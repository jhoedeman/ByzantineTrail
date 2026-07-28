# M5c — Site Suggestions Submission (Design)

**Status:** approved 2026-07-28
**Milestone:** M5c (follows M5a public ratings, M5b private user-state sync)
**Seam:** `SuggestionSubmitting` (already exists; `MockSuggestionService` already exists)

## Goal

Let a user propose a Byzantine site that isn't in the catalog, from a form in
the Profile tab. The submission is written to a CloudKit **public** database
record type that only the owner reads (via the CloudKit Dashboard). No submitter
identity is stored. The whole feature is built and unit-tested against the
existing `MockSuggestionService`; the live CloudKit path is verified once at the
end, exactly as M5a/M5b were.

## Non-goals (YAGNI)

- **No offline queue / replay.** Offline or signed-out, the form's Submit is
  disabled with an explainer — the same *gate* pattern M5a ratings shipped with
  (`RatingGate`), not the "queue and replay" aspiration in the original design
  doc §Offline. This is a deliberate, approved deviation from that line.
- No editing, listing, or moderation of submissions in-app (owner reads via
  Dashboard).
- No submitter identity fields, no analytics.

## Architecture

Mirror the proven M5a shape: **pure logic units** + a thin `@MainActor
@Observable` **store** + a **live CloudKit service confined to one file** +
**gated UI**. Because submission gates (rather than queues) when offline, no
durable queue is needed and every unit is testable without an Apple Developer
account.

```
SuggestSiteForm (View, Profile → Contribute)
    reads AccountStore + NetworkMonitor (environment, like RatingSection)
    owns field @State
        │
        ▼
SuggestionStore (@MainActor @Observable)
    validate → throttle-check → service.submit → record timestamp on success
        │                    │                        │
        ▼                    ▼                        ▼
SuggestionValidator   SuggestionRateLimiter +   SuggestionSubmitting
   (pure)             SuggestionThrottleStore     └ CloudKitSuggestionService (live)
                          (pure + persistence)     └ MockSuggestionService (tests)

SuggestionGate (pure): account → network → rate-limit precedence → Submit enabled?
```

### Existing seam (unchanged)

```swift
struct SiteSuggestion: Equatable, Sendable {
    let name: String
    let location, whyInclude, linksText: String?
}
protocol SuggestionSubmitting: Sendable {
    func submit(_ suggestion: SiteSuggestion) async throws
}
```

`submittedAt` is **not** in `SiteSuggestion` — it is stamped by the live service
at write time, so it never has to be threaded through the UI or the mock.

## Components

### 1. `SuggestionValidator` (pure) — `Core/Suggestions/SuggestionValidator.swift`

Turns the form's raw strings into a validated `SiteSuggestion` or a list of
problems.

- `name`: **required** — non-empty after trimming whitespace/newlines.
- `location`, `whyInclude`, `linksText`: optional — trimmed; empty → `nil`.
- Length caps (validated on the trimmed value): name ≤ 120, location ≤ 120,
  whyInclude ≤ 1000, linksText ≤ 500.

```swift
enum SuggestionValidator {
    enum Problem: Equatable { case nameRequired, tooLong(field: Field) }
    enum Field: Equatable { case name, location, whyInclude, linksText }

    /// `.success(SiteSuggestion)` when valid; `.failure([Problem])` otherwise
    /// (problems in a stable order: name first, then location, why, links).
    static func validate(name: String, location: String,
                         whyInclude: String, linksText: String)
        -> Result<SiteSuggestion, [Problem]>
}
```

Trimming uses `.trimmingCharacters(in: .whitespacesAndNewlines)`. Optional
fields that trim to empty become `nil` in the produced `SiteSuggestion`.

### 2. `SuggestionRateLimiter` (pure) + `SuggestionThrottleStore`

`Core/Suggestions/SuggestionRateLimiter.swift`

Soft anti-spam guardrail: **max 10 submissions per rolling 24 h**.

```swift
enum SuggestionRateLimiter {
    static let maxPerWindow = 10
    static let window: TimeInterval = 24 * 60 * 60

    struct Decision: Equatable { let allowed: Bool; let remaining: Int }

    /// Prune timestamps older than `now - window`, then decide.
    /// remaining = max(0, maxPerWindow - recentCount); allowed = remaining > 0.
    static func decide(recent: [Date], now: Date) -> Decision

    /// The pruned, still-recent timestamps (what the store should persist
    /// after a successful submit, with `now` appended).
    static func pruned(_ timestamps: [Date], now: Date) -> [Date]
}
```

Persistence mirrors `SyncTokenStore` exactly:

`Core/Suggestions/SuggestionThrottleStore.swift`

```swift
protocol SuggestionThrottleStoring {
    func load() -> [Date]
    func save(_ timestamps: [Date])
}
struct UserDefaultsSuggestionThrottleStore: SuggestionThrottleStoring { /* key "byzantinetrail.suggest.timestamps" */ }
final class InMemorySuggestionThrottleStore: SuggestionThrottleStoring { /* for tests */ }
```

Timestamps are stored as `[Date]` (encoded via `UserDefaults` `Array` of
`timeIntervalSince1970` `Double`s, matching the token store's simple encoding).

### 3. `SuggestionGate` (pure) — `Core/Suggestions/SuggestionGate.swift`

Mirrors `RatingGate`, with rate-limit added at lowest precedence.

```swift
enum SuggestionGate {
    struct State: Equatable { let isEnabled: Bool; let explainer: String? }

    static func evaluate(status: AccountStatus, isOnline: Bool,
                         remaining: Int) -> State
}
```

Precedence and copy:
1. `status != .available` → disabled, "Sign in to iCloud to suggest a site."
2. `!isOnline` → disabled, "Connect to the internet to suggest a site."
3. `remaining <= 0` → disabled, "You've reached today's suggestion limit (10)."
4. otherwise → enabled, `explainer == nil`.

Note this gate governs the *account/network/quota* preconditions. Field
validity (e.g. empty name) is governed separately by `SuggestionValidator` and
disables Submit in the view; the two are independent so each is trivially
testable.

### 4. `SuggestionStore` (`@MainActor @Observable`) — `Core/Suggestions/SuggestionStore.swift`

Thin orchestration over the seam, matching `RatingsStore`'s shape.

```swift
@MainActor @Observable
final class SuggestionStore {
    enum SubmitResult: Equatable { case success, invalid([SuggestionValidator.Problem]), rateLimited, failed }

    private(set) var isSubmitting = false
    private(set) var remaining: Int          // for the gate; refreshed from throttle store

    init(service: SuggestionSubmitting, throttle: SuggestionThrottleStoring, now: @escaping () -> Date = Date.init)

    /// validate → throttle-check → service.submit → on success append `now()` to
    /// the throttle store and decrement `remaining`. Never throws; returns a result.
    func submit(name: String, location: String, whyInclude: String, linksText: String) async -> SubmitResult

    /// Recompute `remaining` from the throttle store (call on form appear).
    func refreshRemaining()
}
```

- The injectable `now` closure makes the 24 h window deterministic in tests.
- A thrown error from `service.submit` → `.failed` (swallowed, surfaced as
  inline error copy in the view). No retry, no queue.
- `remaining` is derived via `SuggestionRateLimiter.decide(recent:now:)` so the
  store and gate agree.

### 5. `CloudKitSuggestionService: SuggestionSubmitting` — `Core/Suggestions/CloudKitSuggestionService.swift`

The only file that imports CloudKit for this feature (matches the
`CloudKitRatingsService` convention).

```swift
final class CloudKitSuggestionService: SuggestionSubmitting {
    private let db: CKDatabase
    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        db = CKContainer(identifier: containerID).publicCloudDatabase
    }
    func submit(_ s: SiteSuggestion) async throws {
        let rec = CKRecord(recordType: "SiteSuggestion") // random UUID recordName
        rec["name"] = s.name as CKRecordValue
        if let v = s.location    { rec["location"]    = v as CKRecordValue }
        if let v = s.whyInclude  { rec["whyInclude"]  = v as CKRecordValue }
        if let v = s.linksText   { rec["linksText"]   = v as CKRecordValue }
        rec["submittedAt"] = Date() as CKRecordValue
        _ = try await db.save(rec)
    }
}
```

No submitter identity is written. The record's default `recordName` is a random
UUID; no `userRecordID` is fetched or stored.

### 6. UI — `SuggestSiteForm` + Profile "Contribute" section

`Features/Profile/SuggestSiteForm.swift` — a `Form`/`List`-style screen:

- Fields: `name` (required), `location`, `whyInclude` (multi-line), `linksText`.
- A gated **Submit**: enabled only when `SuggestionGate.evaluate(...).isEnabled`
  **and** the name field is non-empty (cheap client check; full validation runs
  on submit). Gate explainer shown as caption when disabled.
- On `.success`: clear fields, show an inline "Thanks — your suggestion was
  sent." confirmation. On `.invalid`/`.rateLimited`/`.failed`: inline error
  caption with appropriate copy.
- Accessibility identifiers: `suggest.name`, `suggest.location`, `suggest.why`,
  `suggest.links`, `suggest.submit`, `suggest.status`.
- Reads `AccountStore`, `NetworkMonitor`, `SuggestionStore` from the environment
  (like `RatingSection`); `.task { store.refreshRemaining() }` on appear.

`Features/Profile/ProfileView.swift` — add after the Progress section:

```swift
Section("Contribute") {
    NavigationLink { SuggestSiteForm(theme: theme) } label: {
        Label("Suggest a site", systemImage: "plus.circle")
    }
}
```

### 7. Wiring — `App/ByzantineTrailApp.swift`

```swift
@State private var suggestionStore: SuggestionStore
// in init():
_suggestionStore = State(initialValue: SuggestionStore(
    service: CloudKitSuggestionService(),
    throttle: UserDefaultsSuggestionThrottleStore()))
// in body: .environment(suggestionStore)
```

Wired live like M5a. To run offline/without iCloud during development, the gate
disables Submit and the store no-ops — no mock swap required.

### 8. Docs — `docs/CLOUDKIT_SETUP.md` addendum

New "## M5c — site suggestions (public database, create-only)" section:

- Record type **`SiteSuggestion`** — fields `name` (String), `location`
  (String), `whyInclude` (String), `linksText` (String), `submittedAt` (Date).
  Auto-created on first write.
- Security role: **`_icloud` create-only** (no read, no write) so authenticated
  users can submit but cannot read others' suggestions; **owner reads via the
  Dashboard**. Dashboard-only configuration.
- No indexes required (owner browses records in the Dashboard; the app never
  queries this type).
- Note: the client rate-limit (10 / 24 h) is a soft UX guardrail only — not a
  security control.

## Testing

All pure/unit, mock-driven — no Apple Developer account for the whole build.

- **`SuggestionValidatorTests`** — required name; whitespace-only name fails;
  trimming; empty optionals → nil; each length cap boundary (≤ passes, +1 fails);
  problem ordering.
- **`SuggestionRateLimiterTests`** — under limit allows; at limit denies;
  pruning drops timestamps older than 24 h; `remaining` math; boundary at
  exactly `now - window`.
- **`SuggestionThrottleStoreTests`** — UserDefaults round-trip (save/load/empty);
  in-memory round-trip.
- **`SuggestionGateTests`** — precedence: signed-out beats offline beats
  rate-limited; enabled only when all pass; exact explainer strings.
- **`SuggestionStoreTests`** (`@MainActor`, `MockSuggestionService` +
  `InMemorySuggestionThrottleStore` + fixed `now`) — valid submit calls the
  service once and records a timestamp / decrements `remaining`; invalid submit
  does **not** call the service and returns `.invalid`; rate-limited submit does
  not call the service; a throwing service yields `.failed` and records **no**
  timestamp.

The live `CloudKitSuggestionService` path is verified once at the end
(submit from the simulator, confirm one `SiteSuggestion` record appears in the
Dashboard), the same way M5b Task 8 was verified.

## Build order (informs the plan)

1. `SuggestionValidator` (+ tests)
2. `SuggestionRateLimiter` + `SuggestionThrottleStore` (+ tests)
3. `SuggestionGate` (+ tests)
4. `SuggestionStore` (+ tests, mock-driven)
5. `CloudKitSuggestionService` (live; compiles, no unit test)
6. `SuggestSiteForm` + Profile "Contribute" link
7. Wire `SuggestionStore` into `ByzantineTrailApp`
8. `CLOUDKIT_SETUP.md` addendum
9. Live verification (simulator → Dashboard)

## Global constraints (carried from the project)

- iOS 17+, Swift 6.2, SwiftUI + SwiftData + CloudKit; Swift Testing (`import
  Testing`, `@Test`, `#expect`) — never XCTest.
- Regenerate the project with the **real** XcodeGen binary:
  `~/bin/xcodegen_dist/bin/xcodegen generate` (the `xcodegen` symlink silently
  fails). `.xcodeproj` is gitignored.
- Build/test destination: `platform=iOS Simulator,name=iPhone 16`.
- **Privacy hard rule:** the owner's email must never appear in the public repo;
  commit with the GitHub no-reply address. Owner name, code, and Team ID
  (`XY62X6K9VH`) are fine public.
- No submitter identity in `SiteSuggestion` records; no analytics.
