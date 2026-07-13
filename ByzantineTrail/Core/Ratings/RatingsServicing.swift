struct RatingSummary: Equatable, Sendable {
    let siteId: String
    let count, total: Int
    var average: Double { count == 0 ? 0 : Double(total) / Double(count) }
}

protocol RatingsServicing: Sendable {
    func summary(for siteId: String) async throws -> RatingSummary?
    func submit(rating: Int, for siteId: String) async throws
}
