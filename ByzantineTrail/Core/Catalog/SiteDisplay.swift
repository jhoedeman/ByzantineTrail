import SwiftUI

extension SiteType {
    var displayLabel: String {
        switch self {
        case .church: "Church"
        case .monastery: "Monastery"
        case .fortress: "Fortress"
        case .palace: "Palace"
        case .cityWalls: "City Walls"
        case .cistern: "Cistern"
        case .aqueduct: "Aqueduct"
        case .mosaicSite: "Mosaic Site"
        case .archaeologicalSite: "Archaeological Site"
        case .museum: "Museum"
        case .tower: "Tower"
        case .bridge: "Bridge"
        case .column: "Column"
        case .triumphalArch: "Triumphal Arch"
        case .mausoleum: "Mausoleum"
        case .baptistery: "Baptistery"
        case .icon: "Icon"
        case .other: "Site"
        }
    }

    /// SF Symbol name for the type icon.
    var iconName: String {
        switch self {
        case .church: "building.columns"
        case .monastery: "building.2"
        case .fortress: "shield"
        case .palace: "crown"
        case .cityWalls: "square.split.bottomrightquarter"
        case .cistern: "drop"
        case .aqueduct: "water.waves"
        case .mosaicSite: "square.grid.3x3.fill"
        case .archaeologicalSite: "building.columns.circle"
        case .museum: "building.columns"
        case .tower: "building"
        case .bridge: "road.lanes"
        case .column: "building.columns"
        case .triumphalArch: "building.2.crop.circle"
        case .mausoleum: "house.lodge"
        case .baptistery: "drop.circle"
        case .icon: "photo.artframe"
        case .other: "mappin"
        }
    }
}

extension Importance {
    var displayLabel: String {
        switch self {
        case .major: "Major"
        case .notable: "Notable"
        case .minor: "Minor"
        }
    }

    /// Sort rank — lower is more important.
    var rank: Int {
        switch self {
        case .major: 0
        case .notable: 1
        case .minor: 2
        }
    }

    func tierColor(_ theme: Theme) -> Color {
        switch self {
        case .major: theme.tierMajor
        case .notable: theme.tierNotable
        case .minor: theme.tierMinor
        }
    }
}

enum CountryName {
    /// Valid ISO 3166-1 alpha-2 codes, cached once. Non-deprecated replacement
    /// for `Locale.isoRegionCodes`; a Set also avoids the per-call O(n) scan.
    private static let isoRegionCodes: Set<String> = Set(Locale.Region.isoRegions.map(\.identifier))

    /// Editorial display overrides for specific ISO codes, applied ahead of the system
    /// localization. `TR` localizes to "Türkiye" on recent OS versions; we render "Turkey".
    private static let displayOverrides: [String: String] = ["TR": "Turkey"]

    /// ISO 3166-1 alpha-2 → localized region name; falls back to the code.
    ///
    /// Non-ISO inputs (e.g. a disputed-territory label like "Crimea (disputed)") pass
    /// through verbatim, so this doubles as the label function for any country grouping key.
    ///
    /// `Locale.current.localizedString(forRegionCode:)` alone is not sufficient: on some
    /// OS versions it returns a generic "Unknown Region" string (rather than `nil`) for
    /// codes that are well-formed but not assigned, so unrecognized codes must be filtered
    /// out via the cached ISO region set before localizing.
    static func localized(_ code: String) -> String {
        if let override = displayOverrides[code] { return override }
        guard isoRegionCodes.contains(code) else { return code }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
