enum FeatureGate: CaseIterable, Sendable {
    case unlimitedFavorites, altThemes, offlinePhotoPacks
}

protocol EntitlementManager: Sendable {
    func isUnlocked(_ gate: FeatureGate) -> Bool
}

/// v1 implementation: everything is free.
struct FreeEntitlementManager: EntitlementManager {
    func isUnlocked(_ gate: FeatureGate) -> Bool { true }
}
