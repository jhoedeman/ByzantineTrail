import Foundation

/// Lays an ordered list of stops onto the clock.
///
/// Deliberately dumb: it never invents a meal break or reorders anything. The
/// caller supplies blocks (including lunch) as `FixedBlockSpec`s, which keeps
/// this a pure, exhaustively testable function.
enum TimeBudget {
    static func layOut(stops: [(site: PlannerSite, dwellMinutes: Int)],
                       legSeconds: [Int],
                       windowStartMinutes: Int,
                       windowEndMinutes: Int,
                       blocks: [FixedBlockSpec]) -> PlannedDay {
        var clock = windowStartMinutes
        var placedStops: [PlannedStop] = []
        var placedBlocks: [PlannedBlock] = []
        var pending = blocks.sorted { $0.startMinutes < $1.startMinutes }

        for (index, stop) in stops.enumerated() {
            // Consume any block that has come due BEFORE travelling on. You eat
            // lunch when you finish the previous site, not after walking to the
            // next one.
            while let next = pending.first, next.startMinutes <= clock {
                pending.removeFirst()
                let start = max(next.startMinutes, clock)
                placedBlocks.append(PlannedBlock(spec: next,
                                                 startMinutes: start,
                                                 endMinutes: start + next.durationMinutes))
                clock = start + next.durationMinutes
            }

            // Travel in from the previous stop.
            let leg: Int? = index == 0 ? nil : legSeconds[safe: index - 1]
            if let leg { clock += leg / 60 }

            let arrival = clock
            let departure = arrival + stop.dwellMinutes
            placedStops.append(PlannedStop(site: stop.site,
                                           dwellMinutes: stop.dwellMinutes,
                                           arrivalMinutes: arrival,
                                           departureMinutes: departure,
                                           legTravelSeconds: leg))
            clock = departure
        }

        // Blocks that never came due still belong on the day, at their own time.
        for spec in pending {
            placedBlocks.append(PlannedBlock(spec: spec,
                                             startMinutes: spec.startMinutes,
                                             endMinutes: spec.startMinutes + spec.durationMinutes))
        }
        placedBlocks.sort { $0.startMinutes < $1.startMinutes }

        return PlannedDay(stops: placedStops,
                          blocks: placedBlocks,
                          windowStartMinutes: windowStartMinutes,
                          windowEndMinutes: windowEndMinutes,
                          endMinutes: placedStops.last?.departureMinutes ?? windowStartMinutes)
    }
}

private extension Array {
    /// Bounds-checked read. `legSeconds` is caller-supplied and may be short.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
