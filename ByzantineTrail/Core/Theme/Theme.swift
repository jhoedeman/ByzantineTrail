import SwiftUI

struct Theme {
    let bgApp, bgCard, bgCardAlt: Color
    let borderSubtle, borderDefault: Color
    let textPrimary, textSecondary, textDisabled, textOnImage: Color
    let accentPrimary, accentPrimarySubtle, accentSecondary: Color
    let interactiveCtaBg, interactiveCtaText, interactiveCtaPressed: Color
    let success, warning, error, info: Color
    let tierMajor, tierNotable, tierMinor, ratingDisplay, visitedCheck: Color

    static func chrysos(_ scheme: ColorScheme) -> Theme {
        let h = hexes(scheme)
        func c(_ key: String) -> Color { Color(hex: h[key]!) }
        return Theme(
            bgApp: c("bgApp"), bgCard: c("bgCard"), bgCardAlt: c("bgCardAlt"),
            borderSubtle: c("borderSubtle"), borderDefault: c("borderDefault"),
            textPrimary: c("textPrimary"), textSecondary: c("textSecondary"),
            textDisabled: c("textDisabled"), textOnImage: c("textOnImage"),
            accentPrimary: c("accentPrimary"), accentPrimarySubtle: c("accentPrimarySubtle"),
            accentSecondary: c("accentSecondary"),
            interactiveCtaBg: c("interactiveCtaBg"), interactiveCtaText: c("interactiveCtaText"),
            interactiveCtaPressed: c("interactiveCtaPressed"),
            success: c("success"), warning: c("warning"), error: c("error"), info: c("info"),
            tierMajor: c("tierMajor"), tierNotable: c("tierNotable"), tierMinor: c("tierMinor"),
            ratingDisplay: c("ratingDisplay"), visitedCheck: c("visitedCheck")
        )
    }

    // Single source of the token→hex mapping (COLOR_SYSTEM.md §2). Tested directly.
    static func hexes(_ scheme: ColorScheme) -> [String: String] {
        switch scheme {
        case .dark:
            return [
                "bgApp": Palette.stone950, "bgCard": Palette.stone900, "bgCardAlt": Palette.stone800,
                "borderSubtle": Palette.stone800, "borderDefault": Palette.stone700,
                "textPrimary": Palette.stone50, "textSecondary": Palette.stone300,
                "textDisabled": Palette.stone600, "textOnImage": Palette.stone0,
                "accentPrimary": Palette.gold400, "accentPrimarySubtle": Palette.stone800,
                "accentSecondary": Palette.red300,
                "interactiveCtaBg": Palette.gold400, "interactiveCtaText": Palette.stone950,
                "interactiveCtaPressed": Palette.gold300,
                "success": Palette.jadeDark, "warning": Palette.amberDark,
                "error": Palette.red300, "info": Palette.lapisDark,
                "tierMajor": Palette.gold400, "tierNotable": Palette.terracottaDark,
                "tierMinor": Palette.stone400, "ratingDisplay": Palette.gold400,
                "visitedCheck": Palette.jadeDark,
            ]
        default: // .light
            return [
                "bgApp": Palette.stone50, "bgCard": Palette.stone0, "bgCardAlt": Palette.stone100,
                "borderSubtle": Palette.stone200, "borderDefault": Palette.stone300,
                "textPrimary": Palette.stone900, "textSecondary": Palette.stone700,
                "textDisabled": Palette.stone500, "textOnImage": Palette.stone0,
                "accentPrimary": Palette.gold700, "accentPrimarySubtle": Palette.gold50,
                "accentSecondary": Palette.red600,
                "interactiveCtaBg": Palette.gold700, "interactiveCtaText": Palette.stone0,
                "interactiveCtaPressed": Palette.gold800,
                "success": Palette.jadeLight, "warning": Palette.amberLight,
                "error": Palette.red600, "info": Palette.lapisLight,
                "tierMajor": Palette.gold500, "tierNotable": Palette.terracottaLight,
                "tierMinor": Palette.stone400, "ratingDisplay": Palette.gold700,
                "visitedCheck": Palette.jadeLight,
            ]
        }
    }
}

enum ThemePreference: String, CaseIterable {
    case system, light, dark
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
