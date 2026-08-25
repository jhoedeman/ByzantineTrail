import Foundation

// All times in this file are MINUTES FROM MIDNIGHT: 540 == 09:00, 1080 == 18:00.

/// A commitment the day must work around — a train arrival, lunch, check-in.
/// Long-haul travel is declared this way rather than looked up; the planner
/// budgets around it and prices nothing.
struct FixedBlockSpec: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case arrival, departure, meal, lodging, custom
    }

    let kind: Kind
    let title: String
    let startMinutes: Int
    let durationMinutes: Int
}

/// One site placed on the clock.
struct PlannedStop: Equatable, Sendable {
    let site: PlannerSite
    let dwellMinutes: Int
    let arrivalMinutes: Int
    let departureMinutes: Int
    /// Travel FROM the previous stop. `nil` for the first stop of a day.
    let legTravelSeconds: Int?
}

/// A `FixedBlockSpec` placed on the clock.
struct PlannedBlock: Equatable, Sendable {
    let spec: FixedBlockSpec
    let startMinutes: Int
    let endMinutes: Int
}

/// One day of a trip.
struct PlannedDay: Equatable, Sendable {
    let stops: [PlannedStop]
    let blocks: [PlannedBlock]
    let windowStartMinutes: Int
    let windowEndMinutes: Int
    /// When the last stop ends. Equals `windowStartMinutes` for an empty day.
    let endMinutes: Int

    /// Free time left in the window after the last stop, with any block still
    /// ahead of that point deducted — a lunch never reached or a train home is
    /// time already spoken for, not room to spare. Blocks consumed during the
    /// day have already pushed `endMinutes` out, so they are not counted twice.
    /// Negative means the day does not fit.
    var slackMinutes: Int {
        let stillAhead = blocks.reduce(0) { total, block in
            let start = max(block.startMinutes, endMinutes)
            let end = min(block.endMinutes, windowEndMinutes)
            return total + max(0, end - start)
        }
        return windowEndMinutes - endMinutes - stillAhead
    }

    var dwellMinutes: Int { stops.reduce(0) { $0 + $1.dwellMinutes } }

    var travelMinutes: Int {
        stops.reduce(0) { $0 + ($1.legTravelSeconds.map { s in s / 60 } ?? 0) }
    }

    /// Time spent visiting plus time spent moving. Deliberately EXCLUDES
    /// blocks: the dwell ratio in `PlanDiagnostics` asks "am I seeing more than
    /// I'm travelling?", and counting lunch on either side of that would muddy
    /// the answer. So this is not the elapsed length of the day.
    var occupiedMinutes: Int { dwellMinutes + travelMinutes }
}

/// Everything the planner needs to build a trip.
struct TripRequest: Equatable, Sendable {
    let sites: [PlannerSite]
    let mode: TravelMode
    let pace: Pace
    let dayCount: Int
    let dayStartMinutes: Int
    let dayEndMinutes: Int
    /// Keyed by zero-based day index.
    let fixedBlocks: [Int: [FixedBlockSpec]]
    let includeLunch: Bool

    init(sites: [PlannerSite],
         mode: TravelMode,
         pace: Pace = .standard,
         dayCount: Int,
         dayStartMinutes: Int = 540,
         dayEndMinutes: Int = 1_080,
         fixedBlocks: [Int: [FixedBlockSpec]] = [:],
         includeLunch: Bool = true) {
        self.sites = sites
        self.mode = mode
        self.pace = pace
        self.dayCount = dayCount
        self.dayStartMinutes = dayStartMinutes
        self.dayEndMinutes = dayEndMinutes
        self.fixedBlocks = fixedBlocks
        self.includeLunch = includeLunch
    }
}

/// The planner's output.
struct PlannedTrip: Equatable, Sendable {
    let days: [PlannedDay]
    let diagnostics: [PlanDiagnostic]
    /// Sites that did not fit in `dayCount` days.
    let unplacedSiteIds: [String]
}
