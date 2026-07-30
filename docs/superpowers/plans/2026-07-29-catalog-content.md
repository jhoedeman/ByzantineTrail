# Catalog Content & Photo Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, recommended here — Tasks 3 & 5 need owner-supplied data/repo) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repeatable pipeline that turns owner-supplied raw data + full-resolution photos into the shipped catalog schema — optimized, thumbnailed, GPS-stripped, validated — and publish a real Phase-1 catalog live to GitHub Pages, verified online and offline.

**Architecture:** Consume the already-built M1-remote system (refresh, manifest, sha256, validator) untouched. Add (1) a macOS shell photo tool, (2) a baseline-thumbnail bundle wiring, (3) the missing authoring guide, then (4) author + (5) publish real Phase-1 content. Photos: thumbnails bundled for offline first-run; full-size + all thumbnails served from the GitHub Pages content repo via `photoBaseURL`.

**Tech Stack:** Bash + `sips` (macOS built-in) + `exiftool` (`brew install exiftool`); Swift/SwiftUI app (iOS 17+); XcodeGen; GitHub Pages content repo `byzantine-trail-catalog`.

## Global Constraints

- **Owner email must NEVER appear in public content.** Enforced by the validator's email-pattern scan (`tools/validate_catalog.swift`); every published `catalog.json` passes it. Commit author email is always `6411536+jhoedeman@users.noreply.github.com`.
- **Strip location + camera metadata from every published photo** (owner's own photos carry GPS EXIF). Pipeline strips all metadata except image Orientation, then re-scans and fails if any GPS tag survives.
- **Every photo gets a `credit` line — the owner's own included.**
- **`catalogVersion` is monotonically increasing;** the value inside `catalog.json` MUST equal the value in `catalog-manifest.json`.
- **Serve over HTTPS only** (GitHub Pages default).
- **Photo sizing:** full-size longest edge **2560px** (never upscale), JPEG sRGB **q80**; thumbnail longest edge **500px**, JPEG **q72**.
- **Path conventions:** `photo.id` = `<site-id>-NN`; `photo.thumb` = `thumbs/<photo-id>.jpg`; `photo.full` = `full/<photo-id>.jpg`.
- **Host:** `RemoteConfig.catalogBaseURL` = `https://jhoedeman.github.io/byzantine-trail-catalog/` (unchanged); `photoBaseURL` inside `catalog.json` = the same base URL.
- Regenerate the Xcode project via the **real** xcodegen binary: `~/bin/xcodegen_dist/bin/xcodegen generate` (the PATH symlink silently fails).
- App tests use **Swift Testing**, run via `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 16'`.

## File Structure

- `tools/build_photos.sh` (create) — the photo pipeline. One responsibility: originals → optimized `full/` + `thumbs/`, metadata-stripped, GPS-verified.
- `tools/test_build_photos.sh` (create) — self-contained smoke test for the tool.
- `docs/CATALOG_AUTHORING.md` (create) — intake format, controlled vocab, photo conventions, end-to-end publish runbook. (The validator's header already references it.)
- `ByzantineTrail/Resources/thumbs/` (create) — bundled baseline thumbnails (folder reference).
- `ByzantineTrail/Resources/catalog.json` (modify) — refreshed to real Phase-1 content with the real `photoBaseURL`.
- `project.yml` (modify) — add the `thumbs` folder reference; exclude it from the main group.
- Content repo `byzantine-trail-catalog` (external) — `catalog.json`, `catalog-manifest.json`, `thumbs/*`, `full/*`.

---

### Task 1: Photo pipeline tool (`build_photos.sh`)

**Files:**
- Create: `tools/build_photos.sh`
- Test: `tools/test_build_photos.sh`

**Interfaces:**
- Produces: an executable `tools/build_photos.sh <originals-dir> <out-dir>` that writes `<out-dir>/full/<id>.jpg` and `<out-dir>/thumbs/<id>.jpg` for each `<id>.<ext>` original, all metadata-stripped (Orientation kept), exiting non-zero if any output retains GPS. Consumed by Task 3 (content) and Task 5 (publish).

- [ ] **Step 1: Write the failing test**

Create `tools/test_build_photos.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for build_photos.sh — self-contained (builds its own oversized,
# GPS-tagged input from the committed jpg fixture; asserts caps + GPS stripping).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

command -v exiftool >/dev/null 2>&1 || { echo "SKIP: exiftool not installed (brew install exiftool)"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
src="$tmp/src"; out="$tmp/out"; mkdir -p "$src"

fixture="$here/validate_catalog_fixtures/assets/thumbs/a-01.jpg"
[ -f "$fixture" ] || { echo "FAIL: fixture missing: $fixture"; exit 1; }

# Upscale the small fixture to an oversized original (forces the downscale path).
sips -z 3000 4000 "$fixture" --out "$src/test-1.jpg" >/dev/null
# Inject fake GPS so we can prove the tool strips it.
exiftool -overwrite_original -GPSLatitude=41.0086 -GPSLatitudeRef=N \
  -GPSLongitude=28.9802 -GPSLongitudeRef=E "$src/test-1.jpg" >/dev/null

bash "$here/build_photos.sh" "$src" "$out"

[ -f "$out/full/test-1.jpg" ]   || { echo "FAIL: full output missing"; exit 1; }
[ -f "$out/thumbs/test-1.jpg" ] || { echo "FAIL: thumb output missing"; exit 1; }

dim() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w, h}'; }
read -r fw fh < <(dim "$out/full/test-1.jpg")
read -r tw th < <(dim "$out/thumbs/test-1.jpg")
[ "$fw" -le 2560 ] && [ "$fh" -le 2560 ] || { echo "FAIL: full $fw x $fh exceeds 2560"; exit 1; }
[ "$tw" -le 500 ]  && [ "$th" -le 500 ]  || { echo "FAIL: thumb $tw x $th exceeds 500"; exit 1; }

for o in "$out/full/test-1.jpg" "$out/thumbs/test-1.jpg"; do
  if exiftool -s -s -s -GPSLatitude -GPSLongitude "$o" | grep -q .; then
    echo "FAIL: GPS survived in $o"; exit 1
  fi
done

echo "PASS: build_photos smoke test"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tools/test_build_photos.sh`
Expected: FAIL — `build_photos.sh` does not exist yet (bash: cannot open the script). If exiftool is missing it prints `SKIP` and exits 0; install it first (`brew install exiftool`) so the test actually runs.

- [ ] **Step 3: Write the tool**

Create `tools/build_photos.sh`:

```bash
#!/usr/bin/env bash
# build_photos.sh — optimize + thumbnail + strip location/camera metadata.
#
# Usage: tools/build_photos.sh <originals-dir> <out-dir>
#   <originals-dir>  folder of full-res originals named <photo-id>.<ext>
#   <out-dir>        writes <out-dir>/full/<id>.jpg and <out-dir>/thumbs/<id>.jpg
#
# Requires: sips (macOS built-in), exiftool (brew install exiftool).
# Full-size: longest edge 2560px (never upscale), JPEG sRGB q80.
# Thumbnail: longest edge 500px  (never upscale), JPEG q72.
# All metadata stripped except image Orientation. Exits 1 if any output
# still contains GPS metadata.
set -euo pipefail

FULL_MAX=2560; THUMB_MAX=500; FULL_Q=80; THUMB_Q=72

die() { echo "✗ $*" >&2; exit 1; }
command -v sips     >/dev/null 2>&1 || die "sips not found (macOS required)"
command -v exiftool >/dev/null 2>&1 || die "exiftool not found — run: brew install exiftool"
[ "$#" -eq 2 ] || die "usage: build_photos.sh <originals-dir> <out-dir>"

SRC="$1"; OUT="$2"
[ -d "$SRC" ] || die "originals dir not found: $SRC"
mkdir -p "$OUT/full" "$OUT/thumbs"

longest() { sips -g pixelWidth -g pixelHeight "$1" \
  | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print (w>h?w:h)}'; }

# Re-encode to JPEG at a given quality, resampling the longest edge down to a
# cap ONLY when the source exceeds it (never upscales).
encode() { # <in> <out> <max> <q>
  local in="$1" out="$2" max="$3" q="$4"
  if [ "$(longest "$in")" -gt "$max" ]; then
    sips -s format jpeg -s formatOptions "$q" -Z "$max" "$in" --out "$out" >/dev/null
  else
    sips -s format jpeg -s formatOptions "$q" "$in" --out "$out" >/dev/null
  fi
}

shopt -s nullglob nocaseglob
originals=("$SRC"/*.jpg "$SRC"/*.jpeg "$SRC"/*.png "$SRC"/*.heic "$SRC"/*.tif "$SRC"/*.tiff)
shopt -u nocaseglob
[ "${#originals[@]}" -gt 0 ] || die "no image files in $SRC"

count=0
for f in "${originals[@]}"; do
  id="$(basename "$f")"; id="${id%.*}"
  full="$OUT/full/$id.jpg"; thumb="$OUT/thumbs/$id.jpg"
  tmp="$OUT/full/$id.src.tmp"

  cp "$f" "$tmp"
  # Strip everything, then copy back only Orientation (non-sensitive; keeps
  # the image upright without retaining GPS/camera/timestamp metadata).
  exiftool -overwrite_original -all= -tagsfromfile @ -Orientation "$tmp" >/dev/null

  encode "$tmp" "$full"  "$FULL_MAX"  "$FULL_Q"
  encode "$full" "$thumb" "$THUMB_MAX" "$THUMB_Q"
  rm -f "$tmp"

  for out in "$full" "$thumb"; do
    if exiftool -s -s -s -GPSLatitude -GPSLongitude "$out" | grep -q .; then
      die "GPS metadata survived in $out"
    fi
  done

  read -r w h < <(sips -g pixelWidth -g pixelHeight "$full" \
    | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w, h}')
  printf "✓ %-28s full %sx%s %sKB\n" "$id" "$w" "$h" "$(( $(stat -f%z "$full") / 1024 ))"
  count=$((count+1))
done

echo "✓ processed $count photo(s) → $OUT/full, $OUT/thumbs"
```

Then make both executable: `chmod +x tools/build_photos.sh tools/test_build_photos.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tools/test_build_photos.sh`
Expected: `PASS: build_photos smoke test` (exit 0). The full output is ≤2560 on its longest edge, the thumb ≤500, and both are GPS-free.

- [ ] **Step 5: Commit**

```bash
git add tools/build_photos.sh tools/test_build_photos.sh
git -c user.email="6411536+jhoedeman@users.noreply.github.com" commit -m "Catalog photos: build_photos.sh (optimize + thumbnail + GPS strip) + test

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Authoring guide (`docs/CATALOG_AUTHORING.md`)

**Files:**
- Create: `docs/CATALOG_AUTHORING.md`

**Interfaces:**
- Consumes: the controlled vocabularies defined in `tools/validate_catalog.swift` (`allowedSemanticTags`, `allowedEras`, `allowedImportance`) and the photo conventions from Task 1. The doc must state these values verbatim.
- Produces: the single reference the owner + Claude follow when authoring content (Task 3) and publishing (Task 5).

- [ ] **Step 1: Write the guide**

Create `docs/CATALOG_AUTHORING.md`:

````markdown
# Catalog authoring guide

How raw Byzantine-site data + photos become the shipped `catalog.json` and its
images. Pairs with `docs/CATALOG_HOSTING.md` (which covers the GitHub Pages host)
and `tools/validate_catalog.swift` (the pre-publish gate).

## 1. Intake — data in any form → one spreadsheet

You (owner) provide data in whatever form you have (spreadsheet, notes, prose,
an export). Claude normalizes it into a **canonical spreadsheet, one row per
site**, for you to eyeball before any JSON is generated. Columns:

| column | notes |
| --- | --- |
| `name` | required |
| `type` | one of the controlled types below (Claude maps free text) |
| `country` | ISO 3166-1 alpha-2 (TR, GR, IT, …) |
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
| `links` | `title|url` pairs, `;`-separated (optional) |

Claude derives automatically: `id` (slug of `name`), `cities[]` (deduped),
`addedInVersion` (= the version being published), `generatedAt` (ISO 8601).

## 2. Controlled vocabularies (must match the validator)

- **type** (unknown values render as `other` in older apps; keep to this set):
  `church, monastery, fortress, palace, cityWalls, cistern, aqueduct,
  mosaicSite, archaeologicalSite, museum, tower, bridge, other`
- **importance** (validator rejects anything else): `major, notable, minor`
- **period.era**: `constantinian, theodosian, justinianic, macedonian,
  komnenian, palaiologan, other`
- **semanticTags** (⊆): `unesco`
- **country**: ISO 3166-1 alpha-2

## 3. Photos

Provide full-resolution originals named `<photo-id>.<ext>`, where
`photo-id` = `<site-id>-NN` (e.g. `hagia-sophia-1.jpg`, `hagia-sophia-2.jpg`).

Run the pipeline:

```bash
tools/build_photos.sh <originals-dir> <out-dir>
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
2. `tools/build_photos.sh <originals> <out>` → `full/` + `thumbs/`, report clean.
3. Validate (with thumb-existence check against the bundled thumbs root):
   ```bash
   swift tools/validate_catalog.swift catalog.json ByzantineTrail/Resources
   ```
   Exit 0 required. (Also blocks emails; add a git-ignored
   `tools/owner_denylist.txt` to block extra substrings.)
4. `shasum -a 256 catalog.json`; write `catalog-manifest.json` with the matching
   `catalogVersion`, `"url": "catalog.json"`, and that digest.
5. Copy `catalog.json`, `catalog-manifest.json`, `thumbs/*`, `full/*` into the
   content repo; commit + push. The app picks it up on next launch.
6. For a shipped **baseline** (app release only): also refresh
   `ByzantineTrail/Resources/catalog.json` and the bundled
   `ByzantineTrail/Resources/thumbs/`.
````

- [ ] **Step 2: Verify vocab matches the validator**

Run:
```bash
grep -E 'allowedSemanticTags|allowedEras|allowedImportance' -A3 tools/validate_catalog.swift
```
Expected: the printed sets are exactly `unesco`; `constantinian, theodosian, justinianic, macedonian, komnenian, palaiologan, other`; `major, notable, minor`. Confirm each appears verbatim in `docs/CATALOG_AUTHORING.md` §2. Fix the doc if any drift.

- [ ] **Step 3: Commit**

```bash
git add docs/CATALOG_AUTHORING.md
git -c user.email="6411536+jhoedeman@users.noreply.github.com" commit -m "Catalog docs: authoring guide (intake, vocab, photo pipeline, runbook)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Author Phase-1 content + process photos

> **Owner-collaborative.** Inputs (raw site data + full-res photo files) are supplied by the owner at execution time; Claude performs the transform per `docs/CATALOG_AUTHORING.md`. This task produces real files — it cannot be pre-written with invented Byzantine facts.

**Files:**
- Modify: `ByzantineTrail/Resources/catalog.json` (real Phase-1 content, real `photoBaseURL`)
- Create: `ByzantineTrail/Resources/thumbs/<photo-id>.jpg` (baseline thumbnails)
- Create (git-ignored staging): `build/catalog-content/full/*`, `build/catalog-content/thumbs/*`

**Interfaces:**
- Consumes: `tools/build_photos.sh` (Task 1), the intake format + conventions (Task 2).
- Produces: a validated `catalog.json` (~5–10 sites, ≥1 with 2 photos, ≥2 cities, every photo credited) + the processed image set for Task 4 (bundle) and Task 5 (publish).

- [ ] **Step 1: Collect owner inputs**

Ask the owner for: the Phase-1 site rows (any form) and the full-resolution photo files. Confirm the target count (~5–10 sites) and that each photo has a known credit.

- [ ] **Step 2: Normalize data → spreadsheet, then JSON**

Transform the raw data into the canonical one-row-per-site form (`docs/CATALOG_AUTHORING.md` §1) for the owner to eyeball. On approval, generate `catalog.json`: set `schemaVersion` 2, bump `catalogVersion`, `photoBaseURL` = `https://jhoedeman.github.io/byzantine-trail-catalog/`, derive `cities[]`, slug `id`s, map vocab, and attach each site's `photos[]` with `thumb`/`full` paths + required `credit`.

- [ ] **Step 3: Ensure git-ignores the staging dir**

Confirm `build/` is git-ignored (add `build/` to `.gitignore` if absent):
```bash
grep -qxF 'build/' .gitignore || printf 'build/\n' >> .gitignore
```

- [ ] **Step 4: Process the photos**

Run:
```bash
tools/build_photos.sh <owner-originals-dir> build/catalog-content
```
Expected: `✓ processed N photo(s)` with per-file dimensions, no GPS failure. Then copy the baseline thumbnails into the app:
```bash
mkdir -p ByzantineTrail/Resources/thumbs
cp build/catalog-content/thumbs/*.jpg ByzantineTrail/Resources/thumbs/
```

- [ ] **Step 5: Validate the catalog against the bundled thumbs**

Run:
```bash
swift tools/validate_catalog.swift ByzantineTrail/Resources/catalog.json ByzantineTrail/Resources
```
Expected: `✓ catalog valid — N sites, M cities, catalogVersion V` (exit 0). Fix any `✗` line (unknown vocab, missing thumb, email leak, unresolved cityId, …) and re-run until clean.

- [ ] **Step 6: Commit** (bundled catalog + baseline thumbs; staging `build/` stays untracked)

```bash
git add ByzantineTrail/Resources/catalog.json ByzantineTrail/Resources/thumbs .gitignore
git -c user.email="6411536+jhoedeman@users.noreply.github.com" commit -m "Catalog content: Phase-1 sites + baseline thumbnails

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Bundle baseline thumbnails into the app

**Files:**
- Modify: `project.yml`

**Interfaces:**
- Consumes: `ByzantineTrail/Resources/thumbs/*.jpg` (Task 3).
- Produces: a build whose `.app` root contains a `thumbs/` directory, so `PhotoResolver.thumbURL` resolves bundled thumbs locally (offline) instead of via `photoBaseURL`.

- [ ] **Step 1: Add the folder reference and exclude it from the main group**

Edit `project.yml`. Change the `ByzantineTrail` target `sources:` block from:

```yaml
    sources:
      - path: ByzantineTrail
      - path: AppIcon.icon
        buildPhase: resources
```

to:

```yaml
    sources:
      - path: ByzantineTrail
        excludes:
          - "Resources/thumbs/**"
      - path: AppIcon.icon
        buildPhase: resources
      - path: ByzantineTrail/Resources/thumbs
        type: folder
        buildPhase: resources
```

Rationale: `type: folder` makes `thumbs` a folder reference copied to the bundle root as `thumbs/` (a plain group would flatten it and break `subdirectory: "thumbs"` lookup). The `excludes` prevents the parent group from also bundling those files (which would duplicate-output).

- [ ] **Step 2: Regenerate the project with the real xcodegen binary**

Run:
```bash
~/bin/xcodegen_dist/bin/xcodegen generate
```
Expected: `Created project at ByzantineTrail.xcodeproj`. (The PATH `xcodegen` symlink silently no-ops — use this absolute path.)

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project ByzantineTrail.xcodeproj -scheme ByzantineTrail \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`, with no "multiple commands produce .../thumbs/…" duplicate-output error. If that error appears, the `excludes` glob did not take — as a fallback, move the folder to repo root (`git mv ByzantineTrail/Resources/thumbs thumbs`, update the source path to `path: thumbs`, drop the `excludes`, and re-run) and re-validate Task 3 Step 5 with assets root `.`.

- [ ] **Step 4: Verify the thumbs are bundled at the .app root**

Run (locate the freshly built app and list its thumbs dir):
```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -type d -name 'ByzantineTrail.app' -path '*Debug-iphonesimulator*' -print -quit)
ls "$APP/thumbs" | head
```
Expected: the baseline `*.jpg` thumbnails are listed under a single `thumbs/` directory in the bundle (matching what `PhotoResolver` looks up).

- [ ] **Step 5: Run the app test suite (guard against regressions)**

Run:
```bash
xcodebuild -project ByzantineTrail.xcodeproj -scheme ByzantineTrail \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **` (existing PhotoResolver + catalog tests still green).

- [ ] **Step 6: Commit**

```bash
git add project.yml ByzantineTrail.xcodeproj
git -c user.email="6411536+jhoedeman@users.noreply.github.com" commit -m "Catalog photos: bundle baseline thumbnails (thumbs/ folder reference)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Publish to GitHub Pages + verify live and offline

> **Owner-collaborative.** Creating/confirming the `byzantine-trail-catalog` repo + Pages is an owner one-time step (per `docs/CATALOG_HOSTING.md`). Pushing content there is a publish action — confirm with the owner before the push.

**Files:**
- Create (in the content repo, not the app repo): `catalog.json`, `catalog-manifest.json`, `thumbs/*`, `full/*`
- Create (git-ignored staging): `build/catalog-content/catalog-manifest.json`

**Interfaces:**
- Consumes: the validated `catalog.json` + processed images (Task 3).
- Produces: the live catalog the app refreshes from; a verified online + offline experience.

- [ ] **Step 1: Confirm the content repo + Pages exist**

Ask the owner to confirm `byzantine-trail-catalog` exists with Pages enabled and that its URL equals `RemoteConfig.catalogBaseURL` (`https://jhoedeman.github.io/byzantine-trail-catalog/`, trailing slash required). If not yet created, point them to `docs/CATALOG_HOSTING.md` §"One-time setup".

- [ ] **Step 2: Build the manifest**

Run:
```bash
cp ByzantineTrail/Resources/catalog.json build/catalog-content/catalog.json
DIGEST=$(shasum -a 256 build/catalog-content/catalog.json | awk '{print $1}')
VERSION=$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["catalogVersion"])' build/catalog-content/catalog.json)
printf '{\n  "catalogVersion": %s,\n  "url": "catalog.json",\n  "sha256": "%s"\n}\n' "$VERSION" "$DIGEST" > build/catalog-content/catalog-manifest.json
cat build/catalog-content/catalog-manifest.json
```
Expected: a manifest whose `catalogVersion` equals the value inside `catalog.json` and whose `sha256` matches the digest just computed.

- [ ] **Step 3: Re-validate the exact bytes being published**

Run:
```bash
swift tools/validate_catalog.swift build/catalog-content/catalog.json ByzantineTrail/Resources
```
Expected: exit 0. (Validates the published copy, not just the working copy.)

- [ ] **Step 4: Publish to the content repo** (confirm with owner first)

With the content repo checked out at `<content-repo>`:
```bash
cp build/catalog-content/catalog.json build/catalog-content/catalog-manifest.json <content-repo>/
cp build/catalog-content/full/*.jpg   <content-repo>/full/   2>/dev/null || (mkdir -p <content-repo>/full   && cp build/catalog-content/full/*.jpg   <content-repo>/full/)
cp build/catalog-content/thumbs/*.jpg <content-repo>/thumbs/ 2>/dev/null || (mkdir -p <content-repo>/thumbs && cp build/catalog-content/thumbs/*.jpg <content-repo>/thumbs/)
```
Then commit + push in the content repo (no-reply email). After push, confirm the raw URLs resolve:
```bash
curl -sSfI https://jhoedeman.github.io/byzantine-trail-catalog/catalog-manifest.json | head -1
curl -sSf  https://jhoedeman.github.io/byzantine-trail-catalog/catalog.json | shasum -a 256
```
Expected: `HTTP/2 200`, and the digest matches the manifest's `sha256` (Pages may take a minute to publish).

- [ ] **Step 5: Verify live refresh in the simulator**

Build + launch the app on the booted simulator (attach the live panel first so the owner can watch). On launch the app fetches the manifest, sees the higher `catalogVersion`, downloads, verifies, and swaps. Confirm the sites list shows the Phase-1 content and that opening a detail view loads a full-size photo from `photoBaseURL`. If the ghost-tile/state is stale, relaunch (do NOT `simctl erase` — it drops iCloud sign-in).

- [ ] **Step 6: Verify offline first-run experience**

Enable airplane mode (or `xcrun simctl status_bar <udid> override --wifiMode failed` / disable network), relaunch. Confirm the sites list + map still render and **thumbnails still show** (served from the bundle), while full-size images fail gracefully (no crash, no blocking alert). Re-enable network afterward.

- [ ] **Step 7: Final commit (app repo — if any tracked files changed)**

The app-repo content landed in Tasks 3–4; this task's artifacts live in the content repo + git-ignored `build/`. If nothing tracked changed in the app repo, there is nothing to commit here — the milestone is complete.

---

## Self-Review

- **Spec coverage:** photo tool → Task 1; baseline bundling → Task 4; authoring guide → Task 2; content + publish + live/offline verify → Tasks 3+5. Privacy (email scan, GPS strip, sha256, HTTPS) → Global Constraints + Tasks 1/3/5. All spec sections mapped.
- **Placeholder scan:** no TBD/TODO; `<owner-originals-dir>` / `<content-repo>` are genuine owner-supplied paths (documented as such), not unfilled plan gaps. Byzantine site facts are owner input by nature, not placeholders.
- **Type/name consistency:** `photo.id`/`thumb`/`full` conventions, `photoBaseURL` = `catalogBaseURL`, `thumbs/` folder-reference ↔ `PhotoResolver`'s `subdirectory: "thumbs"`, and `catalogVersion` equality (catalog.json ↔ manifest) are consistent across Tasks 1–5 and match the shipped code read during design.
