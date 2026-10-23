import SwiftUI

// MARK: - Load state

enum LoadState<Value> {
    case idle, loading, loaded(Value), failed(String)

    var value: Value? { if case .loaded(let v) = self { v } else { nil } }
    var isLoading: Bool { if case .loading = self { true } else { false } }
}

// MARK: - Buttons

/// Primary action: solid forest, paper text, 10 pt radius.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = NaviqColor.forest
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, NaviqSpacing.l)
            .foregroundStyle(NaviqColor.onForest)
            .background {
                RoundedRectangle(cornerRadius: NaviqSpacing.actionRadius, style: .continuous)
                    .fill(tint.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.35))
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.2), value: configuration.isPressed)
    }
}

/// Secondary action: hairline-outlined, forest text.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, NaviqSpacing.l)
            .foregroundStyle(NaviqColor.forest.opacity(isEnabled ? 1 : 0.45))
            .background {
                RoundedRectangle(cornerRadius: NaviqSpacing.actionRadius, style: .continuous)
                    .fill(configuration.isPressed ? NaviqColor.surfaceSunken : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: NaviqSpacing.actionRadius, style: .continuous)
                    .strokeBorder(NaviqColor.forest.opacity(isEnabled ? 0.55 : 0.2), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.2), value: configuration.isPressed)
    }
}

/// Text action with an arrow — cobalt marks "go here".
struct InlineLink: View {
    let title: String
    var systemImage = "arrow.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: systemImage).imageScale(.small).fontWeight(.semibold)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NaviqColor.accent)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section header

/// Serif section title under a short heavy rule — the Naviq signature.
struct SectionHeader<Trailing: View>: View {
    let kicker: String
    var title: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(NaviqColor.forest).frame(width: 28, height: 3)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text(kicker)
                    .sectionTitleStyle()
                    .foregroundStyle(NaviqColor.ink)
                Spacer()
                trailing()
            }
            if let title {
                Text(title)
                    .font(NaviqFont.callout)
                    .foregroundStyle(NaviqColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(kicker: String, title: String? = nil) {
        self.kicker = kicker
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// Fine divider.
struct Hairline: View {
    var body: some View { Rectangle().fill(NaviqColor.rule).frame(height: 0.75) }
}

/// Monochrome symbol in a hairline square (used sparingly).
struct IconBadge: View {
    let systemImage: String
    var fill: Color = Color.clear
    var foreground: Color = NaviqColor.forest
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background { RoundedRectangle(cornerRadius: 3, style: .continuous).fill(fill) }
            .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(NaviqColor.rule, lineWidth: 0.75) }
            .accessibilityHidden(true)
    }
}

// MARK: - Labels

/// Source-trust label. Always shows text, not only colour.
struct VerificationLabel: View {
    let status: String
    let lastVerifiedAt: Date?
    var isStale = false
    var compact = false

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(accessibilityText)
    }

    private var text: String {
        switch status {
        case "verified":
            if isStale { return compact ? "Check source" : "Verified over 30 days ago" }
            if let lastVerifiedAt { return compact ? "Verified" : "Verified \(lastVerifiedAt.formatted(.dateTime.day().month(.abbreviated)))" }
            return "Verified"
        case "pending": return "Pending verification"
        case "needs_review": return "Source needs review"
        default: return "Unverified"
        }
    }
    private var symbol: String {
        switch status {
        case "verified": isStale ? "clock.badge.exclamationmark" : "checkmark.seal"
        case "pending": "hourglass"
        default: "exclamationmark.triangle"
        }
    }
    private var color: Color {
        switch status {
        case "verified": isStale ? NaviqColor.amber : NaviqColor.jade
        default: NaviqColor.amber
        }
    }
    private var accessibilityText: String {
        status == "verified" && !isStale && lastVerifiedAt != nil
            ? "Verified against official source on \(lastVerifiedAt!.formatted(date: .long, time: .omitted))"
            : text
    }
}

/// Availability with deadline phrase.
struct DeadlineLabel: View {
    let availability: String
    let deadline: Date?

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .monospacedDigit()
    }

    private var urgent: Bool {
        guard let deadline, availability == "open" else { return false }
        return Dates.daysUntil(deadline) <= 10
    }
    private var text: String {
        switch availability {
        case "closed": return deadline.map { "Closed \(Dates.short($0))" } ?? "Closed"
        case "upcoming": return "Opens soon"
        case "unknown": return deadline == nil ? "Dates not published" : Dates.deadlinePhrase(deadline)
        default: return Dates.deadlinePhrase(deadline)
        }
    }
    private var symbol: String {
        switch availability {
        case "closed": "lock"
        case "upcoming": "calendar.badge.clock"
        case "unknown": "questionmark.circle"
        default: urgent ? "timer" : "calendar"
        }
    }
    private var color: Color {
        switch availability {
        case "closed", "unknown": NaviqColor.inkTertiary
        default: urgent ? NaviqColor.coral : NaviqColor.inkSecondary
        }
    }
}

/// Serif day over a tiny month: an open, tile-less date.
struct Dateline: View {
    let date: Date
    var tint: Color = NaviqColor.ink
    var fill: Color = Color.clear

    var body: some View {
        let parts = Dates.dayMonth(date)
        VStack(spacing: 0) {
            Text(parts.day).font(NaviqFont.numeral)
                .foregroundStyle(tint == NaviqColor.coral ? NaviqColor.coral : NaviqColor.ink)
            Text(parts.month).eyebrowStyle()
        }
        .frame(minWidth: 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
    }
}

/// Status as a marker plus text: never colour alone.
struct StatusBadge: View {
    let status: ApplicationStatus

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 7, height: 7)
            Text(status.label).eyebrowStyle(NaviqColor.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch status {
        case .offer: NaviqColor.jade
        case .rejected, .withdrawn: NaviqColor.inkTertiary
        case .applied, .assessment, .interview: NaviqColor.accent
        default: NaviqColor.warm
        }
    }
}

// MARK: - Chips & flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Selectable token: hairline outline, forest fill when selected.
struct Chip: View {
    let text: String
    var selected = false
    var systemImage: String?
    var fill: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(selected ? NaviqColor.onForest : NaviqColor.ink)
        .background { RoundedRectangle(cornerRadius: 3, style: .continuous).fill(selected ? NaviqColor.forest : Color.clear) }
        .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(selected ? Color.clear : NaviqColor.rule, lineWidth: 1) }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Editable token list (skills, interests) with suggestions.
struct TokenEditor: View {
    let title: String
    @Binding var tokens: [String]
    var suggestions: [String] = []
    var placeholder = "Add and press return"
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            Text(title).eyebrowStyle()
            FlowLayout {
                ForEach(tokens, id: \.self) { token in
                    Button {
                        withAnimation(.snappy) { tokens.removeAll { $0 == token } }
                    } label: {
                        Chip(text: token, selected: true, systemImage: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(token)")
                }
            }
            TextField(placeholder, text: $draft)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(add)
                .padding(14)
                .background { RoundedRectangle(cornerRadius: NaviqSpacing.radius, style: .continuous).fill(NaviqColor.surface) }
                .overlay { RoundedRectangle(cornerRadius: NaviqSpacing.radius, style: .continuous).strokeBorder(NaviqColor.rule, lineWidth: 0.75) }
            let remaining = suggestions.filter { s in !tokens.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }
            if !remaining.isEmpty {
                FlowLayout {
                    ForEach(remaining, id: \.self) { s in
                        Button {
                            withAnimation(.snappy) { tokens.append(s) }
                            Haptics.tap()
                        } label: { Chip(text: s, systemImage: "plus") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(s)")
                    }
                }
            }
        }
    }

    private func add() {
        let value = draft.trimmed
        guard !value.isEmpty, !tokens.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { draft = ""; return }
        withAnimation(.snappy) { tokens.append(value) }
        draft = ""
    }
}

// MARK: - States

/// Editorial empty state: a quiet route mark, a serif line, one action.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            RouteGraphic(waypoints: 3, completed: 0, showsCurrent: false)
                .frame(height: 44)
                .frame(maxWidth: 160)
            Text(title)
                .sectionTitleStyle()
                .foregroundStyle(NaviqColor.ink)
            Text(message)
                .font(.callout)
                .foregroundStyle(NaviqColor.inkSecondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, NaviqSpacing.l)
        .accessibilityElement(children: .contain)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            Text("Couldn't load this").eyebrowStyle(NaviqColor.coral)
            Text("Something went wrong")
                .sectionTitleStyle()
                .foregroundStyle(NaviqColor.ink)
            Text(message)
                .font(.callout)
                .foregroundStyle(NaviqColor.inkSecondary)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, NaviqSpacing.l)
    }
}

/// Inline notice with a tone-coloured rule on the left.
struct NoticeBanner: View {
    enum Tone { case error, info, success }
    let text: String
    var tone: Tone = .error

    private var color: Color { tone == .error ? NaviqColor.coral : tone == .success ? NaviqColor.jade : NaviqColor.accent }
    private var soft: Color { tone == .error ? NaviqColor.coralSoft : tone == .success ? NaviqColor.jadeSoft : NaviqColor.accentSoft }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone == .error ? "exclamationmark.circle" : tone == .success ? "checkmark.circle" : "info.circle")
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .foregroundStyle(NaviqColor.ink)
        .padding(12)
        .background { Rectangle().fill(soft) }
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .accessibilityElement(children: .combine)
    }
}

/// Brand loading state: ruled lines that breathe (still when Reduce Motion is on).
struct SkeletonRows: View {
    var count = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.l) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    Rectangle().frame(width: 70, height: 8)
                    Rectangle().frame(height: 16)
                    Rectangle().frame(width: 190, height: 11)
                }
                .foregroundStyle(NaviqColor.rule)
                Hairline()
            }
        }
        .opacity(pulse ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

// MARK: - Form field

struct LabeledField<Content: View>: View {
    let label: String
    var hint: String?
    var error: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrowStyle()
            content()
                .padding(12)
                .background { RoundedRectangle(cornerRadius: NaviqSpacing.radius, style: .continuous).fill(NaviqColor.surface) }
                .overlay { RoundedRectangle(cornerRadius: NaviqSpacing.radius, style: .continuous).strokeBorder(error == nil ? NaviqColor.rule : NaviqColor.coral, lineWidth: error == nil ? 0.75 : 1.5) }
            if let error {
                Text(error).font(.footnote).foregroundStyle(NaviqColor.coral)
            } else if let hint {
                Text(hint).font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
            }
        }
    }
}
