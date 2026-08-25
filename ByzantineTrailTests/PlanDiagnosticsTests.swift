import Testing
@testable import ByzantineTrail

struct PlanDiagnosticsTests {
    private func site(_ id: String) -> PlannerSite {
        PlannerSite(id: id, name: id, coordinate: Coordinate(lat: 0, lon: 0),
                    cityId: "c", type: .church, importance: .notable)
    }

    private func day(dwells: [Int], legMinutes: [Int],
                     start: Int = 540, end: Int = 1_080) -> PlannedDay {
        TimeBudget.layOut(
            stops: dwells.enumerated().map { (site: site("s\($0.offset)"),
                                              dwellMinutes: $0.element) },
            legSeconds: legMinutes.map { $0 * 60 },
            windowStartMinutes: start, windowEndMinutes: end, blocks: [])
    }

    // MARK: tightness boundaries

    @Test func tightnessBands() {
        // Window of 540 minutes: 25% is 135, 10% is 54.
        #expect(PlanDiagnostics.tightness(slackMinutes: 200, windowMinutes: 540) == .relaxed)
        #expect(PlanDiagnostics.tightness(slackMinutes: 100, windowMinutes: 540) == .comfortable)
        #expect(PlanDiagnostics.tightness(slackMinutes: 20, windowMinutes: 540) == .tight)
        #expect(PlanDiagnostics.tightness(slackMinutes: -30, windowMinutes: 540) == .over)
    }

    @Test func tightnessAtExactBoundaries() {
        #expect(PlanDiagnostics.tightness(slackMinutes: 135, windowMinutes: 540) == .comfortable)
        #expect(PlanDiagnostics.tightness(slackMinutes: 136, windowMinutes: 540) == .relaxed)
        #expect(PlanDiagnostics.tightness(slackMinutes: 54, windowMinutes: 540) == .comfortable)
        #expect(PlanDiagnostics.tightness(slackMinutes: 53, windowMinutes: 540) == .tight)
        #expect(PlanDiagnostics.tightness(slackMinutes: 0, windowMinutes: 540) == .tight)
        #expect(PlanDiagnostics.tightness(slackMinutes: -1, windowMinutes: 540) == .over)
    }

    @Test func tightnessWithAZeroWindowIsOverRatherThanACrash() {
        #expect(PlanDiagnostics.tightness(slackMinutes: 0, windowMinutes: 0) == .over)
    }

    // MARK: overrun

    @Test func anOverrunningDayIsReported() {
        let d = day(dwells: [300, 300], legMinutes: [60])   // ends 1200, window 1080
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1, mode: .walking)
        #expect(found.contains(.dayOverruns(dayIndex: 0, byMinutes: 120)))
    }

    @Test func aDayThatFitsIsNotReportedAsOverrunning() {
        let d = day(dwells: [75, 30], legMinutes: [20])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1, mode: .walking)
        #expect(!found.contains { if case .dayOverruns = $0 { true } else { false } })
    }

    // MARK: dwell ratio

    @Test func moreTravelThanVisitingIsReported() {
        // 60 minutes inside sites, 240 travelling: ratio 20%.
        let d = day(dwells: [30, 30], legMinutes: [240])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1, mode: .walking)
        #expect(found.contains(.lowDwellRatio(dayIndex: 0, percent: 20)))
    }

    @Test func aHealthyDwellRatioIsNotReported() {
        // 285 minutes inside, 36 travelling: ratio 89%.
        let d = day(dwells: [75, 75, 45, 30, 30, 15, 15], legMinutes: [6, 6, 6, 6, 6, 6])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1, mode: .walking)
        #expect(!found.contains { if case .lowDwellRatio = $0 { true } else { false } })
    }

    @Test func dwellRatioFloorIsFiftyPercent() {
        #expect(PlanDiagnostics.dwellRatioFloor == 0.50)
    }

    // MARK: slack and outliers

    @Test func aDayWithLotsOfRoomOffersToFillIt() {
        let d = day(dwells: [30], legMinutes: [])   // ends 570, slack 510
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1, mode: .walking)
        #expect(found.contains(.largeSlack(dayIndex: 0, freeMinutes: 510)))
    }

    @Test func aStopMilesFromTheRestIsFlagged() {
        let d = day(dwells: [30, 30, 30], legMinutes: [10, 120])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1, mode: .walking)
        #expect(found.contains(.outlierStop(dayIndex: 0, siteId: "s2", travelMinutes: 120)))
    }

    @Test func outlierThresholdIsNinetyMinutes() {
        #expect(PlanDiagnostics.outlierTravelMinutes == 90)
    }

    // MARK: trip-level

    @Test func moreCitiesThanDaysIsReported() {
        let d = day(dwells: [30], legMinutes: [])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 3, dayCount: 2, mode: .walking)
        #expect(found.contains(.tooManyPlacesForDays(placeCount: 3, dayCount: 2)))
    }

    @Test func enoughDaysForTheCitiesIsNotReported() {
        let d = day(dwells: [30], legMinutes: [])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 2, dayCount: 3, mode: .walking)
        #expect(!found.contains { if case .tooManyPlacesForDays = $0 { true } else { false } })
    }

    @Test func anEmptyTripProducesNoDiagnostics() {
        #expect(PlanDiagnostics.evaluate(days: [], placeCount: 0, dayCount: 0, mode: .walking).isEmpty)
    }

    // MARK: dropped sites and mode

    @Test func droppedSitesAreReported() {
        let d = day(dwells: [30], legMinutes: [])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1,
                                             mode: .walking, unplacedSiteIds: ["a", "b"])
        #expect(found.contains(.sitesDidNotFit(siteIds: ["a", "b"])))
    }

    @Test func nothingDroppedProducesNoSuchDiagnostic() {
        let d = day(dwells: [30], legMinutes: [])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1, mode: .walking)
        #expect(!found.contains { if case .sitesDidNotFit = $0 { true } else { false } })
    }

    @Test func aLongWalkSuggestsChangingMode() {
        let d = day(dwells: [30, 30], legMinutes: [75])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1,
                                             mode: .walking)
        #expect(found.contains(.modeTooSlow(dayIndex: 0, siteId: "s1", travelMinutes: 75)))
    }

    @Test func drivingTheSameLegIsNotFlagged() {
        let d = day(dwells: [30, 30], legMinutes: [75])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1,
                                             mode: .driving)
        #expect(!found.contains { if case .modeTooSlow = $0 { true } else { false } })
    }

    @Test func walkingLegCeilingIsAnHour() {
        #expect(PlanDiagnostics.walkingLegCeilingMinutes == 60)
    }

    @Test func aVeryLongWalkFlagsBothTheOutlierAndTheMode() {
        let d = day(dwells: [30, 30], legMinutes: [120])
        let found = PlanDiagnostics.evaluate(days: [d], placeCount: 1, dayCount: 1,
                                             mode: .walking)
        #expect(found.contains(.outlierStop(dayIndex: 0, siteId: "s1", travelMinutes: 120)))
        #expect(found.contains(.modeTooSlow(dayIndex: 0, siteId: "s1", travelMinutes: 120)))
    }
}
