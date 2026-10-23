import SwiftUI
import UIKit

/// Naviq "Bright" — vibrant colour blocks on a soft lavender canvas.
///
/// One confident accent (electric indigo) drives actions; every opportunity
/// category owns a colour block so lists scan at a glance. Every token has
/// a dark variant and text colours keep AA contrast on their surfaces.
enum NaviqColor {
    // Surfaces
    static let paper = dynamic(light: 0xF4F3FB, dark: 0x0E0D1F)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1A1933)
    static let surfaceSunken = dynamic(light: 0xEAE8F8, dark: 0x25244A)

    // Text
    static let ink = dynamic(light: 0x17153B, dark: 0xF2F1FF)
    static let inkSecondary = dynamic(light: 0x4F4D75, dark: 0xBDBBE0)
    static let inkTertiary = dynamic(light: 0x65638B, dark: 0x9492BC)
    static let rule = dynamic(light: 0xE0DEF2, dark: 0x302F5C)

    // Brand
    static let accent = dynamic(light: 0x4F3BFF, dark: 0xA99EFF)
    static let accentDeep = dynamic(light: 0x2B1DB8, dark: 0x6A5BFF)
    static let accentSoft = dynamic(light: 0xE6E3FF, dark: 0x2A2760)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x120F3A)

    // Status / highlight
    static let coral = dynamic(light: 0xD13B33, dark: 0xFF8A80)
    static let coralSoft = dynamic(light: 0xFFE3DF, dark: 0x3E1F22)
    static let amber = dynamic(light: 0x9A5700, dark: 0xFFD166)
    static let amberSoft = dynamic(light: 0xFFF0C2, dark: 0x3A2E10)
    static let jade = dynamic(light: 0x0A7F61, dark: 0x5BE3B8)
    static let jadeSoft = dynamic(light: 0xD6F5EA, dark: 0x12342B)

    // Category blocks (fill + readable foreground)
    static let sunny = dynamic(light: 0xFFD95A, dark: 0x5C4A12)
    static let mint = dynamic(light: 0x86EBC9, dark: 0x145A45)
    static let lilac = dynamic(light: 0xCDBDFF, dark: 0x41338F)
    static let sky = dynamic(light: 0xA9DAFF, dark: 0x1B4A74)
    static let blush = dynamic(light: 0xFFB8CB, dark: 0x6B2A40)
    static let peach = dynamic(light: 0xFFCBA6, dark: 0x6B3A1A)

    /// Colour block for an opportunity type.
    static func block(for type: String) -> Color {
        switch type {
        case "scholarship": sunny
        case "internship": mint
        case "fellowship": lilac
        case "research": sky
        case "hackathon", "competition": blush
        case "job": peach
        default: lilac
        }
    }

    static let heroGradient = LinearGradient(
        colors: [Color(UIColor(hex: 0x5B47FF)), Color(UIColor(hex: 0x8A3FFC))],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let warmGradient = LinearGradient(
        colors: [Color(UIColor(hex: 0xFF8A5B)), Color(UIColor(hex: 0xFF4F8B))],
        startPoint: .topLeading, endPoint: .bottomTrailing)

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

/// Typography: friendly rounded system design everywhere. Text styles keep
/// Dynamic Type working.
enum NaviqFont {
    static let display = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let title = Font.system(.title, design: .rounded).weight(.bold)
    static let headline = Font.system(.title3, design: .rounded).weight(.bold)
    static let cardTitle = Font.system(.headline, design: .rounded).weight(.bold)
    static let body = Font.system(.body, design: .rounded)
    static let callout = Font.system(.callout, design: .rounded)
    static let meta = Font.system(.footnote, design: .rounded)
    static let kicker = Font.system(.caption, design: .rounded).weight(.bold)
    static let numeral = Font.system(.title, design: .rounded).weight(.heavy).monospacedDigit()
}

enum NaviqSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let page: CGFloat = 20
    static let radius: CGFloat = 24
}

extension View {
    /// Small label above content ("Your next move"). Sentence case, bold, no tracking.
    func kickerStyle(_ color: Color = NaviqColor.inkTertiary) -> some View {
        self.font(NaviqFont.kicker)
            .foregroundStyle(color)
    }

    /// Big rounded card on the lavender canvas. Optional tint fills the card.
    func naviqCard(tint: Color? = nil, padding: CGFloat = NaviqSpacing.l, radius: CGFloat = NaviqSpacing.radius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint ?? NaviqColor.surface)
                    .shadow(color: .black.opacity(tint == nil ? 0.06 : 0), radius: 14, y: 5)
            }
    }

    /// Forms on the canvas instead of system grey.
    func naviqForm() -> some View {
        self.scrollContentBackground(.hidden)
            .background { NaviqColor.paper.ignoresSafeArea() }
    }

    /// Standard page background. Navigation and tab bars use the same canvas
    /// colour, so scrolled content never shows through behind them.
    func naviqPage() -> some View {
        self.background { NaviqColor.paper.ignoresSafeArea() }
            .toolbarBackground(NaviqColor.paper, for: .navigationBar, .tabBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar, .tabBar)
    }
}
