import Foundation

/// Turns a `TripRequest` into a `PlannedTrip`.
///
/// Synchronous and deterministic: the same request always produces the same
/// trip. Real routes and their polylines are layered on afterwards by M7b,
/// which replaces the estimated leg times without re-ordering anything.
enum ItineraryPlanner {
    static let defaultLunch = FixedBlockSpec(kind: .meal, title: "Lunch",
                                             startMinutes: 780, durationMinutes: 60)

    static func plan(_ request: TripRequest,
                     estimator: any TravelEstimating = HaversineEstimator()) -> PlannedTrip {
        guard !request.sites.isEmpty, request.dayCount > 0 else {
            let unplaced = request.dayCount > 0 ? [] : request.sites.map(\.id)
            return PlannedTrip(days: [],
                               diagnostics: unplaced.isEmpty ? [] : [.sitesDidNotFit(siteIds: unplaced)],
                               unplacedSiteIds: unplaced)
        }

        let clusters = DayClusterer.order(DayClusterer.cluster(request.sites),
                                          mode: request.mode, estimator: estimator)

        var days: [PlannedDay] = []
        var unplaced: [String] = []
        var dayIndex = 0

        for cluster in clusters {
            guard dayIndex < request.dayCount else {
                unplaced.append(contentsOf: cluster.sites.map(\.id))
                continue
            }

            // Order the whole cluster once, then take it a day at a time. A
            // city bigger than one day spills into the next, which is what
            // "three days in Rome" needs.
            var remaining = ArraySlice(orderedSites(of: cluster,
                                                    request: request,
                                                    estimator: estimator))

            while !remaining.isEmpty && dayIndex < request.dayCount {
                let take = prefixThatFits(Array(remaining), dayIndex: dayIndex,
                                          request: request, estimator: estimator)
                days.append(buildDay(sites: Array(remaining.prefix(take)),
                                     dayIndex: dayIndex,
                                     request: request,
                                     estimator: estimator))
                remaining = remaining.dropFirst(take)
                dayIndex += 1
            }

            // Whatever is still left had no day to go in. Reported, not dropped.
            unplaced.append(contentsOf: remaining.map(\.id))
        }

        let diagnostics = PlanDiagnostics.evaluate(days: days,
                                                   placeCount: clusters.count,
                                                   dayCount: request.dayCount,
                                                   mode: request.mode,
                                                   unplacedSiteIds: unplaced)

        return PlannedTrip(days: days,
                           diagnostics: diagnostics,
                           unplacedSiteIds: unplaced)
    }

    private static func orderedSites(of cluster: SiteCluster,
                                     request: TripRequest,
                                     estimator: any TravelEstimating) -> [PlannerSite] {
        let order = StopSequencer.sequence(coordinates: cluster.sites.map(\.coordinate),
                                           mode: request.mode,
                                           estimator: estimator)
        return order.map { cluster.sites[$0] }
    }

    /// How many stops from the front of `sites` fit inside one day window.
    /// Always at least one — a day with a single oversized stop is allowed to
    /// overrun and be flagged, but the planner must never loop forever.
    private static func prefixThatFits(_ sites: [PlannerSite],
                                       dayIndex: Int,
                                       request: TripRequest,
                                       estimator: any TravelEstimating) -> Int {
        let window = request.dayEndMinutes - request.dayStartMinutes
        var used = request.includeLunch ? defaultLunch.durationMinutes : 0
        // Declared blocks consume the day as surely as lunch does. Budgeting for
        // lunch alone packs a day that then overruns the moment an arrival or
        // departure is laid onto the clock.
        used += (request.fixedBlocks[dayIndex] ?? []).reduce(0) { $0 + $1.durationMinutes }
        var count = 0

        for (index, site) in sites.enumerated() {
            var addition = VisitDuration.minutes(type: site.type,
                                                 importance: site.importance,
                                                 pace: request.pace)
            if index > 0 {
                addition += Int(estimator.seconds(from: sites[index - 1].coordinate,
                                                  to: site.coordinate,
                                                  mode: request.mode).rounded()) / 60
            }
            if count > 0 && used + addition > window { break }
            used += addition
            count += 1
        }
        return max(1, count)
    }

    private static func buildDay(sites ordered: [PlannerSite],
                                 dayIndex: Int,
                                 request: TripRequest,
                                 estimator: any TravelEstimating) -> PlannedDay {
        let stops = ordered.map { site in
            (site: site,
             dwellMinutes: VisitDuration.minutes(type: site.type,
                                                 importance: site.importance,
                                                 pace: request.pace))
        }

        var legSeconds: [Int] = []
        for i in 0..<max(0, ordered.count - 1) {
            legSeconds.append(Int(estimator.seconds(from: ordered[i].coordinate,
                                                    to: ordered[i + 1].coordinate,
                                                    mode: request.mode).rounded()))
        }

        var blocks = request.fixedBlocks[dayIndex] ?? []
        if request.includeLunch { blocks.append(defaultLunch) }

        return TimeBudget.layOut(stops: stops,
                                 legSeconds: legSeconds,
                                 windowStartMinutes: request.dayStartMinutes,
                                 windowEndMinutes: request.dayEndMinutes,
                                 blocks: blocks)
    }
}
