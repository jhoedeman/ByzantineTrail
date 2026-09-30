# Catalog authoring guide

How raw Byzantine-site data + photos become the shipped `catalog.json` and its
images. Pairs with `docs/CATALOG_HOSTING.md` (which covers the GitHub Pages host)
and `Tools/validate_catalog.swift` (the pre-publish gate).

## 1. Intake — data in any form → one spreadsheet

You (owner) provide data in whatever form you have (spreadsheet, notes, prose,
an export). Claude normalizes it into a **canonical spreadsheet, one row per
site**, for you to eyeball before any JSON is generated. Columns:

| column | notes |
| --- | --- |
| `name` | required |
| `type` | one of the controlled types below (Claude maps free text) |
| `country` | full name (Greece, Italy, …) or ISO 3166-1 alpha-2 — Claude maps to the alpha-2 the app stores. Disputed/unrecognized territories with no ISO code are stored as a literal label (e.g. `Crimea (disputed)`) and must be listed in the validator's `allowedNonISOCountries`. Display can be overridden per code in `CountryName.displayOverrides` (e.g. `TR` → "Turkey") |
| `cityName` | optional; Claude derives `cityId` + the `cities[]` list |
| `lat`, `lon` | decimal degrees |
| `importance` | major \| notable \| minor |
| `century`, `era` | optional; `era` from the controlled set below |
| `summary` | one-line teaser |
| `description` | long-form (optional) |
| `hours`, `entryInfo`, `address` | optional |
| `alternateNames` | `;`-separated (optional) |
| `semanticTags` | `;`-separated, from the controlled set (optional) |
| `tags` | `;`-separated free text (optional) |
| `links` | `title|url` pairs, `;`-separated — or bare URLs, which Claude auto-titles (Wikipedia → "Wikipedia", else "Official website") (optional) |

Claude derives automatically: `id` (slug of `name`), `cities[]` (deduped),
`addedInVersion` (= the version being published), `generatedAt` (ISO 8601).

### 1a. Artifacts — a second worksheet (one site → many artifacts)

Things housed *at* a site (mosaics, fragments, spolia, an object in a museum)
are modeled as content **within** the site — one map pin, artifacts browsable
inside it — not as separate sites (separate sites at one coordinate collide on
the map). Capture them on a **second worksheet named `Artifacts`, one row per
artifact**, keyed back to the site by name:

| column | notes |
| --- | --- |
| `site` | **link key** — must match a site `Name` exactly (case-insensitive, trimmed); unmatched values are flagged as orphans |
| `name` | required |
| `summary` | one-line teaser (same role as a site's `summary`) |
| `description` | long-form (optional) |
| `century` | optional; use when the artifact dates differently from the building |
| `photo` | optional; id `<site-id>-a-NN`, processed via `build_photos.sh` later |
| `links` | optional; `title|url` pairs, `;`-separated |

**Not rendered yet.** Nesting artifacts is a planned schema addition
(`Site.artifacts[]` + detail-view UI). Until it ships, the re-scan reads the
sites sheet and **ignores the `Artifacts` sheet** — so capturing artifact data
early is safe and lossless, it just waits for the feature.

## 2. Controlled vocabularies (must match the validator)

- **type** (unknown values render as `other` in older apps; keep to this set):
  `church, monastery, fortress, palace, cityWalls, cistern, aqueduct,
  mosaicSite, archaeologicalSite, museum, tower, bridge, column,
  triumphalArch, mausoleum, baptistery, icon, other`
- **importance** (validator rejects anything else): `major, notable, minor`
- **period.era**: `constantinian, theodosian, justinianic, macedonian,
  komnenian, palaiologan, postByzantine, other` — `postByzantine` = the
  continuation of Byzantine tradition after the fall of Constantinople (1453);
  key it off the painting/phase date, not the building's founding.
- **semanticTags** (⊆): `unesco`
- **country**: ISO 3166-1 alpha-2
- **coordinate**: must sit within **150 km** of the other sites sharing the same
  `cityId`, or the validator rejects it. The limit is loose on purpose — Istanbul's
  Anastasian Walls are 68 km from the centroid of the city's other sites, and an
  island or a monastic peninsula can spread comparably. What it catches is a
  coordinate from the wrong place entirely: the Cave of the Seven Sleepers once
  carried Ephesus's name, address, country and `cityId` alongside the coordinates
  of its rival Jordanian claimant, 1,034 km away, and every other check passed it.
  A site genuinely that far from its neighbours wants its own city entry.

## 3. Photos

Provide full-resolution originals named `<photo-id>.<ext>`, where
`photo-id` = `<site-id>-NN` (e.g. `hagia-sophia-1.jpg`, `hagia-sophia-2.jpg`).

Run the pipeline:

```bash
Tools/build_photos.sh <originals-dir> <out-dir>
```

It writes optimized `<out-dir>/full/<id>.jpg` (≤2560px, q80) and
`<out-dir>/thumbs/<id>.jpg` (≤500px, q72), **strips all location/camera
metadata** (keeps Orientation), and **fails if any GPS tag survives**.

In `catalog.json`, each photo is:

```json
{ "id": "hagia-sophia-1", "thumb": "thumbs/hagia-sophia-1.jpg",
  "full": "full/hagia-sophia-1.jpg", "caption": "…", "credit": "…" }
```

**`credit` is required for every photo — your own included.** Credit sourced
photos by author + license (e.g. "Photo: Jane Roe, CC BY-SA 4.0"); credit your
own as you prefer (e.g. "Photo: John Hoedeman").

### 3a. Batch import via the manifest

In practice photos are wired through the idempotent driver rather than by hand:

```bash
Tools/import_photos.sh <incoming-root> [--force] [--only "Folder Name"]...
```

Each row of `Tools/photo_manifest.tsv` maps `<folder-name><TAB><site-id>`. For
every mapped folder found under `<incoming-root>`, the driver stages and renames
its images to `<site-id>-N.<ext>` in shot order, runs `build_photos.sh` (strip +
resize), copies thumbnails into `ByzantineTrail/Resources/thumbs/`, merges a
`photos[]` array into `catalog.json`, and finally runs the validator. It is
**idempotent**: a site that already has photos *and* a first thumbnail is
skipped, so re-running only processes newly-added folders.

**Credits sidecar.** A folder may hold a plain-text `_credits.txt` (not `.rtf`)
with one line per source image:

```
1.jpg: Sailko, CC BY 3.0 <https://creativecommons.org/licenses/by/3.0>, via Wikimedia Commons
```

The angle-bracketed URL becomes `licenseURL`; the rest becomes `credit`. Lines
match by filename **stem** (`1.jpg` keys off `1`, regardless of real extension).
Any image with no matching line — or a folder with no `_credits.txt` — falls
back to the owner default (`Photo: John Hoedeman`, no `licenseURL`). The
validator requires a non-empty `licenseURL` on any credit that matches
`CC[ -]?(BY|0)`, so a CC/CC0 line must carry its URL (CC0's canonical URL is
`https://creativecommons.org/publicdomain/zero/1.0`).

### 3b. Swapping a site's photos (e.g. Wikimedia → your own)

Reprocessing **replaces** a site's `photos[]` array (it is not appended to), so
swapping is just "re-run with the new folder contents":

1. Replace the images in that site's incoming folder with your own, keeping the
   `N.ext` numbering (they are re-numbered contiguously in trailing-number
   order).
2. Update `_credits.txt`:
   - **All photos now yours** → delete `_credits.txt` entirely; every photo gets
     the owner default.
   - **Partial swap** → keep only the lines for images that are still
     third-party; your own files (no matching line) fall back to the owner
     default.
3. Re-run scoped to that folder (no `--force` needed — `--only` reprocesses a
   site even if already wired):

   ```bash
   Tools/import_photos.sh <incoming-root> --only "Saint Hilarion Castle"
   ```

   Use `--force` (no `--only`) to rebuild every site instead.

**Gotcha — a shrinking photo count leaves orphan thumbnails.** Thumbnails are
overwritten in place, not pruned. Going from 3 photos to 2 leaves a stale
`<site-id>-3.jpg` in `ByzantineTrail/Resources/thumbs/` (and `photo-build/full/`)
that the catalog no longer references. Remove it by hand:

```bash
git rm ByzantineTrail/Resources/thumbs/<site-id>-3.jpg
```

Same count or more overwrites cleanly with nothing to prune.

## 4. Where files live

- **Content repo (`byzantine-trail-catalog`, GitHub Pages):** `catalog.json`,
  `catalog-manifest.json`, `thumbs/*` (all), `full/*` (all). `photoBaseURL`
  points here.
- **Bundled in the app (offline first-run):** the launch set's thumbnails in
  `ByzantineTrail/Resources/thumbs/` + the baseline `catalog.json`. Full-size
  images are never bundled; they stream from `photoBaseURL` on demand.
- A site added later via remote refresh needs no app release: its thumbnail is
  fetched from `photoBaseURL/thumbs/…` (the resolver's remote fallback).

## 5. Publish runbook

1. Author/normalize data → `catalog.json`; set `photoBaseURL` to the Pages base
   URL; bump `catalogVersion` (monotonic).
2. `Tools/build_photos.sh <originals> <out>` → `full/` + `thumbs/`, report clean.
3. Validate (with thumb-existence check against the bundled thumbs root):
   ```bash
   swift Tools/validate_catalog.swift catalog.json ByzantineTrail/Resources
   ```
   Exit 0 required. (Also blocks emails; add a git-ignored
   `Tools/owner_denylist.txt` to block extra substrings.)
4. `shasum -a 256 catalog.json`; write `catalog-manifest.json` with the matching
   `catalogVersion`, `"url": "catalog.json"`, and that digest.
5. Copy `catalog.json`, `catalog-manifest.json`, `thumbs/*`, `full/*` into the
   content repo; commit + push. The app picks it up on next launch.
6. For a shipped **baseline** (app release only): also refresh
   `ByzantineTrail/Resources/catalog.json` and the bundled
   `ByzantineTrail/Resources/thumbs/`.
