# Byzantine Trail — Design Spec

**Version:** 2.0 (brainstorm-reconciled) · **Date:** 2026-07-12
**Owner:** John (owner identity must never appear in the app, catalog, or public repo)

A universal iPhone/iPad app cataloging Byzantine sites worldwide: browsable list, Apple Maps view, user ratings, favorites, want-to-visit, and visited tracking. Built so the site catalog and every backend service are portable to a future website/backend without rewriting feature code.

This doc supersedes the v1.0 build spec. It carries that spec forward **unchanged** except for three amendments (§0), which resolve the open architectural questions surfaced during brainstorming. The companion `docs/COLOR_SYSTEM.md` ("Chrysos" palette) remains canonical for all color tokens.

---

## 0. Amendments to v1.0 (resolved decisions)

These three decisions override the corresponding v1.0 sections. Everything else in v1.0 stands.

### 0.1 Private sync — "B-lite": protocol-based push/pull, no `CKSyncEngine`

**Goal:** backend agnosticism. Achieved via a protocol seam, *not* by hand-rolling a full sync engine.

- **SwiftData is the local source of truth, always** (backend-neutral persistence).
- A thin `RemoteSyncProvider` protocol owns the backend seam:
  ```swift
  protocol RemoteSyncProvider {
      func push(_ changes: [UserSiteChange]) async throws
      func pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken)
  }
  ```
- `CloudKitSyncProvider` implements it with `CKModifyRecordsOperation` + a server change token. **No `CKSyncEngine`.** A future `RESTSyncProvider` implements the same two methods — no feature-code changes.
- **Write path:** set fields + `updatedAt` + `pendingSync = true`. The `pendingSync` flag is backend-neutral local change-tracking (every backend needs "what changed since last sync").
- **Push:** collect `pendingSync == true` rows → `provider.push(...)` → clear flag on success.
- **Pull:** `provider.pull(since:)` → apply **last-writer-wins by `updatedAt`**.
- Works fully offline; syncs when connectivity returns.

*Replaces the `CKSyncEngine` / `CloudKitSync.swift` language in v1.0 §2 and §4.1. `CloudKitSync.swift` becomes `CloudKitSyncProvider.swift` behind `RemoteSyncProvider`.*

### 0.2 Public ratings — self-healing, rebuildable summaries

- **`Rating` records are the source of truth.** `RatingSummary` is a **derived cache that can always be rebuilt** — never trusted as authoritative.
- Keep the delta fast-path (`total += new − old`, `count += …`, change-tag retry) for O(sites) reads.
- **Add a recompute-from-`Rating` reconcile path:** on mismatch or on a schedule, recompute a site's summary by querying its actual `Rating WHERE siteId == X` records and overwrite. The detail view's live per-site fetch doubles as this reconcile.
- **Owner maintenance script** (next to `validate_catalog`) rebuilds *all* summaries from `Rating` records — the escape hatch if anything ever drifts.
- Authenticated-write on `RatingSummary` trade-off accepted as in v1.0 §4.2 (fine at this scale; revisit with a server function if abuse appears).

*Extends v1.0 §4.2. Both the delta fast-path and the recompute fallback live behind the `RatingsServicing` protocol.*

### 0.3 Monetization — seam only, defer StoreKit

**Build now** (this is the entire "paywall-later-without-refactoring" guarantee):
- `FeatureGate` enum listing gateable features (`.unlimitedFavorites`, `.altThemes`, `.offlinePhotoPacks`, … placeholders).
- `EntitlementManager` **protocol**: `func isUnlocked(_ gate: FeatureGate) -> Bool`.
- `FreeEntitlementManager` returning `true` for everything.
- Call sites already routed through the gate: `if entitlements.isUnlocked(.altThemes) { … }`.

**Defer** until a real product exists: StoreKit 2 integration + transaction listener, `.storekit` config file, `PaywallView` (even a placeholder), Restore Purchases wiring, product-ID constants. Dropping a `StoreKitEntitlementManager` behind the existing protocol later is not a refactor of feature code.

*Trims v1.0 §5.6. Knock-on: M7 shrinks; the seam moves earlier into M0 scaffolding (see §8).*

### 0.4 Protocol backbone (consequence of the above)

Four seams make CloudKit one swappable implementation and make the whole app testable without an Apple Developer account:
`RemoteSyncProvider` · `RatingsServicing` · `SuggestionSubmitting` · `EntitlementManager`.

### 0.5 Map — MKMapView bridge + shared filter model (resolved 2026-07-13, for M3)

**Engine — `MKMapView` via `UIViewRepresentable`, not SwiftUI `Map`.** §5.3 requires *styled* clustering (cluster badges Stone-950 bg / Gold-400 text) at the 500-annotation performance target (§6). SwiftUI `Map` does not cluster `Marker`s automatically and gives no hook to style cluster glyphs; hand-rolling clustering math is high-effort and janky. `MKMapView` provides native clustering via `clusteringIdentifier` and full control over marker/cluster annotation views. The UIKit surface stays quarantined in `Features/Map/` behind a SwiftUI-facing view; the rest of the app remains SwiftUI.

**Shared filter — `SiteFilterModel` (`@Observable`), injected at app root.** Holds one `var filter = SiteFilter()`, read by both the Sites list and the Map (the §5.1 name is canonical). `SiteQuery` stays the pure search→filter→sort transform; the list builds it each render from `filterModel.filter` + its *local* search/sort, and `FilterSheetView` binds to `$filterModel.filter`. The map applies `filterModel.filter.matches` to the catalog. Search and sort remain list-local — the map is filter-only per §5.3.

*Knock-on: M4's per-user state adds the visited-badge pin overlay deferred out of M3 (§5.3), and grows `SiteFilter.matches` for favorite/want/visited flags — the shared `SiteFilterModel` means that growth reaches both tabs at once.*

---

## 1. Product decisions (carried from v1.0, unchanged)

| Decision | Choice |
|---|---|
| Platforms | iOS + iPadOS, universal app. Min deployment: iOS 17. SwiftUI throughout. |
| Catalog backend | JSON catalog: bundled in app, refreshable from a remote URL (no App Store release needed for content updates). |
| User-data backend | CloudKit — private DB for personal state, public DB for shared ratings — behind the §0.4 protocol seams. |
| Identity | Silent iCloud identity. No login screen. Not signed in → local-only favorites/want-to-visit/visited; ratings disabled with a gentle explainer. |
| Scale | 150–500 sites. Data + thumbnails bundled; full-size photos remote, cached. |
| Offline | Browse offline (list, details, thumbnails). Ratings, full-size photos, map tiles require connectivity. Personal state persists locally and syncs when online. |
| Ratings | 1–10 integer scale, one editable rating per user per site. Average + count shown. |
| Importance | Named tiers: `major`, `notable`, `minor` (badge on rows/pins, filterable). |
| Suggestions | Written to a CloudKit record type only the owner can read (Dashboard). No email, no owner info anywhere in the app. |
| Distribution | TestFlight first, then App Store. |
| Monetization | Free for v1. Seam-only scaffold per §0.3. |
| v1 extras | Search; share sheet on detail pages; visited tracking (checklist + progress stats on Profile). |
| Design system | `docs/COLOR_SYSTEM.md` — "Chrysos" palette. Semantic tokens canonical. Dark mode is the showcase; default follows system setting. |
| Deferred (design for, don't build) | Website (reuses JSON catalog), distance-from-me sort, admin dashboard. |

---

## 2. Architecture

```
┌─────────────────────── App (SwiftUI, MVVM-ish) ───────────────────────┐
│  SitesListTab        MapTab            ProfileTab                       │
│      └── SiteDetailView (shared, pushed from list / sheet over map)    │
│                                                                        │
│  CatalogStore (sites.json: bundle → cached remote refresh)             │
│  UserStateStore (SwiftData local) ⇄ RemoteSyncProvider  ← §0.1         │
│  RatingsService : RatingsServicing (delta + recompute)  ← §0.2         │
│  SuggestionService : SuggestionSubmitting (create-only)                │
│  EntitlementManager (protocol; FreeEntitlementManager) ← §0.3          │
│  ThemeManager (system/light/dark + swappable palette)                  │
│  ImageCache (remote full-size photos, disk-cached)                     │
└────────────────────────────────────────────────────────────────────────┘
        │                          │
   Static host (catalog.json,   CloudKit container
   full-size photos)            iCloud.com.<team>.byzantinetrail
```

**Key principle:** the catalog is read-only reference data; CloudKit holds only user-generated data. A future website consumes the same `catalog.json` + photo URLs directly; only the two rating record types would need a web-accessible path (CloudKit JS or a thin API) — nothing else moves.

### Project structure

```
ByzantineTrail/
  App/                    ByzantineTrailApp.swift, RootTabView.swift
  Features/
    SitesList/            SitesListView, SiteRowView, FilterSheet, SortMenu
    SiteDetail/           SiteDetailView, PhotoCarousel, RatingControl, HoursSection
    Map/                  MapTabView, SitePopover, MapFilterSheet
    Profile/              ProfileView, MyRatingsView, FavoritesView, WantToVisitView,
                          VisitedView, ProgressStatsView, ThemePicker, SuggestSiteForm,
                          AccountSection, AboutView
    Entitlements/         FeatureGate.swift, EntitlementManager.swift  (seam only)
  Core/
    Catalog/              Site.swift, CatalogStore.swift, CatalogRefresher.swift
    UserState/            UserSiteState.swift (SwiftData), UserStateStore.swift,
                          RemoteSyncProvider.swift, CloudKitSyncProvider.swift
    Ratings/              RatingsServicing.swift, RatingsService.swift, RatingSummary.swift
    Suggestions/          SuggestionSubmitting.swift, SuggestionService.swift
    Theme/                ThemeManager.swift, Theme.swift, Palettes.swift
    Networking/           ImageCache.swift, RemoteConfig.swift
  Resources/              catalog.json, thumbs/, Assets.xcassets
  Tests/                  Unit + UI tests (protocol mocks)
Tools/
  validate_catalog.swift      schema validation (CI/pre-commit)
  rebuild_summaries.swift      owner-only: recompute all RatingSummary from Rating  ← §0.2
```

---

## 3. Catalog data model

The `catalog.json` schema, loading/remote-refresh flow, and authoring workflow are carried from v1.0 §3 **and are the subject of a dedicated review pass** (see §3.4). The schema below is the current draft pending that review.

### 3.1 `catalog.json` schema (revised 2026-07-12 — findings A–G folded in)

```jsonc
{
  "schemaVersion": 2,              // bumped: photoBaseURL, semanticTags, period, addedInVersion added
  "catalogVersion": 42,            // monotonically increasing; drives remote refresh
  "generatedAt": "2026-07-06T00:00:00Z",
  "photoBaseURL": "https://<static-host>/",  // C: resolves all relative photo paths (app + website)
  "cities": [                      // B: no country — site.country is authoritative; derive if ever needed
    { "id": "istanbul", "name": "Istanbul" },
    { "id": "ravenna",  "name": "Ravenna" }
  ],
  "sites": [
    {
      "id": "hagia-sophia",         // stable slug, never reused/renamed
      "name": "Hagia Sophia",
      "alternateNames": ["Ayasofya", "Church of Holy Wisdom"],
      "type": "church",             // G: primary category only; enum, unknown → .other
      "country": "TR",              // B: authoritative country (ISO 3166-1 alpha-2)
      "cityId": "istanbul",         // nullable; must match a curated city id
      "coordinate": { "lat": 41.0086, "lon": 28.9802 },
      "address": "Sultan Ahmet, Ayasofya Meydanı No:1, 34122 Fatih/İstanbul",
      "importance": "major",        // "major" | "notable" | "minor"
      "addedInVersion": 1,          // E: catalogVersion when this site first appeared; ≤ catalogVersion
      "period": {                   // F: optional structured era metadata (both sub-fields optional)
        "century": 6,               //    primary construction century, AD (Int)
        "era": "justinianic"        //    controlled vocab (validator-checked)
      },
      "summary": "One-line teaser for list rows.",
      "description": "Full multi-paragraph description. Markdown allowed.",
      "hours": "Open daily 09:00–19:00; closed during prayer times.",
      "entryInfo": "Ticketed; museum pass accepted. Modest dress required.",
      "photos": [
        {
          "id": "hagia-sophia-01",
          "thumb": "thumbs/hagia-sophia-01.jpg",   // C: relative — app: bundle first, else photoBaseURL
          "full":  "photos/hagia-sophia-01.jpg",   // C: relative — resolved against photoBaseURL
          "caption": "Interior dome",
          "credit": "Public domain"                // A: NEVER the owner's name; neutral/third-party only
        }
      ],
      "semanticTags": ["unesco"],   // D: controlled vocab — drives UI (badges/filters); validator-enforced
      "tags": ["mosaics"],          // D: freeform, search-only keywords
      "links": [{ "title": "Official site", "url": "https://..." }]
    }
  ]
}
```

**Site type enum** (G — primary category; unknown values decode to `.other` so old app versions survive new catalog values):
`church`, `monastery`, `fortress`, `palace`, `cityWalls`, `cistern`, `aqueduct`, `mosaicSite`, `archaeologicalSite`, `museum`, `tower`, `bridge`, `other`.

**Controlled vocabularies** (D, F — enforced by the validator; lists live in `validate_catalog` + `docs/CATALOG_AUTHORING.md`, extensible):
- `semanticTags` (starter set): `unesco`. UI-affecting only. Unknown values → validation error (a misspelled `unseco` fails the build rather than silently dropping a badge).
- `period.era` (starter set): `constantinian`, `theodosian`, `justinianic`, `macedonian`, `komnenian`, `palaiologan`, `other`.

**Photo-path resolution (C):** `thumb` and `full` are relative. The **app** resolves `thumb` against the bundled `thumbs/` folder first, falling back to `photoBaseURL`; it resolves `full` against `photoBaseURL`. A **future website** resolves both against `photoBaseURL`. One convention, both consumers work.

**Provenance (E):** `addedInVersion` records the `catalogVersion` in which a site first appeared. The app stores `lastSeenCatalogVersion` locally; the "Recently added" filter (§5.1) matches sites with `addedInVersion > lastSeenCatalogVersion`. No timestamps needed.

**Decoding rule:** unknown enum values and unknown JSON keys never crash decoding (custom `init(from:)` with fallbacks). Adding new *optional* keys later is non-breaking; renaming/retyping a *published* key requires dual-read migration — so `period`'s shape may be refined freely until it is populated across shipped catalogs. Log and continue.

### 3.2 Loading & remote refresh (from v1.0 §3.2)

1. On launch, load newest valid: cached remote copy in Application Support if present/valid, else bundled `catalog.json`.
2. Background `GET https://<static-host>/catalog-manifest.json` → `{ "catalogVersion": N, "url": "...", "sha256": "..." }`. If `N` > current: download, verify hash, validate schema, atomically swap, publish to UI.
3. Static host: GitHub Pages from a public content repo for v1 (free, versioned). Full-size photos same host.
4. Bundled thumbnails ship in a `thumbs/` folder resource (not asset catalog) so filenames work for remotely-added sites; the app resolves `thumb` against the bundle first and falls back to `photoBaseURL` (C). `full` resolves against `photoBaseURL`.

### 3.3 Authoring workflow (from v1.0 §3.3)

- `Tools/validate_catalog.swift` validates: schema shape; unique site & photo ids; `cityId` resolves to a curated city; `coordinate` lat ∈ [−90,90], lon ∈ [−180,180]; `country` is a valid ISO 3166-1 alpha-2 code; every referenced photo file exists (bundle or `photoBaseURL`); `semanticTags` ⊆ controlled vocab; `period.era` ⊆ controlled vocab (D, F); `addedInVersion ≤ catalogVersion` (E); and **`credit` matches no entry in an owner-name denylist** (A). Run before publishing.
- `docs/CATALOG_AUTHORING.md`: schema reference, controlled-vocab lists, copy-paste site template.

### 3.4 JSON schema review — RESOLVED (2026-07-12)

Findings A–G reviewed and folded into §3.1/§3.3:
- **A** — owner-identity leak in `credit` → neutral/third-party credits only; validator denylist.
- **B** — redundant `country` → dropped from `city`; `site.country` authoritative.
- **C** — photo-path portability → `photoBaseURL` + relative `thumb`/`full`.
- **D** — fragile semantic tags → controlled `semanticTags` (validator-enforced) split from freeform `tags`.
- **E** — provenance → `addedInVersion` + local `lastSeenCatalogVersion` powers the "Recently added" filter.
- **F** — era metadata → optional structured `period { century, era }` (era controlled vocab).
- **G** — single `type` confirmed as primary category; secondary roles live in `tags`.

---

## 4. CloudKit design (carried from v1.0 §4, as amended by §0.1–0.2)

Container `iCloud.com.<team>.byzantinetrail`.

- **Private DB — `UserSiteState`** (one per touched site): `siteId` (indexed), `isFavorite`, `wantsToVisit`, `visited`, `myRating?` (1–10), `updatedAt`. Synced via `RemoteSyncProvider` (§0.1). Marking visited clears `wantsToVisit` (with undo toast).
- **Public DB — `Rating`**: recordName `"<siteId>|<userRecordID>"` (deterministic upsert). `siteId` (indexed/queryable), `value` (1–10). Creator write, world read. **Source of truth** (§0.2).
- **Public DB — `RatingSummary`**: recordName `"summary-<siteId>"`. `siteId`, `count`, `total`. **Rebuildable derived cache** (§0.2). World read + Authenticated write.
- **Public DB — `SiteSuggestion`**: `name`, `location`, `whyInclude`, `linksText`, `submittedAt`. `_icloud` role **create-only** (no read/write) — owner reads via Dashboard. No submitter identity fields.
- **Account state:** `CKContainer.accountStatus()` observed app-wide. Not signed in → friendly Profile card + disabled rating controls; favorites/want-to-visit/visited still work locally.

Dashboard-only config (roles, queryable/sortable indexes, suggestion create-only role) documented in `docs/CLOUDKIT_SETUP.md`.

---

## 5. Feature specs (carried from v1.0 §5, unchanged except §5.6 → §0.3)

Root `TabView`: **Sites** · **Map** · **Profile**. iPad: same TabView for v1; structure views so a `NavigationSplitView` adaptation is a follow-up, not a rewrite. All orientations on iPad.

- **5.1 Sites list:** searchable/sortable/filterable list. Row = thumbnail, name, city·country, type icon+label, importance badge, avg rating `8.4 ★ (127)`, my-rating chip, favorite/want/visited glyphs (visited check in Jade). Search matches name/alt names/city/country/tags, diacritic+case-insensitive. Sort: name (default), avg rating, my rating, importance, country, city; asc/desc; persisted. Filters include a **"Recently added"** toggle (sites with `addedInVersion > lastSeenCatalogVersion`, §3.1-E). Shared `SiteFilterModel` + `FilterSheetView` (built once, used by list + map).
- **5.2 Site detail:** paged photo carousel (thumb instant, full-size fades in; tap → full-screen zoom). Name/type/importance/city/country. Action row: Favorite, Want to visit, Visited (Jade when on), Share (ShareLink w/ `maps.apple.com` link + first photo). Ratings: avg + 1–10 control, editable, "Remove my rating," disabled+explainer when signed out/offline. Description (Markdown), Hours, Entry info, Links. Location: address, coords, non-interactive map snapshot, "Open in Maps."
- **5.3 Map:** `MKMapView` via a `UIViewRepresentable` (isolated in `Features/Map/`), annotations for filtered sites, native clustering (`clusteringIdentifier`) when dense — see §0.5 for why not SwiftUI `Map`. Pin fill by tier (Major=Gold, Notable=Terracotta, Minor=Stone-400), Stone-950 stroke; selected pin enlarged w/ Gold-300 stroke + shadow; cluster badges Stone-950 bg / Gold-400 text. **Visited-badge deferral:** the "visited adds Jade check badge" pin overlay is per-user state that does not exist until M4, so it lands in M4 with the state that drives it — M3 ships tier-colored pins + selection highlight only. Tap pin → callout (site name) with detail accessory → `SiteDetailView` in `.sheet` `[.medium, .large]`. Filter change animates camera to fit visible annotations; zero → "No sites match" overlay. Filter is the shared `SiteFilterModel` (§0.5); search + sort stay list-local (map is filter-only).
- **5.4 Profile:** My activity (Ratings, Favorites, Want to Visit, Visited) with empty states. Progress stats (visited vs total, overall + per country/tier) with a Gilded progress bar. Account (iCloud status + Settings deep link). Appearance (System/Light/Dark picker). Suggest a site (form → `SuggestionSubmitting`, client-side rate-limit ~5/day). About (version, credits, data disclaimer, privacy policy link; "Restore Purchases" **deferred** per §0.3 — omit from v1 About or show disabled placeholder text only).
- **5.5 Theming:** `Theme` struct mirrors `docs/COLOR_SYSTEM.md` semantic tokens 1:1 (Swift-cased). `ThemeManager` (`@Observable`, environment-injected) exposes current `Theme` + scheme override. No hardcoded hex in feature code. Light+dark values per the doc. Future palettes = new `Theme` instances (natural paywall item — gated via the §0.3 seam).
- **5.6 Freemium:** see §0.3 (seam only).

---

## 6. Cross-cutting requirements (from v1.0 §6)

- **Offline matrix:** list/search/sort/filter/detail/thumbnails/favorites/want/visited → always. Full-size photos, map tiles, avg-rating refresh, rating submission, suggestions → network; all writes queue and replay. Unobtrusive offline indicators, never blocking alerts.
- **Accessibility:** Dynamic Type throughout; VoiceOver on rating control/pins/action buttons; sufficient contrast both themes; `accessibilityIdentifier`s for UI tests.
- **Localization-ready:** all strings in a String Catalog; English at launch.
- **Privacy:** no analytics SDKs v1. `PrivacyInfo.xcprivacy`. App Privacy label: ratings + suggestions = user content not linked to identity. **No location permission in v1** — do not add `NSLocationWhenInUseUsageDescription` (add only when distance-sort ships).
- **Performance:** 500-row list at 60fps (lazy stacks, pre-decoded thumbs); 500-annotation map clusters; catalog decode off the main thread.
- **Error handling:** typed errors as toasts/inline states; CloudKit retry w/ backoff on `.zoneBusy`/`.requestRateLimited`.

---

## 7. Testing (from v1.0 §7)

- **Unit:** catalog decoding (unknown enum/key tolerance), filter/sort logic, rating-summary delta math + **recompute reconcile** (§0.2), suggestion rate-limiting, entitlement gating.
- **Integration:** CloudKit development container; sync round-trip for `UserSiteState` via `RemoteSyncProvider`.
- **UI:** tab nav, list filter→count, map filter→re-zoom, detail rating flow (mocked), theme switch.
- **Mocking:** the four §0.4 protocols (`RemoteSyncProvider`, `RatingsServicing`, `SuggestionSubmitting`, `EntitlementManager`) — all UI work proceeds without an Apple Developer account; live CloudKit impls swap in behind the same protocols.

---

## 8. Milestones (revised for §0.3)

1. **M0 — Scaffold:** Xcode project, three tabs, theme system, **entitlement seam (§0.3)**, sample 10-site catalog, protocol stubs + mocks.
2. **M1 — Catalog + List:** full schema, `CatalogStore`, list w/ search/sort/filter, remote refresh.
3. **M2 — Detail:** full detail view, photo carousel + cache, share, Open in Maps.
4. **M3 — Map:** annotations, clustering, popover → sheet detail, filter + auto-re-zoom.
5. **M4 — Local user state:** SwiftData favorites/want/visited/my-rating, Profile activity + progress stats (local only, no sync yet).
6. **M5 — Sync + ratings:** `RemoteSyncProvider` + `CloudKitSyncProvider` (§0.1); public ratings + rebuildable summaries + recompute (§0.2); account-status handling; offline queues.
7. **M6 — Suggestions + Profile polish:** suggestion flow + Dashboard role docs, About, privacy manifest.
8. **M7 — Hardening:** accessibility pass, performance pass, `rebuild_summaries` owner tool, TestFlight build. *(No StoreKit build-out — deferred per §0.3.)*

---

## 9. Prerequisites the owner must provide (from v1.0 §9)

- Apple Developer Program membership; app ID + CloudKit container (`docs/CLOUDKIT_SETUP.md`, incl. suggestion create-only role — Dashboard-only).
- Static host decision (default: public GitHub repo + Pages) + photo files.
- Catalog content authored per §3.1 (Claude-assisted), validated by §3.3 tool, + curated city list.
- Importance tier + site type per site.
- App icon + name availability check ("Byzantine Trail"), privacy policy URL.

---

## 10. Future roadmap (architecture already accommodates)

Website consuming `catalog.json` + photos; ratings via CloudKit JS or a thin API over the two public record types (or a `RESTSyncProvider` for private state — the §0.1 seam is ready). Distance-from-me sort (adds location permission). Richer visited stats/charts. Offline photo packs (paywall candidate). Alternate theme palettes (paywall candidate). Curated routes/itineraries ("Trails"). Push notification when a suggested site is added. StoreKit implementation behind the §0.3 seam when a product is chosen.
