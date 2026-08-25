import Foundation

/// How much room a day has left.
enum Tightness: String, Equatable, Sendable {
    case relaxed, comfortable, tight, over
}

/// A condition worth telling the user about, with enough data for the UI to
/// write a specific sentence and offer a specific remedy (spec §6).
enum PlanDiagnostic: Equatable, Sendable {
    case tooManyCitiesForDays(cityCount: Int, dayCount: Int)
    case dayOverruns(dayIndex: Int, byMinutes: Int)
    case lowDwellRatio(dayIndex: Int, percent: Int)
    case largeSlack(dayIndex: Int, freeMinutes: Int)
    case outlierStop(dayIndex: Int, siteId: String, travelMinutes: Int)
    case sitesDidNotFit(siteIds: [String])
    case modeTooSlow(dayIndex: Int, siteId: String, travelMinutes: Int)
}

/// Detects the conditions in spec §6. Needs no opening-hours data and no
/// network — everything here follows from geometry and the clock.
enum PlanDiagnostics {
    /// Below this share of the day spent inside sites, warn that the trip is
    /// mostly travelling.
    static let dwellRatioFloor = 0.50
    /// A single leg longer than this makes its stop an outlier.
    static let outlierTravelMinutes = 90
    /// Slack above this share of the window is worth offering to fill.
    static let largeSlackFraction = 0.25
    /// A walking leg longer than this is a suggestion to change mode, not just
    /// a long walk. Distinct from `outlierTravelMinutes`, which asks whether a
    /// stop belongs on this day at all.
    static let walkingLegCeilingMinutes = 60

    static func tightness(slackMinutes: Int, windowMinutes: Int) -> Tightness {
        guard windowMinutes > 0 else { return .over }
        if slackMinutes < 0 { return .over }
        let fraction = Double(slackMinutes) / Double(windowMinutes)
        if fraction > 0.25 { return .relaxed }
        if fraction >= 0.10 { return .comfortable }
        return .tight
    }

    static func evaluate(days: [PlannedDay],
                         cityCount: Int,
                         dayCount: Int,
                         mode: TravelMode = .walking,
                         unplacedSiteIds: [String] = []) -> [PlanDiagnostic] {
        var found: [PlanDiagnostic] = []

        if cityCount > dayCount, dayCount > 0 {
            found.append(.tooManyCitiesForDays(cityCount: cityCount, dayCount: dayCount))
        }

        if !unplacedSiteIds.isEmpty {
            found.append(.sitesDidNotFit(siteIds: unplacedSiteIds))
        }

        for (index, day) in days.enumerated() {
            if day.slackMinutes < 0 {
                found.append(.dayOverruns(dayIndex: index, byMinutes: -day.slackMinutes))
            }

            let occupied = day.occupiedMinutes
            if occupied > 0 {
                let ratio = Double(day.dwellMinutes) / Double(occupied)
                if ratio < dwellRatioFloor {
                    found.append(.lowDwellRatio(dayIndex: index,
                                                percent: Int((ratio * 100).rounded())))
                }
            }

            let window = day.windowEndMinutes - day.windowStartMinutes
            if window > 0, day.slackMinutes > 0,
               Double(day.slackMinutes) / Double(window) > largeSlackFraction {
                found.append(.largeSlack(dayIndex: index, freeMinutes: day.slackMinutes))
            }

            for stop in day.stops {
                guard let seconds = stop.legTravelSeconds else { continue }
                let minutes = seconds / 60
                if minutes > outlierTravelMinutes {
                    found.append(.outlierStop(dayIndex: index,
                                              siteId: stop.site.id,
                                              travelMinutes: minutes))
                }
                if mode == .walking, minutes > walkingLegCeilingMinutes {
                    found.append(.modeTooSlow(dayIndex: index,
                                              siteId: stop.site.id,
                                              travelMinutes: minutes))
                }
            }
        }

        return found
    }
}
