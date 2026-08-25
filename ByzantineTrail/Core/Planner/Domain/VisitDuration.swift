import Foundation

/// How long to budget inside a site, derived from `importance` and `type`.
///
/// Both fields are populated for all 581 catalog sites, so this needs no new
/// authoring. Results are rounded to five minutes on purpose: these are guesses
/// from two categorical fields, and "22 minutes" would imply a precision that
/// does not exist.
enum VisitDuration {
    /// Types that are a single object viewed from outside — a column, an arch.
    private static let singleObjectTypes: Set<SiteType> = [
        .column, .triumphalArch, .icon, .tower, .mausoleum, .aqueduct
    ]

    static func minutes(type: SiteType,
                        importance: Importance,
                        pace: Pace = .standard) -> Int {
        var value = base(importance)

        switch type {
        case .museum:
            // Museums consume time regardless of rank.
            value = max(value, 45)
        case .archaeologicalSite:
            // You walk a whole site, not a building.
            value *= 1.5
        case .monastery:
            // Multiple buildings, often an approach walk.
            value *= 1.25
        default:
            // Caps never apply to major sites. Without this the Theodosian Land
            // Walls — the only major cityWalls site — would get 30 minutes.
            if importance != .major {
                if singleObjectTypes.contains(type) {
                    value = min(value, 15)
                } else if type == .cityWalls {
                    value = min(value, 30)
                }
            }
        }

        return roundToFive(value * pace.multiplier)
    }

    private static func base(_ importance: Importance) -> Double {
        switch importance {
        case .major: 75
        case .notable: 30
        case .minor: 15
        }
    }

    /// Round half up to the nearest five, never below five.
    private static func roundToFive(_ value: Double) -> Int {
        let steps = (value / 5).rounded(.toNearestOrAwayFromZero)
        return max(5, Int(steps) * 5)
    }
}
