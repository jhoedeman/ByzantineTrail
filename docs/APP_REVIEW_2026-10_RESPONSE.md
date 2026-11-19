# App Review Response — Guideline 2.1 (Information Needed), Oct 2026

**Submission:** ByzantineTrail 1.0 (1). Submitted 2026-10-07; rejected 2026-10-08
under **Guideline 2.1.0 Performance: App Completeness** — the standard new-app
"Information Needed" template (not a defect finding). Apple requested a screen
recording on a physical device, a description of purpose/audience, and instructions
for accessing the main features, and included generic conditional items (account
flows, UGC reporting/blocking, paid content) — most of which do not apply.

Submission ID: 44f9492c-f965-42bb-bf4f-38e910d29a27

## Reply (paste into Resolution Center AND App Review Information > Notes)

Thank you for the review. Byzantine Trail is a free reference app — a catalog of
Byzantine-era historical sites worldwide. Here is the information requested.

PURPOSE & TARGET AUDIENCE
Byzantine Trail helps travelers, students, and enthusiasts of Byzantine history
discover and explore Byzantine-era sites (churches, monasteries, fortifications,
archaeological sites). Users browse 580+ catalogued sites, view photos and details,
see locations on a map, open directions in Maps, keep private personal lists
(favorites / want to visit / visited), and rate sites. The audience is
general-interest history and travel; there is no mature or objectionable content.

ACCOUNTS, LOGIN, PAID CONTENT
- The app does NOT create its own accounts and has no login or registration screen.
  Optional features (ratings, personal lists) use the device's existing iCloud
  identity via CloudKit — the app collects no username or password — so there is no
  registration, login, or account-deletion flow, and no demo account is needed.
- The app is completely free. There are no in-app purchases, subscriptions, or paid
  content or features.

HOW TO ACCESS THE MAIN FEATURES
1. Browse: Launch the app; the Sites tab lists all sites. Tap a row to open its
   detail (photos, description, location, Open in Maps).
2. Map: The Map tab shows sites as pins; tap a pin, then the info button to open its detail.
3. Personal lists: In a site's detail, tap Favorite / Want to visit / Visited. These
   sync privately across the user's own devices via their private iCloud database and
   are never visible to anyone else.
4. Rate a site: In a site's detail, tap a star in the 1–10 rating bar. Rating uses
   iCloud, so the device must be signed into iCloud (Settings > [your name]) and
   online. If it is not signed in, the rating control is intentionally disabled and
   shows the text "Sign in to iCloud to rate." Please ensure the review device is
   signed into iCloud so the rating control is active.
5. Suggest a site: Profile tab > Contribute > Suggest a site. The text is sent
   privately to the developer for review.

EXTERNAL SERVICES / TOOLS / PLATFORMS
- Apple CloudKit — stores ratings, site suggestions, and the user's private lists.
- GitHub Pages — hosts the catalog data (a static JSON file).
- Cloudflare R2 — hosts the site photographs (static image files).
No payment processors (the app is free), no AI services, and no advertising or
third-party analytics SDKs.

USER-GENERATED CONTENT
The app has no user-to-user content display — no feed, no profiles, and no way for
one user to view another user's content:
- Ratings are numeric only (1–10). The app shows only the aggregate community average
  and count, never any individual user's data, name, or free text.
- Site suggestions are free text, but they are sent privately to the developer only
  and are not shown to other users anywhere in the app. Every suggestion is reviewed
  by the developer before any site is added to the catalog, which is how submissions
  are filtered.
Because no user ever sees another user's submitted content, there is nothing for
users to report and no users to block; the content-reporting and user-blocking
mechanisms do not apply to this app. We are happy to address any specific concern.

REGIONAL DIFFERENCES
None. The app offers the same features and content in all regions.

REGULATED INDUSTRY
Not applicable. Byzantine Trail is a general-interest history and travel reference
app and does not operate in a regulated industry or provide protected material.

A screen recording captured on a physical iPhone — starting from launch and showing
browse > site detail > map > rating (signed into iCloud) > suggest a site — is attached.

Thank you.

## Screen recording shot list (physical iPhone, SIGNED INTO iCloud)

~1–2 min, start from the Home screen and launch the app:
1. Launch → Sites list loads.
2. Tap a site → detail: scroll photos, show map, tap Favorite.
3. Map tab → tap a pin → info button → detail.
4. Tap a star to RATE (critical: signed-in device → bar is active, rating registers,
   no "Sign in to iCloud" text). Resolves the gating that looked dead on the simulator.
5. Profile → Contribute → Suggest a site → type a word → submit → "Thanks" confirmation.
AirDrop to Mac, attach in the Resolution Center reply (do the reply from the ASC website).

## Resubmit steps
1. Resolution Center → reply with the text above + attach the video.
2. App Information → App Review Information → Notes → paste the same text.
3. Resubmit to App Review. No binary change needed — same build 1.0 (1).
