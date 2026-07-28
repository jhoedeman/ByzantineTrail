import Foundation

/// Persistence seam for suggestion submission timestamps (M5c rate limit).
/// Injected so `SuggestionStore` is testable with no I/O. Main-actor use only.
protocol SuggestionThrottleStoring {
    func load() -> [Date]
    func save(_ timestamps: [Date])
}

struct UserDefaultsSuggestionThrottleStore: SuggestionThrottleStoring {
    private let key = "byzantinetrail.suggest.timestamps"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [Date] {
        let raw = defaults.array(forKey: key) as? [Double] ?? []
        return raw.map { Date(timeIntervalSince1970: $0) }
    }
    func save(_ timestamps: [Date]) {
        defaults.set(timestamps.map { $0.timeIntervalSince1970 }, forKey: key)
    }
}

/// In-memory throttle store for tests.
final class InMemorySuggestionThrottleStore: SuggestionThrottleStoring {
    private var timestamps: [Date]
    init(_ timestamps: [Date] = []) { self.timestamps = timestamps }
    func load() -> [Date] { timestamps }
    func save(_ timestamps: [Date]) { self.timestamps = timestamps }
}
