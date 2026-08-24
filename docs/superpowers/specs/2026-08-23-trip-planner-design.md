# M7 — Trip Planner (Design)

**Status:** Approved for planning (2026-08-23)
**Milestone:** M7 (first post-release feature; first paid feature)
**Depends on:** M0–M6 (all merged). **No backend, no CloudKit schema changes, no
catalog schema changes.**

## 0. Goal

Let a user pick a set of sites, a mode of transport, and a timeframe, and get a
day-by-day itinerary with an efficient stop order, honest time budgeting, a map
with drawn routes, and free-form editing afterwards.

1. **Wizard** — sites → when → how → optional fixed blocks → generate.
2. **Solver** — cluster into days, order stops, budget time, report tightness.
3. **Itinerary** — persisted, editable, readable offline.
4. **Map** — real routes from `MKDirections`, drawn and cached.
5. **Disclosures** — what the planner does and does not know, stated before
   purchase and at each point of reliance (§8).
6. **Paywall** — generation is free and fully visible; **saving** is the gate.

Everything runs **on-device**. There is no server, no API key, and no new
network dependency beyond MapKit, which is already linked.

## 1. Non-goals (YAGNI)

Explicitly out of scope for M7. Each was considered and deferred:

- **No LLM anything.** No conversational planning, no generated prose. The
  "clarifying questions" are deterministic conditions detected in code
  (§6). An LLM concierge is a possible later layer behind its own protocol; it
  is the only part of this feature that would ever require a backend.
- **No structured opening hours.** `hours` stays free text and is **displayed,
  never parsed**. The planner never claims to know whether a site is open.
  Editability is the mitigation (§0.3): the user sees "Mon: closed", swaps the
  stop in two taps, and the day recalculates.
- **No itinerary sync.** Local-only. Merging concurrent reorders across devices
  is a genuinely hard conflict problem and is not worth it before there are
  paying users. The model is shaped so whole-document last-writer-wins can be
  added later (§5, "Sync").
- **No automatic re-optimization.** Manual edits recalculate timings only. There
  is an explicit "Re-optimize this day" action (§7.4).
- **No long-haul routing.** Flights, ferries, and intercity rail are
  **user-declared `FixedBlock`s**, not looked-up schedules. The planner budgets
  around them and prices nothing.
- **No draggable pane divider.** Three discrete states with corner buttons (§7.2).
- **No pane-mode persistence.** Toggling is one tap; `@State` only.
- **No queue/ticket-line modeling.** Seasonal, unpredictable, site-specific.
  Modeling it badly is worse than not modeling it.
- **No per-site authored visit durations.** Derived from `importance` and
  `type`, which are already 100% populated. An optional catalog field can be
  added later where derivation is visibly wrong.
- **No blocking disclaimer gate and no first-launch disclaimer wall.**
  Disclosure is contextual and pre-purchase instead (§8.5).
- **No custom EULA.** Apple's standard EULA applies by default; a short in-app
  Terms screen supplements it (§8.4).

## 2. Constraints (carried from the project)

- **Swift Testing**, not XCTest. iOS 17+ deployment target.
- **XcodeGen**: regenerate via the real binary `~/bin/xcodegen_dist/bin/xcodegen`
  after `project.yml` changes.
- **Architecture pattern:** pure, testable units with no UIKit/MapKit/SwiftData
  imports, separated from thin SwiftUI views. Platform access quarantined at the
  edges — exactly as `RatingsServicing` / `RemoteSyncProvider` already are.
- **Chrysos theme tokens** — no raw hex in views (`docs/COLOR_SYSTEM.md`).
- **Owner email must never appear in public view.** Nothing in M7 emits text.

## 3. What already exists (do not rebuild)

- **`Site`** (`Core/Catalog/Site.swift`) — has `coordinate`, `cityId`,
  `importance`, `type`, `hours` (free text). All the solver needs.
- **`Catalog`** — 581 sites, 281 cities, `catalogVersion`. Cached locally by
  `CatalogCache`; available offline once fetched.
- **`CatalogStore`** — the in-memory catalog; use it for site lookup by id.
- **`SiteFilter` / `SiteQuery`** (`Core/Catalog/`) — reuse verbatim for the
  wizard's site picker. Do not write a second filtering path.
- **`UserStateStore`** (`Core/UserState/`) — `wantIDs` is the **seed** for the
  wizard's pre-checked selection. `@MainActor @Observable`, SwiftData, single
  `apply` choke point. `ItineraryStore` mirrors this shape.
- **`EntitlementManager`** (`Core/Entitlements/`) — protocol with
  `FreeEntitlementManager` returning `true` for everything. Add a
  `.tripPlanner` case to `FeatureGate`; the real StoreKit 2 implementation
  lands behind the same protocol.
- **`ThemeManager`**, **`NetworkMonitor`** (`Core/Networking/`) — reuse as-is.
  `NetworkMonitor` drives the estimated/offline banner.

## 4. Architecture

```
Core/Planner/
  Domain/            pure Swift — no MapKit, no SwiftData, no network
    TripRequest.swift
    TravelMode.swift
    TravelEstimating.swift        protocol (sync, free, unlimited)
    HaversineEstimator.swift
    VisitDuration.swift
    DayClusterer.swift
    StopSequencer.swift
    TimeBudget.swift
    PlanDiagnostics.swift
    ItineraryPlanner.swift
  Routing/
    RouteResolving.swift          protocol (async, throttled, network)
    MapKitRouteResolver.swift     the ONLY file importing MapKit here
  Storage/
    SavedItinerary.swift          @Model + child models
    ItineraryStore.swift          @MainActor @Observable

Features/Trips/                   views
Features/Settings/
  TripEstimatesView.swift         static explainer (§8.3)
  TermsView.swift                 static terms (§8.4)
```

### 4.1 The central decision: two travel-time protocols, not one

```swift
protocol TravelEstimating: Sendable {
    func seconds(from: Coordinate, to: Coordinate, mode: TravelMode) -> TimeInterval
}

protocol RouteResolving: Sendable {
    func route(from: Coordinate, to: Coordinate, mode: TravelMode) async throws -> ResolvedRoute
}
```

They look similar and are not. `TravelEstimating` is **synchronous, free, and
called hundreds of times inside the solver loop**. `RouteResolving` is
**async, throttled, network-dependent, and called ~6 times per day, after the
plan is decided**.

Merging them into one async protocol makes the solver async, network-dependent,
slow, and throttle-bound — and *that* is the change that would eventually force
a backend. Keeping them apart is what keeps this feature free to run.

`HaversineEstimator` = great-circle distance × a mode detour factor ÷ mode speed.
Detour factors: walking 1.30, driving 1.35, transit 1.40. Speeds: walking
4.5 km/h, driving 30 km/h urban, transit 18 km/h door-to-door. All constants
live in one struct and are tunable in one place.

### 4.2 Where a backend would plug in, if ever

`TravelEstimating` gains a remote implementation for long-haul; a concierge
becomes a third protocol. Neither touches `ItineraryPlanner`, `DayClusterer`,
or `StopSequencer` — those never learn a network exists.

## 5. Components

### 1. `VisitDuration` (pure) — `Core/Planner/Domain/VisitDuration.swift`

Derives dwell time from `importance` and `type`. Both fields are 100% populated
across all 581 sites, so this requires **no new authoring**.

```
base:    major 75 · notable 30 · minor 15      (minutes)

type rule (applied to base):
  museum                              floor 45
  archaeologicalSite                  × 1.5
  monastery                           × 1.25
  column, triumphalArch, icon,
    tower, mausoleum, aqueduct        cap 15    ┐ non-major only
  cityWalls                           cap 30    ┘
  everything else                     base

then: × pace   (relaxed 1.3 · standard 1.0 · packed 0.75)
then: round half up to nearest 5, minimum 5
```

**Caps apply only when `importance != .major`.** Without this rule the
Theodosian Land Walls — the sole `major` + `cityWalls` site — would be budgeted
at 30 minutes. No capped single-object type has a major site, so this exception
affects exactly one row and needs no special-casing.

Yields eight distinct values across the catalog at standard pace: **15 · 20 · 25 ·
30 · 40 · 45 · 75 · 95**. Rounding is deliberate — these are guesses derived from
two categorical fields, and displaying "22 minutes" implies precision that does
not exist.

Verified against the shipped catalog: Theodosian Land Walls → 75 (cap exempted),
minor museum → 45, major monastery → 95, minor archaeological site → 25, minor
column → 15.

Per-stop override lives on `ItineraryStop.dwellMinutes` and sets `isPinned`.

### 2. `DayClusterer` (pure) — `Core/Planner/Domain/DayClusterer.swift`

Sites → day-sized clusters. `cityId` does most of the work for free (281 cities
already assigned); distance-based agglomeration handles sites without one and
splits cities too large for a single day. Returns clusters ordered by a
nearest-neighbour pass over cluster centroids.

### 3. `StopSequencer` (pure) — `Core/Planner/Domain/StopSequencer.swift`

Cluster → ordered path. **Open TSP** (a path, not a cycle) unless the trip
declares a lodging anchor, in which case it is a cycle.

- **n ≤ 12** — exact Held–Karp. n²·2ⁿ ≈ 590k operations, a few milliseconds.
- **n > 12** — nearest-neighbour seed + 2-opt improvement to convergence.

Pinned stops (`isPinned`) are fixed in place; the sequencer orders around them.

### 4. `TimeBudget` (pure) — `Core/Planner/Domain/TimeBudget.swift`

Lays stops and legs onto the clock from `dayStartMinutes`, inserting a meal
block and honouring `FixedBlock`s. Produces arrival/departure per stop and the
day's slack.

### 5. `PlanDiagnostics` (pure) — `Core/Planner/Domain/PlanDiagnostics.swift`

Detects conditions and offers specific remedies (§6). Tightness from slack as a
fraction of the day window: **>25% relaxed · 10–25% comfortable · 0–10% tight ·
<0 over**. Dwell ratio = time-inside-sites ÷ total day; **below 50% flags** "more
time traveling than visiting."

### 6. `ItineraryPlanner` (pure) — `Core/Planner/Domain/ItineraryPlanner.swift`

Orchestrates 2→3→4→5 over a `TripRequest`, returns a `PlannedTrip` value type.
Synchronous. No I/O. This is the whole feature's core and it is a pure function.

### 7. `MapKitRouteResolver: RouteResolving` — `Core/Planner/Routing/`

Wraps `MKDirections`. Returns `ResolvedRoute { seconds, distance, polyline }`.
Retries `MKError.loadingThrottled` with exponential backoff and surfaces no
error to the user — a throttled leg simply stays estimated.

The only file in the feature importing MapKit outside the views.

### 8. Storage — `Core/Planner/Storage/`

```swift
@Model final class SavedItinerary {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var startDate: Date?
    var mode: String            // raw value, not enum — migration-safe
    var pace: String
    var dayStartMinutes: Int    // 540 == 09:00
    var dayEndMinutes: Int
    var catalogVersion: Int
    @Relationship(deleteRule: .cascade) var days: [ItineraryDay]
}

@Model final class ItineraryDay {
    var id: UUID
    var order: Int              // explicit — SwiftData does not preserve array order
    var date: Date?
    var anchorCityId: String?
    var notes: String?
    @Relationship(deleteRule: .cascade) var stops: [ItineraryStop]
    @Relationship(deleteRule: .cascade) var blocks: [FixedBlock]
}

@Model final class ItineraryStop {
    var id: UUID
    var order: Int
    var siteId: String
    var nameSnapshot: String    // survives catalog changes
    var lat: Double
    var lon: Double
    var dwellMinutes: Int
    var isPinned: Bool
    var legTravelSeconds: Int?  // travel FROM previous stop; nil for the first
    var legIsEstimated: Bool
    var legPolylineData: Data?  // encoded geometry, local only
    var userNote: String?
}

@Model final class FixedBlock {
    var id: UUID
    var order: Int
    var kind: String            // arrival / departure / meal / lodging / custom
    var title: String
    var startMinutes: Int
    var durationMinutes: Int
}
```

Three deliberate decisions:

**Explicit `order: Int` everywhere.** SwiftData relationships are unordered
sets; array order does not survive a fetch. Every ordered collection carries its
own index and is sorted on read. This is a common and surprising bug — §10 tests
it directly.

**Denormalized `nameSnapshot` / `lat` / `lon`.** Display prefers a live
`CatalogStore` lookup by `siteId` and falls back to the snapshot, so a saved
trip still renders if a site is removed or the catalog fails to load.
Descriptions, photos, and hours are **not** copied — they stay live.

**Persisted `legTravelSeconds` and `legPolylineData` are the offline story.**
A saved trip reads fully offline because its times and geometry are stored, not
recomputed on open. ~30 legs per 5-day trip at 1–3 KB each.

**`ItineraryStore`** — `@MainActor @Observable`, single `apply` choke point,
mirroring `UserStateStore`. Container built with `cloudKitDatabase: .none`.

#### Sync (deferred, but shaped for)

When added, the tractable form is **whole-document last-writer-wins**: one
`CKRecord` per itinerary holding a serialized JSON blob plus `updatedAt`, not
field-level merge. **Exclude polylines** from the blob (1 MB record limit) and
regenerate them on the receiving device when next online.

### 9. Catalog drift

On open, if `catalogVersion` differs and referenced sites are missing or have
moved materially, show a **non-blocking banner** — *"2 sites in this trip have
been updated. Review."* Never silently rewrite the user's document.

### 10. UI — `Features/Trips/`

Fourth tab, **Trips**. A paywalled headline feature buried under Profile costs
discovery and conversion; four tabs is comfortable on iOS.

## 6. Deterministic clarifying questions

All derivable with no hours data and no network. Each is a detected condition
with a specific offered remedy.

| Condition | Message |
|---|---|
| Sites span more cities than days allow | "These are in Ravenna, Rome, and Istanbul. 2 days won't cover them — extend to 5, or split into separate trips?" |
| Day exceeds its window | "Day 2 runs ~2h over. Drop a stop, extend the day, or accept and see it flagged?" |
| Mode cannot cover the distances | "Mystras and Athens are 3½ hours apart on foot. Switch to driving?" |
| One site far from its cluster | "Nicaea is 2h from everything else. Give it its own day, or remove it?" |
| Transit unavailable in that city | "Apple has no transit data for Ohrid. Using walking estimates there." |
| Dwell ratio below 50% | "Day 2: 5½ hours traveling, 3 hours visiting. Consider dropping the Mystras leg." |
| Day has large slack | "Day 3 has ~4 free hours." → offers nearby unchosen sites within 1 km of the route |

**Ordering rule:** surface **infeasibility before generating**, and
**opportunity after**, on the finished plan. Blocking someone with suggestions
before they have seen a result is hostile; offering enrichment once they are
invested is welcome.

The slack row is the most defensible reason to pay — the app knows 581 sites
and the user does not.

## 7. Presentation

### 7.1 Wizard — four steps

1. **Sites** — pre-checked from `wantIDs`, filtered via existing `SiteFilter`.
   Live footer: *"12 sites across 3 cities."*
2. **When** — date range or day count; daily window (default 09:00–18:00).
3. **How** — mode and pace.
4. **Fixed blocks** — optional, skippable.

Generation is synchronous and instant. Routes resolve progressively after.

### 7.2 Day view — split with corner toggles

```swift
enum DayPaneMode { case mapFull, split, listFull }   // @State, not persisted
```

Map on top (36%), timeline below (64%). Each pane has a corner button toggling
between its own full state and `split` — always one tap either way; the icon
flips expand↔contract; the collapsed pane's button hides. Animated with
`withAnimation(.snappy)`.

**Map-full carries a chrome pill** at the bottom — *"3 of 7 · Arch of
Constantine · 11:25"* — so a full-screen map does not lose which pin is which.

### 7.3 Honesty in the numbers

Every leg carries `legIsEstimated`, shown as a **tilde**:

- **`~22 min`** — estimated, haversine-derived
- **`22 min`** — resolved by `MKDirections`

A tilde reads as "approximately" to everyone and needs no legend or warning
icon. Arrival times are derived and shift slightly as legs resolve.

**Never say "optimal route."** Held–Karp is optimal *with respect to estimated
distances*, which is not the claim a user hears. Say **"an efficient order."**

### 7.4 The proxy problem and the re-optimize pass

The solver orders by straight-line distance, but people walk on streets
constrained by rivers and walls — and this catalog is concentrated in exactly
the cities where that bites. Santa Maria in Trastevere → Santa Sabina is ~700 m
straight-line and ~1.2 km on foot because the Tiber is in the way. Galata
versus Sultanahmet is worse.

After real routes return for a day, compare resolved travel against the estimate
that drove the ordering. **If more than 25% over**, offer:

> *"Real walking times came in 40% above estimate — the Tiber crossings add up.
> Re-optimize this day using real distances?"*

Only on the user's tap resolve a full matrix for **that one day** (≤12 stops,
~66 symmetric pairs) with backoff and a progress indicator. Doing this
automatically for every day would blow the throttle and slow generation for no
visible reason.

## 8. Disclosures — what we are actually selling

The planner sells **ordering and time budgeting**. It does not know whether
anything is open. For a paid feature that distinction has to be visible *before
purchase*, not discovered afterwards on a doorstep in Thessaloniki.

Disclosure is **layered and contextual**. A single blanket notice at first launch
is weaker — both as protection and as UX — than a specific statement at each
point of reliance. If every number carries a warning, users stop reading all of
them, including the one that matters.

### 8.1 Paywall copy (load-bearing)

This is where "don't sell what you're not selling" is decided, and it is also an
**App Store Review Guideline 3.1.2** concern: an IAP has to accurately describe
what it delivers. "Trip planner" unqualified invites a reviewer — and a buyer —
to assume hours-awareness.

> **Trip Planner** builds a suggested day-by-day route from the sites you choose,
> estimates walking, driving, and transit times, and suggests how long to spend
> at each site based on its type and significance.
>
> It does **not** check opening hours, closures, holidays, ticket availability,
> or accessibility. Always confirm before you travel.

The App Store description for the IAP carries the same two paragraphs.

### 8.2 Contextual notices

| Where | Text | Frequency |
|---|---|---|
| Estimated leg | `~` prefix (§7.3) | Every estimated leg |
| `hours` row on a stop | "Hours as published — confirm before visiting" | Every stop that has hours |
| Stop with no hours data | "Hours unknown — check before you go" | Every stop without hours |
| Day view footer | "About these estimates" → §8.3 | Persistent, unobtrusive |
| First generated itinerary | Short sheet summarising §8.1 | **Once**, dismissible, never again |

The two `hours` rows matter most: a wrong assumption there is the only failure in
this feature that can actually strand someone.

### 8.3 `TripEstimatesView` — `Features/Settings/TripEstimatesView.swift`

A static explainer, reached from Settings → About and from the day-view footer.
Mirrors the existing `PrivacyPolicyView` structure exactly — bundled text, no
networking, Chrysos tokens. Covers:

- How visit durations are derived (type and significance, not measurement)
- What `~` means, and when a leg becomes a real route
- That straight-line ordering can be wrong where water or walls intervene, and
  what "Re-optimize this day" does (§7.4)
- **What the app does not know:** opening hours, closures, public and religious
  holidays, services in working churches, strikes, ticket availability, queues,
  weather, accessibility, road conditions
- Catalog currency — data is community-maintained and may lag reality

### 8.4 Terms

The app currently ships a Privacy Policy and no terms. Two facts shape the
recommendation:

- **Apple's standard EULA already applies** to every App Store app that does not
  supply its own, and it already disclaims warranties and limits liability. For
  an app in this risk class that is a defensible baseline.
- **EU and UK consumer law caps what can be disclaimed** against consumers
  regardless of EULA wording, and this app's audience skews heavily European
  (Greece, Italy, Turkey, Cyprus). A blanket exclusion buys less than it appears
  to. Apple also controls refunds, so any refund clause of ours is inoperative.

**Recommendation for M7:** rely on Apple's standard EULA and put the effort into
§8.1 and §8.3, which do the real work. Add a short in-app **Terms** screen
alongside `PrivacyPolicyView` stating informational-use-only, no warranty of
accuracy, and that travel decisions remain the user's own.

A custom EULA is a §12 decision, not an M7 blocker. **Not drafted here — this
spec is not legal advice, and the wording should be reviewed by someone
qualified before it ships.**

### 8.5 Deliberately not done

- **No blocking "I understand" gate before generating.** Friction that buys
  little — the purchase is already the consent moment — and it makes a paid
  feature feel defensive.
- **No first-launch disclaimer wall.** Nobody reads it; it displaces the
  contextual notices that people do read.
- **No per-number warning icons.** The `~` convention carries this.

## 9. Error handling and degradation

| Situation | Behavior |
|---|---|
| No network at generation | All legs estimated with `~`; banner offers refresh when back online |
| No network on a saved trip | Reads perfectly — times and polylines persisted |
| `MKDirections` throttled | Keep the estimate, retry with backoff, **no user-facing error** |
| Transit unsupported in that city | Fall back to walking estimates; note **once per day**, not per leg |
| Leg genuinely unroutable (island, closed border) | Mark leg unroutable, flag the day, **never draw a straight line across water** |
| Catalog fails to load | Saved trips still render from snapshots |
| Site removed from catalog | Stop renders from snapshot; drift banner offers review |
| Empty selection / zero days | Generate disabled with inline reason; never produce an empty itinerary |
| Single site selected | Valid — a one-stop day, no legs, no diagnostics |

The unroutable row matters more than it looks: the catalog spans Cyprus, Crimea,
and several Greek islands. A walking route from Athens to Patmos must fail
loudly rather than quietly render a line across the Aegean.

## 10. Testing

Swift Testing. Everything in `Domain/` is a pure function over value types, so
the interesting logic is covered by synchronous unit tests with fixture
coordinates — no UI, no network, no SwiftData.

**`VisitDuration`** — every `type` × `importance` combination present in the
catalog; the Theodosian Walls major-cityWalls exception; museum floor; pace
multipliers; rounding and the 5-minute minimum.

**`StopSequencer`** — a known-optimal fixture (points on a circle) asserts
Held–Karp finds it; n = 13 crosses into the heuristic and must stay within a
tolerance of the exact answer; pinned stops keep their index; n = 0, 1, 2 are
degenerate cases; the open-path and lodging-cycle variants differ correctly.

**`DayClusterer`** — sites sharing a `cityId` cluster together; a city too large
for one day splits; sites with `cityId == nil` cluster by distance; a lone
distant site becomes its own cluster.

**`TimeBudget`** — arrival/departure chain arithmetic; meal insertion;
`FixedBlock` collision; a day that overruns produces negative slack.

**`PlanDiagnostics`** — each row of §6 fires on a fixture that triggers it and
**does not fire** on one that does not. Tightness and dwell-ratio boundaries
tested at their exact thresholds.

**`HaversineEstimator`** — known city-pair distances within tolerance; symmetry;
zero distance for identical coordinates.

**`ItineraryStore`** — save → refetch → **`order` survives** on days, stops, and
blocks (the SwiftData unordered-set trap); cascade delete removes children;
in-memory container per test.

**`MapKitRouteResolver`** — behind `RouteResolving`, so the planner is tested
with a stub. A small number of integration tests exercise the real resolver;
throttle handling is tested with a stub that returns `MKError.loadingThrottled`.

## 11. Build order (informs the plan)

1. `TravelMode`, `Coordinate` helpers, `HaversineEstimator`, `VisitDuration` — pure, fully tested
2. `StopSequencer` — pure, the algorithmic core
3. `DayClusterer`, `TimeBudget`, `PlanDiagnostics`
4. `ItineraryPlanner` — composes 1–3; feature is now provably correct with zero UI
5. Storage models + `ItineraryStore`
6. Trips tab, wizard, itinerary list
7. Day view: split panes, corner toggles, map chrome
8. `MapKitRouteResolver` + progressive leg resolution + tilde treatment
9. Diagnostics UI, re-optimize pass, drift banner
10. Disclosures: contextual notices (§8.2), `TripEstimatesView` (§8.3), Terms screen (§8.4)
11. `FeatureGate.tripPlanner` + StoreKit 2 gate on save + paywall copy (§8.1)

Steps 1–4 deliver a complete, tested planner before any view exists. That is the
point of keeping `Domain/` pure.

Step 10 ships **before** the paywall deliberately. The disclosures have to be in
place the first time anyone is asked to pay.

**Scope note.** This is larger than one implementation plan. The natural split is
at the 4/5 boundary, which is also where the code stops being pure:

- **M7a** — steps 1–4. The solver. No UI, no persistence, no MapKit. Fully
  tested in isolation and independently verifiable.
- **M7b** — steps 5–10. Persistence, Trips tab, day view, real routes,
  diagnostics, disclosures.
- **M7c** — step 11. Paywall, once §12 is decided.

Each gets its own plan. M7a is the one to write first and can proceed
immediately; M7c is blocked on the pricing decisions below.

## 12. Deferred decisions

- **Subscription vs. one-time unlock.** StoreKit 2 covers a one-time unlock
  on-device. A subscription makes server-side receipt validation more attractive
  for renewals and refunds — the one thing in this feature that could later
  justify a backend for non-LLM reasons.
- **Free tier shape.** Recommendation: **one free saved trip**, so the feature is
  not merely a demo. Undecided — must be settled before M7c; nothing in M7a or
  M7b depends on it.
- **Custom EULA.** Apple's standard EULA is the M7 baseline (§8.4). Revisit only
  if the feature does well. Any wording should be reviewed by someone qualified
  before shipping — nothing in this spec is legal advice.
- **Optional `typicalVisitMinutes` catalog field** where derivation is visibly
  wrong.
- **Itinerary export** (PDF, Apple Maps handoff, share sheet).
