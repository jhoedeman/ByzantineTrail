# M5d — Suggestion Delivery via GitHub Issues (Design)

**Status:** approved 2026-07-28
**Milestone:** M5d (follows M5c site-suggestions submission)

## Goal

Deliver user site-suggestions to the owner as **GitHub issues** in a new private
repo, so the owner stops polling the CloudKit Console. A scheduled Cloudflare
Worker reads new `SiteSuggestion` records from the CloudKit public database and
files one issue per suggestion.

## Key decisions (from brainstorming)

1. **Dual destination, CloudKit stays the system of record.** CloudKit keeps the
   authenticated, spam-resistant write (M5c, unchanged). GitHub issues are the
   triage/notification layer.
2. **Server-side poll, not client dual-write.** The **iOS app does not change** —
   it already writes the CloudKit record. A scheduled Worker polls CloudKit and
   files issues. No public webhook exists to abuse; no new app code to re-test.
3. **Poll every 15 minutes.** Free at any interval; 15 min is near-real-time.
4. **Worker lives in the private `byzantine-trail-suggestions` repo** (no secrets
   in source, so co-locating infra with its issues is clean).
5. **Cost: $0** — Cloudflare Workers (free: 100k req/day, cron included), Workers
   KV (free tier), GitHub private repo + API (free).

## Non-goals (YAGNI)

- No iOS/Swift changes whatsoever.
- No real-time delivery (a ≤15-min poll delay is acceptable).
- No email/Slack/Discord destinations (GitHub issues only; the seam stays open
  to add them later).
- No editing/closing suggestions from the app; the owner triages issues in GitHub.
- No moderation/spam-filtering beyond CloudKit's authenticated write + the app's
  existing client rate-limit.

## Architecture

```
[iOS app, UNCHANGED] --submit--> CloudKit public DB (SiteSuggestion record)
                                          │
        Cloudflare Cron Trigger (*/15 min) ▼
   Worker.scheduled():
     1. query SiteSuggestion where submittedAt > (now - lookbackWindow),
        sorted submittedAt ASC     [signed server-to-server request]
     2. for each record whose recordName is NOT in KV `seen:<recordName>`:
            a. POST a GitHub issue to byzantine-trail-suggestions
            b. put KV `seen:<recordName>` = submittedAt (idempotency mark)
```

The Worker is a single Cloudflare Worker (plain JS ES modules, no framework)
with a Cron Trigger, one KV namespace binding, and two secrets.

### Why KV-per-record for dedup (not a bare cursor)

A single "last submittedAt" cursor is fragile: two records sharing a
`submittedAt` value, or a partial-failure mid-run, can drop or duplicate an
issue. Instead the Worker marks each processed record by `recordName` in KV and
skips already-seen ones. Reruns are therefore idempotent. The `submittedAt >
now - lookbackWindow` filter bounds each query to a small recent set;
`lookbackWindow = 24h` comfortably covers any missed run (KV still prevents
duplicates for anything already filed).

## Components

All components are files in the `byzantine-trail-suggestions` repo under
`worker/`.

### 1. `worker/src/cloudkit.js` — CloudKit client + request signer

The trickiest piece. CloudKit Web Services server-to-server requests are signed
with **ECDSA P-256 / SHA-256** (Web Crypto, available in Workers).

- `sign(privateKeyPEM, dateISO, bodyString, subpath)` — computes the signature
  over the exact string `[dateISO]:[base64(sha256(bodyString))]:[subpath]`,
  returns base64 signature. Pure given inputs → unit-testable against a known
  vector.
- `queryRecentSuggestions({ keyID, privateKeyPEM, container, env, sinceDate })`
  — builds the query body:
  ```json
  {
    "recordType": "SiteSuggestion",
    "filterBy": [{ "fieldName": "submittedAt", "comparator": "GREATER_THAN",
                   "fieldValue": { "value": <sinceMillis>, "type": "TIMESTAMP" } }],
    "sortBy": [{ "fieldName": "submittedAt", "ascending": true }]
  }
  ```
  POSTs (signed) to
  `https://api.apple-cloudkit.com/database/1/<container>/<env>/public/records/query`,
  follows the `continuationMarker` across pages, returns a normalized array of
  `{ recordName, name, location, whyInclude, linksText, submittedAt }` (missing
  optional fields → `null`).
- **`env` is `"development"` now.** Flip to `"production"` when the CloudKit
  schema is deployed to Production before App Store release (noted in the
  Worker's README and CLOUDKIT_SETUP addendum).

### 2. `worker/src/issue.js` — issue mapper (pure, unit-tested)

`toIssue(record)` → `{ title, body, labels }`:
- `title`: `"Suggestion: " + name`, truncated to 80 chars (add `…` if cut).
- `body`: markdown with **Name**, **Location**, **Why include**, **Links**
  (each shown only if present; absent → "—"), plus a trailing
  `submittedAt` (ISO) and `CloudKit recordName: <recordName>` line for
  traceability.
- `labels`: `["suggestion"]`.

No I/O — fully unit-testable.

### 3. `worker/src/github.js` — GitHub client

`createIssue({ token, owner, repo, issue })` → `POST
https://api.github.com/repos/<owner>/<repo>/issues` with
`Authorization: Bearer <token>`, `User-Agent`, `Accept:
application/vnd.github+json`. Throws on non-2xx (so the record is NOT marked
seen and is retried next run).

### 4. `worker/src/dedup.js` — dedup decision (pure, unit-tested)

`unseen(records, seenLookup)` → the subset of records whose `recordName` is not
present, given an async `seenLookup(recordName) -> bool`. Keeps the KV-vs-logic
boundary testable without a live KV.

### 5. `worker/src/index.js` — `scheduled()` entrypoint

Wires it together: compute `sinceDate = now - lookbackWindow`; query; filter via
`dedup` against `env.SEEN` (KV); for each unseen record `toIssue` → `createIssue`
→ `env.SEEN.put("seen:" + recordName, submittedAt, { expirationTtl })`. Per-record
try/catch so one failure doesn't block the rest; failures are logged and retried
next cycle (still idempotent via KV).

### 6. `worker/wrangler.toml`

- `name`, `main = "src/index.js"`, `compatibility_date`.
- `[triggers] crons = ["*/15 * * * *"]`.
- `[[kv_namespaces]] binding = "SEEN"` (id filled after `wrangler kv namespace
  create`).
- Non-secret vars: `CLOUDKIT_CONTAINER = "iCloud.com.byzantinetrail.app"`,
  `CLOUDKIT_ENV = "development"`, `CLOUDKIT_KEY_ID`, `GITHUB_OWNER`,
  `GITHUB_REPO = "byzantine-trail-suggestions"`.

### Secrets (via `wrangler secret put`, never committed)
- `CLOUDKIT_PRIVATE_KEY` — the server-to-server EC private key (PEM).
- `GITHUB_TOKEN` — fine-grained PAT, scoped to `byzantine-trail-suggestions`
  only, permission **Issues: write** (+ mandatory Metadata: read).

## Owner setup (one-time; folded into the plan)

1. **Create the private repo** `byzantine-trail-suggestions` (via `gh repo create
   … --private`) and a `suggestion` label.
2. **CloudKit server-to-server key:** CloudKit Console → the container → API
   Tokens/Keys → generate a **Server-to-Server key**; save the **Key ID** and
   download the **private key** (PEM). (Requires a queryable index on
   `SiteSuggestion.submittedAt` — CloudKit auto-created it on first write in M5c.)
3. **GitHub PAT:** fine-grained token, repo `byzantine-trail-suggestions` only,
   Issues: write.
4. **Deploy:** `wrangler kv namespace create SEEN` (paste id into wrangler.toml),
   `wrangler secret put CLOUDKIT_PRIVATE_KEY`, `wrangler secret put GITHUB_TOKEN`,
   set the plain vars, `wrangler deploy`.

## Testing

- **Unit (vitest):**
  - `issue.toIssue` — title truncation, present/absent optional fields, label,
    traceability line.
  - `dedup.unseen` — all-new, all-seen, mixed; preserves order.
  - `cloudkit.sign` — signature over a fixed `(date, body, subpath)` matches a
    precomputed vector using a throwaway test EC key (verifies the signing string
    construction and base64 encoding, no network).
  - `cloudkit.queryRecentSuggestions` record-normalization — parse a canned
    CloudKit JSON response (single + multi-page via `continuationMarker`) into the
    normalized shape, with `fetch` mocked.
- **Live verify once (like M5a–c):** submit a suggestion from the app →
  `wrangler dev`/deployed run within a cycle files an issue in the private repo →
  a second run files **no duplicate** (KV mark works). Confirm the issue body has
  no submitter identity.

## Privacy & secrets

- `SiteSuggestion` records carry **no submitter identity** (M5c), so issues won't
  either — the body is name/location/why/links + submittedAt + recordName.
- The repo is **private**; the CloudKit private key and GitHub PAT are **Worker
  secrets**, never committed. The Worker source contains no secrets, so it is
  safe in the private repo (and would even be safe public — but private
  co-locates it with the issues).
- Owner email rule (project-wide) is unaffected: no email anywhere in the Worker,
  its config, or the issues.

## Global constraints (carried from the project)

- The **iOS app is not modified** in M5d — no Swift, no Xcode, no `project.yml`.
- Cloudflare Worker: plain JS ES modules, no framework; Web Crypto for signing;
  `fetch` for CloudKit + GitHub; Workers KV for dedup. Vitest for unit tests.
- CloudKit environment is `development` until the schema is deployed to
  Production before release, then flip `CLOUDKIT_ENV`.
- Secrets live only in Worker secret config; never in git. Private repo for the
  Worker.
