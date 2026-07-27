import Testing
@testable import ByzantineTrail

struct RatingMathTests {
    private func summary(_ count: Int, _ total: Int) -> RatingSummary {
        RatingSummary(siteId: "s", count: count, total: total)
    }

    @Test func applyDeltaNewRating() {
        let out = RatingMath.applyDelta(to: summary(2, 14), old: nil, new: 8)
        #expect(out.count == 3)
        #expect(out.total == 22)
    }

    @Test func applyDeltaChangedRating() {
        let out = RatingMath.applyDelta(to: summary(3, 22), old: 8, new: 5)
        #expect(out.count == 3)      // count unchanged when editing
        #expect(out.total == 19)     // 22 - 8 + 5
    }

    @Test func applyDeltaRemoval() {
        let out = RatingMath.applyDelta(to: summary(3, 22), old: 8, new: nil)
        #expect(out.count == 2)
        #expect(out.total == 14)
    }

    @Test func applyDeltaRemovalNeverGoesNegative() {
        let out = RatingMath.applyDelta(to: summary(0, 0), old: 8, new: nil)
        #expect(out.count == 0)
        #expect(out.total == 0)
    }

    @Test func recomputeFromValues() {
        let out = RatingMath.recompute(siteId: "s", values: [8, 6, 10])
        #expect(out.count == 3)
        #expect(out.total == 24)
        #expect(out.average == 8.0)
    }

    @Test func recomputeEmpty() {
        let out = RatingMath.recompute(siteId: "s", values: [])
        #expect(out.count == 0)
        #expect(out.average == 0)
    }

    @Test func needsReconcileDetectsDrift() {
        #expect(RatingMath.needsReconcile(cached: summary(3, 22), recomputed: summary(3, 24)))
        #expect(!RatingMath.needsReconcile(cached: summary(3, 24), recomputed: summary(3, 24)))
    }
}
