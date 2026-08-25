# M7a — Trip Planner Solver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure domain layer of the trip planner — given a set of sites, a travel mode, a pace, and a day window, produce a day-by-day itinerary with an efficient stop order, per-stop dwell times, clock times, and diagnostics.

**Architecture:** Everything lives in `ByzantineTrail/Core/Planner/Domain/` and is a pure function over value types. No SwiftUI, no MapKit, no SwiftData, no networking, no `async`. Travel time comes through the `TravelEstimating` protocol, implemented in M7a only by `HaversineEstimator` (great-circle distance × a mode detour factor ÷ a mode speed); the async `MKDirections` resolver is M7b and is deliberately absent here. The domain does not depend on `Site` — an adapter maps `Site` into a small `PlannerSite` value type so tests need no catalog fixtures.

**Tech Stack:** Swift 6.2, Swift Testing, XcodeGen. No third-party dependencies.

## Global Constraints

- iOS deployment floor **17.0**; Swift 6.2.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — never XCTest.
- **Nothing in `Core/Planner/Domain/` may `import SwiftUI`, `import UIKit`, `import MapKit`, `import SwiftData`, or `import Combine`.** `import Foundation` only. This is the whole point of M7a and is asserted by a test in Task 8.
- **No `async`, no actors, no I/O** anywhere in M7a. Every function is synchronous and deterministic.
- All new source files go under `ByzantineTrail/Core/Planner/Domain/`. All new test files go **flat** in `ByzantineTrailTests/` (that directory has no subfolders except `Mocks`).
- XcodeGen: regenerate with the **real binary** `~/bin/xcodegen_dist/bin/xcodegen generate` (NOT the symlink) after adding any file. Sources are path-based, so new files under `ByzantineTrail/` are auto-included on regen. **`*.xcodeproj` is gitignored and never tracked** — regenerate it, but never `git add` it.
- Build/test destination: `platform=iOS Simulator,name=iPhone 16`.
- `xcodebuild` is the authoritative signal. SourceKit shows cross-file "cannot find X in scope" and "No such module 'Testing'" false positives — ignore them, trust `xcodebuild`.
- Spec: `docs/superpowers/specs/2026-08-23-trip-planner-design.md`. Section references below (§4.1, §5, §6) point there.
- **Out of scope for M7a** (do not build, do not stub): persistence, `MKDirections`, any SwiftUI view, the paywall, disclosures copy. Those are M7b/M7c.

---

## File Structure

**Create (source):**
- `ByzantineTrail/Core/Planner/Domain/TravelMode.swift` — `TravelMode` enum plus its detour factor and speed constants. The single place travel constants are tuned.
- `ByzantineTrail/Core/Planner/Domain/GreatCircle.swift` — `GreatCircle.metres(from:to:)`, haversine over `Coordinate`.
- `ByzantineTrail/Core/Planner/Domain/TravelEstimating.swift` — the synchronous estimator protocol (§4.1).
- `ByzantineTrail/Core/Planner/Domain/HaversineEstimator.swift` — the only M7a implementation.
- `ByzantineTrail/Core/Planner/Domain/Pace.swift` — `Pace` enum and its dwell multiplier.
- `ByzantineTrail/Core/Planner/Domain/VisitDuration.swift` — dwell derivation from `type` × `importance` × `pace` (§5.1).
- `ByzantineTrail/Core/Planner/Domain/PlannerSite.swift` — the domain's own site value type plus a `Site` adapter.
- `ByzantineTrail/Core/Planner/Domain/StopSequencer.swift` — stop ordering: exact Held–Karp and the heuristic fallback.
- `ByzantineTrail/Core/Planner/Domain/DayClusterer.swift` — geographic clustering and cluster ordering.
- `ByzantineTrail/Core/Planner/Domain/PlannerTypes.swift` — `FixedBlockSpec`, `PlannedStop`, `PlannedBlock`, `PlannedDay` (Task 6), then `TripRequest` and `PlannedTrip` (Task 8). Shared value types with no behaviour.
- `ByzantineTrail/Core/Planner/Domain/TimeBudget.swift` — lays stops and blocks onto the clock.
- `ByzantineTrail/Core/Planner/Domain/PlanDiagnostics.swift` — tightness and the §6 conditions.
- `ByzantineTrail/Core/Planner/Domain/ItineraryPlanner.swift` — composes everything.

**Create (tests):**
- `ByzantineTrailTests/GreatCircleTests.swift`
- `ByzantineTrailTests/HaversineEstimatorTests.swift`
- `ByzantineTrailTests/VisitDurationTests.swift`
- `ByzantineTrailTests/PlannerSiteTests.swift`
- `ByzantineTrailTests/StopSequencerExactTests.swift`
- `ByzantineTrailTests/StopSequencerHeuristicTests.swift`
- `ByzantineTrailTests/DayClustererTests.swift`
- `ByzantineTrailTests/TimeBudgetTests.swift`
- `ByzantineTrailTests/PlanDiagnosticsTests.swift`
- `ByzantineTrailTests/ItineraryPlannerTests.swift`

**Modify:** nothing. M7a is purely additive.

---

### Task 1: Travel constants, great-circle distance, and the estimator

**Files:**
- Create: `ByzantineTrail/Core/Planner/Domain/TravelMode.swift`
- Create: `ByzantineTrail/Core/Planner/Domain/GreatCircle.swift`
- Create: `ByzantineTrail/Core/Planner/Domain/TravelEstimating.swift`
- Create: `ByzantineTrail/Core/Planner/Domain/HaversineEstimator.swift`
- Test: `ByzantineTrailTests/GreatCircleTests.swift`
- Test: `ByzantineTrailTests/HaversineEstimatorTests.swift`

**Interfaces:**
- Consumes: `Coordinate` from `ByzantineTrail/Core/Catalog/Site.swift` — `struct Coordinate: Codable, Equatable { let lat, lon: Double }`.
- Produces:
  - `enum TravelMode: String, Codable, CaseIterable, Sendable { case walking, driving, transit }` with `var detourFactor: Double` and `var metresPerSecond: Double`
  - `enum GreatCircle { static let earthRadiusMetres: Double; static func metres(from: Coordinate, to: Coordinate) -> Double }`
  - `protocol TravelEstimating: Sendable { func seconds(from: Coordinate, to: Coordinate, mode: TravelMode) -> TimeInterval }`
  - `struct HaversineEstimator: TravelEstimating { init() }`

- [ ] **Step 1: Write the failing distance test**

Create `ByzantineTrailTests/GreatCircleTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct GreatCircleTests {
    private func c(_ lat: Double, _ lon: Double) -> Coordinate {
        Coordinate(lat: lat, lon: lon)
    }

    @Test func zeroDistanceForIdenticalCoordinates() {
        #expect(GreatCircle.metres(from: c(41.0086, 28.9802),
                                   to: c(41.0086, 28.9802)) == 0)
    }

    /// One degree of latitude is R * pi / 180 with R = 6_371_000.
    @Test func oneDegreeOfLatitude() {
        let d = GreatCircle.metres(from: c(0, 0), to: c(1, 0))
        #expect(abs(d - 111_194.93) < 1.0)
    }

    /// At the equator one degree of longitude equals one degree of latitude.
    @Test func oneDegreeOfLongitudeAtEquator() {
        let d = GreatCircle.metres(from: c(0, 0), to: c(0, 1))
        #expect(abs(d - 111_194.93) < 1.0)
    }

    @Test func symmetric() {
        let a = c(41.8902, 12.4922)
        let b = c(41.9022, 12.4539)
        #expect(abs(GreatCircle.metres(from: a, to: b)
                    - GreatCircle.metres(from: b, to: a)) < 0.001)
    }

    /// Colosseum to St Peter's, ~3.44 km.
    @Test func knownRomePair() {
        let d = GreatCircle.metres(from: c(41.8902, 12.4922), to: c(41.9022, 12.4539))
        #expect(abs(d - 3_439.42) < 1.0)
    }

    /// Hagia Sophia to Chora, ~4.24 km.
    @Test func knownIstanbulPair() {
        let d = GreatCircle.metres(from: c(41.0086, 28.9802), to: c(41.0311, 28.9394))
        #expect(abs(d - 4_239.77) < 1.0)
    }

    /// Acropolis to the Rotunda in Thessaloniki, ~303 km.
    @Test func longDistancePair() {
        let d = GreatCircle.metres(from: c(37.9715, 23.7267), to: c(40.6333, 22.9528))
        #expect(abs(d - 303_372.89) < 10.0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/GreatCircleTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'GreatCircle' in scope`.

- [ ] **Step 3: Implement `GreatCircle`**

Create `ByzantineTrail/Core/Planner/Domain/GreatCircle.swift`:

```swift
import Foundation

/// Great-circle distance between catalog coordinates.
///
/// The planner's solver needs hundreds of pairwise distances per generated day,
/// so this must stay allocation-free and synchronous. Real street routes come
/// from `RouteResolving` (M7b) and only for the legs actually displayed.
enum GreatCircle {
    /// Mean Earth radius. Distances are accurate to ~0.5% at planner scale.
    static let earthRadiusMetres = 6_371_000.0

    static func metres(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180

        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMetres * asin(min(1, h.squareRoot()))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/GreatCircleTests 2>&1 | tail -20`

Expected: PASS, 7 tests.

- [ ] **Step 5: Write the failing estimator test**

Create `ByzantineTrailTests/HaversineEstimatorTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct HaversineEstimatorTests {
    private let estimator = HaversineEstimator()
    private func c(_ lat: Double, _ lon: Double) -> Coordinate {
        Coordinate(lat: lat, lon: lon)
    }

    @Test func modeConstantsAreTheSpecValues() {
        #expect(TravelMode.walking.detourFactor == 1.30)
        #expect(TravelMode.driving.detourFactor == 1.35)
        #expect(TravelMode.transit.detourFactor == 1.40)
        // 4.5 km/h, 30 km/h, 18 km/h expressed as metres per second.
        #expect(abs(TravelMode.walking.metresPerSecond - 1.25) < 0.0001)
        #expect(abs(TravelMode.driving.metresPerSecond - 8.3333) < 0.001)
        #expect(abs(TravelMode.transit.metresPerSecond - 5.0) < 0.0001)
    }

    /// Colosseum to St Peter's: 3439.42 m * 1.30 / 1.25 = 3577.0 s.
    @Test func walkingSecondsForKnownPair() {
        let s = estimator.seconds(from: c(41.8902, 12.4922),
                                  to: c(41.9022, 12.4539), mode: .walking)
        #expect(abs(s - 3_577.0) < 2.0)
    }

    @Test func drivingIsFasterThanWalkingOverTheSamePair() {
        let a = c(41.8902, 12.4922), b = c(41.9022, 12.4539)
        #expect(estimator.seconds(from: a, to: b, mode: .driving)
                < estimator.seconds(from: a, to: b, mode: .walking))
    }

    @Test func zeroSecondsForIdenticalCoordinates() {
        let a = c(41.0086, 28.9802)
        #expect(estimator.seconds(from: a, to: a, mode: .walking) == 0)
    }

    @Test func symmetric() {
        let a = c(41.8902, 12.4922), b = c(41.9022, 12.4539)
        #expect(abs(estimator.seconds(from: a, to: b, mode: .walking)
                    - estimator.seconds(from: b, to: a, mode: .walking)) < 0.001)
    }
}
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/HaversineEstimatorTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'HaversineEstimator' in scope`.

- [ ] **Step 7: Implement `TravelMode`, `TravelEstimating`, and `HaversineEstimator`**

Create `ByzantineTrail/Core/Planner/Domain/TravelMode.swift`:

```swift
import Foundation

/// How the traveller moves between stops.
///
/// The constants below are the single tuning point for all estimated travel
/// time. Changing them changes every estimate in the app and nothing else.
enum TravelMode: String, Codable, CaseIterable, Sendable {
    case walking, driving, transit

    /// Multiplier applied to straight-line distance to approximate the real
    /// path. Streets are not straight; 1.3 is a standard urban detour factor.
    var detourFactor: Double {
        switch self {
        case .walking: 1.30
        case .driving: 1.35
        case .transit: 1.40
        }
    }

    /// Door-to-door average speed. Driving is an urban figure, not a highway
    /// one; transit includes waiting and the walk to and from stops.
    var metresPerSecond: Double {
        switch self {
        case .walking: 4_500.0 / 3_600.0   // 4.5 km/h
        case .driving: 30_000.0 / 3_600.0  // 30 km/h
        case .transit: 18_000.0 / 3_600.0  // 18 km/h
        }
    }
}
```

Create `ByzantineTrail/Core/Planner/Domain/TravelEstimating.swift`:

```swift
import Foundation

/// Cheap, synchronous travel-time estimation.
///
/// Deliberately NOT async. The solver calls this hundreds of times while
/// ordering stops; making it async would make the solver async, network-bound,
/// and throttle-bound — the change that would eventually force a backend.
/// Real routes come from `RouteResolving` (M7b), which is async and is called
/// only for the handful of legs actually displayed.
protocol TravelEstimating: Sendable {
    func seconds(from: Coordinate, to: Coordinate, mode: TravelMode) -> TimeInterval
}
```

Create `ByzantineTrail/Core/Planner/Domain/HaversineEstimator.swift`:

```swift
import Foundation

/// The M7a estimator: great-circle distance, inflated by a mode detour factor,
/// divided by a mode speed. Free, offline, and unlimited.
struct HaversineEstimator: TravelEstimating {
    init() {}

    func seconds(from a: Coordinate, to b: Coordinate, mode: TravelMode) -> TimeInterval {
        let straight = GreatCircle.metres(from: a, to: b)
        return straight * mode.detourFactor / mode.metresPerSecond
    }
}
```

- [ ] **Step 8: Run both test suites to verify they pass**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/GreatCircleTests -only-testing:ByzantineTrailTests/HaversineEstimatorTests 2>&1 | tail -20`

Expected: PASS, 12 tests total.

- [ ] **Step 9: Commit**

```bash
git add ByzantineTrail/Core/Planner/Domain/TravelMode.swift \
        ByzantineTrail/Core/Planner/Domain/GreatCircle.swift \
        ByzantineTrail/Core/Planner/Domain/TravelEstimating.swift \
        ByzantineTrail/Core/Planner/Domain/HaversineEstimator.swift \
        ByzantineTrailTests/GreatCircleTests.swift \
        ByzantineTrailTests/HaversineEstimatorTests.swift
git commit -m "feat(planner): great-circle distance and haversine travel estimator"
```

---

### Task 2: Visit duration derivation

**Files:**
- Create: `ByzantineTrail/Core/Planner/Domain/Pace.swift`
- Create: `ByzantineTrail/Core/Planner/Domain/VisitDuration.swift`
- Test: `ByzantineTrailTests/VisitDurationTests.swift`

**Interfaces:**
- Consumes: `SiteType` and `Importance` from `ByzantineTrail/Core/Catalog/SiteType.swift`. `SiteType` cases: `church, monastery, fortress, palace, cityWalls, cistern, aqueduct, mosaicSite, archaeologicalSite, museum, tower, bridge, column, triumphalArch, mausoleum, baptistery, icon, other`. `Importance` cases: `major, notable, minor`.
- Produces:
  - `enum Pace: String, Codable, CaseIterable, Sendable { case relaxed, standard, packed }` with `var multiplier: Double`
  - `enum VisitDuration { static func minutes(type: SiteType, importance: Importance, pace: Pace = .standard) -> Int }`

- [ ] **Step 1: Write the failing test**

Create `ByzantineTrailTests/VisitDurationTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct VisitDurationTests {
    private func m(_ t: SiteType, _ i: Importance, _ p: Pace = .standard) -> Int {
        VisitDuration.minutes(type: t, importance: i, pace: p)
    }

    // MARK: base values

    @Test func plainChurchUsesTheImportanceBase() {
        #expect(m(.church, .major) == 75)
        #expect(m(.church, .notable) == 30)
        #expect(m(.church, .minor) == 15)
    }

    @Test func typesWithNoRuleUseTheBase() {
        #expect(m(.fortress, .notable) == 30)
        #expect(m(.cistern, .minor) == 15)
        #expect(m(.palace, .major) == 75)
        #expect(m(.baptistery, .notable) == 30)
        #expect(m(.other, .minor) == 15)
    }

    // MARK: type rules

    @Test func museumHasAFloorOf45() {
        #expect(m(.museum, .minor) == 45)     // 15 raised to the floor
        #expect(m(.museum, .notable) == 45)   // 30 raised to the floor
        #expect(m(.museum, .major) == 75)     // already above the floor
    }

    @Test func archaeologicalSitesGetHalfAgain() {
        #expect(m(.archaeologicalSite, .minor) == 25)    // 15 * 1.5 = 22.5 -> 25
        #expect(m(.archaeologicalSite, .notable) == 45)  // 30 * 1.5 = 45
    }

    @Test func monasteriesGetAQuarterMore() {
        #expect(m(.monastery, .minor) == 20)     // 15 * 1.25 = 18.75 -> 20
        #expect(m(.monastery, .notable) == 40)   // 30 * 1.25 = 37.5 -> 40
        #expect(m(.monastery, .major) == 95)     // 75 * 1.25 = 93.75 -> 95
    }

    @Test func singleObjectTypesAreCappedAt15() {
        for t: SiteType in [.column, .triumphalArch, .icon, .tower, .mausoleum, .aqueduct] {
            #expect(m(t, .notable) == 15, "\(t) notable should cap to 15")
            #expect(m(t, .minor) == 15, "\(t) minor is already 15")
        }
    }

    @Test func cityWallsAreCappedAt30() {
        #expect(m(.cityWalls, .notable) == 30)
        #expect(m(.cityWalls, .minor) == 15)   // base already below the cap
    }

    // MARK: the major exemption

    /// The Theodosian Land Walls are the catalog's only major cityWalls site.
    /// Without the exemption the cap would budget six kilometres of the most
    /// formidable fortification in the Byzantine world at half an hour.
    @Test func capsDoNotApplyToMajorSites() {
        #expect(m(.cityWalls, .major) == 75)
    }

    // MARK: pace

    @Test func paceMultipliesTheResult() {
        #expect(m(.church, .major, .relaxed) == 100)  // 75 * 1.3 = 97.5 -> 100
        #expect(m(.church, .major, .packed) == 55)    // 75 * 0.75 = 56.25 -> 55
        #expect(m(.church, .notable, .relaxed) == 40) // 30 * 1.3 = 39 -> 40
        #expect(m(.church, .minor, .packed) == 10)    // 15 * 0.75 = 11.25 -> 10
    }

    @Test func paceMultipliersAreTheSpecValues() {
        #expect(Pace.relaxed.multiplier == 1.3)
        #expect(Pace.standard.multiplier == 1.0)
        #expect(Pace.packed.multiplier == 0.75)
    }

    // MARK: invariants

    @Test func everyCombinationRoundsToAMultipleOfFive() {
        for t in SiteType.allCases {
            for i in Importance.allCases {
                for p in Pace.allCases {
                    let v = m(t, i, p)
                    #expect(v % 5 == 0, "\(t)/\(i)/\(p) produced \(v)")
                    #expect(v >= 5, "\(t)/\(i)/\(p) produced \(v)")
                }
            }
        }
    }

    /// Every type/importance combination, including ones the catalog does not
    /// currently contain. The shipped catalog yields the first eight of these;
    /// 115 arises only from a *major archaeological site*, of which there are
    /// none today (all 48 are notable or minor). If a future catalog adds one,
    /// this test documents what it would get.
    @Test func theFullValueSetIsSmallAndRound() {
        var seen = Set<Int>()
        for t in SiteType.allCases {
            for i in Importance.allCases {
                seen.insert(m(t, i))
            }
        }
        #expect(seen == [15, 20, 25, 30, 40, 45, 75, 95, 115])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/VisitDurationTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'VisitDuration' in scope`.

- [ ] **Step 3: Implement `Pace`**

Create `ByzantineTrail/Core/Planner/Domain/Pace.swift`:

```swift
import Foundation

/// How hard the traveller wants to push. Multiplies every dwell time.
enum Pace: String, Codable, CaseIterable, Sendable {
    case relaxed, standard, packed

    var multiplier: Double {
        switch self {
        case .relaxed: 1.3
        case .standard: 1.0
        case .packed: 0.75
        }
    }
}
```

- [ ] **Step 4: Implement `VisitDuration`**

Create `ByzantineTrail/Core/Planner/Domain/VisitDuration.swift`:

```swift
import Foundation

/// How long to budget inside a site, derived from `importance` and `type`.
///
/// Both fields are populated for all 581 catalog sites, so this needs no new
/// authoring. Results are rounded to five minutes on purpose: these are guesses
/// from two categorical fields, and "22 minutes" would imply a precision that
/// does not exist.
enum VisitDuration {
    /// Types that are a single object viewed from outside — a column, an arch.
    private static let singleObjectTypes: Set<SiteType> = [
        .column, .triumphalArch, .icon, .tower, .mausoleum, .aqueduct
    ]

    static func minutes(type: SiteType,
                        importance: Importance,
                        pace: Pace = .standard) -> Int {
        var value = base(importance)

        switch type {
        case .museum:
            // Museums consume time regardless of rank.
            value = max(value, 45)
        case .archaeologicalSite:
            // You walk a whole site, not a building.
            value *= 1.5
        case .monastery:
            // Multiple buildings, often an approach walk.
            value *= 1.25
        default:
            // Caps never apply to major sites. Without this the Theodosian Land
            // Walls — the only major cityWalls site — would get 30 minutes.
            if importance != .major {
                if singleObjectTypes.contains(type) {
                    value = min(value, 15)
                } else if type == .cityWalls {
                    value = min(value, 30)
                }
            }
        }

        return roundToFive(value * pace.multiplier)
    }

    private static func base(_ importance: Importance) -> Double {
        switch importance {
        case .major: 75
        case .notable: 30
        case .minor: 15
        }
    }

    /// Round half up to the nearest five, never below five.
    private static func roundToFive(_ value: Double) -> Int {
        let steps = (value / 5).rounded(.toNearestOrAwayFromZero)
        return max(5, Int(steps) * 5)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/VisitDurationTests 2>&1 | tail -20`

Expected: PASS, 12 tests.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/Planner/Domain/Pace.swift \
        ByzantineTrail/Core/Planner/Domain/VisitDuration.swift \
        ByzantineTrailTests/VisitDurationTests.swift
git commit -m "feat(planner): derive visit duration from importance and type"
```

---

### Task 3: `PlannerSite` and the `Site` adapter

**Files:**
- Create: `ByzantineTrail/Core/Planner/Domain/PlannerSite.swift`
- Test: `ByzantineTrailTests/PlannerSiteTests.swift`

**Interfaces:**
- Consumes: `Site` from `ByzantineTrail/Core/Catalog/Site.swift`. `Site` has `id: String`, `name: String`, `type: SiteType`, `cityId: String?`, `coordinate: Coordinate`, `importance: Importance` (plus many fields the planner does not need). `Site` has **no memberwise initializer** — it only decodes from JSON — so tests build `PlannerSite` directly, never `Site`.
- Produces: `struct PlannerSite: Identifiable, Equatable, Sendable` with `let id: String`, `let name: String`, `let coordinate: Coordinate`, `let cityId: String?`, `let type: SiteType`, `let importance: Importance`, a memberwise `init`, and `init(_ site: Site)`.

- [ ] **Step 1: Write the failing test**

Create `ByzantineTrailTests/PlannerSiteTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct PlannerSiteTests {
    /// Decoding a Site is the only way to build one — it has no memberwise init.
    private func decodeSite() throws -> Site {
        let json = """
        {
          "id": "hagia-sophia",
          "name": "Hagia Sophia",
          "alternateNames": [],
          "type": "church",
          "country": "TR",
          "cityId": "istanbul",
          "coordinate": { "lat": 41.0086, "lon": 28.9802 },
          "importance": "major"
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(Site.self, from: json)
    }

    @Test func adapterCopiesOnlyWhatTheSolverNeeds() throws {
        let site = try decodeSite()
        let planner = PlannerSite(site)
        #expect(planner.id == "hagia-sophia")
        #expect(planner.name == "Hagia Sophia")
        #expect(planner.cityId == "istanbul")
        #expect(planner.type == .church)
        #expect(planner.importance == .major)
        #expect(planner.coordinate.lat == 41.0086)
        #expect(planner.coordinate.lon == 28.9802)
    }

    @Test func memberwiseInitBuildsAFixtureWithoutACatalog() {
        let s = PlannerSite(id: "x", name: "X",
                            coordinate: Coordinate(lat: 1, lon: 2),
                            cityId: nil, type: .column, importance: .minor)
        #expect(s.id == "x")
        #expect(s.cityId == nil)
    }

    @Test func equatableByValue() {
        let a = PlannerSite(id: "x", name: "X", coordinate: Coordinate(lat: 1, lon: 2),
                            cityId: nil, type: .column, importance: .minor)
        let b = PlannerSite(id: "x", name: "X", coordinate: Coordinate(lat: 1, lon: 2),
                            cityId: nil, type: .column, importance: .minor)
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/PlannerSiteTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'PlannerSite' in scope`.

- [ ] **Step 3: Implement `PlannerSite`**

Create `ByzantineTrail/Core/Planner/Domain/PlannerSite.swift`:

```swift
import Foundation

/// The only view of a site the solver needs.
///
/// Keeping this separate from `Site` means the domain never depends on photos,
/// links, descriptions, or decoding, and tests can build fixtures in one line
/// instead of assembling catalog JSON.
struct PlannerSite: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let coordinate: Coordinate
    let cityId: String?
    let type: SiteType
    let importance: Importance

    init(id: String, name: String, coordinate: Coordinate,
         cityId: String?, type: SiteType, importance: Importance) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.cityId = cityId
        self.type = type
        self.importance = importance
    }

    init(_ site: Site) {
        self.init(id: site.id, name: site.name, coordinate: site.coordinate,
                  cityId: site.cityId, type: site.type, importance: site.importance)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/PlannerSiteTests 2>&1 | tail -20`

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Planner/Domain/PlannerSite.swift \
        ByzantineTrailTests/PlannerSiteTests.swift
git commit -m "feat(planner): PlannerSite value type and Site adapter"
```

---

### Task 4: `StopSequencer`

**Files:**
- Create: `ByzantineTrail/Core/Planner/Domain/StopSequencer.swift`
- Test: `ByzantineTrailTests/StopSequencerExactTests.swift`
- Test: `ByzantineTrailTests/StopSequencerHeuristicTests.swift`

**Interfaces:**
- Consumes: `Coordinate`, `TravelMode`, `TravelEstimating`, `HaversineEstimator` (Task 1).
- Produces:
  - `enum StopSequencer` with `static let exactLimit = 12`
  - `static func sequence(coordinates: [Coordinate], mode: TravelMode, estimator: any TravelEstimating, pinnedPositions: Set<Int> = [], closed: Bool = false) -> [Int]` — returns a permutation of `0..<coordinates.count`
  - `static func totalSeconds(order: [Int], coordinates: [Coordinate], mode: TravelMode, estimator: any TravelEstimating, closed: Bool = false) -> TimeInterval`

Two solvers behind one signature: exact Held-Karp when there are no pinned
positions and at most `exactLimit` stops, nearest-neighbour + 2-opt otherwise.

**Pinning semantics:** a position `p` in `pinnedPositions` means the stop that
entered at index `p` stays at index `p` in the result. Free stops fill the
remaining positions. This is what M7b's "Re-optimize this day" needs once the
user has hand-placed a stop.

- [ ] **Step 1: Write both failing test files**

Create `ByzantineTrailTests/StopSequencerExactTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct StopSequencerExactTests {
    private let estimator = HaversineEstimator()

    private func seq(_ coords: [Coordinate], closed: Bool = false) -> [Int] {
        StopSequencer.sequence(coordinates: coords, mode: .walking,
                               estimator: estimator, closed: closed)
    }

    private func cost(_ order: [Int], _ coords: [Coordinate], closed: Bool = false) -> Double {
        StopSequencer.totalSeconds(order: order, coordinates: coords,
                                   mode: .walking, estimator: estimator, closed: closed)
    }

    // MARK: degenerate inputs

    @Test func emptyInput() { #expect(seq([]) == []) }

    @Test func singleStop() {
        #expect(seq([Coordinate(lat: 0, lon: 0)]) == [0])
    }

    @Test func twoStopsKeepInputOrder() {
        #expect(seq([Coordinate(lat: 0, lon: 0), Coordinate(lat: 1, lon: 0)]) == [0, 1])
    }

    // MARK: the provable optimum

    /// Five collinear points fed in scrambled order. The shortest open path is
    /// simply to walk the line, so the answer is the indices sorted by latitude
    /// (or that sequence reversed — both are optimal).
    @Test func collinearPointsAreWalkedInOrder() {
        let coords = [
            Coordinate(lat: 0.02, lon: 0),  // 0
            Coordinate(lat: 0.00, lon: 0),  // 1
            Coordinate(lat: 0.04, lon: 0),  // 2
            Coordinate(lat: 0.01, lon: 0),  // 3
            Coordinate(lat: 0.03, lon: 0),  // 4
        ]
        let result = seq(coords)
        #expect(result == [1, 3, 0, 4, 2] || result == [2, 4, 0, 3, 1])
    }

    /// The open path never costs more than the input order it replaced.
    @Test func neverWorseThanInputOrder() {
        let coords = [
            Coordinate(lat: 41.8902, lon: 12.4922),
            Coordinate(lat: 41.9022, lon: 12.4539),
            Coordinate(lat: 41.8896, lon: 12.4769),
            Coordinate(lat: 41.9029, lon: 12.4534),
            Coordinate(lat: 41.8986, lon: 12.4768),
            Coordinate(lat: 41.8902, lon: 12.4823),
        ]
        let result = seq(coords)
        #expect(cost(result, coords) <= cost(Array(0..<coords.count), coords) + 0.001)
    }

    @Test func resultIsAlwaysAPermutation() {
        let coords = (0..<10).map { Coordinate(lat: Double($0) * 0.013,
                                               lon: Double(($0 * 7) % 10) * 0.011) }
        #expect(Set(seq(coords)) == Set(0..<10))
        #expect(seq(coords).count == 10)
    }

    // MARK: closed tours

    /// Four corners of a square: the optimal cycle is the perimeter, so the
    /// tour cost equals four edge lengths and never a diagonal.
    @Test func closedTourOfASquareIsThePerimeter() {
        let coords = [
            Coordinate(lat: 0.00, lon: 0.00),
            Coordinate(lat: 0.02, lon: 0.02),   // diagonal neighbour of 0
            Coordinate(lat: 0.00, lon: 0.02),
            Coordinate(lat: 0.02, lon: 0.00),
        ]
        let order = seq(coords, closed: true)
        let edge = StopSequencer.totalSeconds(order: [0, 2], coordinates: coords,
                                              mode: .walking, estimator: estimator)
        #expect(abs(cost(order, coords, closed: true) - edge * 4) < 1.0)
    }

    @Test func closedTourStartsAtIndexZero() {
        let coords = (0..<6).map { Coordinate(lat: Double($0) * 0.01,
                                              lon: Double(($0 * 3) % 6) * 0.01) }
        #expect(seq(coords, closed: true).first == 0)
    }

    // MARK: the exact/heuristic boundary

    @Test func exactLimitIsTwelve() {
        #expect(StopSequencer.exactLimit == 12)
    }

    /// Twelve stops is the largest exact case and must stay fast.
    @Test func twelveStopsStillReturnsAPermutation() {
        let coords = (0..<12).map { Coordinate(lat: Double($0) * 0.009,
                                               lon: Double(($0 * 5) % 12) * 0.008) }
        let result = seq(coords)
        #expect(Set(result) == Set(0..<12))
    }
}
```

Create `ByzantineTrailTests/StopSequencerHeuristicTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct StopSequencerHeuristicTests {
    private let estimator = HaversineEstimator()

    private func seq(_ coords: [Coordinate],
                     pinned: Set<Int> = [],
                     closed: Bool = false) -> [Int] {
        StopSequencer.sequence(coordinates: coords, mode: .walking,
                               estimator: estimator,
                               pinnedPositions: pinned, closed: closed)
    }

    private func cost(_ order: [Int], _ coords: [Coordinate]) -> Double {
        StopSequencer.totalSeconds(order: order, coordinates: coords,
                                   mode: .walking, estimator: estimator)
    }

    /// Scrambled collinear points, above the exact limit. The heuristic should
    /// still find the walk-the-line answer on an input this easy.
    private var scrambledLine: [Coordinate] {
        let latitudes = [0.07, 0.00, 0.13, 0.02, 0.11, 0.04, 0.09,
                         0.01, 0.12, 0.05, 0.08, 0.03, 0.10, 0.06]
        return latitudes.map { Coordinate(lat: $0, lon: 0) }
    }

    // MARK: above the exact limit

    @Test func fourteenStopsReturnsAPermutation() {
        let result = seq(scrambledLine)
        #expect(result.count == 14)
        #expect(Set(result) == Set(0..<14))
    }

    @Test func heuristicWalksTheLine() {
        let coords = scrambledLine
        let sorted = (0..<coords.count).sorted { coords[$0].lat < coords[$1].lat }
        let result = seq(coords)
        #expect(result == sorted || result == sorted.reversed())
    }

    @Test func heuristicBeatsTheInputOrder() {
        let coords = scrambledLine
        #expect(cost(seq(coords), coords) < cost(Array(0..<coords.count), coords))
    }

    /// The heuristic must land close to the exact answer on a case both can do.
    @Test func heuristicIsCloseToExactOnATenStopDay() {
        let coords = (0..<10).map {
            Coordinate(lat: 41.89 + Double(($0 * 7) % 10) * 0.004,
                       lon: 12.47 + Double(($0 * 3) % 10) * 0.005)
        }
        let exact = seq(coords)                       // n <= 12, exact path
        let heuristic = seq(coords, pinned: [0])      // forces the heuristic
        #expect(cost(heuristic, coords) <= cost(exact, coords) * 1.25)
    }

    // MARK: pinning

    @Test func pinnedPositionKeepsItsStop() {
        let coords = scrambledLine
        let result = seq(coords, pinned: [3])
        #expect(result[3] == 3)
    }

    @Test func severalPinnedPositionsAllHold() {
        let coords = scrambledLine
        let result = seq(coords, pinned: [0, 5, 13])
        #expect(result[0] == 0)
        #expect(result[5] == 5)
        #expect(result[13] == 13)
        #expect(Set(result) == Set(0..<14))
    }

    @Test func pinningEveryPositionReturnsTheInputOrder() {
        let coords = scrambledLine
        #expect(seq(coords, pinned: Set(0..<14)) == Array(0..<14))
    }

    @Test func pinnedSmallDayStillHonoursPins() {
        let coords = (0..<6).map { Coordinate(lat: Double($0) * 0.01,
                                              lon: Double(($0 * 5) % 6) * 0.01) }
        let result = seq(coords, pinned: [2])
        #expect(result[2] == 2)
        #expect(Set(result) == Set(0..<6))
    }

    @Test func outOfRangePinsAreIgnoredRatherThanCrashing() {
        let coords = scrambledLine
        let result = seq(coords, pinned: [99, -4])
        #expect(Set(result) == Set(0..<14))
    }

    // MARK: closed tours above the limit

    @Test func closedHeuristicTourStartsAtIndexZero() {
        let coords = (0..<14).map { Coordinate(lat: Double($0) * 0.01,
                                               lon: Double(($0 * 5) % 14) * 0.01) }
        #expect(seq(coords, closed: true).first == 0)
    }
}
```

- [ ] **Step 2: Run both suites to verify they fail**

Run: `~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/StopSequencerExactTests -only-testing:ByzantineTrailTests/StopSequencerHeuristicTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'StopSequencer' in scope`.

- [ ] **Step 3: Implement `StopSequencer`**


Create `ByzantineTrail/Core/Planner/Domain/StopSequencer.swift`:

```swift
import Foundation

/// Orders the stops of a single day.
///
/// This is an *open* TSP by default — a path, not a loop — because most days
/// start and end wherever the traveller happens to be. Pass `closed: true` when
/// the day returns to a lodging anchor.
///
/// Note what "optimal" means here: optimal with respect to the *estimated*
/// distances this is fed. Straight-line distance can mislead where water or
/// walls intervene, which is why M7b offers a re-optimize pass over resolved
/// routes. Never present the result to a user as "the optimal route".
enum StopSequencer {
    /// Above this many stops, exact Held-Karp becomes too slow and the
    /// nearest-neighbour + 2-opt heuristic below takes over. At n = 12 the exact solve is n^2 * 2^n ~ 590k
    /// operations — a few milliseconds.
    static let exactLimit = 12

    static func sequence(coordinates: [Coordinate],
                         mode: TravelMode,
                         estimator: any TravelEstimating,
                         pinnedPositions: Set<Int> = [],
                         closed: Bool = false) -> [Int] {
        let n = coordinates.count
        guard n > 2 else { return Array(0..<n) }

        let cost = matrix(coordinates, mode, estimator)

        if pinnedPositions.isEmpty && n <= exactLimit {
            return closed ? heldKarpClosedTour(cost) : heldKarpOpenPath(cost)
        }

        let valid = pinnedPositions.filter { $0 >= 0 && $0 < n }
        let seed = valid.isEmpty
            ? nearestNeighbour(cost)
            : pinnedSeed(cost, pinned: valid)
        return twoOpt(seed, cost, pinned: valid, closed: closed)
    }

    /// Total travel time for an order. Used by diagnostics and by tests.
    static func totalSeconds(order: [Int],
                             coordinates: [Coordinate],
                             mode: TravelMode,
                             estimator: any TravelEstimating,
                             closed: Bool = false) -> TimeInterval {
        guard order.count > 1 else { return 0 }
        var total: TimeInterval = 0
        for i in 0..<(order.count - 1) {
            total += estimator.seconds(from: coordinates[order[i]],
                                       to: coordinates[order[i + 1]], mode: mode)
        }
        if closed, let first = order.first, let last = order.last {
            total += estimator.seconds(from: coordinates[last],
                                       to: coordinates[first], mode: mode)
        }
        return total
    }

    // MARK: - Cost matrix

    static func matrix(_ coordinates: [Coordinate],
                       _ mode: TravelMode,
                       _ estimator: any TravelEstimating) -> [[Double]] {
        coordinates.map { a in
            coordinates.map { b in estimator.seconds(from: a, to: b, mode: mode) }
        }
    }

    // MARK: - Exact: minimum Hamiltonian path (open)

    private static func heldKarpOpenPath(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        let full = 1 << n
        var dp = [[Double]](repeating: [Double](repeating: .infinity, count: n),
                            count: full)
        var parent = [[Int]](repeating: [Int](repeating: -1, count: n), count: full)

        // A path may start anywhere.
        for j in 0..<n { dp[1 << j][j] = 0 }

        for mask in 1..<full {
            for j in 0..<n where mask & (1 << j) != 0 {
                let base = dp[mask][j]
                if base == .infinity { continue }
                for k in 0..<n where mask & (1 << k) == 0 {
                    let next = mask | (1 << k)
                    let candidate = base + cost[j][k]
                    if candidate < dp[next][k] {
                        dp[next][k] = candidate
                        parent[next][k] = j
                    }
                }
            }
        }

        var bestEnd = 0
        var best = Double.infinity
        for j in 0..<n where dp[full - 1][j] < best {
            best = dp[full - 1][j]
            bestEnd = j
        }
        return reconstruct(parent: parent, end: bestEnd, n: n)
    }

    // MARK: - Exact: minimum Hamiltonian cycle (closed, anchored at 0)

    private static func heldKarpClosedTour(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        let full = 1 << n
        var dp = [[Double]](repeating: [Double](repeating: .infinity, count: n),
                            count: full)
        var parent = [[Int]](repeating: [Int](repeating: -1, count: n), count: full)

        dp[1][0] = 0   // the tour is anchored at index 0

        for mask in 1..<full where mask & 1 != 0 {
            for j in 0..<n where mask & (1 << j) != 0 {
                let base = dp[mask][j]
                if base == .infinity { continue }
                for k in 1..<n where mask & (1 << k) == 0 {
                    let next = mask | (1 << k)
                    let candidate = base + cost[j][k]
                    if candidate < dp[next][k] {
                        dp[next][k] = candidate
                        parent[next][k] = j
                    }
                }
            }
        }

        var bestEnd = 1
        var best = Double.infinity
        for j in 1..<n {
            let closingCost = dp[full - 1][j] + cost[j][0]
            if closingCost < best {
                best = closingCost
                bestEnd = j
            }
        }
        return reconstruct(parent: parent, end: bestEnd, n: n)
    }

    private static func reconstruct(parent: [[Int]], end: Int, n: Int) -> [Int] {
        var path: [Int] = []
        var mask = (1 << n) - 1
        var node = end
        while node != -1 {
            path.append(node)
            let previous = parent[mask][node]
            mask &= ~(1 << node)
            node = previous
        }
        return path.reversed()
    }

    // MARK: - Heuristic: nearest neighbour + 2-opt

    private static func nearestNeighbour(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        var visited = [Bool](repeating: false, count: n)
        var order = [0]
        visited[0] = true
        var current = 0

        for _ in 1..<n {
            var best = -1
            var bestCost = Double.infinity
            for k in 0..<n where !visited[k] && cost[current][k] < bestCost {
                bestCost = cost[current][k]
                best = k
            }
            guard best >= 0 else { break }
            visited[best] = true
            order.append(best)
            current = best
        }
        return order
    }

    /// Seeds an order in which every pinned position already holds its own
    /// stop; free positions are filled greedily from the preceding stop.
    private static func pinnedSeed(_ cost: [[Double]], pinned: Set<Int>) -> [Int] {
        let n = cost.count
        var order = [Int](repeating: -1, count: n)
        for p in pinned { order[p] = p }

        var remaining = Set(0..<n).subtracting(pinned)
        var current: Int?

        for position in 0..<n {
            if order[position] != -1 {
                current = order[position]
                continue
            }
            guard !remaining.isEmpty else { break }
            let pick: Int
            if let from = current {
                pick = remaining.min { cost[from][$0] < cost[from][$1] } ?? remaining.first!
            } else {
                pick = remaining.min() ?? remaining.first!
            }
            order[position] = pick
            remaining.remove(pick)
            current = pick
        }
        return order
    }

    /// 2-opt: repeatedly reverse a segment when doing so shortens the route.
    /// A segment containing a pinned position is skipped, because reversing it
    /// would move that stop away from the position the user chose.
    ///
    /// An OPEN path may reverse a prefix (`i == 0`) — the path is free to start
    /// anywhere, and forbidding it strands nearest-neighbour seeds that begin in
    /// the middle of a line. A CLOSED tour keeps `i >= 1` so it stays anchored
    /// at index 0.
    private static func twoOpt(_ initial: [Int],
                               _ cost: [[Double]],
                               pinned: Set<Int>,
                               closed: Bool) -> [Int] {
        var order = initial
        let n = order.count
        guard n > 3 else { return order }

        let lowerBound = closed ? 1 : 0
        var improved = true
        while improved {
            improved = false
            for i in lowerBound..<(n - 1) {
                for j in (i + 1)..<n {
                    if pinned.contains(where: { $0 >= i && $0 <= j }) { continue }
                    if swapDelta(order, cost, i, j, closed) < -1e-9 {
                        order[i...j].reverse()
                        improved = true
                    }
                }
            }
        }
        return order
    }

    /// Change in total cost from reversing `order[i...j]`. Negative is better.
    private static func swapDelta(_ order: [Int],
                                  _ cost: [[Double]],
                                  _ i: Int,
                                  _ j: Int,
                                  _ closed: Bool) -> Double {
        let n = order.count
        let head = order[i]
        let tail = order[j]

        // Edge on the far side of the segment, which the reversal replaces.
        let removedEdge: Double
        let addedEdge: Double
        if j + 1 < n {
            removedEdge = cost[tail][order[j + 1]]
            addedEdge = cost[head][order[j + 1]]
        } else if closed {
            removedEdge = cost[tail][order[0]]
            addedEdge = cost[head][order[0]]
        } else {
            removedEdge = 0
            addedEdge = 0
        }

        // Reversing a prefix of an open path has no preceding edge at all.
        guard i > 0 else { return addedEdge - removedEdge }

        let before = order[i - 1]
        return (cost[before][tail] + addedEdge) - (cost[before][head] + removedEdge)
    }
}
```

- [ ] **Step 4: Run both suites to verify they pass**

Run: `~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/StopSequencerExactTests -only-testing:ByzantineTrailTests/StopSequencerHeuristicTests 2>&1 | tail -20`

Expected: PASS, 20 tests.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Planner/Domain/StopSequencer.swift \
        ByzantineTrailTests/StopSequencerExactTests.swift \
        ByzantineTrailTests/StopSequencerHeuristicTests.swift
git commit -m "feat(planner): exact and heuristic stop ordering with pinned positions"
```

---
### Task 5: `DayClusterer`

**Files:**
- Create: `ByzantineTrail/Core/Planner/Domain/DayClusterer.swift`
- Test: `ByzantineTrailTests/DayClustererTests.swift`

**Interfaces:**
- Consumes: `PlannerSite` (Task 3), `GreatCircle` and `TravelEstimating` (Task 1), `StopSequencer.sequence` (Task 4).
- Produces:
  - `struct SiteCluster: Equatable, Sendable { let cityId: String?; let sites: [PlannerSite]; let centroid: Coordinate }`
  - `enum DayClusterer` with `static let orphanThresholdMetres = 15_000.0`
  - `static func cluster(_ sites: [PlannerSite]) -> [SiteCluster]`
  - `static func order(_ clusters: [SiteCluster], mode: TravelMode, estimator: any TravelEstimating) -> [SiteCluster]`

Clustering here is **purely geographic**. Splitting a cluster across several days is a time-budget question and belongs to `ItineraryPlanner` (Task 8), which knows the day window.

- [ ] **Step 1: Write the failing test**

Create `ByzantineTrailTests/DayClustererTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct DayClustererTests {
    private func site(_ id: String, _ lat: Double, _ lon: Double,
                      city: String?) -> PlannerSite {
        PlannerSite(id: id, name: id, coordinate: Coordinate(lat: lat, lon: lon),
                    cityId: city, type: .church, importance: .notable)
    }

    // MARK: grouping by city

    @Test func sitesSharingACityFormOneCluster() {
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 41.90, 12.45, city: "rome"),
            site("c", 41.88, 12.47, city: "rome"),
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 1)
        #expect(clusters[0].cityId == "rome")
        #expect(clusters[0].sites.count == 3)
    }

    @Test func differentCitiesFormSeparateClusters() {
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 44.42, 12.20, city: "ravenna"),
            site("c", 41.00, 28.98, city: "istanbul"),
        ]
        #expect(DayClusterer.cluster(sites).count == 3)
    }

    @Test func clusterCentroidIsTheMeanOfItsSites() {
        let sites = [
            site("a", 40.0, 20.0, city: "x"),
            site("b", 42.0, 22.0, city: "x"),
        ]
        let centroid = DayClusterer.cluster(sites)[0].centroid
        #expect(abs(centroid.lat - 41.0) < 0.0001)
        #expect(abs(centroid.lon - 21.0) < 0.0001)
    }

    // MARK: sites with no city

    @Test func nearbyCitylessSiteJoinsTheClosestCluster() {
        let sites = [
            site("a", 41.890, 12.492, city: "rome"),
            site("b", 41.902, 12.454, city: "rome"),
            site("orphan", 41.895, 12.470, city: nil),   // ~1 km away
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 1)
        #expect(clusters[0].sites.count == 3)
    }

    @Test func distantCitylessSiteBecomesItsOwnCluster() {
        let sites = [
            site("a", 41.890, 12.492, city: "rome"),
            site("far", 37.971, 23.727, city: nil),      // Athens
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 2)
        #expect(clusters.contains { $0.cityId == nil && $0.sites.count == 1 })
    }

    @Test func citylessSitesNearEachOtherClusterTogether() {
        let sites = [
            site("p", 39.100, 21.500, city: nil),
            site("q", 39.104, 21.506, city: nil),        // ~0.7 km away
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 1)
        #expect(clusters[0].sites.count == 2)
    }

    @Test func orphanThresholdIsFifteenKilometres() {
        #expect(DayClusterer.orphanThresholdMetres == 15_000.0)
    }

    // MARK: degenerate inputs

    @Test func emptyInputProducesNoClusters() {
        #expect(DayClusterer.cluster([]).isEmpty)
    }

    @Test func everySiteEndsUpInExactlyOneCluster() {
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 44.42, 12.20, city: "ravenna"),
            site("c", 41.00, 28.98, city: nil),
            site("d", 41.01, 28.99, city: nil),
        ]
        let placed = DayClusterer.cluster(sites).flatMap { $0.sites.map(\.id) }
        #expect(Set(placed) == ["a", "b", "c", "d"])
        #expect(placed.count == 4)
    }

    // MARK: ordering

    @Test func clustersAreOrderedIntoAShortChain() {
        // Ravenna, Rome, Athens fed out of geographic order.
        let sites = [
            site("athens", 37.97, 23.73, city: "athens"),
            site("rome", 41.89, 12.49, city: "rome"),
            site("ravenna", 44.42, 12.20, city: "ravenna"),
        ]
        let ordered = DayClusterer.order(DayClusterer.cluster(sites),
                                         mode: .driving, estimator: HaversineEstimator())
        let ids = ordered.map { $0.cityId }
        #expect(ids == ["ravenna", "rome", "athens"]
                || ids == ["athens", "rome", "ravenna"])
    }

    @Test func orderingASingleClusterIsIdentity() {
        let sites = [site("a", 41.89, 12.49, city: "rome")]
        let clusters = DayClusterer.cluster(sites)
        let ordered = DayClusterer.order(clusters, mode: .walking,
                                         estimator: HaversineEstimator())
        #expect(ordered.map(\.cityId) == ["rome"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/DayClustererTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'DayClusterer' in scope`.

- [ ] **Step 3: Implement `DayClusterer`**

Create `ByzantineTrail/Core/Planner/Domain/DayClusterer.swift`:

```swift
import Foundation

/// A geographically coherent group of sites — usually one city.
struct SiteCluster: Equatable, Sendable {
    let cityId: String?
    let sites: [PlannerSite]
    let centroid: Coordinate
}

/// Groups chosen sites into day-sized geographic clusters.
///
/// `cityId` does almost all the work: every catalog site carries one, and 281
/// cities are already assigned. Only sites without a city need distance-based
/// handling. Splitting a cluster across several days is a *time* question and
/// belongs to `ItineraryPlanner`, which knows the day window.
enum DayClusterer {
    /// A city-less site further than this from every cluster becomes its own.
    static let orphanThresholdMetres = 15_000.0

    static func cluster(_ sites: [PlannerSite]) -> [SiteCluster] {
        guard !sites.isEmpty else { return [] }

        // Stable city grouping: first appearance decides the order.
        var cityOrder: [String] = []
        var byCity: [String: [PlannerSite]] = [:]
        var cityless: [PlannerSite] = []

        for site in sites {
            guard let cityId = site.cityId else {
                cityless.append(site)
                continue
            }
            if byCity[cityId] == nil {
                byCity[cityId] = []
                cityOrder.append(cityId)
            }
            byCity[cityId]?.append(site)
        }

        var groups: [(cityId: String?, sites: [PlannerSite])] =
            cityOrder.map { (cityId: $0, sites: byCity[$0] ?? []) }

        // Each city-less site joins the nearest group within the threshold, or
        // starts a new one that later city-less sites can also join.
        for site in cityless {
            var bestIndex: Int?
            var bestDistance = orphanThresholdMetres
            for (index, group) in groups.enumerated() {
                let distance = GreatCircle.metres(from: site.coordinate,
                                                  to: centroid(of: group.sites))
                if distance <= bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            if let index = bestIndex {
                groups[index].sites.append(site)
            } else {
                groups.append((cityId: nil, sites: [site]))
            }
        }

        return groups.map {
            SiteCluster(cityId: $0.cityId, sites: $0.sites,
                        centroid: centroid(of: $0.sites))
        }
    }

    /// Orders clusters into a short chain by their centroids.
    static func order(_ clusters: [SiteCluster],
                      mode: TravelMode,
                      estimator: any TravelEstimating) -> [SiteCluster] {
        guard clusters.count > 2 else { return clusters }
        let indices = StopSequencer.sequence(coordinates: clusters.map(\.centroid),
                                             mode: mode, estimator: estimator)
        return indices.map { clusters[$0] }
    }

    static func centroid(of sites: [PlannerSite]) -> Coordinate {
        guard !sites.isEmpty else { return Coordinate(lat: 0, lon: 0) }
        let count = Double(sites.count)
        let lat = sites.reduce(0.0) { $0 + $1.coordinate.lat } / count
        let lon = sites.reduce(0.0) { $0 + $1.coordinate.lon } / count
        return Coordinate(lat: lat, lon: lon)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/DayClustererTests 2>&1 | tail -20`

Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Planner/Domain/DayClusterer.swift \
        ByzantineTrailTests/DayClustererTests.swift
git commit -m "feat(planner): geographic day clustering and cluster ordering"
```

---

### Task 6: Planner value types and `TimeBudget`

**Files:**
- Create: `ByzantineTrail/Core/Planner/Domain/PlannerTypes.swift`
- Create: `ByzantineTrail/Core/Planner/Domain/TimeBudget.swift`
- Test: `ByzantineTrailTests/TimeBudgetTests.swift`

**Interfaces:**
- Consumes: `PlannerSite` (Task 3), `TravelMode` and `Pace` (Tasks 1–2).
- Produces (all in `PlannerTypes.swift`):
  - `struct FixedBlockSpec: Equatable, Sendable` — `enum Kind: String, Codable, Sendable { case arrival, departure, meal, lodging, custom }`, `let kind: Kind`, `let title: String`, `let startMinutes: Int`, `let durationMinutes: Int`
  - `struct PlannedStop: Equatable, Sendable` — `let site: PlannerSite`, `let dwellMinutes: Int`, `let arrivalMinutes: Int`, `let departureMinutes: Int`, `let legTravelSeconds: Int?`
  - `struct PlannedBlock: Equatable, Sendable` — `let spec: FixedBlockSpec`, `let startMinutes: Int`, `let endMinutes: Int`
  - `struct PlannedDay: Equatable, Sendable` — `let stops: [PlannedStop]`, `let blocks: [PlannedBlock]`, `let windowStartMinutes: Int`, `let windowEndMinutes: Int`, `let endMinutes: Int`, plus computed `slackMinutes`, `dwellMinutes`, `travelMinutes`, `occupiedMinutes`
  - `PlannedTrip` and `TripRequest` are **not** defined in this task — `PlannedTrip` references `PlanDiagnostic` (Task 7), and `TripRequest` has no consumer until Task 8.
- Produces (in `TimeBudget.swift`):
  - `enum TimeBudget { static func layOut(stops:legSeconds:windowStartMinutes:windowEndMinutes:blocks:) -> PlannedDay }`

All times are **minutes from midnight** (`540 == 09:00`). `TimeBudget` never invents a meal — the caller supplies one as a `FixedBlockSpec`, which keeps this function dumb and testable.

- [ ] **Step 1: Write the failing test**

Create `ByzantineTrailTests/TimeBudgetTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct TimeBudgetTests {
    private func site(_ id: String) -> PlannerSite {
        PlannerSite(id: id, name: id, coordinate: Coordinate(lat: 0, lon: 0),
                    cityId: "c", type: .church, importance: .notable)
    }

    private func layOut(dwells: [Int],
                        legMinutes: [Int],
                        start: Int = 540,
                        end: Int = 1080,
                        blocks: [FixedBlockSpec] = []) -> PlannedDay {
        TimeBudget.layOut(
            stops: dwells.enumerated().map { (site: site("s\($0.offset)"),
                                              dwellMinutes: $0.element) },
            legSeconds: legMinutes.map { $0 * 60 },
            windowStartMinutes: start,
            windowEndMinutes: end,
            blocks: blocks)
    }

    // MARK: the clock chain

    @Test func firstStopStartsAtTheWindowOpening() {
        let day = layOut(dwells: [30], legMinutes: [])
        #expect(day.stops[0].arrivalMinutes == 540)
        #expect(day.stops[0].departureMinutes == 570)
        #expect(day.stops[0].legTravelSeconds == nil)
    }

    @Test func laterStopsChainThroughTheirTravelLegs() {
        let day = layOut(dwells: [75, 30, 15], legMinutes: [22, 14])
        #expect(day.stops[0].arrivalMinutes == 540)   // 09:00
        #expect(day.stops[0].departureMinutes == 615) // 10:15
        #expect(day.stops[1].arrivalMinutes == 637)   // +22 min walk
        #expect(day.stops[1].departureMinutes == 667)
        #expect(day.stops[2].arrivalMinutes == 681)   // +14 min walk
        #expect(day.stops[2].departureMinutes == 696)
        #expect(day.endMinutes == 696)
    }

    @Test func legTravelSecondsArePreservedOnEachStop() {
        let day = layOut(dwells: [30, 30], legMinutes: [22])
        #expect(day.stops[0].legTravelSeconds == nil)
        #expect(day.stops[1].legTravelSeconds == 1_320)
    }

    // MARK: blocks

    @Test func aBlockIsConsumedOnceItsStartTimeIsReached() {
        let lunch = FixedBlockSpec(kind: .meal, title: "Lunch",
                                   startMinutes: 780, durationMinutes: 60)
        let day = layOut(dwells: [75, 75, 30], legMinutes: [30, 30], blocks: [lunch])
        // 540 +75 = 615, +30 = 645, +75 = 720, +30 travel = 750.
        // 750 < 780, so the third stop begins before lunch is due.
        #expect(day.stops[2].arrivalMinutes == 750)
        #expect(day.blocks.count == 1)
        #expect(day.blocks[0].startMinutes == 780)
        #expect(day.blocks[0].endMinutes == 840)
    }

    @Test func aDueBlockPushesTheFollowingStopLater() {
        let lunch = FixedBlockSpec(kind: .meal, title: "Lunch",
                                   startMinutes: 600, durationMinutes: 60)
        let day = layOut(dwells: [75, 30], legMinutes: [15], blocks: [lunch])
        // Stop 0: 540-615. Clock 615 >= 600, so lunch runs 615-675.
        // Then the 15-minute leg, so stop 1 arrives at 690.
        #expect(day.blocks[0].startMinutes == 615)
        #expect(day.blocks[0].endMinutes == 675)
        #expect(day.stops[1].arrivalMinutes == 690)
    }

    @Test func blocksNeverDueAreStillReportedAtTheirRequestedTime() {
        let arrival = FixedBlockSpec(kind: .arrival, title: "Train",
                                     startMinutes: 1_020, durationMinutes: 30)
        let day = layOut(dwells: [30], legMinutes: [], blocks: [arrival])
        #expect(day.blocks.count == 1)
        #expect(day.blocks[0].startMinutes == 1_020)
    }

    // MARK: totals

    @Test func totalsAddUp() {
        let day = layOut(dwells: [75, 30, 15], legMinutes: [22, 14])
        #expect(day.dwellMinutes == 120)
        #expect(day.travelMinutes == 36)
        #expect(day.occupiedMinutes == 156)
    }

    @Test func slackIsWhatRemainsInTheWindow() {
        let day = layOut(dwells: [75, 30, 15], legMinutes: [22, 14])
        #expect(day.endMinutes == 696)
        #expect(day.slackMinutes == 1_080 - 696)   // 384
    }

    @Test func anOverrunningDayHasNegativeSlack() {
        let day = layOut(dwells: [300, 300], legMinutes: [60])
        #expect(day.endMinutes == 1_200)
        #expect(day.slackMinutes == -120)
    }

    // MARK: degenerate inputs

    @Test func emptyDayEndsWhenItStarts() {
        let day = layOut(dwells: [], legMinutes: [])
        #expect(day.stops.isEmpty)
        #expect(day.endMinutes == 540)
        #expect(day.slackMinutes == 540)
    }

    @Test func aSingleStopHasNoLegs() {
        let day = layOut(dwells: [45], legMinutes: [])
        #expect(day.stops.count == 1)
        #expect(day.travelMinutes == 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/TimeBudgetTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'TimeBudget' in scope`.

- [ ] **Step 3: Implement the value types**

Create `ByzantineTrail/Core/Planner/Domain/PlannerTypes.swift`:

```swift
import Foundation

// All times in this file are MINUTES FROM MIDNIGHT: 540 == 09:00, 1080 == 18:00.

/// A commitment the day must work around — a train arrival, lunch, check-in.
/// Long-haul travel is declared this way rather than looked up; the planner
/// budgets around it and prices nothing.
struct FixedBlockSpec: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case arrival, departure, meal, lodging, custom
    }

    let kind: Kind
    let title: String
    let startMinutes: Int
    let durationMinutes: Int

    init(kind: Kind, title: String, startMinutes: Int, durationMinutes: Int) {
        self.kind = kind
        self.title = title
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
    }
}

/// One site placed on the clock.
struct PlannedStop: Equatable, Sendable {
    let site: PlannerSite
    let dwellMinutes: Int
    let arrivalMinutes: Int
    let departureMinutes: Int
    /// Travel FROM the previous stop. `nil` for the first stop of a day.
    let legTravelSeconds: Int?
}

/// A `FixedBlockSpec` placed on the clock.
struct PlannedBlock: Equatable, Sendable {
    let spec: FixedBlockSpec
    let startMinutes: Int
    let endMinutes: Int
}

/// One day of a trip.
struct PlannedDay: Equatable, Sendable {
    let stops: [PlannedStop]
    let blocks: [PlannedBlock]
    let windowStartMinutes: Int
    let windowEndMinutes: Int
    /// When the last stop ends. Equals `windowStartMinutes` for an empty day.
    let endMinutes: Int

    /// Positive means room to spare; negative means the day does not fit.
    var slackMinutes: Int { windowEndMinutes - endMinutes }

    var dwellMinutes: Int { stops.reduce(0) { $0 + $1.dwellMinutes } }

    var travelMinutes: Int {
        stops.reduce(0) { $0 + ($1.legTravelSeconds.map { s in s / 60 } ?? 0) }
    }

    var occupiedMinutes: Int { dwellMinutes + travelMinutes }
}
```

- [ ] **Step 4: Implement `TimeBudget`**

Create `ByzantineTrail/Core/Planner/Domain/TimeBudget.swift`:

```swift
import Foundation

/// Lays an ordered list of stops onto the clock.
///
/// Deliberately dumb: it never invents a meal break or reorders anything. The
/// caller supplies blocks (including lunch) as `FixedBlockSpec`s, which keeps
/// this a pure, exhaustively testable function.
enum TimeBudget {
    static func layOut(stops: [(site: PlannerSite, dwellMinutes: Int)],
                       legSeconds: [Int],
                       windowStartMinutes: Int,
                       windowEndMinutes: Int,
                       blocks: [FixedBlockSpec]) -> PlannedDay {
        var clock = windowStartMinutes
        var placedStops: [PlannedStop] = []
        var placedBlocks: [PlannedBlock] = []
        var pending = blocks.sorted { $0.startMinutes < $1.startMinutes }

        for (index, stop) in stops.enumerated() {
            // Consume any block that has come due BEFORE travelling on. You eat
            // lunch when you finish the previous site, not after walking to the
            // next one.
            while let next = pending.first, next.startMinutes <= clock {
                pending.removeFirst()
                let start = max(next.startMinutes, clock)
                placedBlocks.append(PlannedBlock(spec: next,
                                                 startMinutes: start,
                                                 endMinutes: start + next.durationMinutes))
                clock = start + next.durationMinutes
            }

            // Travel in from the previous stop.
            let leg: Int? = index == 0 ? nil : legSeconds[safe: index - 1]
            if let leg { clock += leg / 60 }

            let arrival = clock
            let departure = arrival + stop.dwellMinutes
            placedStops.append(PlannedStop(site: stop.site,
                                           dwellMinutes: stop.dwellMinutes,
                                           arrivalMinutes: arrival,
                                           departureMinutes: departure,
                                           legTravelSeconds: leg))
            clock = departure
        }

        // Blocks that never came due still belong on the day, at their own time.
        for spec in pending {
            placedBlocks.append(PlannedBlock(spec: spec,
                                             startMinutes: spec.startMinutes,
                                             endMinutes: spec.startMinutes + spec.durationMinutes))
        }
        placedBlocks.sort { $0.startMinutes < $1.startMinutes }

        return PlannedDay(stops: placedStops,
                          blocks: placedBlocks,
                          windowStartMinutes: windowStartMinutes,
                          windowEndMinutes: windowEndMinutes,
                          endMinutes: placedStops.last?.departureMinutes ?? windowStartMinutes)
    }
}

private extension Array {
    /// Bounds-checked read. `legSeconds` is caller-supplied and may be short.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/TimeBudgetTests 2>&1 | tail -20`

Expected: PASS, 11 tests.

- [ ] **Step 6: Commit**

```bash
git add ByzantineTrail/Core/Planner/Domain/PlannerTypes.swift \
        ByzantineTrail/Core/Planner/Domain/TimeBudget.swift \
        ByzantineTrailTests/TimeBudgetTests.swift
git commit -m "feat(planner): planner value types and clock layout"
```

---

### Task 7: `PlanDiagnostics`

**Files:**
- Create: `ByzantineTrail/Core/Planner/Domain/PlanDiagnostics.swift`
- Test: `ByzantineTrailTests/PlanDiagnosticsTests.swift`

**Interfaces:**
- Consumes: `PlannedDay`, `PlannedStop` (Task 6).
- Produces:
  - `enum Tightness: String, Equatable, Sendable { case relaxed, comfortable, tight, over }`
  - `enum PlanDiagnostic: Equatable, Sendable` with cases `tooManyCitiesForDays(cityCount: Int, dayCount: Int)`, `dayOverruns(dayIndex: Int, byMinutes: Int)`, `lowDwellRatio(dayIndex: Int, percent: Int)`, `largeSlack(dayIndex: Int, freeMinutes: Int)`, `outlierStop(dayIndex: Int, siteId: String, travelMinutes: Int)`
  - `enum PlanDiagnostics` with `static let dwellRatioFloor = 0.50`, `static let outlierTravelMinutes = 90`, `static func tightness(slackMinutes: Int, windowMinutes: Int) -> Tightness`, `static func evaluate(days: [PlannedDay], cityCount: Int, dayCount: Int) -> [PlanDiagnostic]`

Thresholds (spec §5.5): slack as a fraction of the window — `> 0.25` relaxed, `0.10 ..< 0.25` comfortable, `0 ..< 0.10` tight, `< 0` over.

- [ ] **Step 1: Write the failing test**

Create `ByzantineTrailTests/PlanDiagnosticsTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct PlanDiagnosticsTests {
    private func site(_ id: String) -> PlannerSite {
        PlannerSite(id: id, name: id, coordinate: Coordinate(lat: 0, lon: 0),
                    cityId: "c", type: .church, importance: .notable)
    }

    private func day(dwells: [Int], legMinutes: [Int],
                     start: Int = 540, end: Int = 1_080) -> PlannedDay {
        TimeBudget.layOut(
            stops: dwells.enumerated().map { (site: site("s\($0.offset)"),
                                              dwellMinutes: $0.element) },
            legSeconds: legMinutes.map { $0 * 60 },
            windowStartMinutes: start, windowEndMinutes: end, blocks: [])
    }

    // MARK: tightness boundaries

    @Test func tightnessBands() {
        // Window of 540 minutes: 25% is 135, 10% is 54.
        #expect(PlanDiagnostics.tightness(slackMinutes: 200, windowMinutes: 540) == .relaxed)
        #expect(PlanDiagnostics.tightness(slackMinutes: 100, windowMinutes: 540) == .comfortable)
        #expect(PlanDiagnostics.tightness(slackMinutes: 20, windowMinutes: 540) == .tight)
        #expect(PlanDiagnostics.tightness(slackMinutes: -30, windowMinutes: 540) == .over)
    }

    @Test func tightnessAtExactBoundaries() {
        #expect(PlanDiagnostics.tightness(slackMinutes: 135, windowMinutes: 540) == .comfortable)
        #expect(PlanDiagnostics.tightness(slackMinutes: 136, windowMinutes: 540) == .relaxed)
        #expect(PlanDiagnostics.tightness(slackMinutes: 54, windowMinutes: 540) == .comfortable)
        #expect(PlanDiagnostics.tightness(slackMinutes: 53, windowMinutes: 540) == .tight)
        #expect(PlanDiagnostics.tightness(slackMinutes: 0, windowMinutes: 540) == .tight)
        #expect(PlanDiagnostics.tightness(slackMinutes: -1, windowMinutes: 540) == .over)
    }

    @Test func tightnessWithAZeroWindowIsOverRatherThanACrash() {
        #expect(PlanDiagnostics.tightness(slackMinutes: 0, windowMinutes: 0) == .over)
    }

    // MARK: overrun

    @Test func anOverrunningDayIsReported() {
        let d = day(dwells: [300, 300], legMinutes: [60])   // ends 1200, window 1080
        let found = PlanDiagnostics.evaluate(days: [d], cityCount: 1, dayCount: 1)
        #expect(found.contains(.dayOverruns(dayIndex: 0, byMinutes: 120)))
    }

    @Test func aDayThatFitsIsNotReportedAsOverrunning() {
        let d = day(dwells: [75, 30], legMinutes: [20])
        let found = PlanDiagnostics.evaluate(days: [d], cityCount: 1, dayCount: 1)
        #expect(!found.contains { if case .dayOverruns = $0 { true } else { false } })
    }

    // MARK: dwell ratio

    @Test func moreTravelThanVisitingIsReported() {
        // 60 minutes inside sites, 240 travelling: ratio 20%.
        let d = day(dwells: [30, 30], legMinutes: [240])
        let found = PlanDiagnostics.evaluate(days: [d], cityCount: 1, dayCount: 1)
        #expect(found.contains(.lowDwellRatio(dayIndex: 0, percent: 20)))
    }

    @Test func aHealthyDwellRatioIsNotReported() {
        // 285 minutes inside, 36 travelling: ratio 89%.
        let d = day(dwells: [75, 75, 45, 30, 30, 15, 15], legMinutes: [6, 6, 6, 6, 6, 6])
        let found = PlanDiagnostics.evaluate(days: [d], cityCount: 1, dayCount: 1)
        #expect(!found.contains { if case .lowDwellRatio = $0 { true } else { false } })
    }

    @Test func dwellRatioFloorIsFiftyPercent() {
        #expect(PlanDiagnostics.dwellRatioFloor == 0.50)
    }

    // MARK: slack and outliers

    @Test func aDayWithLotsOfRoomOffersToFillIt() {
        let d = day(dwells: [30], legMinutes: [])   // ends 570, slack 510
        let found = PlanDiagnostics.evaluate(days: [d], cityCount: 1, dayCount: 1)
        #expect(found.contains(.largeSlack(dayIndex: 0, freeMinutes: 510)))
    }

    @Test func aStopMilesFromTheRestIsFlagged() {
        let d = day(dwells: [30, 30, 30], legMinutes: [10, 120])
        let found = PlanDiagnostics.evaluate(days: [d], cityCount: 1, dayCount: 1)
        #expect(found.contains(.outlierStop(dayIndex: 0, siteId: "s2", travelMinutes: 120)))
    }

    @Test func outlierThresholdIsNinetyMinutes() {
        #expect(PlanDiagnostics.outlierTravelMinutes == 90)
    }

    // MARK: trip-level

    @Test func moreCitiesThanDaysIsReported() {
        let d = day(dwells: [30], legMinutes: [])
        let found = PlanDiagnostics.evaluate(days: [d], cityCount: 3, dayCount: 2)
        #expect(found.contains(.tooManyCitiesForDays(cityCount: 3, dayCount: 2)))
    }

    @Test func enoughDaysForTheCitiesIsNotReported() {
        let d = day(dwells: [30], legMinutes: [])
        let found = PlanDiagnostics.evaluate(days: [d], cityCount: 2, dayCount: 3)
        #expect(!found.contains { if case .tooManyCitiesForDays = $0 { true } else { false } })
    }

    @Test func anEmptyTripProducesNoDiagnostics() {
        #expect(PlanDiagnostics.evaluate(days: [], cityCount: 0, dayCount: 0).isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/PlanDiagnosticsTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'PlanDiagnostics' in scope`.

- [ ] **Step 3: Implement `PlanDiagnostics`**

Create `ByzantineTrail/Core/Planner/Domain/PlanDiagnostics.swift`:

```swift
import Foundation

/// How much room a day has left.
enum Tightness: String, Equatable, Sendable {
    case relaxed, comfortable, tight, over
}

/// A condition worth telling the user about, with enough data for the UI to
/// write a specific sentence and offer a specific remedy (spec §6).
enum PlanDiagnostic: Equatable, Sendable {
    case tooManyCitiesForDays(cityCount: Int, dayCount: Int)
    case dayOverruns(dayIndex: Int, byMinutes: Int)
    case lowDwellRatio(dayIndex: Int, percent: Int)
    case largeSlack(dayIndex: Int, freeMinutes: Int)
    case outlierStop(dayIndex: Int, siteId: String, travelMinutes: Int)
}

/// Detects the conditions in spec §6. Needs no opening-hours data and no
/// network — everything here follows from geometry and the clock.
enum PlanDiagnostics {
    /// Below this share of the day spent inside sites, warn that the trip is
    /// mostly travelling.
    static let dwellRatioFloor = 0.50
    /// A single leg longer than this makes its stop an outlier.
    static let outlierTravelMinutes = 90
    /// Slack above this share of the window is worth offering to fill.
    static let largeSlackFraction = 0.25

    static func tightness(slackMinutes: Int, windowMinutes: Int) -> Tightness {
        guard windowMinutes > 0 else { return .over }
        if slackMinutes < 0 { return .over }
        let fraction = Double(slackMinutes) / Double(windowMinutes)
        if fraction > 0.25 { return .relaxed }
        if fraction >= 0.10 { return .comfortable }
        return .tight
    }

    static func evaluate(days: [PlannedDay],
                         cityCount: Int,
                         dayCount: Int) -> [PlanDiagnostic] {
        var found: [PlanDiagnostic] = []

        if cityCount > dayCount, dayCount > 0 {
            found.append(.tooManyCitiesForDays(cityCount: cityCount, dayCount: dayCount))
        }

        for (index, day) in days.enumerated() {
            if day.slackMinutes < 0 {
                found.append(.dayOverruns(dayIndex: index, byMinutes: -day.slackMinutes))
            }

            let occupied = day.occupiedMinutes
            if occupied > 0 {
                let ratio = Double(day.dwellMinutes) / Double(occupied)
                if ratio < dwellRatioFloor {
                    found.append(.lowDwellRatio(dayIndex: index,
                                                percent: Int((ratio * 100).rounded())))
                }
            }

            let window = day.windowEndMinutes - day.windowStartMinutes
            if window > 0, day.slackMinutes > 0,
               Double(day.slackMinutes) / Double(window) > largeSlackFraction {
                found.append(.largeSlack(dayIndex: index, freeMinutes: day.slackMinutes))
            }

            for stop in day.stops {
                guard let seconds = stop.legTravelSeconds else { continue }
                let minutes = seconds / 60
                if minutes > outlierTravelMinutes {
                    found.append(.outlierStop(dayIndex: index,
                                              siteId: stop.site.id,
                                              travelMinutes: minutes))
                }
            }
        }

        return found
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/PlanDiagnosticsTests 2>&1 | tail -20`

Expected: PASS, 14 tests.

- [ ] **Step 5: Commit**

```bash
git add ByzantineTrail/Core/Planner/Domain/PlanDiagnostics.swift \
        ByzantineTrailTests/PlanDiagnosticsTests.swift
git commit -m "feat(planner): plan diagnostics and day tightness"
```

---

### Task 8: `ItineraryPlanner`

**Files:**
- Create: `ByzantineTrail/Core/Planner/Domain/ItineraryPlanner.swift`
- Modify: `ByzantineTrail/Core/Planner/Domain/PlannerTypes.swift` — append `TripRequest` and `PlannedTrip`
- Test: `ByzantineTrailTests/ItineraryPlannerTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces:
  - `struct TripRequest: Equatable, Sendable` and `struct PlannedTrip: Equatable, Sendable`, appended to `PlannerTypes.swift`
  - `enum ItineraryPlanner { static let defaultLunch: FixedBlockSpec; static func plan(_ request: TripRequest, estimator: any TravelEstimating = HaversineEstimator()) -> PlannedTrip }`

Pipeline: cluster → order clusters → sequence each cluster's stops → fill days with as many stops as fit → lay out the clock → diagnose.

**`dayCount` is a maximum, not a quota.** The planner produces at most that many
days and never pads out empty ones — seven sites over five allowed days is a
one-day trip with a `largeSlack` diagnostic. Conversely a city bigger than one
day spills into the next, which is what "three days in Rome" needs, and anything
still left over is reported in `unplacedSiteIds` rather than crammed into an
overrunning day.

- [ ] **Step 1: Add the two remaining value types**

Neither could live in Task 6: `PlannedTrip` references `PlanDiagnostic`, which
arrives in Task 7, and `TripRequest` has no consumer until this task. Append
both to `ByzantineTrail/Core/Planner/Domain/PlannerTypes.swift`:

```swift
/// Everything the planner needs to build a trip.
struct TripRequest: Equatable, Sendable {
    let sites: [PlannerSite]
    let mode: TravelMode
    let pace: Pace
    let dayCount: Int
    let dayStartMinutes: Int
    let dayEndMinutes: Int
    /// Keyed by zero-based day index.
    let fixedBlocks: [Int: [FixedBlockSpec]]
    let includeLunch: Bool

    init(sites: [PlannerSite],
         mode: TravelMode,
         pace: Pace = .standard,
         dayCount: Int,
         dayStartMinutes: Int = 540,
         dayEndMinutes: Int = 1_080,
         fixedBlocks: [Int: [FixedBlockSpec]] = [:],
         includeLunch: Bool = true) {
        self.sites = sites
        self.mode = mode
        self.pace = pace
        self.dayCount = dayCount
        self.dayStartMinutes = dayStartMinutes
        self.dayEndMinutes = dayEndMinutes
        self.fixedBlocks = fixedBlocks
        self.includeLunch = includeLunch
    }
}

/// The planner's output.
struct PlannedTrip: Equatable, Sendable {
    let days: [PlannedDay]
    let diagnostics: [PlanDiagnostic]
    /// Sites that did not fit in `dayCount` days.
    let unplacedSiteIds: [String]
}
```

- [ ] **Step 2: Write the failing test**

Create `ByzantineTrailTests/ItineraryPlannerTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct ItineraryPlannerTests {
    private func site(_ id: String, _ lat: Double, _ lon: Double,
                      city: String?, _ type: SiteType = .church,
                      _ importance: Importance = .notable) -> PlannerSite {
        PlannerSite(id: id, name: id, coordinate: Coordinate(lat: lat, lon: lon),
                    cityId: city, type: type, importance: importance)
    }

    /// Seven real Rome sites, roughly the worked example in the spec.
    private var romeDay: [PlannerSite] {
        [
            site("trastevere", 41.8896, 12.4695, city: "rome", .church, .major),
            site("sabina", 41.8843, 12.4794, city: "rome", .church, .notable),
            site("arch", 41.8898, 12.4906, city: "rome", .triumphalArch, .minor),
            site("maxentius", 41.8925, 12.4880, city: "rome", .archaeologicalSite, .notable),
            site("phocas", 41.8925, 12.4853, city: "rome", .column, .minor),
            site("clemente", 41.8894, 12.4977, city: "rome", .church, .major),
            site("prassede", 41.8959, 12.4981, city: "rome", .church, .notable),
        ]
    }

    // MARK: shape

    @Test func aSingleCityTripProducesOneDay() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        #expect(trip.days.count == 1)
        #expect(trip.days[0].stops.count == 7)
        #expect(trip.unplacedSiteIds.isEmpty)
    }

    @Test func everyChosenSiteAppearsExactlyOnce() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 2))
        let ids = trip.days.flatMap { $0.stops.map(\.site.id) }
        #expect(Set(ids) == Set(romeDay.map(\.id)))
        #expect(ids.count == romeDay.count)
    }

    @Test func dwellTimesComeFromVisitDuration() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        let byId = Dictionary(uniqueKeysWithValues:
            trip.days[0].stops.map { ($0.site.id, $0.dwellMinutes) })
        #expect(byId["trastevere"] == 75)   // major church
        #expect(byId["sabina"] == 30)       // notable church
        #expect(byId["arch"] == 15)         // minor arch, capped
        #expect(byId["maxentius"] == 45)    // notable archaeological, x1.5
        #expect(byId["phocas"] == 15)       // minor column, capped
    }

    @Test func paceFlowsThroughToDwellTimes() {
        let relaxed = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, pace: .relaxed, dayCount: 1))
        let packed = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, pace: .packed, dayCount: 1))
        #expect(relaxed.days[0].dwellMinutes > packed.days[0].dwellMinutes)
    }

    // MARK: clock

    @Test func theFirstStopStartsWhenTheDayOpens() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1,
                        dayStartMinutes: 600, dayEndMinutes: 1_140))
        #expect(trip.days[0].stops[0].arrivalMinutes == 600)
    }

    @Test func arrivalsAreMonotonicWithinADay() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        let arrivals = trip.days[0].stops.map(\.arrivalMinutes)
        #expect(arrivals == arrivals.sorted())
    }

    @Test func onlyTheFirstStopOfADayHasNoInboundLeg() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        let stops = trip.days[0].stops
        #expect(stops[0].legTravelSeconds == nil)
        #expect(stops.dropFirst().allSatisfy { $0.legTravelSeconds != nil })
    }

    // MARK: lunch and fixed blocks

    @Test func lunchIsAddedByDefault() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        #expect(trip.days[0].blocks.contains { $0.spec.kind == .meal })
    }

    @Test func lunchCanBeTurnedOff() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1, includeLunch: false))
        #expect(!trip.days[0].blocks.contains { $0.spec.kind == .meal })
    }

    @Test func aDeclaredArrivalBlockIsPlacedOnItsDay() {
        let arrival = FixedBlockSpec(kind: .arrival, title: "Train from Naples",
                                     startMinutes: 840, durationMinutes: 45)
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1,
                        fixedBlocks: [0: [arrival]]))
        #expect(trip.days[0].blocks.contains { $0.spec.kind == .arrival })
    }

    // MARK: multi-city splitting

    @Test func citiesAreSpreadAcrossDays() {
        let sites = [
            site("r1", 41.89, 12.49, city: "rome"),
            site("r2", 41.90, 12.45, city: "rome"),
            site("v1", 44.42, 12.20, city: "ravenna"),
            site("v2", 44.41, 12.19, city: "ravenna"),
        ]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .driving, dayCount: 2))
        #expect(trip.days.count == 2)
        for day in trip.days {
            #expect(Set(day.stops.compactMap(\.site.cityId)).count == 1)
        }
    }

    /// "Three days in Rome" — one city, more sites than a single day holds.
    /// This is the app's most common trip and must not collapse into one
    /// overstuffed day.
    @Test func aBigCityIsSplitAcrossTheAvailableDays() {
        let many = (0..<30).map {
            site("m\($0)", 41.88 + Double($0 % 6) * 0.003,
                 12.47 + Double($0 / 6) * 0.003, city: "rome", .church, .major)
        }
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: many, mode: .walking, dayCount: 3))
        #expect(trip.days.count == 3)
        #expect(trip.days.allSatisfy { !$0.stops.isEmpty })
        // Thirty major churches cannot fit in three days; the rest are reported.
        #expect(!trip.unplacedSiteIds.isEmpty)
        let placed = trip.days.flatMap { $0.stops.map(\.site.id) }
        #expect(Set(placed).isDisjoint(with: Set(trip.unplacedSiteIds)))
        #expect(placed.count + trip.unplacedSiteIds.count == 30)
    }

    /// `dayCount` is a maximum, not a quota — the planner never pads out empty
    /// days just because the user allowed for more.
    @Test func dayCountIsAMaximumNotAQuota() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 5))
        #expect(trip.days.count == 1)
        #expect(trip.unplacedSiteIds.isEmpty)
    }

    @Test func sitesThatDoNotFitAreReportedRatherThanDropped() {
        // Three distant cities, one day: two cities cannot be placed.
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 44.42, 12.20, city: "ravenna"),
            site("c", 41.00, 28.98, city: "istanbul"),
        ]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .driving, dayCount: 1))
        #expect(trip.days.count == 1)
        #expect(trip.unplacedSiteIds.count == 2)
        let placed = trip.days.flatMap { $0.stops.map(\.site.id) }
        #expect(Set(placed).union(trip.unplacedSiteIds) == ["a", "b", "c"])
    }

    // MARK: diagnostics

    @Test func tooManyCitiesForTheDaysIsDiagnosed() {
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 44.42, 12.20, city: "ravenna"),
            site("c", 41.00, 28.98, city: "istanbul"),
        ]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .driving, dayCount: 1))
        #expect(trip.diagnostics.contains(
            .tooManyCitiesForDays(cityCount: 3, dayCount: 1)))
    }

    @Test func aRoomyDayIsDiagnosedAsHavingSlack() {
        let sites = [site("a", 41.89, 12.49, city: "rome")]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .walking, dayCount: 1))
        #expect(trip.diagnostics.contains { if case .largeSlack = $0 { true } else { false } })
    }

    // MARK: degenerate inputs

    @Test func noSitesProducesNoDaysAndNoCrash() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: [], mode: .walking, dayCount: 3))
        #expect(trip.days.isEmpty)
        #expect(trip.unplacedSiteIds.isEmpty)
    }

    @Test func zeroDaysProducesNoDaysAndEverythingUnplaced() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 0))
        #expect(trip.days.isEmpty)
        #expect(Set(trip.unplacedSiteIds) == Set(romeDay.map(\.id)))
    }

    @Test func oneSiteIsAValidTrip() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: [site("solo", 41.0, 28.9, city: "istanbul")],
                        mode: .walking, dayCount: 1))
        #expect(trip.days.count == 1)
        #expect(trip.days[0].stops.count == 1)
        #expect(trip.days[0].travelMinutes == 0)
    }

    @Test func planningIsDeterministic() {
        let request = TripRequest(sites: romeDay, mode: .walking, dayCount: 2)
        let a = ItineraryPlanner.plan(request)
        let b = ItineraryPlanner.plan(request)
        #expect(a == b)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/ItineraryPlannerTests 2>&1 | tail -20`

Expected: FAIL — `cannot find 'ItineraryPlanner' in scope`.

- [ ] **Step 4: Implement `ItineraryPlanner`**

Create `ByzantineTrail/Core/Planner/Domain/ItineraryPlanner.swift`:

```swift
import Foundation

/// Turns a `TripRequest` into a `PlannedTrip`.
///
/// Synchronous and deterministic: the same request always produces the same
/// trip. Real routes and their polylines are layered on afterwards by M7b,
/// which replaces the estimated leg times without re-ordering anything.
enum ItineraryPlanner {
    static let defaultLunch = FixedBlockSpec(kind: .meal, title: "Lunch",
                                             startMinutes: 780, durationMinutes: 60)

    static func plan(_ request: TripRequest,
                     estimator: any TravelEstimating = HaversineEstimator()) -> PlannedTrip {
        guard !request.sites.isEmpty, request.dayCount > 0 else {
            return PlannedTrip(days: [], diagnostics: [],
                               unplacedSiteIds: request.dayCount > 0
                                   ? [] : request.sites.map(\.id))
        }

        let clusters = DayClusterer.order(DayClusterer.cluster(request.sites),
                                          mode: request.mode, estimator: estimator)
        let cityCount = Set(request.sites.compactMap(\.cityId)).count

        var days: [PlannedDay] = []
        var unplaced: [String] = []
        var dayIndex = 0

        for cluster in clusters {
            guard dayIndex < request.dayCount else {
                unplaced.append(contentsOf: cluster.sites.map(\.id))
                continue
            }

            // Order the whole cluster once, then take it a day at a time. A
            // city bigger than one day spills into the next, which is what
            // "three days in Rome" needs.
            var remaining = ArraySlice(orderedSites(of: cluster,
                                                    request: request,
                                                    estimator: estimator))

            while !remaining.isEmpty && dayIndex < request.dayCount {
                let take = prefixThatFits(Array(remaining),
                                          request: request, estimator: estimator)
                days.append(buildDay(sites: Array(remaining.prefix(take)),
                                     dayIndex: dayIndex,
                                     request: request,
                                     estimator: estimator))
                remaining = remaining.dropFirst(take)
                dayIndex += 1
            }

            // Whatever is still left had no day to go in. Reported, not dropped.
            unplaced.append(contentsOf: remaining.map(\.id))
        }

        let diagnostics = PlanDiagnostics.evaluate(days: days,
                                                   cityCount: cityCount,
                                                   dayCount: request.dayCount)

        return PlannedTrip(days: days,
                           diagnostics: diagnostics,
                           unplacedSiteIds: unplaced)
    }

    private static func orderedSites(of cluster: SiteCluster,
                                     request: TripRequest,
                                     estimator: any TravelEstimating) -> [PlannerSite] {
        let order = StopSequencer.sequence(coordinates: cluster.sites.map(\.coordinate),
                                           mode: request.mode,
                                           estimator: estimator)
        return order.map { cluster.sites[$0] }
    }

    /// How many stops from the front of `sites` fit inside one day window.
    /// Always at least one — a day with a single oversized stop is allowed to
    /// overrun and be flagged, but the planner must never loop forever.
    private static func prefixThatFits(_ sites: [PlannerSite],
                                       request: TripRequest,
                                       estimator: any TravelEstimating) -> Int {
        let window = request.dayEndMinutes - request.dayStartMinutes
        var used = request.includeLunch ? defaultLunch.durationMinutes : 0
        var count = 0

        for (index, site) in sites.enumerated() {
            var addition = VisitDuration.minutes(type: site.type,
                                                 importance: site.importance,
                                                 pace: request.pace)
            if index > 0 {
                addition += Int(estimator.seconds(from: sites[index - 1].coordinate,
                                                  to: site.coordinate,
                                                  mode: request.mode).rounded()) / 60
            }
            if count > 0 && used + addition > window { break }
            used += addition
            count += 1
        }
        return max(1, count)
    }

    private static func buildDay(sites ordered: [PlannerSite],
                                 dayIndex: Int,
                                 request: TripRequest,
                                 estimator: any TravelEstimating) -> PlannedDay {
        let stops = ordered.map { site in
            (site: site,
             dwellMinutes: VisitDuration.minutes(type: site.type,
                                                 importance: site.importance,
                                                 pace: request.pace))
        }

        var legSeconds: [Int] = []
        for i in 0..<max(0, ordered.count - 1) {
            legSeconds.append(Int(estimator.seconds(from: ordered[i].coordinate,
                                                    to: ordered[i + 1].coordinate,
                                                    mode: request.mode).rounded()))
        }

        var blocks = request.fixedBlocks[dayIndex] ?? []
        if request.includeLunch { blocks.append(defaultLunch) }

        return TimeBudget.layOut(stops: stops,
                                 legSeconds: legSeconds,
                                 windowStartMinutes: request.dayStartMinutes,
                                 windowEndMinutes: request.dayEndMinutes,
                                 blocks: blocks)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/ItineraryPlannerTests 2>&1 | tail -20`

Expected: PASS, 20 tests.

- [ ] **Step 6: Add the purity guard test**

Append to `ByzantineTrailTests/ItineraryPlannerTests.swift`:

```swift
/// M7a's central constraint: the domain layer must stay free of platform
/// frameworks so it can be reasoned about and tested without a simulator.
/// If this fails, something imported a framework into `Core/Planner/Domain/`.
struct PlannerDomainPurityTests {
    private static let forbidden = ["SwiftUI", "UIKit", "MapKit", "SwiftData", "Combine"]

    @Test func domainSourcesImportOnlyFoundation() throws {
        let root = URL(fileURLWithPath: #filePath)      // .../ByzantineTrailTests/ItineraryPlannerTests.swift
            .deletingLastPathComponent()                 // .../ByzantineTrailTests
            .deletingLastPathComponent()                 // repo root
            .appendingPathComponent("ByzantineTrail/Core/Planner/Domain")

        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        #expect(!files.isEmpty, "found no domain sources at \(root.path)")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for framework in Self.forbidden {
                #expect(!text.contains("import \(framework)"),
                        "\(file.lastPathComponent) imports \(framework)")
            }
        }
    }
}
```

- [ ] **Step 7: Run the full test suite**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -25`

Expected: PASS. Every pre-existing test still passes — M7a is purely additive and modifies no existing file.

- [ ] **Step 8: Commit**

```bash
git add ByzantineTrail/Core/Planner/Domain/ItineraryPlanner.swift \
        ByzantineTrail/Core/Planner/Domain/PlannerTypes.swift \
        ByzantineTrailTests/ItineraryPlannerTests.swift
git commit -m "feat(planner): compose the solver into ItineraryPlanner"
```

---

## Done criteria

M7a is complete when:

1. `xcodebuild ... test` passes with no failures.
2. `ByzantineTrail/Core/Planner/Domain/` contains 13 source files, none importing SwiftUI, UIKit, MapKit, SwiftData, or Combine — enforced by `PlannerDomainPurityTests`.
3. `ItineraryPlanner.plan(_:)` turns a `TripRequest` into a `PlannedTrip` with ordered stops, derived dwell times, clock times, and diagnostics — with no view, no persistence, and no network anywhere in the feature.
4. No existing file has been modified.

M7b picks up from here: `SavedItinerary` persistence, the Trips tab, the day view, `MapKitRouteResolver`, and the disclosures in spec §8.
