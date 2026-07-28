# M5c — Site Suggestions Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user propose a Byzantine site from a gated form in the Profile tab, written to a create-only CloudKit public record with no submitter identity.

**Architecture:** Mirror the shipped M5a shape — pure logic units (`SuggestionValidator`, `SuggestionRateLimiter`, `SuggestionGate`) + a thin `@MainActor @Observable` `SuggestionStore` + a live `CloudKitSuggestionService` confined to one file + a gated `SuggestSiteForm`. Offline/signed-out **gates** (disables Submit) rather than queueing, so no durable queue exists. Everything but the live service is unit-tested against the existing `MockSuggestionService`.

**Tech Stack:** Swift 6.2, SwiftUI, CloudKit (public DB), Swift Testing.

## Global Constraints

- iOS 17+, Swift 6.2; SwiftUI + CloudKit. **Swift Testing only** (`import Testing`, `@Test`, `#expect`) — never XCTest.
- New/removed source files require regenerating the project with the **real** binary: `~/bin/xcodegen_dist/bin/xcodegen generate` (the bare `xcodegen` symlink silently fails). `.xcodeproj` is gitignored.
- Build/test destination: `platform=iOS Simulator,name=iPhone 16`.
- **Privacy hard rule:** the owner's email must never appear in the public repo — commit only with the configured GitHub no-reply address (already set). Owner name, code, and Team ID (`XY62X6K9VH`) are fine public.
- `SiteSuggestion` records carry **no submitter identity**; no analytics.
- Rate limit: **10 submissions per rolling 24 h**. Field length caps: name ≤ 120, location ≤ 120, whyInclude ≤ 1000, linksText ≤ 500.
- Existing seam (do not change): `struct SiteSuggestion: Equatable, Sendable { let name: String; let location, whyInclude, linksText: String? }` and `protocol SuggestionSubmitting: Sendable { func submit(_ suggestion: SiteSuggestion) async throws }`.

### Standard commands (referenced by tasks)

**Regenerate + run the full test target** (Swift TDD: a test referencing a not-yet-written type fails at *compile*, which is the red state):

```bash
~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild test -scheme ByzantineTrail \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ByzantineTrailTests 2>&1 | tail -30
```

**Regenerate + build only** (for UI/live-service tasks with no unit test):

```bash
~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild build -scheme ByzantineTrail \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

All new source files live under folders XcodeGen already globs (`ByzantineTrail/Core/Suggestions/`, `ByzantineTrail/Features/Profile/`, `ByzantineTrailTests/`), so no `project.yml` edit is needed — only a regenerate.

---

### Task 1: SuggestionValidator (pure)

**Files:**
- Create: `ByzantineTrail/Core/Suggestions/SuggestionValidator.swift`
- Test: `ByzantineTrailTests/SuggestionValidatorTests.swift`

**Interfaces:**
- Consumes: `SiteSuggestion` (existing seam).
- Produces:
  - `enum SuggestionValidator.Field: Equatable { case name, location, whyInclude, linksText }`
  - `enum SuggestionValidator.Problem: Equatable { case nameRequired, tooLong(field: Field) }`
  - `static func SuggestionValidator.validate(name: String, location: String, whyInclude: String, linksText: String) -> Result<SiteSuggestion, [Problem]>`
  - `static let maxName = 120`, `maxLocation = 120`, `maxWhyInclude = 1000`, `maxLinksText = 500`

- [ ] **Step 1: Write the failing test**

Create `ByzantineTrailTests/SuggestionValidatorTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct SuggestionValidatorTests {
    @Test func requiresNonEmptyName() {
        let r = SuggestionValidator.validate(name: "   ", location: "", whyInclude: "", linksText: "")
        #expect(r == .failure([.nameRequired]))
    }

    @Test func trimsAndDropsEmptyOptionals() {
        let r = SuggestionValidator.validate(name: "  Hagia  ", location: " ",
                                             whyInclude: "", linksText: "  x ")
        #expect(r == .success(SiteSuggestion(name: "Hagia", location: nil,
                                             whyInclude: nil, linksText: "x")))
    }

    @Test func nameAtCapPasses() {
        let ok = String(repeating: "a", count: 120)
        let r = SuggestionValidator.validate(name: ok, location: "", whyInclude: "", linksText: "")
        #expect(r == .success(SiteSuggestion(name: ok, location: nil, whyInclude: nil, linksText: nil)))
    }

    @Test func nameOverCapFails() {
        let tooLong = String(repeating: "a", count: 121)
        #expect(SuggestionValidator.validate(name: tooLong, location: "", whyInclude: "", linksText: "")
            == .failure([.tooLong(field: .name)]))
    }

    @Test func eachOptionalFieldCapEnforced() {
        #expect(SuggestionValidator.validate(name: "n", location: String(repeating: "b", count: 121),
                                             whyInclude: "", linksText: "")
            == .failure([.tooLong(field: .location)]))
        #expect(SuggestionValidator.validate(name: "n", location: "",
                                             whyInclude: String(repeating: "c", count: 1001), linksText: "")
            == .failure([.tooLong(field: .whyInclude)]))
        #expect(SuggestionValidator.validate(name: "n", location: "", whyInclude: "",
                                             linksText: String(repeating: "d", count: 501))
            == .failure([.tooLong(field: .linksText)]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the **Regenerate + run the full test target** command.
Expected: **compile failure** — `cannot find 'SuggestionValidator' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ByzantineTrail/Core/Suggestions/SuggestionValidator.swift`:

```swift
import Foundation

/// Pure validation for the Suggest-a-Site form (M5c). Trims input, enforces a
/// required name and per-field length caps, and produces a `SiteSuggestion`
/// (optional fields empty → nil). No I/O — unit-tested alone.
enum SuggestionValidator {
    enum Field: Equatable { case name, location, whyInclude, linksText }
    enum Problem: Equatable { case nameRequired, tooLong(field: Field) }

    static let maxName = 120
    static let maxLocation = 120
    static let maxWhyInclude = 1000
    static let maxLinksText = 500

    static func validate(name: String, location: String,
                         whyInclude: String, linksText: String)
        -> Result<SiteSuggestion, [Problem]> {
        let n = trim(name), loc = trim(location), why = trim(whyInclude), links = trim(linksText)

        var problems: [Problem] = []
        if n.isEmpty { problems.append(.nameRequired) }
        if n.count > maxName { problems.append(.tooLong(field: .name)) }
        if loc.count > maxLocation { problems.append(.tooLong(field: .location)) }
        if why.count > maxWhyInclude { problems.append(.tooLong(field: .whyInclude)) }
        if links.count > maxLinksText { problems.append(.tooLong(field: .linksText)) }

        guard problems.isEmpty else { return .failure(problems) }
        return .success(SiteSuggestion(name: n, location: nilIfEmpty(loc),
                                       whyInclude: nilIfEmpty(why), linksText: nilIfEmpty(links)))
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the **Regenerate + run the full test target** command.
Expected: **TEST SUCCEEDED** — all 5 new tests pass, plus the existing suite (150+ tests) stays green.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Suggestions/SuggestionValidator.swift ByzantineTrailTests/SuggestionValidatorTests.swift
git commit -m "M5c Task 1: SuggestionValidator (required name, trim, length caps)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: SuggestionRateLimiter + SuggestionThrottleStore

**Files:**
- Create: `ByzantineTrail/Core/Suggestions/SuggestionRateLimiter.swift`
- Create: `ByzantineTrail/Core/Suggestions/SuggestionThrottleStore.swift`
- Test: `ByzantineTrailTests/SuggestionRateLimiterTests.swift`
- Test: `ByzantineTrailTests/SuggestionThrottleStoreTests.swift`

**Interfaces:**
- Produces:
  - `static let SuggestionRateLimiter.maxPerWindow = 10`, `static let window: TimeInterval = 24*60*60`
  - `struct SuggestionRateLimiter.Decision: Equatable { let allowed: Bool; let remaining: Int }`
  - `static func SuggestionRateLimiter.pruned(_ timestamps: [Date], now: Date) -> [Date]` (keeps `t > now - window`)
  - `static func SuggestionRateLimiter.decide(recent: [Date], now: Date) -> Decision`
  - `protocol SuggestionThrottleStoring { func load() -> [Date]; func save(_ timestamps: [Date]) }`
  - `struct UserDefaultsSuggestionThrottleStore: SuggestionThrottleStoring` (init `defaults: UserDefaults = .standard`)
  - `final class InMemorySuggestionThrottleStore: SuggestionThrottleStoring` (init `_ timestamps: [Date] = []`)

- [ ] **Step 1: Write the failing tests**

Create `ByzantineTrailTests/SuggestionRateLimiterTests.swift`:

```swift
import Testing
import Foundation
@testable import ByzantineTrail

struct SuggestionRateLimiterTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func allowsUnderLimit() {
        let d = SuggestionRateLimiter.decide(recent: Array(repeating: now, count: 9), now: now)
        #expect(d == .init(allowed: true, remaining: 1))
    }

    @Test func deniesAtLimit() {
        let d = SuggestionRateLimiter.decide(recent: Array(repeating: now, count: 10), now: now)
        #expect(d == .init(allowed: false, remaining: 0))
    }

    @Test func prunesAtAndBeforeWindowEdge() {
        let old = now.addingTimeInterval(-SuggestionRateLimiter.window - 1)
        let edge = now.addingTimeInterval(-SuggestionRateLimiter.window) // exactly at cutoff → pruned
        let fresh = now.addingTimeInterval(-1)
        #expect(SuggestionRateLimiter.pruned([old, edge, fresh], now: now) == [fresh])
    }

    @Test func remainingCountsOnlyRecent() {
        let old = now.addingTimeInterval(-SuggestionRateLimiter.window - 1)
        let recent = Array(repeating: now.addingTimeInterval(-10), count: 3)
        #expect(SuggestionRateLimiter.decide(recent: [old] + recent, now: now).remaining == 7)
    }
}
```

Create `ByzantineTrailTests/SuggestionThrottleStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import ByzantineTrail

struct SuggestionThrottleStoreTests {
    @Test func userDefaultsRoundTrips() {
        let defaults = UserDefaults(suiteName: "m5c.throttle.test")!
        defaults.removePersistentDomain(forName: "m5c.throttle.test")
        let store = UserDefaultsSuggestionThrottleStore(defaults: defaults)
        #expect(store.load().isEmpty)
        let ts = [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)]
        store.save(ts)
        #expect(store.load() == ts)
    }

    @Test func inMemoryRoundTrips() {
        let store = InMemorySuggestionThrottleStore()
        #expect(store.load().isEmpty)
        let ts = [Date(timeIntervalSince1970: 1)]
        store.save(ts)
        #expect(store.load() == ts)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the **Regenerate + run the full test target** command.
Expected: **compile failure** — `cannot find 'SuggestionRateLimiter' in scope` / `'UserDefaultsSuggestionThrottleStore' in scope`.

- [ ] **Step 3: Write the implementations**

Create `ByzantineTrail/Core/Suggestions/SuggestionRateLimiter.swift`:

```swift
import Foundation

/// Pure rolling-window rate limit for site suggestions (M5c): at most
/// `maxPerWindow` submissions per `window`. Operates on stored timestamps;
/// persistence lives in `SuggestionThrottleStore`. No I/O — unit-tested alone.
enum SuggestionRateLimiter {
    static let maxPerWindow = 10
    static let window: TimeInterval = 24 * 60 * 60

    struct Decision: Equatable { let allowed: Bool; let remaining: Int }

    /// Timestamps strictly newer than `now - window` (edge and older are dropped).
    static func pruned(_ timestamps: [Date], now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-window)
        return timestamps.filter { $0 > cutoff }
    }

    static func decide(recent: [Date], now: Date) -> Decision {
        let remaining = max(0, maxPerWindow - pruned(recent, now: now).count)
        return Decision(allowed: remaining > 0, remaining: remaining)
    }
}
```

Create `ByzantineTrail/Core/Suggestions/SuggestionThrottleStore.swift`:

```swift
import Foundation

/// Persistence seam for suggestion submission timestamps (M5c rate limit).
/// Injected so `SuggestionStore` is testable with no I/O. Main-actor use only.
protocol SuggestionThrottleStoring {
    func load() -> [Date]
    func save(_ timestamps: [Date])
}

struct UserDefaultsSuggestionThrottleStore: SuggestionThrottleStoring {
    private let key = "byzantinetrail.suggest.timestamps"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [Date] {
        let raw = defaults.array(forKey: key) as? [Double] ?? []
        return raw.map { Date(timeIntervalSince1970: $0) }
    }
    func save(_ timestamps: [Date]) {
        defaults.set(timestamps.map { $0.timeIntervalSince1970 }, forKey: key)
    }
}

/// In-memory throttle store for tests.
final class InMemorySuggestionThrottleStore: SuggestionThrottleStoring {
    private var timestamps: [Date]
    init(_ timestamps: [Date] = []) { self.timestamps = timestamps }
    func load() -> [Date] { timestamps }
    func save(_ timestamps: [Date]) { self.timestamps = timestamps }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the **Regenerate + run the full test target** command.
Expected: **TEST SUCCEEDED** — 6 new tests pass; existing suite green.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Suggestions/SuggestionRateLimiter.swift ByzantineTrail/Core/Suggestions/SuggestionThrottleStore.swift ByzantineTrailTests/SuggestionRateLimiterTests.swift ByzantineTrailTests/SuggestionThrottleStoreTests.swift
git commit -m "M5c Task 2: SuggestionRateLimiter (10/24h rolling) + throttle store seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: SuggestionGate (pure)

**Files:**
- Create: `ByzantineTrail/Core/Suggestions/SuggestionGate.swift`
- Test: `ByzantineTrailTests/SuggestionGateTests.swift`

**Interfaces:**
- Consumes: `AccountStatus` (cases `.available, .noAccount, .restricted, .unknown`).
- Produces:
  - `struct SuggestionGate.State: Equatable { let isEnabled: Bool; let explainer: String? }`
  - `static func SuggestionGate.evaluate(status: AccountStatus, isOnline: Bool, remaining: Int) -> State`

- [ ] **Step 1: Write the failing test**

Create `ByzantineTrailTests/SuggestionGateTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct SuggestionGateTests {
    @Test func signedOutBeatsEverything() {
        let s = SuggestionGate.evaluate(status: .noAccount, isOnline: false, remaining: 0)
        #expect(s == .init(isEnabled: false, explainer: "Sign in to iCloud to suggest a site."))
    }

    @Test func offlineBeatsRateLimit() {
        let s = SuggestionGate.evaluate(status: .available, isOnline: false, remaining: 0)
        #expect(s == .init(isEnabled: false, explainer: "Connect to the internet to suggest a site."))
    }

    @Test func rateLimitedWhenNoneRemain() {
        let s = SuggestionGate.evaluate(status: .available, isOnline: true, remaining: 0)
        #expect(s == .init(isEnabled: false, explainer: "You've reached today's suggestion limit (10)."))
    }

    @Test func enabledWhenAllPass() {
        let s = SuggestionGate.evaluate(status: .available, isOnline: true, remaining: 3)
        #expect(s == .init(isEnabled: true, explainer: nil))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the **Regenerate + run the full test target** command.
Expected: **compile failure** — `cannot find 'SuggestionGate' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ByzantineTrail/Core/Suggestions/SuggestionGate.swift`:

```swift
/// Pure gating for the Suggest-a-Site Submit control (M5c). Precedence:
/// account availability, then connectivity, then the client rate limit.
/// Mirrors `RatingGate`.
enum SuggestionGate {
    struct State: Equatable {
        let isEnabled: Bool
        let explainer: String?
    }

    static func evaluate(status: AccountStatus, isOnline: Bool, remaining: Int) -> State {
        guard status == .available else {
            return .init(isEnabled: false, explainer: "Sign in to iCloud to suggest a site.")
        }
        guard isOnline else {
            return .init(isEnabled: false, explainer: "Connect to the internet to suggest a site.")
        }
        guard remaining > 0 else {
            return .init(isEnabled: false, explainer: "You've reached today's suggestion limit (10).")
        }
        return .init(isEnabled: true, explainer: nil)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the **Regenerate + run the full test target** command.
Expected: **TEST SUCCEEDED** — 4 new tests pass; existing suite green.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Suggestions/SuggestionGate.swift ByzantineTrailTests/SuggestionGateTests.swift
git commit -m "M5c Task 3: SuggestionGate (account -> network -> rate-limit precedence)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: SuggestionStore (+ StubSuggestionService)

**Files:**
- Create: `ByzantineTrail/Core/Suggestions/SuggestionStore.swift`
- Modify: `ByzantineTrailTests/Mocks/MockProviders.swift` (append `StubSuggestionService`)
- Test: `ByzantineTrailTests/SuggestionStoreTests.swift`

**Interfaces:**
- Consumes: `SuggestionValidator`, `SuggestionRateLimiter`, `SuggestionThrottleStoring`, `SuggestionSubmitting`, `SiteSuggestion`.
- Produces:
  - `@MainActor @Observable final class SuggestionStore`
  - `enum SuggestionStore.SubmitResult: Equatable { case success; case invalid([SuggestionValidator.Problem]); case rateLimited; case failed }`
  - `init(service: any SuggestionSubmitting, throttle: any SuggestionThrottleStoring, now: @escaping () -> Date = Date.init)`
  - `private(set) var isSubmitting: Bool`, `private(set) var remaining: Int`
  - `func refreshRemaining()`
  - `func submit(name: String, location: String, whyInclude: String, linksText: String) async -> SubmitResult`
  - Test double: `actor StubSuggestionService: SuggestionSubmitting` with `init(failSubmit: Bool = false)` and `private(set) var submitted: [SiteSuggestion]`.

- [ ] **Step 1: Write the failing test + test double**

Append to `ByzantineTrailTests/Mocks/MockProviders.swift` (keep the existing `MockSuggestionService` — `SeamTests` uses it):

```swift

/// Controllable SuggestionSubmitting for store tests: captures submissions and
/// can force a failure. (The plain `MockSuggestionService` above always succeeds.)
actor StubSuggestionService: SuggestionSubmitting {
    private let failSubmit: Bool
    private(set) var submitted: [SiteSuggestion] = []
    struct StubError: Error {}
    init(failSubmit: Bool = false) { self.failSubmit = failSubmit }
    func submit(_ suggestion: SiteSuggestion) async throws {
        if failSubmit { throw StubError() }
        submitted.append(suggestion)
    }
}
```

Create `ByzantineTrailTests/SuggestionStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import ByzantineTrail

@MainActor
struct SuggestionStoreTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func make(service: any SuggestionSubmitting, seed: [Date] = [])
        -> (SuggestionStore, InMemorySuggestionThrottleStore) {
        let throttle = InMemorySuggestionThrottleStore(seed)
        let store = SuggestionStore(service: service, throttle: throttle, now: { self.now })
        return (store, throttle)
    }

    @Test func validSubmitCallsServiceAndRecordsTimestamp() async {
        let stub = StubSuggestionService()
        let (store, throttle) = make(service: stub)
        let result = await store.submit(name: "Hagia Sophia", location: "Istanbul",
                                        whyInclude: "", linksText: "")
        #expect(result == .success)
        let submitted = await stub.submitted
        #expect(submitted == [SiteSuggestion(name: "Hagia Sophia", location: "Istanbul",
                                             whyInclude: nil, linksText: nil)])
        #expect(throttle.load() == [now])
        #expect(store.remaining == SuggestionRateLimiter.maxPerWindow - 1)
    }

    @Test func invalidSubmitSkipsServiceAndRecordsNothing() async {
        let stub = StubSuggestionService()
        let (store, throttle) = make(service: stub)
        let result = await store.submit(name: "   ", location: "", whyInclude: "", linksText: "")
        #expect(result == .invalid([.nameRequired]))
        let submitted = await stub.submitted
        #expect(submitted.isEmpty)
        #expect(throttle.load().isEmpty)
    }

    @Test func rateLimitedSubmitSkipsService() async {
        let stub = StubSuggestionService()
        let seed = Array(repeating: now.addingTimeInterval(-10),
                         count: SuggestionRateLimiter.maxPerWindow)
        let (store, _) = make(service: stub, seed: seed)
        let result = await store.submit(name: "Valid", location: "", whyInclude: "", linksText: "")
        #expect(result == .rateLimited)
        let submitted = await stub.submitted
        #expect(submitted.isEmpty)
    }

    @Test func failedServiceRecordsNoTimestamp() async {
        let stub = StubSuggestionService(failSubmit: true)
        let (store, throttle) = make(service: stub)
        let result = await store.submit(name: "Valid", location: "", whyInclude: "", linksText: "")
        #expect(result == .failed)
        #expect(throttle.load().isEmpty)
        #expect(store.remaining == SuggestionRateLimiter.maxPerWindow)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the **Regenerate + run the full test target** command.
Expected: **compile failure** — `cannot find 'SuggestionStore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ByzantineTrail/Core/Suggestions/SuggestionStore.swift`:

```swift
import Observation
import Foundation

/// Observable orchestration for site suggestions (M5c). Validates the form,
/// enforces the client rate limit, calls the `SuggestionSubmitting` seam, and
/// records a timestamp on success. Never throws; returns a `SubmitResult`.
@MainActor
@Observable
final class SuggestionStore {
    enum SubmitResult: Equatable {
        case success
        case invalid([SuggestionValidator.Problem])
        case rateLimited
        case failed
    }

    private let service: any SuggestionSubmitting
    private let throttle: any SuggestionThrottleStoring
    private let now: () -> Date

    private(set) var isSubmitting = false
    private(set) var remaining: Int

    init(service: any SuggestionSubmitting,
         throttle: any SuggestionThrottleStoring,
         now: @escaping () -> Date = Date.init) {
        self.service = service
        self.throttle = throttle
        self.now = now
        self.remaining = SuggestionRateLimiter.decide(recent: throttle.load(), now: now()).remaining
    }

    /// Recompute `remaining` from the throttle store (call when the form appears).
    func refreshRemaining() {
        remaining = SuggestionRateLimiter.decide(recent: throttle.load(), now: now()).remaining
    }

    func submit(name: String, location: String,
                whyInclude: String, linksText: String) async -> SubmitResult {
        let suggestion: SiteSuggestion
        switch SuggestionValidator.validate(name: name, location: location,
                                            whyInclude: whyInclude, linksText: linksText) {
        case .failure(let problems): return .invalid(problems)
        case .success(let value): suggestion = value
        }

        let current = now()
        let recent = SuggestionRateLimiter.pruned(throttle.load(), now: current)
        guard SuggestionRateLimiter.decide(recent: recent, now: current).allowed else {
            remaining = 0
            return .rateLimited
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.submit(suggestion)
        } catch {
            return .failed
        }

        let updated = recent + [current]
        throttle.save(updated)
        remaining = SuggestionRateLimiter.decide(recent: updated, now: current).remaining
        return .success
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the **Regenerate + run the full test target** command.
Expected: **TEST SUCCEEDED** — 4 new store tests pass; the existing `SeamTests.mockSuggestionRecords` still passes; suite green.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Suggestions/SuggestionStore.swift ByzantineTrailTests/SuggestionStoreTests.swift ByzantineTrailTests/Mocks/MockProviders.swift
git commit -m "M5c Task 4: SuggestionStore (validate -> throttle -> submit) + StubSuggestionService

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: CloudKitSuggestionService (live)

**Files:**
- Create: `ByzantineTrail/Core/Suggestions/CloudKitSuggestionService.swift`

No unit test — CloudKit is verified live in Task 9 (matches how `CloudKitRatingsService` / `CloudKitSyncProvider` are treated). This task's gate is a clean build.

**Interfaces:**
- Consumes: `SiteSuggestion`, `SuggestionSubmitting`.
- Produces: `final class CloudKitSuggestionService: SuggestionSubmitting` with `init(containerID: String = "iCloud.com.byzantinetrail.app")`.

- [ ] **Step 1: Write the implementation**

Create `ByzantineTrail/Core/Suggestions/CloudKitSuggestionService.swift`:

```swift
import CloudKit

/// Live public-database backend for site suggestions (M5c). Writes a create-only
/// `SiteSuggestion` record the owner reads via the CloudKit Dashboard. No
/// submitter identity is stored (random UUID recordName; no userRecordID fetch).
/// All CloudKit is confined to this file. Activated by the owner (CLOUDKIT_SETUP.md).
final class CloudKitSuggestionService: SuggestionSubmitting {
    private let db: CKDatabase

    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        db = CKContainer(identifier: containerID).publicCloudDatabase
    }

    func submit(_ suggestion: SiteSuggestion) async throws {
        let rec = CKRecord(recordType: "SiteSuggestion") // random UUID recordName
        rec["name"] = suggestion.name as CKRecordValue
        if let v = suggestion.location   { rec["location"]   = v as CKRecordValue }
        if let v = suggestion.whyInclude { rec["whyInclude"] = v as CKRecordValue }
        if let v = suggestion.linksText  { rec["linksText"]  = v as CKRecordValue }
        rec["submittedAt"] = Date() as CKRecordValue
        _ = try await db.save(rec)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run the **Regenerate + build only** command.
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Commit**

```bash
git add ByzantineTrail/Core/Suggestions/CloudKitSuggestionService.swift
git commit -m "M5c Task 5: CloudKitSuggestionService (public DB, create-only, no identity)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: SuggestSiteForm + Profile "Contribute" link

**Files:**
- Create: `ByzantineTrail/Features/Profile/SuggestSiteForm.swift`
- Modify: `ByzantineTrail/Features/Profile/ProfileView.swift` (add a `Section("Contribute")` after the `Progress` section)

No unit test (SwiftUI view); gate is a clean build. `SuggestionStore` is read from the environment — it is injected in Task 7, but the view compiles against the type now.

**Interfaces:**
- Consumes: `SuggestionStore` (env), `AccountStore` (env), `NetworkMonitor` (env), `SuggestionGate`, `Theme`.
- Produces: `struct SuggestSiteForm: View` with `init(theme: Theme)`.

- [ ] **Step 1: Write the view**

Create `ByzantineTrail/Features/Profile/SuggestSiteForm.swift`:

```swift
import SwiftUI

/// Profile → Contribute → Suggest a site (M5c). A gated form that submits a
/// `SiteSuggestion` via `SuggestionStore`. Reads account/network from the
/// environment (like `RatingSection`); Submit is disabled when signed out,
/// offline, over the daily limit, or the name is empty.
struct SuggestSiteForm: View {
    let theme: Theme

    @Environment(SuggestionStore.self) private var store
    @Environment(AccountStore.self) private var accountStore
    @Environment(NetworkMonitor.self) private var network

    @State private var name = ""
    @State private var location = ""
    @State private var whyInclude = ""
    @State private var linksText = ""
    @State private var status: SuggestionStore.SubmitResult?

    var body: some View {
        let gate = SuggestionGate.evaluate(status: accountStore.status,
                                           isOnline: network.isOnline,
                                           remaining: store.remaining)
        let nameEntered = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canSubmit = gate.isEnabled && nameEntered && !store.isSubmitting

        Form {
            Section("Site") {
                TextField("Name (required)", text: $name)
                    .accessibilityIdentifier("suggest.name")
                TextField("Location", text: $location)
                    .accessibilityIdentifier("suggest.location")
            }
            Section("Details (optional)") {
                TextField("Why should it be included?", text: $whyInclude, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("suggest.why")
                TextField("Links", text: $linksText, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("suggest.links")
            }
            Section {
                Button {
                    Task { await performSubmit() }
                } label: {
                    if store.isSubmitting { ProgressView() } else { Text("Submit suggestion") }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("suggest.submit")

                if let message = statusMessage(gate: gate) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(status == .success ? theme.accentPrimary : theme.textSecondary)
                        .accessibilityIdentifier("suggest.status")
                }
            }
        }
        .navigationTitle("Suggest a Site")
        .navigationBarTitleDisplayMode(.inline)
        .background(theme.bgApp)
        .task { store.refreshRemaining() }
    }

    private func performSubmit() async {
        let result = await store.submit(name: name, location: location,
                                        whyInclude: whyInclude, linksText: linksText)
        status = result
        if result == .success { name = ""; location = ""; whyInclude = ""; linksText = "" }
    }

    /// Post-submit status wins over the pre-submit gate explainer.
    private func statusMessage(gate: SuggestionGate.State) -> String? {
        switch status {
        case .success: return "Thanks — your suggestion was sent."
        case .invalid(let problems):
            return problems.contains(.nameRequired)
                ? "Please enter a site name."
                : "One of your entries is too long."
        case .rateLimited: return "You've reached today's suggestion limit (10)."
        case .failed: return "Couldn't send right now. Please try again."
        case .none: return gate.explainer
        }
    }
}
```

- [ ] **Step 2: Add the Profile entry point**

In `ByzantineTrail/Features/Profile/ProfileView.swift`, add a new section immediately after the `Section("Progress") { … }` block (still inside the `List`):

```swift
                Section("Contribute") {
                    NavigationLink {
                        SuggestSiteForm(theme: theme)
                    } label: {
                        Label("Suggest a site", systemImage: "plus.circle")
                    }
                }
```

- [ ] **Step 3: Verify it builds**

Run the **Regenerate + build only** command.
Expected: **BUILD SUCCEEDED**. (The view references `SuggestionStore` from the environment; it compiles now and is injected in Task 7.)

- [ ] **Step 4: Commit**

```bash
git add ByzantineTrail/Features/Profile/SuggestSiteForm.swift ByzantineTrail/Features/Profile/ProfileView.swift
git commit -m "M5c Task 6: SuggestSiteForm + Profile Contribute entry point

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Wire SuggestionStore into the app

**Files:**
- Modify: `ByzantineTrail/App/ByzantineTrailApp.swift`

**Interfaces:**
- Consumes: `SuggestionStore`, `CloudKitSuggestionService`, `UserDefaultsSuggestionThrottleStore`.

- [ ] **Step 1: Add the state property**

In `ByzantineTrailApp`, after `@State private var syncCoordinator: SyncCoordinator`:

```swift
    @State private var suggestionStore: SuggestionStore
```

- [ ] **Step 2: Construct it in `init()`**

At the end of `init()` (after the `_syncCoordinator = …` assignment):

```swift
        // Site suggestions (M5c): live public-DB create-only writes. Gates (not
        // queues) when offline / signed out, so no mock fallback is needed.
        _suggestionStore = State(initialValue: SuggestionStore(
            service: CloudKitSuggestionService(),
            throttle: UserDefaultsSuggestionThrottleStore()))
```

- [ ] **Step 3: Inject into the environment**

In `body`, add to the `RootTabView()` modifier chain (next to `.environment(accountStore)`):

```swift
                .environment(suggestionStore)
```

- [ ] **Step 4: Verify the full suite builds and passes**

Run the **Regenerate + run the full test target** command.
Expected: **TEST SUCCEEDED** — entire suite green (existing + all M5c unit tests). Confirms the wired app compiles and the environment injection type-checks.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/App/ByzantineTrailApp.swift
git commit -m "M5c Task 7: wire SuggestionStore (CloudKitSuggestionService) into the app

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: CLOUDKIT_SETUP.md addendum

**Files:**
- Modify: `docs/CLOUDKIT_SETUP.md` (append a new section at the end)

No code, no test — documentation for the owner's one-time Dashboard setup. Folded into its own task because it is the deliverable that makes the live path usable and a reviewer can accept/reject it independently.

- [ ] **Step 1: Append the section**

Add to the end of `docs/CLOUDKIT_SETUP.md`:

```markdown

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
```

- [ ] **Step 2: Commit**

```bash
git add docs/CLOUDKIT_SETUP.md
git commit -m "M5c Task 8: CLOUDKIT_SETUP addendum for SiteSuggestion (create-only public DB)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Live verification (manual, simulator → Dashboard)

**Files:** none (verification only).

This is the owner-run end-to-end check, the same style as M5b's live Task. It needs the simulator signed into a real iCloud account and the Dashboard open. It is **not** automated.

- [ ] **Step 1: Owner completes the Dashboard setup** from the Task 8 addendum (create the `SiteSuggestion` record type on first write or explicitly; set the `_icloud` create-only role).

- [ ] **Step 2: Build & run** on `iPhone 16` simulator signed into iCloud:

```bash
~/bin/xcodegen_dist/bin/xcodegen generate
xcodebuild build -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Then launch the app in the simulator (Xcode Run, or `xcrun simctl`).

- [ ] **Step 3: Submit a suggestion** — Profile → Contribute → Suggest a site → enter a name (e.g. "Test Site") → Submit. Expect the inline "Thanks — your suggestion was sent." confirmation and the fields to clear.

- [ ] **Step 4: Confirm in the Dashboard** — CloudKit Console → Development → Public Database → Records → `SiteSuggestion`: one record with the entered `name` and a `submittedAt`, and **no identity fields**.

- [ ] **Step 5: Spot-check the gates** — sign out of iCloud (Submit disabled, "Sign in to iCloud to suggest a site."); sign back in, disable networking (Submit disabled, "Connect to the internet to suggest a site.").

- [ ] **Step 6:** No commit — verification only. Record the outcome, then proceed to finishing-a-development-branch.

---

## Self-Review

**1. Spec coverage:**
- Validation (required name, trim, optional→nil, length caps) → Task 1. ✅
- Rate limit 10/24 h rolling + persistence seam → Task 2. ✅
- Gate (account→network→rate-limit precedence, exact copy) → Task 3. ✅
- Store (validate→throttle→submit, records timestamp on success only) → Task 4. ✅
- Live create-only public-DB service, no identity → Task 5. ✅
- Form + Profile "Contribute" entry, a11y ids, gated Submit → Task 6. ✅
- App wiring (live) → Task 7. ✅
- CLOUDKIT_SETUP addendum (record type, create-only role) → Task 8. ✅
- Live verification (simulator → Dashboard) → Task 9. ✅
- Global constraints (Swift Testing, real xcodegen, iPhone 16, no-reply email, no identity) → header. ✅

**2. Placeholder scan:** No TBD/TODO; every code step shows full code; every run step names an exact command and expected output. ✅

**3. Type consistency:** `SubmitResult` cases (`success`/`invalid([Problem])`/`rateLimited`/`failed`) identical in Task 4 interface, implementation, store tests, and the Task 6 view switch. `SuggestionGate.State`/`evaluate` signature identical in Tasks 3, 6. `SuggestionRateLimiter.pruned`/`decide`/`Decision`/`maxPerWindow`/`window` identical in Tasks 2, 4. `SuggestionThrottleStoring.load()->[Date]`/`save([Date])` identical in Tasks 2, 4. `SiteSuggestion` memberwise init order (`name`,`location`,`whyInclude`,`linksText`) matches the existing seam in Tasks 1, 4, 5. Rate-limit copy "limit (10)" consistent in Tasks 3, 6, and store. ✅
