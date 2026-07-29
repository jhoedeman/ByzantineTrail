import Foundation

/// Maps an `AccountStatus` to display fields. No UIKit; fully unit-testable.
struct AccountStatusPresentation: Equatable {
    let title: String
    let explainer: String?
    let symbolName: String

    static func make(for status: AccountStatus) -> AccountStatusPresentation {
        switch status {
        case .available:
            return .init(title: "Signed in to iCloud",
                         explainer: nil,
                         symbolName: "checkmark.icloud")
        case .noAccount:
            return .init(title: "Not signed in to iCloud",
                         explainer: "Sign in to iCloud to rate sites and sync across your devices.",
                         symbolName: "xmark.icloud")
        case .restricted:
            return .init(title: "iCloud restricted",
                         explainer: "iCloud access is restricted on this device (e.g. by Screen Time or a profile).",
                         symbolName: "exclamationmark.icloud")
        case .unknown:
            return .init(title: "Checking iCloud status…",
                         explainer: nil,
                         symbolName: "icloud")
        }
    }
}
