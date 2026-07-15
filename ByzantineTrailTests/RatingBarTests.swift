import Testing
@testable import ByzantineTrail

struct RatingBarTests {
    @Test func tenSegments() { #expect(RatingScale.count == 10) }

    @Test func segmentMapsToOneBasedRating() {
        #expect(RatingScale.rating(forSegment: 0) == 1)
        #expect(RatingScale.rating(forSegment: 9) == 10)
    }

    @Test func fillsUpToValue() {
        #expect(RatingScale.isFilled(segment: 0, for: 3))   // rating 1 ≤ 3
        #expect(RatingScale.isFilled(segment: 2, for: 3))   // rating 3 ≤ 3
        #expect(!RatingScale.isFilled(segment: 3, for: 3))  // rating 4 > 3
    }

    @Test func nothingFilledForNil() {
        #expect(!RatingScale.isFilled(segment: 0, for: nil))
    }
}
