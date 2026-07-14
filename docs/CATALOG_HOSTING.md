# Catalog hosting (M1-remote)

The app refreshes its catalog from a **separate public GitHub repo** served over
GitHub Pages. This repo is NOT the app repo, and it must carry no owner identity
(photo `credit` fields stay neutral — the owner-name denylist in the pre-publish catalog validator (spec §3.3; see note below) enforces this).

## One-time setup

1. Create a public repo, e.g. `byzantine-trail-catalog`.
2. Settings → Pages → Deploy from branch → `main` / root. Note the published URL,
   e.g. `https://jhoedeman.github.io/byzantine-trail-catalog/`.
3. Confirm that URL matches `RemoteConfig.catalogBaseURL` in the app
   (`ByzantineTrail/Core/Networking/RemoteConfig.swift`). It MUST end with `/`.
   (To use a custom domain later, point DNS at Pages and update this one constant.)

## Publishing a catalog update

1. Author/validate the new `catalog.json` with `Tools/validate_catalog.swift` (the pre-publish validator specified in spec §3.3 — note: this tool is not built yet as of the M1-remote milestone; until it exists, hand-check the catalog against the spec's rules before publishing).
   Bump its `catalogVersion` (monotonically increasing).
2. Compute its SHA-256:
   ```bash
   shasum -a 256 catalog.json
   ```
3. Write `catalog-manifest.json` next to it:
   ```json
   {
     "catalogVersion": 2,
     "url": "catalog.json",
     "sha256": "<the hex digest from step 2>"
   }
   ```
   `url` may be relative (resolved against the Pages base URL) or an absolute
   `https://` URL. `catalogVersion` here MUST equal the `catalogVersion` inside
   `catalog.json`, or the app rejects the update.
4. Commit and push both files. The app picks up the update on next launch:
   it fetches the manifest, sees the higher version, downloads, verifies the
   SHA-256, decodes, and atomically swaps.

## Safety notes

- Serve over **HTTPS** (GitHub Pages is HTTPS by default).
- A wrong or stale `sha256` makes the app reject the download and keep its current
  catalog — no user-visible error. Always regenerate the digest after editing the file.
- The app never deletes or downgrades: a manifest version ≤ the app's current
  version is ignored.
