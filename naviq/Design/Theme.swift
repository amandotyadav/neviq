import SwiftUI
import UIKit

/// Naviq Editorial — design tokens.
///
/// Paper and forest dominate. Cobalt marks meaningful action or focus; the
/// warm signal is rare and means "needs attention". Every token has a dark
/// variant. Small text uses the darker `inkSecondary`/`warmText` values so it
/// keeps WCAG AA contrast on paper (the lighter art-direction values are kept
/// for lines and large marks).
enum NaviqColor {
    // Surfaces
    static let paper = dynamic(light: 0xF6F4EC, dark: 0x111A16)
    static let surface = dynamic(light: 0xFCFBF7, dark: 0x18241F)
    static let surfaceSunken = dynamic(light: 0xECEADF, dark: 0x22302A)

    // Brand
    /// Primary brand ink: headings, primary actions, key panels.
    static let forest = dynamic(light: 0x163C32, dark: 0xDCE9DD)
    static let onForest = dynamic(light: 0xFCFBF7, dark: 0x102B25)
    static let deepForest = dynamic(light: 0x102B25, dark: 0x1D3D33)
    static let onDeepForest = dynamic(light: 0xF6F4EC, dark: 0xF1EFE6)

    // Text
    static let ink = dynamic(light: 0x202722, dark: 0xF1EFE6)
    static let inkSecondary = dynamic(light: 0x4F554D, dark: 0xB2B8AE)
    static let inkTertiary = dynamic(light: 0x666C63, dark: 0x98A096)
    static let rule = dynamic(light: 0xDCDDD3, dark: 0x2B3832)

    // Signal
    static let accent = dynamic(light: 0x315BE8, dark: 0x86A0FF)        // cobalt: action / focus
    static let accentDeep = dynamic(light: 0x2347C4, dark: 0x6A87F0)
    static let accentSoft = dynamic(light: 0xE4E9FB, dark: 0x1D2850)
    static let onAccent = dynamic(light: 0xFCFBF7, dark: 0x0B1330)

    static let warm = dynamic(light: 0xD96A45, dark: 0xFF9170)          // marks and rules
    static let coral = dynamic(light: 0xB8482A, dark: 0xFF9170)         // text-safe warm signal
    static let coralSoft = dynamic(light: 0xF8E6DD, dark: 0x3A2119)

    static let jade = dynamic(light: 0x2E6B4F, dark: 0x6FD6A6)          // text-safe success
    static let jadeSoft = dynamic(light: 0xDCE9DD, dark: 0x1F3A31)

    static let amber = dynamic(light: 0x8A5A00, dark: 0xF5B942)
    static let amberSoft = dynamic(light: 0xFBF0D6, dark: 0x38290E)

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

// MARK: - Typography

/// Roles of the Naviq type scale. Serif (New York) carries editorial moments;
/// SF Pro carries interface text. Sizes scale with Dynamic Type.
enum NaviqFont {
    static let body = Font.body                                   // 17
    static let callout = Font.subheadline                         // 15
    static let meta = Font.footnote                               // 13
    static let kicker = Font.caption2.weight(.semibold)           // 11, used with tracking + caps
    static let cardTitle = Font.system(.title3, design: .serif).weight(.semibold)
    static let headline = Font.system(.title3, design: .serif).weight(.semibold)
    static let title = Font.system(.title2, design: .serif).weight(.semibold)
    static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let numeral = Font.system(.title2, design: .serif).weight(.semibold).monospacedDigit()
}

private struct SerifRole: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat

    init(base: CGFloat, relativeTo: Font.TextStyle, weight: Font.Weight, tracking: CGFloat) {
        _size = ScaledMetric(wrappedValue: base, relativeTo: relativeTo)
        self.weight = weight
        self.tracking = tracking
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: .serif))
            .tracking(tracking)
    }

}

extension View {
    /// Hero statement: ~40 pt serif, tight tracking.
    func heroStyle() -> some View {
        modifier(SerifRole(base: 40, relativeTo: .largeTitle, weight: .semibold, tracking: -0.8))
            .lineSpacing(-2)
            .minimumScaleFactor(0.6)
    }
    /// Screen title: ~32 pt serif.
    func screenTitleStyle() -> some View {
        modifier(SerifRole(base: 32, relativeTo: .largeTitle, weight: .semibold, tracking: -0.5))
            .minimumScaleFactor(0.7)
    }
    /// Section title: ~22 pt serif.
    func sectionTitleStyle() -> some View {
        modifier(SerifRole(base: 22, relativeTo: .title2, weight: .semibold, tracking: -0.2))
    }
    /// Item title inside lists: ~19 pt serif.
    func itemTitleStyle() -> some View {
        modifier(SerifRole(base: 19, relativeTo: .headline, weight: .semibold, tracking: -0.1))
    }
    /// Tiny uppercase metadata with restrained tracking.
    func eyebrowStyle(_ color: Color = NaviqColor.inkSecondary) -> some View {
        self.font(NaviqFont.kicker)
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
    /// Sentence-case label used by older call sites.
    func kickerStyle(_ color: Color = NaviqColor.inkSecondary) -> some View {
        eyebrowStyle(color)
    }
}

// MARK: - Geometry

enum NaviqSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 36
    static let page: CGFloat = 22
    /// Content surfaces are nearly square; actions are slightly softer.
    static let radius: CGFloat = 4
    static let actionRadius: CGFloat = 10
}

extension View {
    /// One of the few real surfaces: pure paper with a hairline edge.
    func naviqCard(tint: Color? = nil, padding: CGFloat = NaviqSpacing.l, radius: CGFloat = NaviqSpacing.radius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint ?? NaviqColor.surface) }
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(NaviqColor.rule, lineWidth: 0.75) }
    }

    /// Forms on the paper background.
    func naviqForm() -> some View {
        self.scrollContentBackground(.hidden)
            .background { NaviqColor.paper.ignoresSafeArea() }
    }

    /// Standard page background.
    func naviqPage() -> some View {
        self.background { NaviqColor.paper.ignoresSafeArea() }
            // Opaque strip behind the status bar so scrolled content never collides with the clock.
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    Rectangle().fill(NaviqColor.paper)
                        .frame(height: geo.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .top)
                }
                .frame(height: 0)
                .allowsHitTesting(false)
            }
    }
}
