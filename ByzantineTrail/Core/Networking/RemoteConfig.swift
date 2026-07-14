import Foundation

/// Remote-host configuration. `catalogBaseURL` is the single swappable constant
/// (Global Constraint / spec §3.2): change this one line — or point a custom
/// domain at the same content — to move hosts without an app release.
///
/// Host: GitHub Pages served from a SEPARATE public content repo (not the app
/// repo). The owner creates that repo and enables Pages; see
/// `docs/CATALOG_HOSTING.md`. The URL MUST end with `/` so relative
/// `manifest.url` values resolve against it.
enum RemoteConfig {
    static let catalogBaseURL = URL(string: "https://jhoedeman.github.io/byzantine-trail-catalog/")!
}
