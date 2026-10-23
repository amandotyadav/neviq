import SwiftUI

// MARK: - Load state

enum LoadState<Value> {
    case idle, loading, loaded(Value), failed(String)

    var value: Value? { if case .loaded(let v) = self { v } else { nil } }
    var isLoading: Bool { if case .loading = self { true } else { false } }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = NaviqColor.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, NaviqSpacing.l)
            .foregroundStyle(NaviqColor.onAccent)
            .background { Capsule().fill(tint.opacity(isEnabled ? 1 : 0.4)) }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, NaviqSpacing.l)
            .foregroundStyle(NaviqColor.ink)
            .background { Capsule().strokeBorder(NaviqColor.ink.opacity(0.8), lineWidth: 1.2) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Compact text button with an arrow, used for "See all" and inline actions.
struct InlineLink: View {
    let title: String
    var systemImage = "arrow.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: systemImage).imageScale(.small)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NaviqColor.accent)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section header

struct SectionHeader<Trailing: View>: View {
    let kicker: String
    var title: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(kicker).kickerStyle()
                Spacer()
                trailing()
            }
            Rectangle().fill(NaviqColor.ink).frame(height: 1.5)
            if let title {
                Text(title)
                    .font(NaviqFont.headline)
                    .foregroundStyle(NaviqColor.ink)
                    .padding(.top, 4)
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

struct Hairline: View {
    var body: some View { Rectangle().fill(NaviqColor.rule).frame(height: 1) }
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
        .font(NaviqFont.meta.weight(.medium))
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
        case "verified": isStale ? "clock.badge.exclamationmark" : "checkmark.seal.fill"
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
            .font(NaviqFont.meta.weight(.medium))
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

/// Editorial dateline: large serif day over a small-caps month.
struct Dateline: View {
    let date: Date
    var tint: Color = NaviqColor.ink

    var body: some View {
        let parts = Dates.dayMonth(date)
        VStack(spacing: 0) {
            Text(parts.day).font(NaviqFont.numeral).foregroundStyle(tint)
            Text(parts.month).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(tint.opacity(0.8))
        }
        .frame(minWidth: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
    }
}

struct StatusBadge: View {
    let status: ApplicationStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(foreground)
            .background { Capsule().fill(background) }
    }

    private var foreground: Color {
        switch status {
        case .offer: NaviqColor.jade
        case .rejected, .withdrawn: NaviqColor.inkTertiary
        case .applied, .assessment, .interview: NaviqColor.accent
        default: NaviqColor.ink
        }
    }
    private var background: Color {
        switch status {
        case .offer: NaviqColor.jadeSoft
        case .rejected, .withdrawn: NaviqColor.surfaceSunken
        case .applied, .assessment, .interview: NaviqColor.accentSoft
        default: NaviqColor.surfaceSunken
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

struct Chip: View {
    let text: String
    var selected = false
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.subheadline.weight(selected ? .semibold : .regular))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(selected ? NaviqColor.onAccent : NaviqColor.ink)
        .background {
            Capsule().fill(selected ? NaviqColor.ink : NaviqColor.surface)
        }
        .overlay { Capsule().strokeBorder(selected ? Color.clear : NaviqColor.rule, lineWidth: 1) }
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
            Text(title).kickerStyle()
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
                .padding(12)
                .background { RoundedRectangle(cornerRadius: 10).fill(NaviqColor.surface) }
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(NaviqColor.rule) }
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

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: NaviqSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NaviqColor.inkTertiary)
            Text(title)
                .font(NaviqFont.headline)
                .foregroundStyle(NaviqColor.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(NaviqColor.inkSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 260)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, NaviqSpacing.xxl)
        .padding(.horizontal, NaviqSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: NaviqSpacing.m) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(NaviqColor.coral)
            Text("Something went wrong")
                .font(NaviqFont.cardTitle)
                .foregroundStyle(NaviqColor.ink)
            Text(message)
                .font(.callout)
                .foregroundStyle(NaviqColor.inkSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 200)
            }
        }
        .padding(NaviqSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Inline banner for non-blocking errors and notices.
struct NoticeBanner: View {
    enum Tone { case error, info, success }
    let text: String
    var tone: Tone = .error

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone == .error ? "exclamationmark.circle.fill" : tone == .success ? "checkmark.circle.fill" : "info.circle.fill")
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .foregroundStyle(tone == .error ? NaviqColor.coral : tone == .success ? NaviqColor.jade : NaviqColor.accent)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(tone == .error ? NaviqColor.coralSoft : tone == .success ? NaviqColor.jadeSoft : NaviqColor.accentSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Placeholder rows shown only while a real request is pending.
struct SkeletonRows: View {
    var count = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.l) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 10)
                    RoundedRectangle(cornerRadius: 4).frame(height: 16)
                    RoundedRectangle(cornerRadius: 4).frame(width: 200, height: 12)
                }
                .foregroundStyle(NaviqColor.rule)
                Hairline()
            }
        }
        .opacity(pulse ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
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
            Text(label).kickerStyle()
            content()
                .padding(12)
                .background { RoundedRectangle(cornerRadius: 10).fill(NaviqColor.surface) }
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(error == nil ? NaviqColor.rule : NaviqColor.coral) }
            if let error {
                Text(error).font(.footnote).foregroundStyle(NaviqColor.coral)
            } else if let hint {
                Text(hint).font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
            }
        }
    }
}
