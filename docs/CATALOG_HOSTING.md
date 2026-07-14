# Catalog hosting (M1-remote)

The app refreshes its catalog from a **separate public GitHub repo** served over
GitHub Pages. This repo is NOT the app repo. Keep it free of anything that could
be abused: the pre-publish validator (`Tools/validate_catalog.swift`, spec §3.3)
scans every string for **email addresses** and fails if it finds one, so your
personal email can never be published. Photo credits may name a person — a name in
a credit is fine; only emails (and any substrings you add to an optional
`Tools/owner_denylist.txt`) are blocked.

## One-time setup

1. Create a public repo, e.g. `byzantine-trail-catalog`.
2. Settings → Pages → Deploy from branch → `main` / root. Note the published URL,
   e.g. `https://jhoedeman.github.io/byzantine-trail-catalog/`.
3. Confirm that URL matches `RemoteConfig.catalogBaseURL` in the app
   (`ByzantineTrail/Core/Networking/RemoteConfig.swift`). It MUST end with `/`.
   (To use a custom domain later, point DNS at Pages and update this one constant.)

## Publishing a catalog update

1. Author the new `catalog.json` and bump its `catalogVersion` (monotonically
   increasing). Validate it before publishing:
   ```bash
   # from the app repo root; the second arg (optional) enables thumb-file checks
   swift Tools/validate_catalog.swift path/to/catalog.json [ByzantineTrail/Resources]
   ```
   Exit 0 means valid; any problem prints a `✗` line and exits non-zero. The
   validator checks schema shape, unique site/photo ids, `cityId` resolution,
   coordinate ranges, ISO-3166 country codes, controlled `semanticTags`/`period.era`,
   valid `importance`, `addedInVersion ≤ catalogVersion`, and no email leaks.
   (To also block a specific handle/username, copy `Tools/owner_denylist.example.txt`
   to the git-ignored `Tools/owner_denylist.txt` and list it there. Run the tool's
   own tests with `bash Tools/run_validator_tests.sh`.)
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
