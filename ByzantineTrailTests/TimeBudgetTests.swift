import Testing
@testable import ByzantineTrail

struct TimeBudgetTests {
    private func site(_ id: String) -> PlannerSite {
        PlannerSite(id: id, name: id, coordinate: Coordinate(lat: 0, lon: 0),
                    cityId: "c", type: .church, importance: .notable)
    }

    private func layOut(dwells: [Int],
                        legMinutes: [Int],
                        start: Int = 540,
                        end: Int = 1080,
                        blocks: [FixedBlockSpec] = []) -> PlannedDay {
        TimeBudget.layOut(
            stops: dwells.enumerated().map { (site: site("s\($0.offset)"),
                                              dwellMinutes: $0.element) },
            legSeconds: legMinutes.map { $0 * 60 },
            windowStartMinutes: start,
            windowEndMinutes: end,
            blocks: blocks)
    }

    // MARK: the clock chain

    @Test func firstStopStartsAtTheWindowOpening() {
        let day = layOut(dwells: [30], legMinutes: [])
        #expect(day.stops[0].arrivalMinutes == 540)
        #expect(day.stops[0].departureMinutes == 570)
        #expect(day.stops[0].legTravelSeconds == nil)
    }

    @Test func laterStopsChainThroughTheirTravelLegs() {
        let day = layOut(dwells: [75, 30, 15], legMinutes: [22, 14])
        #expect(day.stops[0].arrivalMinutes == 540)   // 09:00
        #expect(day.stops[0].departureMinutes == 615) // 10:15
        #expect(day.stops[1].arrivalMinutes == 637)   // +22 min walk
        #expect(day.stops[1].departureMinutes == 667)
        #expect(day.stops[2].arrivalMinutes == 681)   // +14 min walk
        #expect(day.stops[2].departureMinutes == 696)
        #expect(day.endMinutes == 696)
    }

    @Test func legTravelSecondsArePreservedOnEachStop() {
        let day = layOut(dwells: [30, 30], legMinutes: [22])
        #expect(day.stops[0].legTravelSeconds == nil)
        #expect(day.stops[1].legTravelSeconds == 1_320)
    }

    // MARK: blocks

    @Test func aBlockIsConsumedOnceItsStartTimeIsReached() {
        let lunch = FixedBlockSpec(kind: .meal, title: "Lunch",
                                   startMinutes: 780, durationMinutes: 60)
        let day = layOut(dwells: [75, 75, 30], legMinutes: [30, 30], blocks: [lunch])
        // 540 +75 = 615, +30 = 645, +75 = 720, +30 travel = 750.
        // 750 < 780, so the third stop begins before lunch is due.
        #expect(day.stops[2].arrivalMinutes == 750)
        #expect(day.blocks.count == 1)
        #expect(day.blocks[0].startMinutes == 780)
        #expect(day.blocks[0].endMinutes == 840)
    }

    @Test func aDueBlockPushesTheFollowingStopLater() {
        let lunch = FixedBlockSpec(kind: .meal, title: "Lunch",
                                   startMinutes: 600, durationMinutes: 60)
        let day = layOut(dwells: [75, 30], legMinutes: [15], blocks: [lunch])
        // Stop 0: 540-615. Clock 615 >= 600, so lunch runs 615-675.
        // Then the 15-minute leg, so stop 1 arrives at 690.
        #expect(day.blocks[0].startMinutes == 615)
        #expect(day.blocks[0].endMinutes == 675)
        #expect(day.stops[1].arrivalMinutes == 690)
    }

    @Test func blocksNeverDueAreStillReportedAtTheirRequestedTime() {
        let arrival = FixedBlockSpec(kind: .arrival, title: "Train",
                                     startMinutes: 1_020, durationMinutes: 30)
        let day = layOut(dwells: [30], legMinutes: [], blocks: [arrival])
        #expect(day.blocks.count == 1)
        #expect(day.blocks[0].startMinutes == 1_020)
    }

    @Test func consumedAndNeverDueBlocksComeBackInTimeOrder() {
        let lunch = FixedBlockSpec(kind: .meal, title: "Lunch",
                                   startMinutes: 600, durationMinutes: 60)
        let departure = FixedBlockSpec(kind: .departure, title: "Train",
                                       startMinutes: 1_020, durationMinutes: 30)
        // Passed in reverse time order to prove the result is sorted, not echoed.
        let day = layOut(dwells: [75, 30], legMinutes: [15], blocks: [departure, lunch])
        #expect(day.blocks.count == 2)
        #expect(day.blocks.map(\.spec.kind) == [.meal, .departure])
        #expect(day.blocks[0].startMinutes == 615)    // consumed once the clock reached it
        #expect(day.blocks[1].startMinutes == 1_020)  // never came due; keeps its requested time
    }

    // MARK: totals

    @Test func totalsAddUp() {
        let day = layOut(dwells: [75, 30, 15], legMinutes: [22, 14])
        #expect(day.dwellMinutes == 120)
        #expect(day.travelMinutes == 36)
        #expect(day.occupiedMinutes == 156)
    }

    @Test func slackIsWhatRemainsInTheWindow() {
        let day = layOut(dwells: [75, 30, 15], legMinutes: [22, 14])
        #expect(day.endMinutes == 696)
        #expect(day.slackMinutes == 1_080 - 696)   // 384
    }

    @Test func anOverrunningDayHasNegativeSlack() {
        let day = layOut(dwells: [300, 300], legMinutes: [60])
        #expect(day.endMinutes == 1_200)
        #expect(day.slackMinutes == -120)
    }

    @Test func slackExcludesBlockTimeStillAhead() {
        let train = FixedBlockSpec(kind: .departure, title: "Train home",
                                   startMinutes: 1_020, durationMinutes: 30)
        let day = layOut(dwells: [30], legMinutes: [], blocks: [train])
        #expect(day.endMinutes == 570)
        #expect(day.slackMinutes == 480)   // 1080 - 570, less the 30 the train takes
    }

    @Test func slackDoesNotDoubleCountAConsumedBlock() {
        let lunch = FixedBlockSpec(kind: .meal, title: "Lunch",
                                   startMinutes: 600, durationMinutes: 60)
        let day = layOut(dwells: [75, 30], legMinutes: [15], blocks: [lunch])
        #expect(day.endMinutes == 720)     // lunch already pushed the day out
        #expect(day.slackMinutes == 360)   // 1080 - 720, nothing further deducted
    }

    @Test func overlappingBlocksCannotManufactureAnOverrun() {
        let arrival = FixedBlockSpec(kind: .arrival, title: "Ferry",
                                     startMinutes: 1_020, durationMinutes: 60)
        let checkIn = FixedBlockSpec(kind: .lodging, title: "Check in",
                                     startMinutes: 1_020, durationMinutes: 60)
        let day = layOut(dwells: [30], legMinutes: [], blocks: [arrival, checkIn])
        #expect(day.endMinutes == 570)
        #expect(day.slackMinutes >= 0)
    }

    // MARK: degenerate inputs

    @Test func emptyDayEndsWhenItStarts() {
        let day = layOut(dwells: [], legMinutes: [])
        #expect(day.stops.isEmpty)
        #expect(day.endMinutes == 540)
        #expect(day.slackMinutes == 540)
    }

    @Test func aSingleStopHasNoLegs() {
        let day = layOut(dwells: [45], legMinutes: [])
        #expect(day.stops.count == 1)
        #expect(day.travelMinutes == 0)
    }
}
