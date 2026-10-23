import SwiftUI

// MARK: - Route language (cartography)

/// A gently winding route from lower-left to upper-right.
struct RouteShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 4, y: r.maxY - 6))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.46, y: r.minY + r.height * 0.52),
                   control1: CGPoint(x: r.minX + r.width * 0.18, y: r.maxY + r.height * 0.1),
                   control2: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.55))
        p.addCurve(to: CGPoint(x: r.maxX - 4, y: r.minY + 6),
                   control1: CGPoint(x: r.minX + r.width * 0.62, y: r.minY + r.height * 0.48),
                   control2: CGPoint(x: r.minX + r.width * 0.72, y: r.minY + r.height * 0.02))
        return p
    }
}

/// Route with waypoints. Completed legs are solid; the rest is dashed.
/// Decorative unless `completed` reflects real progress supplied by the caller.
struct RouteGraphic: View {
    var waypoints: Int
    var completed: Int
    /// Highlights the next waypoint in cobalt ("you are here").
    var showsCurrent = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    private var count: Int { max(2, min(waypoints, 7)) }
    private var doneFraction: CGFloat {
        completed <= 0 ? 0 : CGFloat(min(completed, count - 1)) / CGFloat(count - 1)
    }

    var body: some View {
        Canvas { ctx, size in
            let route = RouteShape().path(in: CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 14))
            ctx.stroke(route, with: .color(NaviqColor.forest.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
            let solid = route.trimmedPath(from: 0, to: doneFraction * drawn)
            ctx.stroke(solid, with: .color(NaviqColor.forest), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count - 1)
                let pt = route.trimmedPath(from: 0, to: max(t, 0.0001)).currentPoint ?? .zero
                let isDone = i < completed
                let isCurrent = showsCurrent && i == min(completed, count - 1)
                let radius: CGFloat = isCurrent ? 6.5 : 5
                let dot = Path(ellipseIn: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2))
                if isDone {
                    ctx.fill(dot, with: .color(NaviqColor.forest))
                } else if isCurrent {
                    ctx.fill(dot, with: .color(NaviqColor.accent))
                    let ring = Path(ellipseIn: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22))
                    ctx.stroke(ring, with: .color(NaviqColor.accent.opacity(0.4)), lineWidth: 1.2)
                } else {
                    ctx.fill(dot, with: .color(NaviqColor.paper))
                    ctx.stroke(dot, with: .color(NaviqColor.forest.opacity(0.7)), lineWidth: 1.5)
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion { drawn = 1 } else { withAnimation(.easeOut(duration: 0.9)) { drawn = 1 } }
        }
    }
}

enum WaypointState { case done, current, upcoming, paused }

/// A single waypoint marker used on the roadmap journey.
struct WaypointMarker: View {
    let state: WaypointState
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(NaviqColor.forest)
                Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(NaviqColor.onForest)
            case .current:
                Circle().fill(NaviqColor.paper)
                Circle().strokeBorder(NaviqColor.accent, lineWidth: 2)
                Circle().fill(NaviqColor.accent).frame(width: size * 0.42, height: size * 0.42)
            case .paused:
                Circle().fill(NaviqColor.paper)
                Circle().strokeBorder(NaviqColor.amber, lineWidth: 2)
                Image(systemName: "pause.fill").font(.system(size: size * 0.38)).foregroundStyle(NaviqColor.amber)
            case .upcoming:
                Circle().fill(NaviqColor.paper)
                Circle().strokeBorder(NaviqColor.forest.opacity(0.55), lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Headings

/// Screen opening: tiny eyebrow, large serif title, optional dek.
struct EditorialHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow).eyebrowStyle(NaviqColor.accent)
                Spacer()
                trailing()
            }
            Text(title)
                .screenTitleStyle()
                .foregroundStyle(NaviqColor.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NaviqColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension EditorialHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

/// Numbered section label with a rule running to the right edge.
struct SectionEyebrow<Trailing: View>: View {
    var number: String?
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let number { Text(number).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(NaviqColor.accent) }
            Text(title).eyebrowStyle(NaviqColor.ink)
            Rectangle().fill(NaviqColor.rule).frame(height: 0.75)
            trailing()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionEyebrow where Trailing == EmptyView {
    init(number: String? = nil, title: String) {
        self.number = number
        self.title = title
        self.trailing = { EmptyView() }
    }
}

struct EditorialDivider: View {
    var label: String?
    var body: some View {
        if let label {
            HStack(spacing: 10) {
                Text(label).eyebrowStyle()
                Rectangle().fill(NaviqColor.rule).frame(height: 0.75)
            }
        } else {
            Hairline()
        }
    }
}

// MARK: - Data marks

/// Days-left readout: big serif number, small unit, warm only when urgent.
struct DeadlineIndicator: View {
    let date: Date?
    var availability = "open"

    private var days: Int? { date.map { Dates.daysUntil($0) } }
    private var urgent: Bool { (days ?? 99) <= 7 && (days ?? -1) >= 0 && availability != "closed" }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let days, availability != "closed", days >= 0 {
                Text("\(days)")
                    .font(NaviqFont.numeral)
                    .foregroundStyle(urgent ? NaviqColor.coral : NaviqColor.ink)
                Text(days == 1 ? "day left" : "days left").eyebrowStyle(urgent ? NaviqColor.coral : NaviqColor.inkSecondary)
            } else if availability == "closed" {
                Text("Closed").eyebrowStyle(NaviqColor.inkTertiary)
            } else {
                Text("No date").eyebrowStyle(NaviqColor.inkTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let days else { return "No deadline published" }
        if availability == "closed" || days < 0 { return "Closed" }
        return days == 0 ? "Closes today" : "\(days) day\(days == 1 ? "" : "s") left"
    }
}

/// Outlined stamp for the overall eligibility result.
struct EligibilityStamp: View {
    let overall: String

    private var content: (text: String, color: Color) {
        switch overall {
        case "all_criteria_met": ("Criteria met", NaviqColor.jade)
        case "missing_information": ("To confirm", NaviqColor.accent)
        case "likely_ineligible": ("Likely not eligible", NaviqColor.coral)
        default: ("Can't assess yet", NaviqColor.amber)
        }
    }

    var body: some View {
        Text(content.text)
            .eyebrowStyle(content.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(content.color, lineWidth: 1.5) }
            .padding(3)
            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(content.color.opacity(0.45), lineWidth: 0.75) }
            .rotationEffect(.degrees(-1.5))
            .accessibilityLabel("Eligibility: \(content.text)")
    }
}

/// Horizontal route of application stages with real counts.
struct ProgressPath: View {
    struct Stage: Identifiable { let id: String; let label: String; let count: Int }
    let stages: [Stage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let step = stages.count > 1 ? (geo.size.width - 12) / CGFloat(stages.count - 1) : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(NaviqColor.rule).frame(height: 1.5).offset(y: 0)
                    ForEach(Array(stages.enumerated()), id: \.element.id) { i, s in
                        Circle()
                            .fill(s.count > 0 ? NaviqColor.forest : NaviqColor.paper)
                            .overlay { Circle().strokeBorder(s.count > 0 ? NaviqColor.forest : NaviqColor.rule, lineWidth: 1.5) }
                            .frame(width: 12, height: 12)
                            .offset(x: CGFloat(i) * step)
                    }
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            HStack(alignment: .top, spacing: 0) {
                ForEach(stages) { s in
                    VStack(spacing: 2) {
                        Text("\(s.count)").font(NaviqFont.numeral).foregroundStyle(s.count > 0 ? NaviqColor.ink : NaviqColor.inkTertiary)
                        Text(s.label).font(.system(size: 9, weight: .semibold)).tracking(0.3).foregroundStyle(NaviqColor.inkSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Application stages: " + stages.map { "\($0.label) \($0.count)" }.joined(separator: ", "))
    }
}

// MARK: - Actions

/// Primary call to action with a trailing arrow.
struct PrimaryAction: View {
    let title: String
    var systemImage = "arrow.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: systemImage).font(.body.weight(.semibold))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

// MARK: - Tab bar

struct NaviqTabBar: View {
    @Binding var selection: AppRouter.Tab
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [(AppRouter.Tab, String, String)] = [
        (.home, "Home", "house"),
        (.discover, "Discover", "magnifyingglass"),
        (.saathi, "Saathi", "text.bubble"),
        (.roadmap, "Roadmap", "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath"),
        (.applications, "Applications", "tray.full"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(items, id: \.0) { tab, title, symbol in
                    let selected = selection == tab
                    Button {
                        guard selection != tab else { return }
                        Haptics.tap()
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) { selection = tab }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .top) {
                                if selected {
                                    Rectangle().fill(NaviqColor.accent).frame(width: 22, height: 2.5)
                                        .matchedGeometryEffect(id: "indicator", in: indicator)
                                        .offset(y: -9)
                                }
                                Image(systemName: symbol)
                                    .font(.system(size: 20, weight: selected ? .medium : .light))
                            }
                            .frame(height: 24)
                            Text(title)
                                .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(selected ? NaviqColor.forest : NaviqColor.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("tab.\(title.lowercased())")
                }
            }
            .padding(.horizontal, 6)
        }
        .background { NaviqColor.paper.ignoresSafeArea(edges: .bottom) }
    }
}
