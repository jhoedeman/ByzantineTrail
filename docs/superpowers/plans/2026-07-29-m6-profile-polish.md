# M6 — Profile Polish & Release Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the Profile/Settings surface (Settings screen with Appearance, Account, About) and add the `PrivacyInfo.xcprivacy` manifest so the app is submittable.

**Architecture:** Pure, testable value units (`AccountStatusPresentation`, `AppVersionInfo`) live in `Core/Settings` with no UIKit/Bundle dependency; thin SwiftUI views in `Features/Settings` consume them. `ThemeManager` becomes the single persisted source of truth for appearance (UserDefaults-backed) and its preference is applied once at the app root via `.preferredColorScheme`. No new networking, no CloudKit access, no seam changes.

**Tech Stack:** Swift, SwiftUI, Swift Testing, XcodeGen, iOS 17+.

## Global Constraints

- **Hard privacy rule:** the owner's real **email must never appear in public view.** Commit author email uses `6411536+jhoedeman@users.noreply.github.com`. → About screen shows **no contact/email line and no developer credit**; privacy policy text contains no personal email (its "Contact" line points at the App Store listing). Owner **name** and **Team ID `XY62X6K9VH`** are public-OK.
- **Swift Testing**, not XCTest. iOS 17+ deployment target.
- **XcodeGen:** after adding/removing files, regenerate with the **real binary** `~/bin/xcodegen_dist/bin/xcodegen generate` (NOT the bare `xcodegen` symlink — it silently fails). Sources are path-based, so files under `ByzantineTrail/` and `ByzantineTrailTests/` auto-include; the `.xcodeproj` is git-ignored and regenerated — never edit it by hand.
- **Build/test destination:** `platform=iOS Simulator,name=iPhone 16`. `xcodebuild` is the authoritative signal — SourceKit "cannot find X in scope" / "No such module 'Testing'" cross-file errors are false positives; trust `xcodebuild`.
- **Architecture pattern:** pure units (no UIKit/Bundle) separated from thin SwiftUI views; platform access (`UIApplication.openSettingsURLString`, `Bundle.main`) quarantined at the view/edge layer.
- **Chrysos theme tokens** — no raw hex in views; colors come from the resolved `Theme` (`docs/COLOR_SYSTEM.md`).
- **Reuse, do not rebuild:** `ThemePreference` (`Core/Theme/Theme.swift`), `AccountStore` / `AccountStatus` (`Core/Account/`), `ProfileView`'s existing `NavigationStack`.

---

### Task 1: Appearance foundations — persist + apply the theme preference

Closes the two gaps in `ThemeManager`: preference is in-memory only (not persisted) and applied nowhere. Adds `ThemePreference.displayName` (used by the picker in Task 3), makes `ThemeManager` UserDefaults-backed, and applies `preferredColorScheme` at the app root.

**Files:**
- Modify: `ByzantineTrail/Core/Theme/Theme.swift` (add `displayName` to `ThemePreference`)
- Modify: `ByzantineTrail/Core/Theme/ThemeManager.swift` (UserDefaults-backed `preference`)
- Modify: `ByzantineTrail/App/ByzantineTrailApp.swift` (`.preferredColorScheme` at root)
- Modify: `ByzantineTrailTests/ThemeTests.swift` (add `displayName` test)
- Create: `ByzantineTrailTests/ThemeManagerPersistenceTests.swift`

**Interfaces:**
- Consumes: existing `enum ThemePreference: String, CaseIterable { case system, light, dark }` with `var colorScheme: ColorScheme?`.
- Produces:
  - `ThemePreference.displayName: String` → `"System"` / `"Light"` / `"Dark"`.
  - `ThemeManager.init(defaults: UserDefaults = .standard)`; `var preference: ThemePreference` (persists on set to key `"settings.appearance"`, restores on init); `func theme(for: ColorScheme) -> Theme` (unchanged behavior).

- [ ] **Step 1: Add the `displayName` failing test**

In `ByzantineTrailTests/ThemeTests.swift`, add this `@Test` inside `struct ThemeTests`:

```swift
    @Test func displayNamesAreCapitalized() {
        #expect(ThemePreference.system.displayName == "System")
        #expect(ThemePreference.light.displayName == "Light")
        #expect(ThemePreference.dark.displayName == "Dark")
    }
```

- [ ] **Step 2: Create the ThemeManager persistence failing tests**

Create `ByzantineTrailTests/ThemeManagerPersistenceTests.swift`:

```swift
import Testing
import Foundation
@testable import ByzantineTrail

@MainActor
struct ThemeManagerPersistenceTests {
    private func freshDefaults(_ suite: String) -> UserDefaults {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func defaultsToSystemWhenEmpty() {
        let m = ThemeManager(defaults: freshDefaults("m6.theme.empty"))
        #expect(m.preference == .system)
    }

    @Test func persistsAndRestoresAcrossInstances() {
        let d = freshDefaults("m6.theme.roundtrip")
        let m = ThemeManager(defaults: d)
        m.preference = .dark
        let restored = ThemeManager(defaults: d)
        #expect(restored.preference == .dark)
    }

    @Test func garbageValueFallsBackToSystem() {
        let d = freshDefaults("m6.theme.garbage")
        d.set("purple", forKey: "settings.appearance")
        let m = ThemeManager(defaults: d)
        #expect(m.preference == .system)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/ThemeManagerPersistenceTests -only-testing:ByzantineTrailTests/ThemeTests/displayNamesAreCapitalized 2>&1 | tail -20`
Expected: FAIL — `displayName` unresolved and `ThemeManager(defaults:)` initializer not found / preference does not persist.

- [ ] **Step 4: Add `displayName` to `ThemePreference`**

In `ByzantineTrail/Core/Theme/Theme.swift`, replace the `ThemePreference` enum with:

```swift
enum ThemePreference: String, CaseIterable {
    case system, light, dark
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
```

- [ ] **Step 5: Make `ThemeManager` UserDefaults-backed**

Replace the entire contents of `ByzantineTrail/Core/Theme/ThemeManager.swift` with:

```swift
import SwiftUI

@MainActor
@Observable
final class ThemeManager {
    private let defaults: UserDefaults
    private static let key = "settings.appearance"

    /// Persisted appearance preference. `.system` follows the device.
    var preference: ThemePreference {
        didSet { defaults.set(preference.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.key)
        self.preference = raw.flatMap(ThemePreference.init(rawValue:)) ?? .system
    }

    /// Resolves the active Theme. When preference is `.system`, use the
    /// environment's colorScheme; otherwise use the forced preference.
    func theme(for environmentScheme: ColorScheme) -> Theme {
        Theme.chrysos(preference.colorScheme ?? environmentScheme)
    }
}
```

- [ ] **Step 6: Apply the preference at the app root**

In `ByzantineTrail/App/ByzantineTrailApp.swift`, add a `.preferredColorScheme` modifier to `RootTabView()`. Insert it immediately after the `.environment(\.entitlements, FreeEntitlementManager())` line and before `.task {`:

```swift
                .environment(\.entitlements, FreeEntitlementManager())
                .preferredColorScheme(themeManager.preference.colorScheme)
                .task {
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/ThemeManagerPersistenceTests -only-testing:ByzantineTrailTests/ThemeTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail
git add ByzantineTrail/Core/Theme/Theme.swift ByzantineTrail/Core/Theme/ThemeManager.swift ByzantineTrail/App/ByzantineTrailApp.swift ByzantineTrailTests/ThemeTests.swift ByzantineTrailTests/ThemeManagerPersistenceTests.swift
git commit -m "M6: persist theme preference via UserDefaults and apply at app root"
```

---

### Task 2: Pure Settings units — `AppVersionInfo` + `AccountStatusPresentation`

Two dependency-free value types the Settings views consume. Fully unit-testable without a real bundle or CloudKit.

**Files:**
- Create: `ByzantineTrail/Core/Settings/AppVersionInfo.swift`
- Create: `ByzantineTrail/Core/Settings/AccountStatusPresentation.swift`
- Create: `ByzantineTrailTests/AppVersionInfoTests.swift`
- Create: `ByzantineTrailTests/AccountStatusPresentationTests.swift`

**Interfaces:**
- Consumes: existing `enum AccountStatus { case available, noAccount, restricted, unknown }` (`Core/Account/AccountStatus.swift`).
- Produces:
  - `AppVersionInfo` (Equatable): `let version: String`, `let build: String`, `var displayString: String`, `static func from(_:) -> AppVersionInfo`, `static var current: AppVersionInfo`.
  - `AccountStatusPresentation` (Equatable): `let title: String`, `let explainer: String?`, `let symbolName: String`, `static func make(for: AccountStatus) -> AccountStatusPresentation`.

- [ ] **Step 1: Write the failing tests**

Create `ByzantineTrailTests/AppVersionInfoTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct AppVersionInfoTests {
    @Test func readsPresentKeys() {
        let info = AppVersionInfo.from([
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        ])
        #expect(info.version == "1.0")
        #expect(info.build == "1")
        #expect(info.displayString == "1.0 (1)")
    }

    @Test func missingKeysFallBackToDash() {
        let info = AppVersionInfo.from(nil)
        #expect(info.version == "—")
        #expect(info.build == "—")
        #expect(info.displayString == "— (—)")
    }
}
```

Create `ByzantineTrailTests/AccountStatusPresentationTests.swift`:

```swift
import Testing
@testable import ByzantineTrail

struct AccountStatusPresentationTests {
    @Test func availableHasTitleAndNoExplainer() {
        let p = AccountStatusPresentation.make(for: .available)
        #expect(p.title == "Signed in to iCloud")
        #expect(p.explainer == nil)
        #expect(p.symbolName == "checkmark.icloud")
    }

    @Test func noAccountHasExplainer() {
        let p = AccountStatusPresentation.make(for: .noAccount)
        #expect(p.title == "Not signed in to iCloud")
        #expect(p.explainer != nil)
        #expect(p.symbolName == "xmark.icloud")
    }

    @Test func restrictedHasExplainer() {
        let p = AccountStatusPresentation.make(for: .restricted)
        #expect(p.title == "iCloud restricted")
        #expect(p.explainer != nil)
        #expect(p.symbolName == "exclamationmark.icloud")
    }

    @Test func unknownHasNoExplainer() {
        let p = AccountStatusPresentation.make(for: .unknown)
        #expect(p.title == "Checking iCloud status…")
        #expect(p.explainer == nil)
        #expect(p.symbolName == "icloud")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/AppVersionInfoTests -only-testing:ByzantineTrailTests/AccountStatusPresentationTests 2>&1 | tail -20`
Expected: FAIL — `AppVersionInfo` / `AccountStatusPresentation` unresolved.

- [ ] **Step 3: Implement `AppVersionInfo`**

Create `ByzantineTrail/Core/Settings/AppVersionInfo.swift`:

```swift
import Foundation

/// App version/build read from an injected info dictionary (defaults to the
/// main bundle), so it is testable without a real bundle. No UIKit.
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

- [ ] **Step 4: Implement `AccountStatusPresentation`**

Create `ByzantineTrail/Core/Settings/AccountStatusPresentation.swift`:

```swift
import Foundation

/// Maps an `AccountStatus` to display fields. No UIKit; fully unit-testable.
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

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ByzantineTrailTests/AppVersionInfoTests -only-testing:ByzantineTrailTests/AccountStatusPresentationTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail
git add ByzantineTrail/Core/Settings ByzantineTrailTests/AppVersionInfoTests.swift ByzantineTrailTests/AccountStatusPresentationTests.swift
git commit -m "M6: add pure AppVersionInfo and AccountStatusPresentation units"
```

---

### Task 3: Settings UI — Profile gear entry + Settings/About/Privacy screens

The navigable Settings surface. All view code, verified by a successful build (no unit tests — SwiftUI views are exercised in the Task 5 sim pass). Consumes the units from Tasks 1 & 2.

**Files:**
- Create: `ByzantineTrail/Features/Settings/SettingsView.swift`
- Create: `ByzantineTrail/Features/Settings/AboutView.swift`
- Create: `ByzantineTrail/Features/Settings/PrivacyPolicyView.swift`
- Modify: `ByzantineTrail/Features/Profile/ProfileView.swift` (add gear toolbar link)

**Interfaces:**
- Consumes: `ThemePreference.displayName`, `ThemeManager.preference` (Task 1); `AppVersionInfo.current.displayString`, `AccountStatusPresentation.make(for:)` (Task 2); environment `ThemeManager`, `AccountStore`; `AccountStore.status`, `AccountStore.refresh()`.
- Produces: `SettingsView`, `AboutView`, `PrivacyPolicyView` (all `View`s, no initializer args).

- [ ] **Step 1: Create `PrivacyPolicyView`**

Create `ByzantineTrail/Features/Settings/PrivacyPolicyView.swift`:

```swift
import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(Self.policyText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityIdentifier("privacy.body")
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// In-app source of truth for the privacy policy. No personal email — the
    /// Contact line points at the App Store listing (hard privacy rule).
    private static let policyText = """
    Byzantine Trail — Privacy Policy
    Last updated: July 2026

    Byzantine Trail is designed to collect as little as possible.

    No tracking. The app contains no advertising, no third-party analytics, and no tracking of any kind. It does not use the Advertising Identifier and never shares data with data brokers.

    Ratings you submit are public. When you rate a site (1–10), that rating and its site are stored in Apple's CloudKit public database so other users can see the community average. Ratings are not shown next to your name.

    Site suggestions. If you suggest a site, the details you type are stored in Apple's CloudKit database. Suggestions carry no identifying information about you.

    Your favorites, want-to-visit, and visited lists are private. These sync across your own devices through your personal iCloud account. They are stored in your private iCloud database, which the developer cannot read.

    Where your data lives. All data stays within Apple's CloudKit. Apple's handling of it is governed by Apple's Privacy Policy. The app has no separate servers and no separate account system.

    Contact. Questions about this policy can be raised through the app's App Store listing.
    """
}
```

- [ ] **Step 2: Create `AboutView`**

Create `ByzantineTrail/Features/Settings/AboutView.swift`:

```swift
import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                Text("Byzantine Trail")
                    .font(.headline)
            }
            Section("Version") {
                Text(AppVersionInfo.current.displayString)
                    .accessibilityIdentifier("about.version")
            }
            Section {
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    .accessibilityIdentifier("about.privacy")
            }
        }
        .navigationTitle("About")
    }
}
```

- [ ] **Step 3: Create `SettingsView`**

Create `ByzantineTrail/Features/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var themeManager = themeManager
        let theme = themeManager.theme(for: colorScheme)
        let presentation = AccountStatusPresentation.make(for: accountStore.status)

        List {
            Section("Appearance") {
                Picker("Theme", selection: $themeManager.preference) {
                    ForEach(ThemePreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance")
            }

            Section("Account") {
                HStack(alignment: .top) {
                    Image(systemName: presentation.symbolName)
                        .foregroundStyle(theme.accentPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                        if let explainer = presentation.explainer {
                            Text(explainer)
                                .font(.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                .accessibilityIdentifier("settings.account.status")

                Button("Open Settings") { openAppSettings() }
                    .accessibilityIdentifier("settings.account.openSettings")
            }

            Section {
                NavigationLink("About") { AboutView() }
                    .accessibilityIdentifier("settings.about")
            }
        }
        .navigationTitle("Settings")
        .background(theme.bgApp)
        .task { await accountStore.refresh() }
    }

    /// iOS only permits deep-linking to the app's OWN Settings page, not the
    /// iCloud account pane. This is the standard iOS pattern.
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
```

- [ ] **Step 4: Add the gear entry point to `ProfileView`**

In `ByzantineTrail/Features/Profile/ProfileView.swift`, add a `.toolbar` modifier to the `List`. It goes directly after the existing `.background(theme.bgApp)` line (which follows `.navigationTitle("Profile")`):

```swift
            .navigationTitle("Profile")
            .background(theme.bgApp)
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

- [ ] **Step 5: Regenerate the project and build**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the full test suite to confirm no regressions**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail
git add ByzantineTrail/Features/Settings ByzantineTrail/Features/Profile/ProfileView.swift
git commit -m "M6: add Settings/About/Privacy screens reached from Profile gear"
```

---

### Task 4: Privacy manifest — `PrivacyInfo.xcprivacy`

Add the App Store privacy manifest as a bundled resource and verify it ships in the built `.app`.

**Files:**
- Create: `ByzantineTrail/PrivacyInfo.xcprivacy`

**Interfaces:**
- Consumes: nothing (static resource).
- Produces: a `PrivacyInfo.xcprivacy` resource present at the root of the built `.app` bundle.

- [ ] **Step 1: Create the manifest**

Create `ByzantineTrail/PrivacyInfo.xcprivacy`:

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

- [ ] **Step 2: Regenerate the project and build**

XcodeGen classifies `.xcprivacy` under the `ByzantineTrail` source path as a resource automatically — no `project.yml` change expected.

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify the manifest is bundled into the built `.app`**

Run:
```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail
APP=$(xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
ls "$APP/PrivacyInfo.xcprivacy" && plutil -lint "$APP/PrivacyInfo.xcprivacy"
```
Expected: the path lists successfully and `plutil -lint` prints `OK`.

If the file is **absent** from the bundle, add it explicitly to `project.yml` under the app target's `sources` as a resource and regenerate:

```yaml
    sources:
      - path: ByzantineTrail
      - path: ByzantineTrail/PrivacyInfo.xcprivacy
        buildPhase: resources
```

Then re-run Step 2 and this step. (Only apply this fallback if the verification failed.)

- [ ] **Step 4: Commit**

```bash
cd /Users/jhoedeman/Documents/Programs/ByzantineTrail
git add ByzantineTrail/PrivacyInfo.xcprivacy project.yml
git commit -m "M6: add PrivacyInfo.xcprivacy App Store privacy manifest"
```

---

### Task 5: Simulator verification (controller-verified)

Final human/controller-in-the-loop check on the iPhone 16 simulator, matching prior milestones. No new code; this task gates the milestone on observed behavior.

**Files:** none (verification only).

- [ ] **Step 1: Confirm the full suite is green**

Run: `cd /Users/jhoedeman/Documents/Programs/ByzantineTrail && ~/bin/xcodegen_dist/bin/xcodegen generate && xcodebuild -scheme ByzantineTrail -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -25`
Expected: `** TEST SUCCEEDED **` across all suites (including `ThemeManagerPersistenceTests`, `AppVersionInfoTests`, `AccountStatusPresentationTests`).

- [ ] **Step 2: Build, install, and launch on the booted iPhone 16 simulator**

Boot the iPhone 16 simulator, then build/install/launch the app (via the simulator control tooling or `xcrun simctl install` + `launch`).

- [ ] **Step 3: Verify Appearance**

Profile → gear → Settings → Appearance. Confirm:
- Selecting **Light** re-themes the whole app immediately; selecting **Dark** does too.
- Selecting **System** follows the simulator's appearance.
- Force-quit and relaunch → the last choice is still selected (persistence).

- [ ] **Step 4: Verify Account**

In Settings → Account: the status row reflects the simulator's iCloud state (signed-in shows "Signed in to iCloud"). Tap **Open Settings** → the iOS Settings app opens to the app's own Settings page.

- [ ] **Step 5: Verify About + Privacy**

Settings → About: shows "Byzantine Trail" and the correct version/build (e.g. `1.0 (1)`). Tap **Privacy Policy** → the policy screen scrolls and reads correctly, with **no email address** anywhere in the text.

- [ ] **Step 6: Milestone complete**

All checks pass. Proceed to `superpowers:finishing-a-development-branch` to close out the `m6-profile-polish` branch.

---

## Notes for the implementer

- **`@Bindable` on an environment `@Observable`:** inside `SettingsView.body`, `@Bindable var themeManager = themeManager` re-declares the environment value locally so `$themeManager.preference` yields a `Binding`. This is the idiomatic iOS 17 route — do not add a manual `Binding(get:set:)`.
- **Root re-render:** `ByzantineTrailApp.body` reads `themeManager.preference.colorScheme`; because `ThemeManager` is `@Observable` and held in `@State`, changing `preference` in Settings re-evaluates the root and updates `.preferredColorScheme` live.
- **Do not** introduce raw hex in any view — resolve colors through `themeManager.theme(for: colorScheme)`.
