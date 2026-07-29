# M6 — Profile Polish & Release Prep (Design)

**Status:** Approved for planning (2026-07-29)
**Milestone:** M6 (final roadmap milestone before a submittable build)
**Depends on:** M0–M5d (all merged). No CloudKit schema changes, no backend changes.

## 0. Goal

Complete the Profile/Settings surface and add the App Store privacy manifest so
the app is submittable:

1. **Settings screen** reached from Profile (gear button), holding three sections.
2. **Appearance** — System / Light / Dark picker, persisted and actually applied.
3. **Account** — iCloud status display + "Open Settings" deep link.
4. **About** — app name, version/build, and a bundled Privacy Policy screen.
5. **`PrivacyInfo.xcprivacy`** — the App Store privacy manifest.

Everything here is local UI + app-metadata. There is **no new networking, no
CloudKit access, and no change to any existing seam**.

## 1. Constraints (carried from the project)

- **The one hard privacy rule:** the owner's real **email must never appear in
  public view.** Commit author email uses the GitHub no-reply address
  (`6411536+jhoedeman@users.noreply.github.com`). The owner's **name** and
  **Team ID `XY62X6K9VH`** are public-OK. → *Consequence for M6:* the About
  screen shows **no contact/email line** and **no developer credit** (owner
  chose minimal About). The privacy policy text contains no personal email.
- **Swift Testing**, not XCTest. iOS 17+ deployment target.
- **XcodeGen**: project regenerated via the real binary
  `~/bin/xcodegen_dist/bin/xcodegen` (not the symlink) after `project.yml`
  changes.
- **Architecture pattern:** pure, testable units (no UIKit/Bundle) separated
  from thin SwiftUI views; platform access (UIKit `openSettingsURLString`,
  `Bundle.main`) quarantined at the view/edge layer.
- Follow the **Chrysos** theme token approach — no raw hex in views; colors come
  from `Theme` (`docs/COLOR_SYSTEM.md`).

## 2. What already exists (do not rebuild)

- **`ThemeManager`** (`Core/Theme/ThemeManager.swift`): `@MainActor @Observable`,
  holds `var preference: ThemePreference = .system` and resolves
  `theme(for: environmentScheme)` as `Theme.chrysos(preference.colorScheme ?? environmentScheme)`.
  **Gaps M6 closes:** `preference` is **in-memory only** (not persisted) and is
  **applied nowhere** (nothing sets `preferredColorScheme`), so today the
  setting would have no visible effect.
- **`ThemePreference`** (`Core/Theme/Theme.swift`): `enum ThemePreference: String, CaseIterable { case system, light, dark }` with
  `var colorScheme: ColorScheme?` (`system → nil`, `light → .light`, `dark → .dark`). Reuse as-is.
- **`AccountStore`** (`Core/Account/AccountStore.swift`): `@MainActor @Observable`,
  `private(set) var status: AccountStatus`, `func refresh() async`. Already
  created at app root with `CloudKitAccountStatusProvider` and refreshed at
  launch. Injected into the environment.
- **`AccountStatus`** (`Core/Account/AccountStatus.swift`):
  `enum { case available, noAccount, restricted, unknown }`.
- **`ProfileView`** (`Features/Profile/ProfileView.swift`): a `NavigationStack`
  wrapping a `List` with sections My Activity / Progress / Contribute. Reads
  `ThemeManager`, `CatalogStore`, `UserStateStore` from the environment.
- **Persistence precedent:** `SitesListView` uses
  `@AppStorage("sites.sortField")` / `@AppStorage("sites.sortAscending")`.
- **App root** (`App/ByzantineTrailApp.swift`): injects all stores into the
  environment; `RootTabView` is the top content view.

## 3. Component design

### 3.1 Navigation entry point (`ProfileView` change)

Add a trailing nav-bar button to Profile that pushes `SettingsView`:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        NavigationLink { SettingsView() } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("profile.settings")
    }
}
```

`SettingsView` inherits Profile's existing `NavigationStack` (it pushes within
it), so it does **not** create its own `NavigationStack`.

### 3.2 `SettingsView` (`Features/Settings/SettingsView.swift`)

A `List` with three `Section`s, styled with the resolved `theme` (read
`ThemeManager` + `\.colorScheme`, same as ProfileView). Reads `ThemeManager` and
`AccountStore` from the environment. On appear, refresh account status:

```swift
.task { await accountStore.refresh() }
.navigationTitle("Settings")
```

**Appearance section**

```swift
Section("Appearance") {
    Picker("Theme", selection: appearanceBinding) {
        ForEach(ThemePreference.allCases, id: \.self) { pref in
            Text(pref.displayName).tag(pref)   // "System" / "Light" / "Dark"
        }
    }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("settings.appearance")
}
```

`appearanceBinding` writes through to `themeManager.preference` (a `Binding`
built from the `@Observable` manager, since `@Bindable` on an environment
`@Observable` is the idiomatic route: `@Bindable var themeManager` then
`$themeManager.preference`). `ThemePreference` gains a `displayName` computed
property (`system → "System"`, `light → "Light"`, `dark → "Dark"`).

**Account section**

```swift
Section("Account") {
    HStack {
        Image(systemName: presentation.symbolName)
        VStack(alignment: .leading) {
            Text(presentation.title)
            if let explainer = presentation.explainer {
                Text(explainer).font(.footnote).foregroundStyle(theme.textSecondary)
            }
        }
    }
    .accessibilityIdentifier("settings.account.status")

    Button("Open Settings") { openAppSettings() }
        .accessibilityIdentifier("settings.account.openSettings")
}
```

where `presentation = AccountStatusPresentation.make(for: accountStore.status)`
(pure; §3.4) and `openAppSettings()` opens
`UIApplication.openSettingsURLString`:

```swift
private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
```

*Behavior note (documented, not a defect):* iOS only permits deep-linking to the
**app's own** Settings page, not the iCloud account pane. "Open Settings" takes
the user there; from Settings they can reach iCloud. This is the best available
behavior and is the standard iOS pattern.

**About section**

```swift
Section {
    NavigationLink("About") { AboutView() }
        .accessibilityIdentifier("settings.about")
}
```

### 3.3 `AboutView` (`Features/Settings/AboutView.swift`)

Minimal, per owner decision. A `List`/`Form`:

- App display name: **"Byzantine Trail"** (static string).
- Version row: `Text(AppVersionInfo.current.displayString)` → e.g. `"1.0 (1)"`
  (a11y id `about.version`).
- `NavigationLink("Privacy Policy") { PrivacyPolicyView() }`
  (a11y id `about.privacy`).

No developer credit, no attribution line, no contact line (owner's minimal
choice + the email rule).

### 3.4 Pure unit: `AccountStatusPresentation` (`Core/Settings/AccountStatusPresentation.swift`)

No UIKit. Maps status → display fields. Fully unit-testable.

```swift
struct AccountStatusPresentation: Equatable {
    let title: String
    let explainer: String?
    let symbolName: String

    static func make(for status: AccountStatus) -> AccountStatusPresentation {
        switch status {
        case .available:
            return .init(title: "Signed in to iCloud",
                         explainer: nil,
                         symbolName: "checkmark.icloud")
        case .noAccount:
            return .init(title: "Not signed in to iCloud",
                         explainer: "Sign in to iCloud to rate sites and sync across your devices.",
                         symbolName: "xmark.icloud")
        case .restricted:
            return .init(title: "iCloud restricted",
                         explainer: "iCloud access is restricted on this device (e.g. by Screen Time or a profile).",
                         symbolName: "exclamationmark.icloud")
        case .unknown:
            return .init(title: "Checking iCloud status…",
                         explainer: nil,
                         symbolName: "icloud")
        }
    }
}
```

### 3.5 Pure unit: `AppVersionInfo` (`Core/Settings/AppVersionInfo.swift`)

No UIKit. Reads version/build from an injected dictionary (defaults to
`Bundle.main.infoDictionary`) so it's testable without a real bundle.

```swift
struct AppVersionInfo: Equatable {
    let version: String   // CFBundleShortVersionString, e.g. "1.0"
    let build: String     // CFBundleVersion, e.g. "1"

    var displayString: String { "\(version) (\(build))" }

    static func from(_ info: [String: Any]?) -> AppVersionInfo {
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return AppVersionInfo(version: version, build: build)
    }

    static var current: AppVersionInfo { from(Bundle.main.infoDictionary) }
}
```

### 3.6 `PrivacyPolicyView` (`Features/Settings/PrivacyPolicyView.swift`)

A `ScrollView` rendering the bundled policy text (the in-app **source of
truth**; the same text is later copied to a hosted URL for App Store Connect).
Text stored as a `private let` multi-line string constant (or a small bundled
`.md`); rendered as sectioned `Text`. `navigationTitle("Privacy Policy")`,
a11y id `privacy.body` on the scroll content.

**Policy content (final wording; may be lightly edited during implementation):**

> **Byzantine Trail — Privacy Policy**
> *Last updated: July 2026*
>
> Byzantine Trail is designed to collect as little as possible.
>
> **No tracking.** The app contains no advertising, no third-party analytics,
> and no tracking of any kind. It does not use the Advertising Identifier and
> never shares data with data brokers.
>
> **Ratings you submit are public.** When you rate a site (1–10), that rating
> and its site are stored in Apple's CloudKit public database so other users can
> see the community average. Ratings are not shown next to your name.
>
> **Site suggestions.** If you suggest a site, the details you type are stored
> in Apple's CloudKit database. Suggestions carry no identifying information
> about you.
>
> **Your favorites, want-to-visit, and visited lists are private.** These sync
> across your own devices through your personal iCloud account. They are stored
> in your private iCloud database, which the developer cannot read.
>
> **Where your data lives.** All data stays within Apple's CloudKit. Apple's
> handling of it is governed by Apple's Privacy Policy. The app has no separate
> servers and no separate account system.
>
> **Contact.** Questions about this policy can be raised through the app's App
> Store listing.

*(The "Contact" line points at the App Store listing, not a personal email, per
the hard privacy rule.)*

### 3.7 Appearance persistence + application

**Persist (in `ThemeManager`):** add injectable `UserDefaults` and a persisted
`preference`. Keep `ThemeManager` the single source of truth.

```swift
@MainActor @Observable
final class ThemeManager {
    private let defaults: UserDefaults
    private static let key = "settings.appearance"

    var preference: ThemePreference {
        didSet { defaults.set(preference.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.key)
        self.preference = raw.flatMap(ThemePreference.init(rawValue:)) ?? .system
    }

    func theme(for environmentScheme: ColorScheme) -> Theme {
        Theme.chrysos(preference.colorScheme ?? environmentScheme)
    }
}
```

*(`@Observable` tracks the stored `preference`; the `didSet` persists on every
change. `ThemePreference` is already `String`-`RawRepresentable`.)*

**Apply (at the app root):** attach `preferredColorScheme` to the root content
so a Light/Dark choice forces the whole app, and System (`nil`) follows the
device. Because `theme(for:)` resolves via `preference.colorScheme ?? environmentScheme`,
forcing the environment keeps token resolution consistent everywhere.

```swift
RootTabView()
    .environment(themeManager)
    // …other environment injections…
    .preferredColorScheme(themeManager.preference.colorScheme)
```

### 3.8 `PrivacyInfo.xcprivacy` (`ByzantineTrail/PrivacyInfo.xcprivacy`)

A property-list resource bundled into the app target (added under the app
sources so XcodeGen includes it; verified present in the built `.app`).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyTrackingDomains</key>
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array>
    <!-- Site suggestions: free-text content the user submits (public DB). -->
    <dict>
      <key>NSPrivacyCollectedDataType</key>
      <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
      <key>NSPrivacyCollectedDataTypeLinked</key>
      <false/>
      <key>NSPrivacyCollectedDataTypeTracking</key>
      <false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array>
        <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
      </array>
    </dict>
    <!-- Ratings: how the user interacts with catalog content (public DB). -->
    <dict>
      <key>NSPrivacyCollectedDataType</key>
      <string>NSPrivacyCollectedDataTypeProductInteraction</string>
      <key>NSPrivacyCollectedDataTypeLinked</key>
      <false/>
      <key>NSPrivacyCollectedDataTypeTracking</key>
      <false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array>
        <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
      </array>
    </dict>
  </array>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <!-- UserDefaults: app's own settings (appearance, sort) and sync/throttle state. -->
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>CA92.1</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
```

**Rationale for the collected-data declaration:**
- Private-DB user-state (favorites/want/visited) is stored in the user's own
  iCloud and is **not readable by the developer** → per Apple guidance, **not
  "collected"** → not declared.
- Public ratings + suggestions are readable by the developer via the CloudKit
  dashboard → **collected**, but **not linked** to a resolvable identity and
  **not used for tracking**; purpose is App Functionality.
- Only required-reason API in use is **UserDefaults** (`CA92.1`).

**Submission note:** this manifest must stay consistent with the App Store
Connect "App Privacy" questionnaire answered at submission time.

## 4. File structure

| File | Responsibility | New/Modified |
|------|----------------|--------------|
| `Features/Profile/ProfileView.swift` | Add gear → `SettingsView` toolbar link | Modified |
| `Features/Settings/SettingsView.swift` | 3 sections (Appearance/Account/About) | New |
| `Features/Settings/AboutView.swift` | App name, version, privacy link | New |
| `Features/Settings/PrivacyPolicyView.swift` | Bundled policy text | New |
| `Core/Settings/AccountStatusPresentation.swift` | Pure status→display mapping | New |
| `Core/Settings/AppVersionInfo.swift` | Pure bundle version reader | New |
| `Core/Theme/ThemeManager.swift` | Persist `preference` via UserDefaults | Modified |
| `Core/Theme/Theme.swift` | `ThemePreference.displayName` | Modified |
| `App/ByzantineTrailApp.swift` | `.preferredColorScheme(...)` at root | Modified |
| `ByzantineTrail/PrivacyInfo.xcprivacy` | Privacy manifest resource | New |
| `project.yml` | Ensure manifest is bundled | Modified (if needed) |
| `Tests/…` | Unit tests for the 3 pure units + ThemeManager persistence | New |

## 5. Testing

**Unit (Swift Testing, no UIKit):**
- `AccountStatusPresentation.make` returns the correct title/explainer/symbol for
  all four `AccountStatus` cases (explainer present for `.noAccount`/`.restricted`,
  absent for `.available`/`.unknown`).
- `AppVersionInfo.from` — present keys → `"1.0 (1)"`; missing keys → `"—"`
  fallbacks; `displayString` format.
- `ThemeManager` persistence round-trip with an injected `UserDefaults`
  (in-memory suite): setting `preference` writes the raw value; a fresh manager
  on the same defaults restores it; empty/garbage defaults → `.system`.
- `ThemePreference.displayName` for all three cases.

**Static/build:** the `.xcprivacy` is verified by a successful build plus a check
that the file is present in the built `.app` bundle (it is a resource, not
unit-testable).

**Simulator (controller-verified, per prior milestones):**
- Appearance: switch Light/Dark → whole app re-themes immediately; System →
  follows the device; relaunch → choice persisted.
- Account: row reflects the signed-in state; "Open Settings" opens the app's
  Settings page.
- About: shows `Byzantine Trail` + correct version/build; Privacy Policy screen
  scrolls and reads correctly.

## 6. Out of scope (explicitly)

- No StoreKit / paywall / entitlement changes (still `FreeEntitlementManager`).
- No CloudKit schema or backend changes; no Development→Production deploy (that
  is a separate owner step at release).
- No hosted privacy-policy page (the in-app text is the source of truth; hosting
  is a later, non-code step for App Store Connect).
- No developer credit / contact line / attribution line in About.
- No changes to the catalog, photos, or the Worker.
```

