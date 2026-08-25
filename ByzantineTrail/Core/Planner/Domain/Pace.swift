import Foundation

/// How hard the traveller wants to push. Multiplies every dwell time.
enum Pace: String, Codable, CaseIterable, Sendable {
    case relaxed, standard, packed

    var multiplier: Double {
        switch self {
        case .relaxed: 1.3
        case .standard: 1.0
        case .packed: 0.75
        }
    }
}
