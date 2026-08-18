# Known issues

Tracked defects to address in a later pass. Each entry names the file/line so
the fix is unambiguous.

_No open issues._

## Resolved

### "Open in Maps" opened driving directions instead of just the pin — fixed 2026-08-17

**Where:** `ByzantineTrail/Features/SiteDetail/SiteLocationSection.swift`

Tapping **Open in Maps** launched Apple Maps in *directions* mode, routing from
the user's current location to the site. Caused by the
`MKLaunchOptionsDirectionsModeKey` launch option. Fixed by calling
`.openInMaps()` with no directions option, so Maps opens centered on the site
and drops its pin. Users can start directions themselves if they want them.
