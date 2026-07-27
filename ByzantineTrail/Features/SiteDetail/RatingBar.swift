import SwiftUI

/// Pure pip↔value mapping for the 1–10 rating bar.
enum RatingScale {
    static let count = 10
    static func rating(forSegment index: Int) -> Int { index + 1 }
    static func isFilled(segment index: Int, for value: Int?) -> Bool {
        guard let value else { return false }
        return rating(forSegment: index) <= value
    }
}

/// A row of 10 tappable segments; filled up to `value`. Disabled state dims and
/// ignores taps. Colors are theme tokens (no hardcoded hex).
struct RatingBar: View {
    let value: Int?
    let isEnabled: Bool
    let theme: Theme
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<RatingScale.count, id: \.self) { index in
                let filled = RatingScale.isFilled(segment: index, for: value)
                Capsule()
                    .fill(filled ? theme.ratingDisplay : theme.bgCardAlt)
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { if isEnabled { onSelect(RatingScale.rating(forSegment: index)) } }
                    .accessibilityHidden(true)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel("Your rating")
        .accessibilityValue(value.map { "\($0) of 10" } ?? "Not rated")
        .accessibilityIdentifier("detail.ratingBar")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let current = value ?? 0
            switch direction {
            case .increment: onSelect(min(RatingScale.count, current + 1))
            case .decrement: onSelect(max(1, current - 1))
            @unknown default: break
            }
        }
    }
}
