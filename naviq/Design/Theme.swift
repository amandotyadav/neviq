import SwiftUI
import UIKit

/// Naviq Editorial — semantic color tokens.
///
/// Warm paper backgrounds, deep forest ink, a cobalt action accent, and coral
/// reserved for time-sensitive highlights. Every token has a dark variant.
enum NaviqColor {
    static let paper = dynamic(light: 0xF6F1E7, dark: 0x111613)
    static let surface = dynamic(light: 0xFCF9F2, dark: 0x19201C)
    static let surfaceSunken = dynamic(light: 0xEFE8DA, dark: 0x0C100E)
    static let ink = dynamic(light: 0x17322B, dark: 0xEDE7DA)
    static let inkSecondary = dynamic(light: 0x4C5C55, dark: 0xB1B9B2)
    static let inkTertiary = dynamic(light: 0x6F7A74, dark: 0x8A948D)
    static let rule = dynamic(light: 0xDDD4C3, dark: 0x2B3530)
    static let accent = dynamic(light: 0x2944C2, dark: 0x9DB0FF)
    static let accentSoft = dynamic(light: 0xE3E7F8, dark: 0x222B4D)
    static let coral = dynamic(light: 0xB8432A, dark: 0xFF9479)
    static let coralSoft = dynamic(light: 0xF6E0D7, dark: 0x3A221B)
    static let amber = dynamic(light: 0x8C5D0A, dark: 0xF2C068)
    static let amberSoft = dynamic(light: 0xF3E6C8, dark: 0x33291A)
    static let jade = dynamic(light: 0x23694D, dark: 0x7DD3AE)
    static let jadeSoft = dynamic(light: 0xDCEBE1, dark: 0x16302A)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0E1430)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Typography: serif (New York) for editorial titles, system sans for
/// reading, small tracked caps for kickers and metadata. All text styles
/// scale with Dynamic Type.
enum NaviqFont {
    static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let title = Font.system(.title, design: .serif).weight(.semibold)
    static let headline = Font.system(.title3, design: .serif).weight(.semibold)
    static let cardTitle = Font.system(.headline, design: .serif).weight(.semibold)
    static let body = Font.body
    static let callout = Font.callout
    static let meta = Font.footnote
    static let kicker = Font.caption.weight(.semibold)
    static let numeral = Font.system(.title, design: .serif).weight(.semibold).monospacedDigit()
}

enum NaviqSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 36
    static let page: CGFloat = 20
}

extension View {
    /// Tracked uppercase label used for section kickers ("YOUR NEXT MOVE").
    func kickerStyle(_ color: Color = NaviqColor.inkTertiary) -> some View {
        self.font(NaviqFont.kicker)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(color)
    }

    /// Forms on the warm paper background instead of system grey.
    func naviqForm() -> some View {
        self.scrollContentBackground(.hidden)
            .background { NaviqColor.paper.ignoresSafeArea() }
    }

    /// Standard page background.
    func naviqPage() -> some View {
        self.background { NaviqColor.paper.ignoresSafeArea() }
    }
}
