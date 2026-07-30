# Catalog Content & Photo Pipeline — Design

**Date:** 2026-07-29
**Milestone:** Catalog content (data + photos)
**Status:** Draft for review

## Goal

Get real Byzantine-site content — text data **and** photos — into the app, and
establish a **repeatable, low-friction pipeline** for adding more over time
without an App Store release. The owner supplies raw data (in mixed forms) and
full-resolution photos; the pipeline transforms them into the shipped schema,
produces optimized images + thumbnails, strips location metadata, validates, and
publishes to the existing GitHub Pages content host.

## What already exists (do NOT rebuild)

The remote-update system was built and merged in **M1-remote**. This milestone
consumes it; it does not touch it.

- **Remote refresh:** [`CatalogRefresher`](../../../ByzantineTrail/Core/Catalog/CatalogRefresher.swift)
  fetches `catalog-manifest.json` on launch, and if it advertises a newer
  `catalogVersion`, downloads → sha256-verifies → decodes → atomically swaps the
  catalog. Any failure is a silent no-op (offline-tolerant).
- **Newest-valid selection:** [`CatalogStore.newestValid`](../../../ByzantineTrail/Core/Catalog/CatalogStore.swift)
  picks the newer of the bundled vs. downloaded catalog at launch.
- **Host wiring:** [`RemoteConfig.catalogBaseURL`](../../../ByzantineTrail/Core/Networking/RemoteConfig.swift)
  → `https://jhoedeman.github.io/byzantine-trail-catalog/` (a **separate public
  content repo** on GitHub Pages). One-line host swap.
- **Photo resolution:** [`PhotoResolver`](../../../ByzantineTrail/Core/Catalog/PhotoResolver.swift)
  serves a thumbnail from the app bundle if present, else from `photoBaseURL`;
  full-size images always resolve against `photoBaseURL`.
- **Pre-publish validator:** [`tools/validate_catalog.swift`](../../../tools/validate_catalog.swift)
  — strict gate with a fixture suite ([`tools/run_validator_tests.sh`](../../../tools/run_validator_tests.sh)).
  Checks schema shape, unique site/photo ids, `cityId` resolution, coordinate
  ranges, ISO-3166 country codes, controlled `semanticTags`/`period.era`, valid
  `importance`, `addedInVersion ≤ catalogVersion`, thumb-file existence (when an
  assets root is passed), and **scans every string for email addresses** plus an
  optional git-ignored denylist. CI runs it on catalog/tools changes.
- **Hosting runbook:** [`docs/CATALOG_HOSTING.md`](../../../docs/CATALOG_HOSTING.md)
  — one-time GitHub Pages setup + the publish flow for `catalog.json` +
  `catalog-manifest.json`.

## What this milestone adds

1. **Photo build tool** — optimize full-size originals, generate thumbnails,
   strip location/camera metadata. (New; nothing like it exists.)
2. **Baseline thumbnail bundling** — ship the launch set's thumbnails inside the
   app so first-run browsing is fully offline. (No `thumbs/` folder exists yet.)
3. **Authoring guide** — `docs/CATALOG_AUTHORING.md` (the validator already
   references it; it was never written): the intake format, the controlled
   vocabularies, the photo conventions, and the end-to-end publish runbook
   including photos.
4. **Content** — the launch catalog: real data + credited photos, validated and
   published, verified live and offline in the app.

## Non-goals

- No changes to `CatalogRefresher`, `newestValid`, the manifest format, or the
  refresh wiring — all done and working.
- No switch to R2 or any other host — GitHub Pages is already wired, free, and
  the lowest-setup option (decision confirmed 2026-07-29).
- No new app UI. The detail carousel, list rows, and map already render photos.
- No CMS. Authoring stays file-based (spreadsheet/CSV → JSON via the pipeline).

## Global constraints (binding, verbatim)

- **Owner email must NEVER appear in public content.** The validator's
  email-pattern scan is the automated gate; every published `catalog.json`
  passes it. (Names in photo credits are fine; emails are not.)
- **Strip location + camera metadata from every published photo.** The owner's
  own photos carry GPS EXIF; a public app must not leak where the owner stood.
  This is a pipeline requirement, not optional.
- **Every photo gets a credit line — the owner's own included** (owner decision
  2026-07-29). `credit` is required by the authoring process for all photos.
- **`catalogVersion` is monotonically increasing;** the value inside
  `catalog.json` MUST equal the value in `catalog-manifest.json`.
- **Serve over HTTPS only** (GitHub Pages default).
- Use **Swift Testing** (`import Testing`, `@Test`, `#expect`) for any app-side
  tests, run via `xcodebuild` on `platform=iOS Simulator,name=iPhone 16`.
- Regenerate the Xcode project via the **real** xcodegen binary
  (`~/bin/xcodegen_dist/bin/xcodegen generate`) after any `project.yml` change.

## Data model (unchanged — reference)

Shipped schema, from [`Site.swift`](../../../ByzantineTrail/Core/Catalog/Site.swift):

```
Catalog { schemaVersion:Int, catalogVersion:Int, generatedAt:String?,
          photoBaseURL:String, cities:[City], sites:[Site] }
City    { id, name }
Site    { id, name, alternateNames:[String], type:SiteType, country:ISO2,
          cityId:String?, coordinate:{lat,lon}, address:String?,
          importance:major|notable|minor, addedInVersion:Int?,
          period:{century:Int?, era:String?}?,
          summary?, description?, hours?, entryInfo?,
          photos:[Photo], semanticTags:[String], tags:[String], links:[{title,url}] }
Photo   { id, thumb, full, caption?, credit? }
```

**Controlled vocabularies** (enforced by the validator):
- `type` ∈ church, monastery, fortress, palace, cityWalls, cistern, aqueduct,
  mosaicSite, archaeologicalSite, museum, tower, bridge, other
  *(unknown values are tolerated by the app as `.other`, but the authoring guide
  lists the canonical set; the validator does NOT reject unknown `type`.)*
- `importance` ∈ major, notable, minor *(validator rejects anything else)*
- `period.era` ∈ constantinian, theodosian, justinianic, macedonian, komnenian,
  palaiologan, other
- `semanticTags` ⊆ { unesco }
- `country` = ISO 3166-1 alpha-2 (TR, GR, IT, …)

## Intake format (data → JSON)

Source data is "mixed / not sure," so we define **one canonical intake form** and
normalize everything into it:

- **Canonical intake: a spreadsheet (CSV/TSV), one row per site**, columns named
  for the schema fields (`name`, `type`, `country`, `cityId`, `lat`, `lon`,
  `importance`, `century`, `era`, `summary`, `description`, `hours`, `entryInfo`,
  `alternateNames` (semicolon-separated), `semanticTags`, `tags`, `links`).
- **Messy/prose input** is fine — the owner hands it over in whatever form, and
  Claude structures it into the canonical spreadsheet first, for the owner to
  eyeball, before generating JSON.
- **Derived automatically:** `id` (slug of `name`), the `cities[]` list (deduped
  from `cityId`/city-name columns), `addedInVersion` (= the version being
  published), `generatedAt` (ISO timestamp).
- **Vocab normalization:** Claude maps free-text type/era/importance/country to
  the controlled values and flags anything ambiguous for the owner.

The transform is a **documented Claude-run process**, not a rigid script — the
data is too heterogeneous to hard-code a parser now. The validator is the
backstop that guarantees the output is well-formed regardless of intake path.

## Photo pipeline (new)

A macOS shell tool, `tools/build_photos.sh`, run against a folder of
full-resolution originals named `<photo-id>.<ext>`:

1. **Strip metadata** — remove all EXIF/GPS/camera metadata (`exiftool -all= `).
   *This is the privacy gate; it runs first so nothing downstream can reintroduce
   location data.*
2. **Full-size** — resize longest edge to **2560px** (never upscale), re-encode
   JPEG sRGB quality ~80 → `out/full/<photo-id>.jpg` (`sips`).
3. **Thumbnail** — resize longest edge to **500px**, JPEG quality ~72 →
   `out/thumbs/<photo-id>.jpg` (`sips`).
4. **Report** — print each file's output dimensions + byte size, and **fail loudly
   if any output still contains GPS metadata** (re-scan with `exiftool`).

**Dependencies:** `sips` (built into macOS) + `exiftool` (`brew install exiftool`
— the one new dependency, justified by reliable GPS stripping; `sips` alone does
not guarantee GPS removal).

**Naming & path conventions:**
- `photo.id` = `<site-id>-NN` (e.g. `hagia-sophia-1`).
- `photo.thumb` = `thumbs/<photo-id>.jpg`
- `photo.full`  = `full/<photo-id>.jpg`
- These are relative paths; the resolver joins them onto `photoBaseURL` (or, for
  thumbs, finds them in the bundle first).

**Sizing rationale:** 2560px long edge is crisp on the largest iPad at 2× while
keeping files ~300–600 KB; 500px thumbnails are ~30–50 KB, fast to bundle and to
stream for list/carousel use.

## Hosting layout

The content repo (`byzantine-trail-catalog`, GitHub Pages) holds everything the
app fetches remotely:

```
byzantine-trail-catalog/
  catalog.json
  catalog-manifest.json
  thumbs/<photo-id>.jpg     ← all thumbnails
  full/<photo-id>.jpg       ← all full-size photos
```

`photoBaseURL` inside `catalog.json` is set to the **same** Pages base URL as
`catalogBaseURL` (`https://jhoedeman.github.io/byzantine-trail-catalog/`), so
`thumbs/…` and `full/…` resolve against it. (Currently `photoBaseURL` is the
placeholder `https://example.invalid/…`; the pipeline sets the real value.)

## Baseline bundling (app change)

To make first-run browsing fully offline **with images**, the launch set's
thumbnails ship inside the app:

- Add `ByzantineTrail/Resources/thumbs/<photo-id>.jpg` for the baseline photos.
- In `project.yml`, add the thumbs folder as a **folder reference**
  (`type: folder`, `buildPhase: resources`) so it is copied to the bundle root
  as `thumbs/` — which is exactly what `PhotoResolver` looks up
  (`subdirectory: "thumbs"`, then `bundleURL/thumbs/<name>`). A plain group would
  flatten the structure and break the lookup.
- The bundled `catalog.json` is refreshed to the real launch content (it is
  already a bundled resource).
- Full-size baseline photos are **not** bundled (kept remote) — they stream on
  demand when a detail view opens, and cache thereafter. Thumbnails alone give an
  offline-complete list/map/detail-preview experience.

A site added later via remote refresh has no bundled thumbnail → the resolver's
existing remote fallback fetches it from `photoBaseURL/thumbs/…`. No app release
needed for later additions.

## Publish runbook (extends CATALOG_HOSTING.md)

Per content update:

1. Author/normalize the data → `catalog.json`; bump `catalogVersion`.
2. `tools/build_photos.sh <originals-dir> <out-dir>` → optimized `full/` +
   `thumbs/`, GPS-stripped, report clean.
3. Validate: `swift tools/validate_catalog.swift catalog.json <thumbs-assets-root>`
   → exit 0.
4. Compute `shasum -a 256 catalog.json`; write `catalog-manifest.json` with the
   matching `catalogVersion`, `url: "catalog.json"`, and that digest.
5. Copy `catalog.json`, `catalog-manifest.json`, `thumbs/*`, `full/*` into the
   content repo; commit + push. App picks it up on next launch.
6. For a **shipped baseline** (new app release only): also copy the baseline
   thumbnails into `ByzantineTrail/Resources/thumbs/` and refresh the bundled
   `catalog.json`.

## Validation & privacy (already enforced, reaffirmed)

- Email scan + optional denylist → owner email can never be published.
- Metadata strip + post-strip GPS re-scan → no location leak via photos.
- sha256 in manifest → tampered/partial downloads rejected.
- HTTPS-only → transport safety.

## Phased delivery

- **Phase 1 — prove the pipeline end to end (small, real).** Build
  `build_photos.sh`; wire baseline thumbnail bundling; write
  `CATALOG_AUTHORING.md`; author a small real launch batch (≈5–10 sites, 1–2
  credited photos each); create/point the content repo; validate; publish; verify
  **live refresh** and **offline** (airplane mode) in the simulator.
- **Phase 2 — bulk ingest.** Feed the full dataset through the same pipeline in
  reviewable batches (data work, iterative), each ending in a validated publish.
  No new engineering — Phase 1 delivers the machine; Phase 2 feeds it.

## Open decisions (defaults chosen; flag to change)

1. **exiftool dependency** — accepted as the one new tool for reliable GPS
   stripping. *(Alternative: ImageMagick `-strip`; also a brew install, no
   advantage. Default: exiftool.)*
2. **Full-size 2560px / q80, thumb 500px / q72** — defaults above. Adjustable if
   the owner wants larger/sharper or smaller/lighter.
3. **Full-size baseline photos stay remote** (only thumbnails bundled). Keeps the
   app binary small. *(Alternative: bundle a few hero full-size images for
   marquee sites — deferred unless wanted.)*
4. **Phase-1 pilot size ≈5–10 sites.** Big enough to exercise cities, multi-photo
   sites, credits, and offline; small enough to iterate fast.
