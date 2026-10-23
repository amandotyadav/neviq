import SwiftUI

@Observable
final class RoadmapModel {
    var state: LoadState<Roadmap?> = .idle
    var actionError: String?
    var aiAvailable: Bool?

    var roadmap: Roadmap? { state.value ?? nil }

    func load() async {
        if state.value == nil { state = .loading }
        if aiAvailable == nil { aiAvailable = try? await NaviqAPI.aiStatus().available }
        do { state = .loaded(try await NaviqAPI.roadmap()) }
        catch { state = .failed(error.localizedDescription) }
    }

    func update(_ milestone: Milestone, _ fields: [String: Any?]) async {
        actionError = nil
        do {
            state = .loaded(try await NaviqAPI.updateMilestone(milestone.id, JSONBody.object(fields)))
        } catch {
            actionError = error.localizedDescription
        }
    }

    func delete(_ milestone: Milestone) async {
        do { state = .loaded(try await NaviqAPI.deleteMilestone(milestone.id)) }
        catch { actionError = error.localizedDescription }
    }
}

struct RoadmapView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var model = RoadmapModel()
    @State private var showGenerate = false
    @State private var showAdd = false
    @State private var expanded: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NaviqSpacing.xl) {
                    Text("Roadmap").font(NaviqFont.display).foregroundStyle(NaviqColor.ink)
                    switch model.state {
                    case .idle, .loading: SkeletonRows(count: 3)
                    case .failed(let m): ErrorStateView(message: m) { Task { await model.load() } }
                    case .loaded(nil): emptyState
                    case .loaded(let r?): roadmapContent(r)
                    }
                    if let e = model.actionError { NoticeBanner(text: e) }
                }
                .padding(.horizontal, NaviqSpacing.page)
                .padding(.bottom, NaviqSpacing.xxl)
            }
            .naviqPage()
            .refreshable { await model.load() }
            .toolbar {
                if model.roadmap != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { showAdd = true } label: { Label("Add milestone", systemImage: "plus") }
                            Button { showGenerate = true } label: { Label("Generate a new roadmap", systemImage: "sparkles") }
                        } label: { Image(systemName: "plus.circle") }
                            .accessibilityLabel("Roadmap actions")
                    }
                }
            }
            .task(id: router.roadmapVersion) { await model.load() }
            .sheet(isPresented: $showGenerate) {
                GenerateRoadmapSheet(defaultGoal: model.roadmap?.goal ?? session.user?.profile.careerGoal ?? "") { roadmap in
                    model.state = .loaded(roadmap)
                    router.roadmapVersion += 1
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAdd) {
                AddMilestoneSheet(goal: model.roadmap?.goal) { roadmap in
                    model.state = .loaded(roadmap)
                }
                .presentationDetents([.large])
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.l) {
            Text("A plan you can actually follow.")
                .font(NaviqFont.headline)
                .foregroundStyle(NaviqColor.ink)
            Text("Saathi turns your goal and profile into milestones with concrete steps. Or add your own — your roadmap works without AI.")
                .foregroundStyle(NaviqColor.inkSecondary)
            if model.aiAvailable == false {
                Button("Add your first milestone") { showAdd = true }
                    .buttonStyle(PrimaryButtonStyle())
                NoticeBanner(text: "Saathi AI isn't configured on this server, so AI-generated roadmaps are unavailable. Manual milestones work fully.", tone: .info)
            } else {
                Button { showGenerate = true } label: { Label("Generate with Saathi", systemImage: "sparkles") }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Add a milestone myself") { showAdd = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.top, NaviqSpacing.l)
    }

    private func roadmapContent(_ r: Roadmap) -> some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.xl) {
            VStack(alignment: .leading, spacing: NaviqSpacing.s) {
                Text("Goal").kickerStyle(NaviqColor.coral)
                Text(r.goal).font(NaviqFont.title).foregroundStyle(NaviqColor.ink)
                if let summary = r.summary {
                    Text(summary).foregroundStyle(NaviqColor.inkSecondary)
                    if r.generatedBy == "ai" {
                        Label("Plan drafted by Saathi AI from your profile", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(NaviqColor.inkTertiary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: NaviqSpacing.l) {
                    ProgressRing(completed: r.progress.completed, total: r.progress.total)
                    Text("\(r.progress.completed) of \(r.progress.total) milestones complete")
                        .font(NaviqFont.cardTitle)
                        .foregroundStyle(NaviqColor.ink)
                }
                .naviqCard()
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(r.milestones.enumerated()), id: \.element.id) { index, m in
                    MilestoneRow(milestone: m, index: index + 1, isLast: index == r.milestones.count - 1,
                                 expanded: expanded == m.id,
                                 toggle: { withAnimation(.snappy) { expanded = expanded == m.id ? nil : m.id } },
                                 model: model)
                }
            }
        }
    }
}

private struct MilestoneRow: View {
    let milestone: Milestone
    let index: Int
    let isLast: Bool
    let expanded: Bool
    let toggle: () -> Void
    let model: RoadmapModel
    @State private var showDate = false
    @State private var date: Date = .now

    private var done: Bool { milestone.status == "completed" }

    var body: some View {
        HStack(alignment: .top, spacing: NaviqSpacing.m) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(done ? NaviqColor.jade : NaviqColor.surfaceSunken).frame(width: 30, height: 30)
                    Circle().strokeBorder(done ? NaviqColor.jade : milestone.status == "in_progress" ? NaviqColor.accent : Color.clear, lineWidth: 2.5)
                        .frame(width: 30, height: 30)
                    if done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(NaviqColor.paper) }
                    else { Text("\(index)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(NaviqColor.ink) }
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NaviqSpacing.s) {
                Button(action: toggle) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(statusLabel).kickerStyle(statusColor)
                            Text("· \(milestone.priority.capitalized) priority").kickerStyle()
                        }
                        Text(milestone.title)
                            .font(NaviqFont.cardTitle)
                            .strikethrough(done, color: NaviqColor.inkTertiary)
                            .foregroundStyle(done ? NaviqColor.inkSecondary : NaviqColor.ink)
                            .multilineTextAlignment(.leading)
                        if let effort = milestone.effortEstimate {
                            Text("Estimate: \(effort)").font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
                        }
                        if let t = milestone.targetDate {
                            Label("Target \(Dates.short(t))", systemImage: "flag").font(.footnote).foregroundStyle(NaviqColor.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Milestone \(index): \(milestone.title), \(statusLabel)")
                .accessibilityHint(expanded ? "Collapse" : "Expand details")

                if expanded { details }

                HStack(spacing: NaviqSpacing.s) {
                    if !done {
                        Button(milestone.status == "in_progress" ? "Mark complete" : "Start") {
                            Task {
                                await model.update(milestone, ["status": milestone.status == "in_progress" ? "completed" : "in_progress"])
                                Haptics.success()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(milestone.status == "in_progress" ? NaviqColor.jade : NaviqColor.accent)
                    }
                    Menu {
                        if done { Button("Reopen") { Task { await model.update(milestone, ["status": "in_progress"]) } } }
                        if milestone.status == "in_progress" { Button("Pause") { Task { await model.update(milestone, ["status": "paused"]) } } }
                        if milestone.status == "paused" { Button("Resume") { Task { await model.update(milestone, ["status": "in_progress"]) } } }
                        Menu("Priority") {
                            ForEach(["high", "medium", "low"], id: \.self) { p in
                                Button(p.capitalized) { Task { await model.update(milestone, ["priority": p]) } }
                            }
                        }
                        Button("Set target date") { date = milestone.targetDate ?? .now.addingTimeInterval(14 * 86400); showDate = true }
                        if milestone.targetDate != nil { Button("Clear target date") { Task { await model.update(milestone, ["targetDate": NSNull()]) } } }
                        Divider()
                        Button("Delete milestone", role: .destructive) { Task { await model.delete(milestone) } }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(NaviqColor.inkSecondary)
                    }
                    .accessibilityLabel("More actions for \(milestone.title)")
                }
            }
        }
        .naviqCard()
        .padding(.bottom, NaviqSpacing.m)
        .sheet(isPresented: $showDate) {
            NavigationStack {
                DatePicker("Target date", selection: $date, in: Date.now..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDate = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { showDate = false; Task { await model.update(milestone, ["targetDate": date]) } }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            if let purpose = milestone.purpose { Text(purpose).foregroundStyle(NaviqColor.inkSecondary) }
            if !milestone.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Steps").kickerStyle()
                    ForEach(Array(milestone.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1).").font(.callout.monospacedDigit()).foregroundStyle(NaviqColor.inkTertiary)
                            Text(s).font(.callout).foregroundStyle(NaviqColor.ink)
                        }
                    }
                }
            }
            if !milestone.skills.isEmpty {
                FlowLayout { ForEach(milestone.skills, id: \.self) { Chip(text: $0) } }
            }
            if !milestone.prerequisites.isEmpty {
                Text("Before this: \(milestone.prerequisites.joined(separator: ", "))").font(.footnote).foregroundStyle(NaviqColor.inkSecondary)
            }
            if !milestone.verifiedResources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Checked resources", systemImage: "checkmark.seal").kickerStyle(NaviqColor.jade)
                    ForEach(milestone.verifiedResources) { r in
                        if let url = URL(string: r.url) {
                            Link(destination: url) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.title).font(.subheadline.weight(.semibold))
                                        Text("\(r.provider) · \(r.cost.capitalized)").font(.caption).foregroundStyle(NaviqColor.inkTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                }
                            }
                        }
                    }
                }
            }
            if !milestone.suggestedResources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("AI suggestions · not verified", systemImage: "sparkles").kickerStyle(NaviqColor.amber)
                    ForEach(milestone.suggestedResources, id: \.self) { s in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(.subheadline)
                            if let n = s.note { Text(n).font(.caption).foregroundStyle(NaviqColor.inkTertiary) }
                        }
                    }
                }
            }
            if !milestone.projectIdeas.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project ideas").kickerStyle()
                    ForEach(milestone.projectIdeas, id: \.self) { Label($0, systemImage: "hammer").font(.callout) }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var statusLabel: String {
        switch milestone.status {
        case "completed": "Done"
        case "in_progress": "In progress"
        case "paused": "Paused"
        default: "Not started"
        }
    }
    private var statusColor: Color {
        switch milestone.status {
        case "completed": NaviqColor.jade
        case "in_progress": NaviqColor.accent
        case "paused": NaviqColor.amber
        default: NaviqColor.inkTertiary
        }
    }
}

struct GenerateRoadmapSheet: View {
    let defaultGoal: String
    let onCreated: (Roadmap) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var goal: String = ""
    @State private var generating = false
    @State private var error: APIError?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Land a cybersecurity internship by summer", text: $goal, axis: .vertical)
                        .lineLimit(2...4)
                } header: { Text("Your goal") } footer: {
                    Text("Saathi uses your degree, year, skills, interests, and projects. A new roadmap replaces your current one (the old one is archived).")
                }
                if let error {
                    Section {
                        Text(error.localizedDescription).foregroundStyle(NaviqColor.coral)
                        if error.isAIUnavailable { Text("You can still add milestones yourself.").font(.footnote) }
                    }
                }
            }
            .navigationTitle("Generate roadmap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if generating { ProgressView() } else {
                        Button("Generate") { generate() }.disabled(goal.trimmed.count < 3).fontWeight(.semibold)
                    }
                }
            }
            .onAppear { if goal.isEmpty { goal = defaultGoal } }
            .interactiveDismissDisabled(generating)
        }
    }

    private func generate() {
        generating = true
        error = nil
        Task {
            do {
                let r = try await NaviqAPI.generateRoadmap(goal: goal.trimmed, opportunityId: nil)
                Haptics.success()
                onCreated(r)
                dismiss()
            } catch let e as APIError {
                error = e
            } catch {
                self.error = .network(error.localizedDescription)
            }
            generating = false
        }
    }
}

struct AddMilestoneSheet: View {
    let goal: String?
    let onSaved: (Roadmap) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var goalText: String = ""
    @State private var title: String = ""
    @State private var purpose: String = ""
    @State private var steps: [String] = []
    @State private var skills: [String] = []
    @State private var priority = "medium"
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                if goal == nil {
                    Section("Goal") { TextField("What is this roadmap for?", text: $goalText) }
                }
                Section("Milestone") {
                    TextField("Title", text: $title)
                    TextField("Why it matters (optional)", text: $purpose, axis: .vertical)
                    Picker("Priority", selection: $priority) {
                        Text("High").tag("high"); Text("Medium").tag("medium"); Text("Low").tag("low")
                    }
                }
                Section { TokenEditor(title: "Steps", tokens: $steps, placeholder: "Add a step and press return") }
                Section { TokenEditor(title: "Skills", tokens: $skills) }
                if let error { Section { Text(error).foregroundStyle(NaviqColor.coral) } }
            }
            .navigationTitle("Add milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmed.isEmpty || (goal == nil && goalText.trimmed.count < 3) || saving)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                let r = try await NaviqAPI.addMilestone(JSONBody.object([
                    "goal": goal == nil ? goalText.trimmed : nil,
                    "title": title.trimmed,
                    "purpose": purpose.nilIfEmpty,
                    "steps": steps,
                    "skills": skills,
                    "priority": priority,
                ]))
                Haptics.success()
                onSaved(r)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}
