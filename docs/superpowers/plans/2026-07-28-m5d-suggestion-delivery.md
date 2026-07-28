# M5d — Suggestion Delivery via GitHub Issues Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A scheduled Cloudflare Worker polls the CloudKit public DB every 15 min and files one GitHub issue per new `SiteSuggestion` into the private repo `byzantine-trail-suggestions`.

**Architecture:** Server-side poll; the iOS app is untouched (it already writes the CloudKit record in M5c). The Worker (plain JS ES modules) signs CloudKit server-to-server requests, dedups by `recordName` in Workers KV, maps each record to an issue, and calls the GitHub API. Pure units (issue mapper, dedup, signing helpers) are unit-tested; live CloudKit signing + end-to-end delivery are verified once.

**Tech Stack:** Cloudflare Workers (JS ES modules), Workers KV, Web Crypto (ECDSA P-256), Vitest, Wrangler, GitHub REST API.

## Global Constraints

- **The iOS app / ByzantineTrail Xcode project is NOT modified in M5d** — no Swift, no `project.yml`, no `xcodegen`.
- The Worker lives in a **new private repo `byzantine-trail-suggestions`** at `/Users/jhoedeman/Documents/Programs/byzantine-trail-suggestions`. The spec and this plan live in the `ByzantineTrail` repo under `docs/superpowers/`.
- Plain **JS ES modules** (`"type": "module"`), no framework. **Vitest** for tests (`npm test` → `vitest run`).
- **Secrets live only in Worker secret config** (`wrangler secret put`), never committed: the CloudKit server-to-server private key and the GitHub fine-grained PAT. Non-secret config (CloudKit Key ID, KV namespace id, container, owner, repo) may live in `wrangler.toml`.
- **CloudKit environment is `development`** until the schema is deployed to Production before App Store release; then flip `CLOUDKIT_ENV` to `production`.
- Commit the new repo with the GitHub no-reply email `6411536+jhoedeman@users.noreply.github.com` (project-wide email-privacy rule; the repo is private but stay consistent). No owner email anywhere in the Worker, config, or issues.
- Poll interval `*/15 * * * *`. Dedup TTL comfortably exceeds the query lookback (30 days vs 24 h).

### Standard test command (run from the new repo)

```bash
cd /Users/jhoedeman/Documents/Programs/byzantine-trail-suggestions && npm test
```

In JS TDD, a test importing a not-yet-written module fails at import (the red state); implementing the module turns it green.

---

### Task 1: Scaffold the private repo + Worker project

**Files (in `/Users/jhoedeman/Documents/Programs/byzantine-trail-suggestions`):**
- Create: `package.json`, `wrangler.toml`, `.gitignore`, `README.md`, `src/` (empty), `test/` (empty)

**Interfaces:**
- Produces: a git repo with `npm test` runnable (0 tests initially), `wrangler.toml` with the cron + KV binding + non-secret vars (ids as clearly-marked placeholders filled in Task 8).

- [ ] **Step 1: Create the private GitHub repo and clone it**

```bash
cd /Users/jhoedeman/Documents/Programs
gh repo create byzantine-trail-suggestions --private \
  --description "Private triage backlog: user-submitted Byzantine Trail site suggestions (auto-filed by the delivery Worker)."
gh repo clone jhoedeman/byzantine-trail-suggestions
cd byzantine-trail-suggestions
git config user.email "6411536+jhoedeman@users.noreply.github.com"
git config user.name "John Hoedeman"
```

- [ ] **Step 2: Create the `suggestion` label**

```bash
gh label create suggestion --repo jhoedeman/byzantine-trail-suggestions \
  --color BFD4F2 --description "User-submitted site suggestion" || true
```

- [ ] **Step 3: Initialize the Node project and install dev deps**

```bash
cd /Users/jhoedeman/Documents/Programs/byzantine-trail-suggestions
npm init -y
npm pkg set type=module
npm pkg set scripts.test="vitest run"
npm pkg set scripts.deploy="wrangler deploy"
npm install -D vitest wrangler
mkdir -p src test
```

- [ ] **Step 4: Write `wrangler.toml`**

```toml
name = "byzantine-trail-suggestions"
main = "src/index.js"
compatibility_date = "2026-07-01"

[triggers]
crons = ["*/15 * * * *"]

# Filled in Task 8 after `wrangler kv namespace create SEEN`
[[kv_namespaces]]
binding = "SEEN"
id = "REPLACE_WITH_KV_NAMESPACE_ID"

[vars]
CLOUDKIT_CONTAINER = "iCloud.com.byzantinetrail.app"
CLOUDKIT_ENV = "development"
CLOUDKIT_KEY_ID = "REPLACE_WITH_CLOUDKIT_KEY_ID"
GITHUB_OWNER = "jhoedeman"
GITHUB_REPO = "byzantine-trail-suggestions"
```

- [ ] **Step 5: Write `.gitignore` and `README.md`**

`.gitignore`:
```
node_modules/
.wrangler/
.dev.vars
```

`README.md` (short): what this Worker does, that secrets (`CLOUDKIT_PRIVATE_KEY`, `GITHUB_TOKEN`) are set via `wrangler secret put` and never committed, and that `CLOUDKIT_ENV` must flip `development`→`production` when the CloudKit schema is deployed for release.

- [ ] **Step 6: Verify the test runner works (no tests yet)**

Run: `npm test`
Expected: Vitest runs and reports **no test files found** (exit is non-zero for "no tests", which is fine here) — or add `--passWithNoTests`: `npx vitest run --passWithNoTests` → exit 0. Confirm Vitest is installed and executes.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "M5d Task 1: scaffold Worker project (wrangler + vitest, cron + KV binding)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Issue mapper (`src/issue.js`)

**Files:** Create `src/issue.js`, `test/issue.test.js`

**Interfaces:**
- Produces: `export function toIssue(record) -> { title, body, labels }` where `record` = `{ recordName, name, location?, whyInclude?, linksText?, submittedAt }` (optionals may be `null`).

- [ ] **Step 1: Write the failing test** — `test/issue.test.js`

```js
import { describe, test, expect } from "vitest";
import { toIssue } from "../src/issue.js";

describe("toIssue", () => {
  test("maps all fields into title/body/labels", () => {
    const issue = toIssue({ recordName: "R1", name: "Hagia Sophia", location: "Istanbul",
      whyInclude: "Iconic", linksText: "https://x", submittedAt: "2026-07-28T00:00:00Z" });
    expect(issue.title).toBe("Suggestion: Hagia Sophia");
    expect(issue.labels).toEqual(["suggestion"]);
    expect(issue.body).toContain("**Name:** Hagia Sophia");
    expect(issue.body).toContain("**Location:** Istanbul");
    expect(issue.body).toContain("**Why include:** Iconic");
    expect(issue.body).toContain("**Links:** https://x");
    expect(issue.body).toContain("CloudKit recordName: R1");
  });

  test("absent optionals render as em dash", () => {
    const issue = toIssue({ recordName: "R2", name: "X", location: null,
      whyInclude: null, linksText: null, submittedAt: "t" });
    expect(issue.body).toContain("**Location:** —");
    expect(issue.body).toContain("**Why include:** —");
    expect(issue.body).toContain("**Links:** —");
  });

  test("truncates a long title to 80 chars with an ellipsis", () => {
    const issue = toIssue({ recordName: "R3", name: "A".repeat(200), submittedAt: "t" });
    expect(issue.title.length).toBe(80);
    expect(issue.title.endsWith("…")).toBe(true);
    expect(issue.title.startsWith("Suggestion: A")).toBe(true);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL (cannot find `../src/issue.js`).

- [ ] **Step 3: Write `src/issue.js`**

```js
const TITLE_MAX = 80;

export function toIssue(record) {
  const title = truncate(`Suggestion: ${record.name ?? "(no name)"}`, TITLE_MAX);
  const body = [
    `**Name:** ${record.name ?? "—"}`,
    `**Location:** ${record.location ?? "—"}`,
    `**Why include:** ${record.whyInclude ?? "—"}`,
    `**Links:** ${record.linksText ?? "—"}`,
    ``,
    `submittedAt: ${record.submittedAt ?? "—"}`,
    `CloudKit recordName: ${record.recordName}`,
  ].join("\n");
  return { title, body, labels: ["suggestion"] };
}

function truncate(s, max) {
  return s.length <= max ? s : s.slice(0, max - 1) + "…";
}
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → 3 pass.

- [ ] **Step 5: Commit**

```bash
git add src/issue.js test/issue.test.js
git commit -m "M5d Task 2: issue mapper (record -> title/body/labels)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Dedup decision (`src/dedup.js`)

**Files:** Create `src/dedup.js`, `test/dedup.test.js`

**Interfaces:**
- Produces: `export async function unseen(records, seenLookup) -> records[]` where `seenLookup(recordName) -> Promise<boolean>`; preserves input order.

- [ ] **Step 1: Write the failing test** — `test/dedup.test.js`

```js
import { describe, test, expect } from "vitest";
import { unseen } from "../src/dedup.js";

const rec = (n) => ({ recordName: n });

describe("unseen", () => {
  test("returns all when none seen", async () => {
    const out = await unseen([rec("a"), rec("b")], async () => false);
    expect(out.map(r => r.recordName)).toEqual(["a", "b"]);
  });
  test("returns none when all seen", async () => {
    const out = await unseen([rec("a"), rec("b")], async () => true);
    expect(out).toEqual([]);
  });
  test("filters mixed and preserves order", async () => {
    const seen = new Set(["b"]);
    const out = await unseen([rec("a"), rec("b"), rec("c")], async (n) => seen.has(n));
    expect(out.map(r => r.recordName)).toEqual(["a", "c"]);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL (cannot find `../src/dedup.js`).

- [ ] **Step 3: Write `src/dedup.js`**

```js
export async function unseen(records, seenLookup) {
  const result = [];
  for (const r of records) {
    if (!(await seenLookup(r.recordName))) result.push(r);
  }
  return result;
}
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add src/dedup.js test/dedup.test.js
git commit -m "M5d Task 3: dedup decision (unseen records by recordName)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: CloudKit request signing (`src/cloudkit.js` — signing half)

**Files:** Create `src/cloudkit.js` (signing helpers), `test/signing.test.js`

CloudKit Web Services server-to-server signing: the signature is **ECDSA P-256 / SHA-256** over the exact string `[ISO8601 date]:[base64(sha256(body))]:[subpath]`, DER-encoded, base64'd, sent in `X-Apple-CloudKit-Request-SignatureV1`. Web Crypto `ECDSA.sign` returns the raw IEEE-P1363 `r‖s`, so it must be converted to ASN.1 DER (what Apple expects).

> **Note (test method refinement vs spec):** the spec said "matches a precomputed vector". ECDSA signing is non-deterministic (random k), so a fixed signature can't be asserted. Instead we unit-test the **deterministic** pieces (`sha256Base64`, `signingString`, `p1363ToDer`) against fixed vectors, and prove `sign` produces a **valid** signature via a sign-then-verify round-trip with a throwaway key. End-to-end acceptance by Apple is confirmed live in Task 9.

**Interfaces:**
- Produces:
  - `export function base64FromBytes(Uint8Array) -> string`
  - `export function bytesFromBase64(string) -> Uint8Array`
  - `export async function sha256Base64(text) -> string`
  - `export async function signingString(dateISO, bodyString, subpath) -> string`
  - `export function p1363ToDer(rawSig: Uint8Array) -> Uint8Array`
  - `export async function importPrivateKey(pkcs8Pem) -> CryptoKey`
  - `export async function sign(pkcs8Pem, message) -> string` (base64 DER)

- [ ] **Step 1: Write the failing test** — `test/signing.test.js`

```js
import { describe, test, expect } from "vitest";
import { webcrypto } from "node:crypto";
import { sha256Base64, signingString, p1363ToDer, sign, base64FromBytes } from "../src/cloudkit.js";

describe("signing helpers", () => {
  test("sha256Base64 matches the known empty-string digest", async () => {
    expect(await sha256Base64("")).toBe("47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=");
  });

  test("signingString joins date:hash:subpath", async () => {
    const s = await signingString("2026-07-28T00:00:00Z", "", "/p");
    expect(s).toBe("2026-07-28T00:00:00Z:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:/p");
  });

  test("p1363ToDer wraps r and s as an ASN.1 SEQUENCE of INTEGERs", () => {
    const raw = new Uint8Array(64);
    raw[0] = 0x01;   // r = 1 (after leading zeros stripped)
    raw[63] = 0x02;  // s = 2
    const der = p1363ToDer(raw);
    // SEQUENCE(0x30) len, INTEGER(0x02) len 0x01 val 0x01, INTEGER(0x02) len 0x01 val 0x02
    expect(Array.from(der)).toEqual([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02]);
  });

  test("p1363ToDer prepends 0x00 when the high bit is set", () => {
    const raw = new Uint8Array(64);
    raw[0] = 0x80;   // r high bit set → needs 0x00 pad
    raw[63] = 0x01;  // s = 1
    const der = p1363ToDer(raw);
    // r INTEGER: 0x02 len 0x02 [0x00 0x80]; s INTEGER: 0x02 0x01 0x01
    expect(Array.from(der)).toEqual([0x30, 0x08, 0x02, 0x02, 0x00, 0x80, 0x02, 0x01, 0x01]);
  });

  test("sign produces a DER signature that verifies against the public key", async () => {
    const pair = await webcrypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const pkcs8 = new Uint8Array(await webcrypto.subtle.exportKey("pkcs8", pair.privateKey));
    const pem = "-----BEGIN PRIVATE KEY-----\n" +
      base64FromBytes(pkcs8).replace(/(.{64})/g, "$1\n") +
      "\n-----END PRIVATE KEY-----\n";
    const message = "2026-07-28T00:00:00Z:abc:/database/1/x/development/public/records/query";
    const sigB64 = await sign(pem, message);

    // Verify the DER signature with Node's crypto (which speaks DER).
    const { createVerify, KeyObject } = await import("node:crypto");
    const spki = Buffer.from(await webcrypto.subtle.exportKey("spki", pair.publicKey));
    const pubPem = "-----BEGIN PUBLIC KEY-----\n" +
      spki.toString("base64").replace(/(.{64})/g, "$1\n") + "\n-----END PUBLIC KEY-----\n";
    const v = createVerify("SHA256"); v.update(message); v.end();
    expect(v.verify(pubPem, Buffer.from(sigB64, "base64"))).toBe(true);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL (cannot find `../src/cloudkit.js`).

- [ ] **Step 3: Write `src/cloudkit.js` (signing half)**

```js
export function base64FromBytes(bytes) {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

export function bytesFromBase64(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function sha256Base64(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return base64FromBytes(new Uint8Array(digest));
}

export async function signingString(dateISO, bodyString, subpath) {
  return `${dateISO}:${await sha256Base64(bodyString)}:${subpath}`;
}

// Web Crypto ECDSA returns raw r‖s (IEEE P1363); Apple expects ASN.1 DER.
export function p1363ToDer(rawSig) {
  const half = rawSig.length / 2;
  const r = encodeInteger(rawSig.slice(0, half));
  const s = encodeInteger(rawSig.slice(half));
  const body = [...r, ...s];
  return Uint8Array.from([0x30, body.length, ...body]);
}

function encodeInteger(bytes) {
  let i = 0;
  while (i < bytes.length - 1 && bytes[i] === 0) i++;
  let v = bytes.slice(i);
  if (v[0] & 0x80) v = Uint8Array.from([0x00, ...v]);
  return [0x02, v.length, ...v];
}

export async function importPrivateKey(pkcs8Pem) {
  const b64 = pkcs8Pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  return crypto.subtle.importKey("pkcs8", bytesFromBase64(b64),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

export async function sign(pkcs8Pem, message) {
  const key = await importPrivateKey(pkcs8Pem);
  const raw = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(message)));
  return base64FromBytes(p1363ToDer(raw));
}
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → all signing tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/cloudkit.js test/signing.test.js
git commit -m "M5d Task 4: CloudKit server-to-server signing (ECDSA P-256, P1363->DER)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: CloudKit query + record normalization (`src/cloudkit.js` — query half)

**Files:** Modify `src/cloudkit.js` (append), Create `test/cloudkit-query.test.js`

**Interfaces:**
- Consumes: `sign`, `signingString` (Task 4).
- Produces:
  - `export function normalizeRecord(ckRecord) -> { recordName, name, location, whyInclude, linksText, submittedAt }` (missing fields → `null`; pure).
  - `export function isoDate(date) -> string` (`YYYY-MM-DDTHH:mm:ssZ`, no millis).
  - `export async function queryRecentSuggestions({ container, env, keyID, privateKeyPem, sinceMillis, fetchImpl = fetch }) -> record[]` (follows `continuationMarker`).

- [ ] **Step 1: Write the failing test** — `test/cloudkit-query.test.js`

```js
import { describe, test, expect } from "vitest";
import { webcrypto } from "node:crypto";
import { normalizeRecord, isoDate, queryRecentSuggestions, base64FromBytes } from "../src/cloudkit.js";

async function testKeyPem() {
  const pair = await webcrypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await webcrypto.subtle.exportKey("pkcs8", pair.privateKey));
  return "-----BEGIN PRIVATE KEY-----\n" +
    base64FromBytes(pkcs8).replace(/(.{64})/g, "$1\n") + "\n-----END PRIVATE KEY-----\n";
}

const ckRecord = (name, fields) => ({ recordName: name, recordType: "SiteSuggestion", fields });

describe("normalizeRecord", () => {
  test("maps present fields and nulls missing ones", () => {
    const out = normalizeRecord(ckRecord("R1", {
      name: { value: "Hagia" }, location: { value: "Istanbul" }, submittedAt: { value: 1690000000000 },
    }));
    expect(out).toEqual({ recordName: "R1", name: "Hagia", location: "Istanbul",
      whyInclude: null, linksText: null, submittedAt: 1690000000000 });
  });
});

describe("isoDate", () => {
  test("formats without milliseconds", () => {
    expect(isoDate(new Date("2026-07-28T14:03:09.123Z"))).toBe("2026-07-28T14:03:09Z");
  });
});

describe("queryRecentSuggestions", () => {
  test("follows continuationMarker and aggregates records", async () => {
    const pem = await testKeyPem();
    const pages = [
      { records: [ckRecord("R1", { name: { value: "A" }, submittedAt: { value: 1 } })],
        continuationMarker: "next" },
      { records: [ckRecord("R2", { name: { value: "B" }, submittedAt: { value: 2 } })] },
    ];
    let call = 0;
    const fetchImpl = async () => ({ ok: true, json: async () => pages[call++] });
    const out = await queryRecentSuggestions({
      container: "iCloud.com.byzantinetrail.app", env: "development", keyID: "K",
      privateKeyPem: pem, sinceMillis: 0, fetchImpl });
    expect(out.map(r => r.recordName)).toEqual(["R1", "R2"]);
    expect(call).toBe(2);
  });

  test("throws on a non-ok response", async () => {
    const pem = await testKeyPem();
    const fetchImpl = async () => ({ ok: false, status: 401, text: async () => "bad auth" });
    await expect(queryRecentSuggestions({ container: "c", env: "development", keyID: "K",
      privateKeyPem: pem, sinceMillis: 0, fetchImpl })).rejects.toThrow(/401/);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL (`normalizeRecord`/`queryRecentSuggestions` not exported).

- [ ] **Step 3: Append to `src/cloudkit.js`**

```js
export function normalizeRecord(ck) {
  const f = ck.fields ?? {};
  const val = (k) => (f[k] && f[k].value !== undefined ? f[k].value : null);
  return {
    recordName: ck.recordName,
    name: val("name"),
    location: val("location"),
    whyInclude: val("whyInclude"),
    linksText: val("linksText"),
    submittedAt: val("submittedAt"),
  };
}

export function isoDate(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

export async function queryRecentSuggestions({ container, env, keyID, privateKeyPem,
                                              sinceMillis, fetchImpl = fetch }) {
  const subpath = `/database/1/${container}/${env}/public/records/query`;
  const url = `https://api.apple-cloudkit.com${subpath}`;
  const out = [];
  let continuationMarker;
  do {
    const bodyObj = {
      query: {
        recordType: "SiteSuggestion",
        filterBy: [{ fieldName: "submittedAt", comparator: "GREATER_THAN",
                     fieldValue: { value: sinceMillis, type: "TIMESTAMP" } }],
        sortBy: [{ fieldName: "submittedAt", ascending: true }],
      },
    };
    if (continuationMarker) bodyObj.continuationMarker = continuationMarker;
    const body = JSON.stringify(bodyObj);
    const dateISO = isoDate(new Date());
    const signature = await sign(privateKeyPem, await signingString(dateISO, body, subpath));
    const res = await fetchImpl(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Apple-CloudKit-Request-KeyID": keyID,
        "X-Apple-CloudKit-Request-ISO8601Date": dateISO,
        "X-Apple-CloudKit-Request-SignatureV1": signature,
      },
      body,
    });
    if (!res.ok) throw new Error(`CloudKit query failed: ${res.status} ${await res.text()}`);
    const json = await res.json();
    for (const rec of json.records ?? []) out.push(normalizeRecord(rec));
    continuationMarker = json.continuationMarker;
  } while (continuationMarker);
  return out;
}
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add src/cloudkit.js test/cloudkit-query.test.js
git commit -m "M5d Task 5: CloudKit query + record normalization (submittedAt filter, pagination)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: GitHub client (`src/github.js`)

**Files:** Create `src/github.js`, `test/github.test.js`

**Interfaces:**
- Produces: `export async function createIssue({ token, owner, repo, issue, fetchImpl = fetch }) -> object` (throws on non-2xx).

- [ ] **Step 1: Write the failing test** — `test/github.test.js`

```js
import { describe, test, expect, vi } from "vitest";
import { createIssue } from "../src/github.js";

describe("createIssue", () => {
  test("POSTs to the repo issues endpoint with auth + body", async () => {
    const fetchImpl = vi.fn(async () => ({ ok: true, json: async () => ({ number: 7 }) }));
    const res = await createIssue({ token: "tok", owner: "o", repo: "r",
      issue: { title: "T", body: "B", labels: ["suggestion"] }, fetchImpl });
    expect(res).toEqual({ number: 7 });
    const [url, opts] = fetchImpl.mock.calls[0];
    expect(url).toBe("https://api.github.com/repos/o/r/issues");
    expect(opts.method).toBe("POST");
    expect(opts.headers.Authorization).toBe("Bearer tok");
    expect(JSON.parse(opts.body)).toEqual({ title: "T", body: "B", labels: ["suggestion"] });
  });

  test("throws on a non-ok response", async () => {
    const fetchImpl = vi.fn(async () => ({ ok: false, status: 422, text: async () => "nope" }));
    await expect(createIssue({ token: "t", owner: "o", repo: "r",
      issue: { title: "T" }, fetchImpl })).rejects.toThrow(/422/);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL (cannot find `../src/github.js`).

- [ ] **Step 3: Write `src/github.js`**

```js
export async function createIssue({ token, owner, repo, issue, fetchImpl = fetch }) {
  const res = await fetchImpl(`https://api.github.com/repos/${owner}/${repo}/issues`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/vnd.github+json",
      "User-Agent": "byzantine-trail-suggestions-worker",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(issue),
  });
  if (!res.ok) throw new Error(`GitHub createIssue failed: ${res.status} ${await res.text()}`);
  return res.json();
}
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add src/github.js test/github.test.js
git commit -m "M5d Task 6: GitHub client (create issue, throw on non-2xx)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Worker entrypoint (`src/index.js`)

**Files:** Create `src/index.js`, `test/run.test.js`

**Interfaces:**
- Consumes: `queryRecentSuggestions`, `unseen`, `toIssue`, `createIssue`.
- Produces:
  - `export default { async scheduled(event, env, ctx) }`
  - `export async function run(env, deps = {}) -> { attempted, filed }` (deps override for tests: `queryRecentSuggestions`, `createIssue`, `now`).

- [ ] **Step 1: Write the failing test** — `test/run.test.js`

```js
import { describe, test, expect, vi } from "vitest";
import { run } from "../src/index.js";

function fakeEnv() {
  const store = new Map();
  const env = {
    CLOUDKIT_CONTAINER: "c", CLOUDKIT_ENV: "development", CLOUDKIT_KEY_ID: "k",
    CLOUDKIT_PRIVATE_KEY: "pem", GITHUB_TOKEN: "t", GITHUB_OWNER: "o", GITHUB_REPO: "r",
    SEEN: {
      get: async (key) => (store.has(key) ? store.get(key) : null),
      put: async (key, val) => { store.set(key, val); },
    },
  };
  return { env, store };
}

const record = (n, at) => ({ recordName: n, name: "N" + n, location: null,
  whyInclude: null, linksText: null, submittedAt: at });

describe("run", () => {
  test("files issues for new records and marks them seen", async () => {
    const { env, store } = fakeEnv();
    const createIssue = vi.fn(async () => ({ number: 1 }));
    const queryRecentSuggestions = vi.fn(async () => [record("R1", 1000), record("R2", 2000)]);
    const res = await run(env, { createIssue, queryRecentSuggestions, now: () => 5000 });
    expect(res).toEqual({ attempted: 2, filed: 2 });
    expect(createIssue).toHaveBeenCalledTimes(2);
    expect(store.get("seen:R1")).toBe("1000");
    expect(store.get("seen:R2")).toBe("2000");
  });

  test("does not refile already-seen records", async () => {
    const { env, store } = fakeEnv();
    store.set("seen:R1", "1000");
    const createIssue = vi.fn(async () => ({ number: 1 }));
    const queryRecentSuggestions = vi.fn(async () => [record("R1", 1000)]);
    const res = await run(env, { createIssue, queryRecentSuggestions, now: () => 5000 });
    expect(res).toEqual({ attempted: 0, filed: 0 });
    expect(createIssue).not.toHaveBeenCalled();
  });

  test("a failing createIssue is not marked seen (retried next run)", async () => {
    const { env, store } = fakeEnv();
    const createIssue = vi.fn(async () => { throw new Error("boom"); });
    const queryRecentSuggestions = vi.fn(async () => [record("R1", 1000)]);
    const res = await run(env, { createIssue, queryRecentSuggestions, now: () => 5000 });
    expect(res).toEqual({ attempted: 1, filed: 0 });
    expect(store.has("seen:R1")).toBe(false);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npm test` → FAIL (cannot find `../src/index.js`).

- [ ] **Step 3: Write `src/index.js`**

```js
import { queryRecentSuggestions } from "./cloudkit.js";
import { unseen } from "./dedup.js";
import { toIssue } from "./issue.js";
import { createIssue } from "./github.js";

const LOOKBACK_MS = 24 * 60 * 60 * 1000;
const SEEN_TTL_S = 30 * 24 * 60 * 60;

export default {
  async scheduled(event, env, ctx) {
    await run(env);
  },
};

export async function run(env, deps = {}) {
  const query = deps.queryRecentSuggestions ?? queryRecentSuggestions;
  const create = deps.createIssue ?? createIssue;
  const now = deps.now ? deps.now() : Date.now();

  const records = await query({
    container: env.CLOUDKIT_CONTAINER,
    env: env.CLOUDKIT_ENV,
    keyID: env.CLOUDKIT_KEY_ID,
    privateKeyPem: env.CLOUDKIT_PRIVATE_KEY,
    sinceMillis: now - LOOKBACK_MS,
  });

  const seenLookup = async (recordName) => (await env.SEEN.get("seen:" + recordName)) !== null;
  const fresh = await unseen(records, seenLookup);

  let filed = 0;
  for (const record of fresh) {
    try {
      await create({ token: env.GITHUB_TOKEN, owner: env.GITHUB_OWNER,
        repo: env.GITHUB_REPO, issue: toIssue(record) });
      await env.SEEN.put("seen:" + record.recordName,
        String(record.submittedAt ?? now), { expirationTtl: SEEN_TTL_S });
      filed++;
    } catch (err) {
      console.error(`Failed to file issue for ${record.recordName}:`, err);
    }
  }
  return { attempted: fresh.length, filed };
}
```

- [ ] **Step 4: Run to verify it passes** — `npm test` → full suite (all tasks) green.

- [ ] **Step 5: Commit**

```bash
git add src/index.js test/run.test.js
git commit -m "M5d Task 7: scheduled() entrypoint (query -> dedup -> issue -> mark seen)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Owner setup + deploy (manual)

**Files:** Modify `wrangler.toml` (real KV id + CloudKit Key ID)

Manual owner steps — needs the CloudKit Console and GitHub token UI. No automated test; the gate is a successful `wrangler deploy` and a manual smoke run.

- [ ] **Step 1: Generate the CloudKit server-to-server key**

Generate an EC P-256 key locally and register the **public** half with CloudKit:

```bash
openssl ecparam -name prime256v1 -genkey -noout -out eckey_sec1.pem
openssl pkcs8 -topk8 -nocrypt -in eckey_sec1.pem -out eckey_pkcs8.pem   # Web Crypto needs pkcs8
openssl ec -in eckey_sec1.pem -pubout -out eckey_pub.pem
```

In **CloudKit Console → the `iCloud.com.byzantinetrail.app` container → Tokens & Keys → Server-to-Server Keys → Add** — paste the contents of `eckey_pub.pem`, save, and copy the generated **Key ID**. (Keep `eckey_pkcs8.pem` private; it is the `CLOUDKIT_PRIVATE_KEY` secret. Delete the local copies after setting the secret.)

- [ ] **Step 2: Create the GitHub fine-grained PAT**

GitHub → Settings → Developer settings → Fine-grained tokens → Generate: **Resource owner** = you, **Repository access** = only `byzantine-trail-suggestions`, **Permissions → Issues: Read and write** (Metadata: Read is added automatically). Copy the token.

- [ ] **Step 3: Create the KV namespace and fill `wrangler.toml`**

```bash
cd /Users/jhoedeman/Documents/Programs/byzantine-trail-suggestions
npx wrangler kv namespace create SEEN
```

Paste the printed `id` into `wrangler.toml` (`[[kv_namespaces]] id = "…"`), and replace `CLOUDKIT_KEY_ID` with the Key ID from Step 1.

- [ ] **Step 4: Set the secrets**

```bash
npx wrangler secret put CLOUDKIT_PRIVATE_KEY   # paste contents of eckey_pkcs8.pem
npx wrangler secret put GITHUB_TOKEN           # paste the fine-grained PAT
```

- [ ] **Step 5: Deploy**

```bash
npx wrangler deploy
```
Expected: deploy succeeds and reports the cron trigger `*/15 * * * *`.

- [ ] **Step 6: Commit the resolved config**

```bash
git add wrangler.toml
git commit -m "M5d Task 8: wrangler config with KV namespace + CloudKit Key ID (no secrets)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Live verification (manual, end-to-end)

**Files:** none.

Confirms the one thing unit tests can't: that Apple accepts the signature and the full poll→issue path works.

- [ ] **Step 1: Trigger a run against real CloudKit + GitHub**

Either wait for the cron, or force a run immediately:

```bash
cd /Users/jhoedeman/Documents/Programs/byzantine-trail-suggestions
npx wrangler dev --test-scheduled &
curl "http://localhost:8787/__scheduled?cron=*/15+*+*+*+*"
```

(If the signature is rejected, the log shows a CloudKit 401 with a signature error — recheck the pkcs8 key, Key ID, and that `CLOUDKIT_ENV` matches where the data lives, `development`.)

- [ ] **Step 2: Submit a fresh suggestion from the app** — iPhone 16 simulator (signed into iCloud) → Profile → Contribute → Suggest a site → submit a uniquely-named test suggestion.

- [ ] **Step 3: Run the Worker again** (cron or the curl above) and confirm **one** new issue appears:

```bash
gh issue list --repo jhoedeman/byzantine-trail-suggestions --label suggestion
```

The issue title is `Suggestion: <your test name>`, the body has the fields + `CloudKit recordName`, and **no submitter identity**.

- [ ] **Step 4: Run the Worker a third time** and confirm **no duplicate** issue is filed (KV dedup works).

- [ ] **Step 5:** No commit — verification only. Record the outcome, then proceed to finishing-a-development-branch (which finalizes the M5d spec/plan commits on the `ByzantineTrail` `m5d-suggestion-delivery` branch; the Worker repo is already pushed via its own commits).

---

## Self-Review

**1. Spec coverage:**
- Scheduled Worker polling CloudKit public DB → Tasks 5, 7, 8. ✅
- Server-to-server ECDSA signing → Task 4. ✅
- `submittedAt`-windowed query + pagination → Task 5. ✅
- KV-per-record dedup / idempotency → Tasks 3, 7. ✅
- Issue mapper (title/body/labels, traceability, no identity) → Task 2. ✅
- GitHub client (fine-grained PAT, that repo) → Tasks 6, 8. ✅
- Private repo + `suggestion` label → Task 1. ✅
- Secrets only in Worker config; `development` env; $0 infra → Global Constraints, Tasks 1, 8. ✅
- No iOS/app changes → Global Constraints (no Swift task exists). ✅
- Unit tests (mapper, dedup, signing, query-normalization, run) + one live verify → Tasks 2–7, 9. ✅

**2. Placeholder scan:** No TBD/TODO. `wrangler.toml`'s `REPLACE_WITH_*` are deploy-time config values explicitly resolved in Task 8, not plan gaps. Every code step shows full code; every run step names a command + expected result.

**3. Type/name consistency:** `run(env, deps)` return `{ attempted, filed }` matches Task 7 impl + tests. `queryRecentSuggestions({container, env, keyID, privateKeyPem, sinceMillis, fetchImpl})` signature identical in Tasks 5 and 7. `createIssue({token, owner, repo, issue, fetchImpl})` identical in Tasks 6 and 7. `toIssue(record)` shape (`{title, body, labels}`) consistent in Tasks 2, 7. `unseen(records, seenLookup)` consistent in Tasks 3, 7. Record shape (`recordName/name/location/whyInclude/linksText/submittedAt`) consistent across `normalizeRecord` (5), `toIssue` (2), `run` (7). KV key prefix `seen:` consistent in Task 7 impl + tests. ✅
