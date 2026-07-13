import SwiftUI

extension Color {
    init(hex: String) {
        guard let c = RGBA(hex: hex) else { self = .clear; return }
        self = Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}
