#!/usr/bin/env swift
//
// validate_catalog.swift — strict pre-publish gate for catalog.json (spec §3.3).
//
// Run:   swift Tools/validate_catalog.swift <catalog.json> [assetsRoot]
//        (assetsRoot is optional; when given, referenced `thumb` files are checked
//         to exist under it — e.g. ByzantineTrail/Resources)
//
// Exit:  0 = valid, 1 = validation problems found, 2 = usage / unreadable input.
//
// This mirrors ByzantineTrail/Core/Catalog/Site.swift but is INTENTIONALLY STRICTER
// than the app. The app tolerates unknown enum values for forward-compat
// (SiteType → .other, Importance → .minor); this gate instead catches authoring
// typos before they are published. `type` is deliberately NOT validated against the
// enum (spec §3.1-G: new type values are a feature, rendered as .other by old apps);
// `importance` IS validated because it is a fixed 3-value scale and a typo would
// silently degrade a site to "minor".
//
// Privacy: every string in the catalog is scanned for email addresses. Your personal
// email must never be published in this public reference data. The scan matches the
// email *pattern*, so no address is hardcoded in this (public) tool. An optional,
// git-ignored denylist (Tools/owner_denylist.txt, or $CATALOG_DENYLIST) can forbid
// additional specific substrings; names are fine unless you explicitly deny them.
//
import Foundation

// MARK: - Controlled vocabularies (also documented in docs/CATALOG_AUTHORING.md)

let allowedSemanticTags: Set<String> = ["unesco"]
let allowedEras: Set<String> = [
    "constantinian", "theodosian", "justinianic", "macedonian",
    "komnenian", "palaiologan", "other",
]
let allowedImportance: Set<String> = ["major", "notable", "minor"]

// MARK: - Parsing models (permissive shape; semantic checks run after decode)

struct VCoordinate: Decodable { let lat: Double; let lon: Double }
struct VPeriod: Decodable { let century: Int?; let era: String? }
struct VPhoto: Decodable {
    let id: String; let thumb: String; let full: String
    let caption: String?; let credit: String?
}
struct VLink: Decodable { let title: String; let url: String }
struct VCity: Decodable { let id: String; let name: String }

struct VSite: Decodable {
    let id: String
    let name: String
    let alternateNames: [String]?
    let type: String
    let country: String
    let cityId: String?
    let coordinate: VCoordinate
    let address: String?
    let importance: String
    let addedInVersion: Int?
    let period: VPeriod?
    let summary, description, hours, entryInfo: String?
    let photos: [VPhoto]?
    let semanticTags: [String]?
    let tags: [String]?
    let links: [VLink]?
}

struct VCatalog: Decodable {
    let schemaVersion: Int
    let catalogVersion: Int
    let generatedAt: String?
    let photoBaseURL: String
    let cities: [VCity]
    let sites: [VSite]
}

// MARK: - Small helpers

let stderr = FileHandle.standardError
func printErr(_ s: String) { stderr.write(Data((s + "\n").utf8)) }

var problems: [String] = []
func fail(_ msg: String) { problems.append(msg) }

// MARK: - CLI

let args = CommandLine.arguments
guard args.count >= 2 else {
    printErr("usage: validate_catalog <catalog.json> [assetsRoot]")
    exit(2)
}
let catalogPath = args[1]
let assetsRoot: String? = args.count >= 3 ? args[2] : nil

guard let rawData = FileManager.default.contents(atPath: catalogPath) else {
    printErr("error: cannot read file: \(catalogPath)")
    exit(2)
}
let rawText = String(decoding: rawData, as: UTF8.self)

// MARK: - Schema shape

let catalog: VCatalog
do {
    catalog = try JSONDecoder().decode(VCatalog.self, from: rawData)
} catch {
    printErr("✗ schema: catalog does not match the expected shape")
    printErr("  \(error)")
    printErr("✗ 1 problem found")
    exit(1)
}

// MARK: - Semantic checks

// (1) unique site ids
var seenSiteIDs = Set<String>()
for site in catalog.sites {
    if !seenSiteIDs.insert(site.id).inserted {
        fail("duplicate site id: \(site.id)")
    }
}

// (2) unique photo ids across the whole catalog
var seenPhotoIDs = Set<String>()
for site in catalog.sites {
    for photo in site.photos ?? [] {
        if !seenPhotoIDs.insert(photo.id).inserted {
            fail("duplicate photo id: \(photo.id) (site \(site.id))")
        }
    }
}

// (3) cityId resolves to a listed city (null is allowed)
let cityIDs = Set(catalog.cities.map(\.id))
for site in catalog.sites {
    if let cid = site.cityId, !cityIDs.contains(cid) {
        fail("site \(site.id): cityId '\(cid)' does not match any city")
    }
}

// (4) coordinate ranges
for site in catalog.sites {
    let c = site.coordinate
    if !(-90...90).contains(c.lat) {
        fail("site \(site.id): coordinate lat \(c.lat) out of range [-90, 90]")
    }
    if !(-180...180).contains(c.lon) {
        fail("site \(site.id): coordinate lon \(c.lon) out of range [-180, 180]")
    }
}

// (5) country is a valid ISO 3166-1 alpha-2 code
let isoCountries = Set(Locale.Region.isoRegions.map(\.identifier))
for site in catalog.sites {
    if !isoCountries.contains(site.country.uppercased()) {
        fail("site \(site.id): country '\(site.country)' is not a valid ISO 3166-1 alpha-2 code")
    }
}

// (6) semanticTags ⊆ controlled vocab
for site in catalog.sites {
    for tag in site.semanticTags ?? [] where !allowedSemanticTags.contains(tag) {
        fail("site \(site.id): unknown semanticTag '\(tag)' (allowed: \(allowedSemanticTags.sorted().joined(separator: ", ")))")
    }
}

// (7) period.era ⊆ controlled vocab
for site in catalog.sites {
    if let era = site.period?.era, !allowedEras.contains(era) {
        fail("site \(site.id): unknown period.era '\(era)' (allowed: \(allowedEras.sorted().joined(separator: ", ")))")
    }
}

// (8) importance ∈ controlled vocab (stricter than the app, by design)
for site in catalog.sites {
    if !allowedImportance.contains(site.importance) {
        fail("site \(site.id): unknown importance '\(site.importance)' (allowed: major, notable, minor)")
    }
}

// (9) addedInVersion ≤ catalogVersion
for site in catalog.sites {
    if let added = site.addedInVersion, added > catalog.catalogVersion {
        fail("site \(site.id): addedInVersion \(added) exceeds catalogVersion \(catalog.catalogVersion)")
    }
}

// (10) referenced thumb files exist (only when an assetsRoot is provided; `full`
//      resolves against the remote photoBaseURL and is out of scope for this gate)
if let root = assetsRoot {
    for site in catalog.sites {
        for photo in site.photos ?? [] {
            let path = (root as NSString).appendingPathComponent(photo.thumb)
            if !FileManager.default.fileExists(atPath: path) {
                fail("site \(site.id): photo '\(photo.id)' thumb file not found: \(photo.thumb) (looked in \(root))")
            }
        }
    }
}

// (11) no email addresses anywhere (privacy), plus optional denylist substrings
func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return re.matches(in: text, range: range).compactMap {
        Range($0.range, in: text).map { String(text[$0]) }
    }
}

let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
for hit in Set(matches(emailPattern, in: rawText)) {
    fail("email address found in catalog: '\(hit)' — remove it (personal email must never be published)")
}

// Optional git-ignored denylist: $CATALOG_DENYLIST, else ./Tools/owner_denylist.txt,
// else ./owner_denylist.txt. One case-insensitive substring per line; blank lines and
// lines starting with '#' are ignored.
func loadDenylist() -> [String] {
    let env = ProcessInfo.processInfo.environment["CATALOG_DENYLIST"]
    let candidates = [env, "Tools/owner_denylist.txt", "owner_denylist.txt"].compactMap { $0 }
    for path in candidates where FileManager.default.fileExists(atPath: path) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
    return []
}
let denylist = loadDenylist()
let lowerText = rawText.lowercased()
for term in denylist where lowerText.contains(term.lowercased()) {
    fail("denylisted string found in catalog: '\(term)'")
}

// MARK: - Report

if problems.isEmpty {
    var note = "✓ catalog valid — \(catalog.sites.count) sites, \(catalog.cities.count) cities, catalogVersion \(catalog.catalogVersion)"
    if assetsRoot == nil {
        note += "\n  (note: thumb-file existence not checked — pass an assetsRoot to enable)"
    }
    print(note)
    exit(0)
} else {
    for p in problems.sorted() { printErr("✗ \(p)") }
    printErr("✗ \(problems.count) problem\(problems.count == 1 ? "" : "s") found")
    exit(1)
}
