import SwiftUI

/// The Naviq mark: a compass needle tilted north-east inside a thin ring —
/// "moving toward your goals". Drawn as vector paths so it stays crisp at
/// any size, from tab bars to the welcome screen.
struct NaviqMark: View {
    var size: CGFloat = 32
    var ink: Color = NaviqColor.ink
    var accent: Color = NaviqColor.coral

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ink, lineWidth: max(1.2, size * 0.06))
            NeedleShape(half: .north)
                .fill(accent)
            NeedleShape(half: .south)
                .fill(ink)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(40))
        .accessibilityHidden(true)
    }
}

private struct NeedleShape: Shape {
    enum Half { case north, south }
    let half: Half

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let length = rect.height * 0.36
        let width = rect.width * 0.13
        var p = Path()
        let tip = CGPoint(x: c.x, y: half == .north ? c.y - length : c.y + length)
        p.move(to: tip)
        p.addLine(to: CGPoint(x: c.x - width, y: c.y))
        p.addLine(to: CGPoint(x: c.x + width, y: c.y))
        p.closeSubpath()
        return p
    }
}

/// Wordmark: lowercase serif "naviq" paired with the mark.
struct NaviqWordmark: View {
    var markSize: CGFloat = 26
    var font: Font = .system(.title2, design: .serif).weight(.semibold)

    var body: some View {
        HStack(spacing: 8) {
            NaviqMark(size: markSize)
            Text("naviq")
                .font(font)
                .tracking(-0.5)
                .foregroundStyle(NaviqColor.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Naviq")
    }
}

#Preview {
    VStack(spacing: 24) {
        NaviqMark(size: 96)
        NaviqWordmark()
    }
    .padding()
    .naviqPage()
}
