import Foundation

/// Persistence seam for the pull sync token. Injected so `SyncCoordinator` is
/// testable with no I/O. Used only on the main actor (no Sendable needed).
protocol SyncTokenStoring {
    func load() -> SyncToken?
    func save(_ token: SyncToken?)
}

struct UserDefaultsSyncTokenStore: SyncTokenStoring {
    private let key = "byzantinetrail.sync.token"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> SyncToken? { defaults.string(forKey: key).map(SyncToken.init(raw:)) }
    func save(_ token: SyncToken?) {
        if let token { defaults.set(token.raw, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}

/// In-memory token store for tests.
final class InMemorySyncTokenStore: SyncTokenStoring {
    private var token: SyncToken?
    init(_ token: SyncToken? = nil) { self.token = token }
    func load() -> SyncToken? { token }
    func save(_ token: SyncToken?) { self.token = token }
}
