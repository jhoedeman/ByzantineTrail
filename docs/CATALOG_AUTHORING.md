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
