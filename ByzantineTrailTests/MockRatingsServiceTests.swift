import Testing
@testable import ByzantineTrail

struct MockRatingsServiceTests {
    @Test func submitFromEmptyCreatesRating() async throws {
        let svc = MockRatingsService()
        let summary = try await svc.submit(rating: 8, for: "s")
        #expect(summary.count == 1)
        #expect(summary.total == 8)
        let state = try await svc.load(for: "s")
        #expect(state.mine == 8)
        #expect(state.summary?.count == 1)
    }

    @Test func resubmitEditsWithoutInflatingCount() async throws {
        let svc = MockRatingsService()
        _ = try await svc.submit(rating: 8, for: "s")
        let summary = try await svc.submit(rating: 5, for: "s")
        #expect(summary.count == 1)
        #expect(summary.total == 5)
        #expect(try await svc.load(for: "s").mine == 5)
    }

    @Test func removeClearsMineAndDecrements() async throws {
        let svc = MockRatingsService()
        _ = try await svc.submit(rating: 8, for: "s")
        let summary = try await svc.removeRating(for: "s")
        #expect(summary.count == 0)
        #expect(try await svc.load(for: "s").mine == nil)
    }

    @Test func submitStacksOnSeededOthers() async throws {
        let svc = MockRatingsService(seed: ["s": RatingSummary(siteId: "s", count: 2, total: 14)])
        let summary = try await svc.submit(rating: 10, for: "s")
        #expect(summary.count == 3)     // 2 seeded others + me
        #expect(summary.total == 24)
    }

    @Test func allSummariesReturnsSeeded() async throws {
        let svc = MockRatingsService(seed: ["a": RatingSummary(siteId: "a", count: 1, total: 9)])
        let all = try await svc.allSummaries()
        #expect(all["a"]?.total == 9)
    }
}
