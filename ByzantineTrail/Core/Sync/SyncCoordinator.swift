import Foundation
import Observation

/// Orchestrates the private-state sync cycle (spec §3): pull + merge (LWW),
/// persist the token, then push still-pending local changes. Any provider throw
/// is a silent no-op — offline just defers work to the next sync. Driven by app
/// lifecycle (launch + foreground); no screen depends on it.
@MainActor
@Observable
final class SyncCoordinator {
    private let provider: any RemoteSyncProvider
    private let userState: UserStateStore
    private let tokenStore: any SyncTokenStoring
    private(set) var lastSyncedAt: Date?

    init(provider: any RemoteSyncProvider, userState: UserStateStore,
         tokenStore: any SyncTokenStoring) {
        self.provider = provider
        self.userState = userState
        self.tokenStore = tokenStore
    }

    func sync() async {
        // 1. Pull + merge (LWW). Token only advances on a successful pull.
        if let result = try? await provider.pull(since: tokenStore.load()) {
            userState.mergeRemote(result.changes)
            tokenStore.save(result.token)
        }
        // 2. Push still-pending local changes; clear them only on success.
        let pending = userState.pendingChanges()
        if !pending.isEmpty {
            do {
                try await provider.push(pending)
                userState.clearPending(pending.map(\.siteId))
            } catch {
                // Keep pending for the next sync.
            }
        }
        lastSyncedAt = .now
    }
}
