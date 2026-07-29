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
