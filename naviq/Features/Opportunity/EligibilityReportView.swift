import SwiftUI

/// "What am I missing?" — deterministic, criterion-by-criterion report.
/// Self-declared answers are used only for this check and never stored.
struct EligibilityReportView: View {
    let state: LoadState<EligibilityResult>
    @Binding var declarations: [String: Bool]
    let recheck: () -> Void
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "What am I missing?")
            switch state {
            case .idle, .loading:
                SkeletonRows(count: 2)
            case .failed(let m):
                ErrorStateView(message: m, retry: recheck)
            case .loaded(let r):
                overall(r)
                ForEach(r.caveats) { c in
                    Label(c.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(NaviqColor.amber)
                }
                VStack(spacing: 0) {
                    ForEach(r.criteria) { c in
                        criterionRow(c)
                        Hairline()
                    }
                }
                Text(r.disclaimer).font(.caption).foregroundStyle(NaviqColor.inkTertiary)
            }
        }
    }

    private func overall(_ r: EligibilityResult) -> some View {
        let (title, detail, _, _) = summary(r)
        return VStack(alignment: .leading, spacing: 10) {
            EligibilityStamp(overall: r.overall)
            Text(title).sectionTitleStyle().foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
            Text(detail).font(.subheadline).foregroundStyle(NaviqColor.inkSecondary)
            Text(countsLine(r))
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(NaviqColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    /// Uses the same "required" definition as the match explanation.
    private func countsLine(_ r: EligibilityResult) -> String {
        let requiredUnknown = r.criteria.filter { $0.mandatory && $0.status == "unknown" }.count
        let optionalUnknown = r.criteria.filter { !$0.mandatory && $0.status == "unknown" }.count
        var line = "\(r.counts.met) met · \(r.counts.unmet) not met · \(requiredUnknown) required to confirm"
        if optionalUnknown > 0 { line += " · \(optionalUnknown) optional" }
        return line
    }

    private func summary(_ r: EligibilityResult) -> (String, String, Color, String) {
        switch r.overall {
        case "all_criteria_met":
            ("All checked criteria met", "Based on your profile, you meet every criterion Naviq could check.", NaviqColor.jade, "checkmark.circle.fill")
        case "missing_information":
            ("Possibly eligible — confirm a few things", "Nothing rules you out, but some criteria need information Naviq doesn't have.", NaviqColor.accent, "questionmark.circle.fill")
        case "likely_ineligible":
            ("Likely not eligible", "At least one required criterion isn't met according to your profile.", NaviqColor.coral, "xmark.circle.fill")
        default:
            ("Can't assess yet", "The source doesn't publish enough structured criteria to check.", NaviqColor.amber, "exclamationmark.circle.fill")
        }
    }

    private func criterionRow(_ c: Criterion) -> some View {
        let isOpen = expanded.contains(c.key)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) {
                    if isOpen { expanded.remove(c.key) } else { expanded.insert(c.key) }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    statusIcon(c.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.requirement).font(.system(.body, design: .serif)).foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(statusText(c.status)).font(.caption.weight(.semibold)).foregroundStyle(statusColor(c.status))
                            if !c.mandatory { Text("· Optional").font(.caption).foregroundStyle(NaviqColor.inkTertiary) }
                            if c.restrictsAudience == true { Text("· Limited to a specific group").font(.caption).foregroundStyle(NaviqColor.inkTertiary) }
                            if let v = c.studentValue { Text("· You: \(v)").font(.caption).foregroundStyle(NaviqColor.inkTertiary) }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .font(.footnote)
                        .foregroundStyle(NaviqColor.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Collapse explanation" : "Expand explanation")

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.explanation).font(.callout).foregroundStyle(NaviqColor.inkSecondary)
                    if let step = c.nextStep {
                        Label(step, systemImage: "arrow.turn.down.right").font(.callout).foregroundStyle(NaviqColor.accent)
                    }
                    if let excerpt = c.sourceExcerpt {
                        Text("“\(excerpt)”")
                            .font(.system(.footnote, design: .serif).italic())
                            .foregroundStyle(NaviqColor.inkSecondary)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) { Rectangle().fill(NaviqColor.rule).frame(width: 2) }
                    }
                    if c.kind == "self_declared" {
                        HStack {
                            Text("Does this apply to you?").font(.footnote).foregroundStyle(NaviqColor.inkSecondary)
                            Spacer()
                            declarationButton("Yes", key: c.key, value: true, tint: NaviqColor.jade)
                            declarationButton("No", key: c.key, value: false, tint: NaviqColor.coral)
                        }
                        Text("Your answer is used only for this check and isn't saved.")
                            .font(.caption2)
                            .foregroundStyle(NaviqColor.inkTertiary)
                    }
                }
                .padding(.leading, 30)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 12)
    }

    /// Selected answers are filled and carry a checkmark, so state is not conveyed by colour alone.
    private func declarationButton(_ title: String, key: String, value: Bool, tint: Color) -> some View {
        let selected = declarations[key] == value
        return Button { declare(key, value) } label: {
            Label(title, systemImage: selected ? "checkmark" : "circle")
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? NaviqColor.onForest : NaviqColor.ink)
                .background { RoundedRectangle(cornerRadius: 3, style: .continuous).fill(selected ? NaviqColor.forest : Color.clear) }
                .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(selected ? Color.clear : NaviqColor.rule, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func declare(_ key: String, _ value: Bool) {
        if declarations[key] == value { declarations.removeValue(forKey: key) } else { declarations[key] = value }
        Haptics.tap()
        recheck()
    }

    private func statusIcon(_ s: String) -> some View {
        Image(systemName: s == "met" ? "checkmark.circle.fill" : s == "unmet" ? "xmark.circle.fill" : "questionmark.circle")
            .foregroundStyle(statusColor(s))
            .font(.body)
            .accessibilityHidden(true)
    }
    private func statusText(_ s: String) -> String { s == "met" ? "Met" : s == "unmet" ? "Not met" : "Unknown" }
    private func statusColor(_ s: String) -> Color { s == "met" ? NaviqColor.jade : s == "unmet" ? NaviqColor.coral : NaviqColor.amber }
}

/// Add an opportunity to the tracker with an optional next action.
struct TrackSheet: View {
    let opportunity: Opportunity
    let onTracked: (TrackedApplication) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var status: ApplicationStatus = .interested
    @State private var nextAction: String = ""
    @State private var hasDue = false
    @State private var due: Date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(opportunity.title).font(.headline)
                    if let d = opportunity.deadline {
                        LabeledContent("Deadline", value: d.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach([ApplicationStatus.interested, .preparing, .ready_to_apply]) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField("e.g. Ask a teacher for a reference", text: $nextAction, axis: .vertical)
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue { DatePicker("Due", selection: $due, in: Date.now..., displayedComponents: .date) }
                } header: { Text("Next action") } footer: {
                    Text("Naviq can remind you before your deadline and next action.")
                }
                if let error { Section { Text(error).foregroundStyle(NaviqColor.coral) } }
            }
            .naviqForm()
            .navigationTitle("Track application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(saving).fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                let app = try await NaviqAPI.createApplication(JSONBody.object([
                    "opportunityId": opportunity.id,
                    "status": status.rawValue,
                    "nextAction": nextAction.nilIfEmpty,
                    "nextActionDue": hasDue && nextAction.nilIfEmpty != nil ? due : nil,
                ]))
                Haptics.success()
                onTracked(app)
                await ReminderCoordinator.syncAfterChange(requestPermission: true)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}
