import Testing
@testable import ByzantineTrail

struct FilterSummaryTests {
    @Test func emptyGivesEmptyString() {
        #expect(FilterSummary.summarize([]) == "")
    }

    @Test func oneName() {
        #expect(FilterSummary.summarize(["Church"]) == "Church")
    }

    @Test func twoNames() {
        #expect(FilterSummary.summarize(["Church", "Monastery"]) == "Church, Monastery")
    }

    @Test func threeOrMoreAppendsOverflowCount() {
        #expect(FilterSummary.summarize(["Church", "Monastery", "Fortress"])
                == "Church, Monastery +1")
        #expect(FilterSummary.summarize(["A", "B", "C", "D"]) == "A, B +2")
    }
}
