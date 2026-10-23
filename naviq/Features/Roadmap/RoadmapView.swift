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
                VStack(alignment: .leading, spacing: 0) {
                    switch model.state {
                    case .idle, .loading:
                        EditorialHeader(eyebrow: "Roadmap", title: "Your route").padding(.top, 8)
                        SkeletonRows(count: 3).padding(.top, 28)
                    case .failed(let m):
                        EditorialHeader(eyebrow: "Roadmap", title: "Your route").padding(.top, 8)
                        ErrorStateView(message: m) { Task { await model.load() } }.padding(.top, 20)
                    case .loaded(nil): emptyState
                    case .loaded(let r?): roadmapContent(r)
                    }
                    if let e = model.actionError { NoticeBanner(text: e).padding(.top, 16) }
                }
                .padding(.horizontal, NaviqSpacing.page)
                .padding(.bottom, 48)
            }
            .naviqPage()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.load() }
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

    /// First use: an intentional opening, not an empty list.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.l) {
            EditorialHeader(eyebrow: "Roadmap", title: "A route you can actually follow",
                            subtitle: "Saathi turns your goal and profile into milestones with concrete steps. Or add your own — your roadmap works without AI.")
                .padding(.top, 8)
            RouteGraphic(waypoints: 5, completed: 0)
                .frame(height: 150)
                .padding(.vertical, 8)
            if model.aiAvailable == false {
                PrimaryAction(title: "Add your first milestone", systemImage: "plus") { showAdd = true }
                NoticeBanner(text: "Saathi AI isn't configured on this server, so AI-generated roadmaps are unavailable. Manual milestones work fully.", tone: .info)
            } else {
                PrimaryAction(title: "Generate with Saathi") { showGenerate = true }
                Button("Add a milestone myself") { showAdd = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func roadmapContent(_ r: Roadmap) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialHeader(eyebrow: "Roadmap · Your goal", title: r.goal, subtitle: r.summary) {
                Menu {
                    Button { showAdd = true } label: { Label("Add milestone", systemImage: "plus") }
                    Button { showGenerate = true } label: { Label("Generate a new roadmap", systemImage: "sparkles") }
                } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Add") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(NaviqColor.accent)
                }
                .accessibilityLabel("Roadmap actions")
            }
            .padding(.top, 8)
            if r.generatedBy == "ai" {
                Label("Plan drafted by Saathi AI from your profile", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(NaviqColor.inkTertiary).padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 6) {
                RouteGraphic(waypoints: max(r.progress.total, 2), completed: r.progress.completed)
                    .frame(height: 84)
                Text("\(r.progress.completed) of \(r.progress.total) milestones complete")
                    .font(.footnote.monospacedDigit()).foregroundStyle(NaviqColor.inkSecondary)
            }
            .padding(.vertical, 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Roadmap progress")
            .accessibilityValue("\(r.progress.completed) of \(r.progress.total) milestones complete")

            SectionEyebrow(title: "The journey").padding(.bottom, 20)
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
    private var markerState: WaypointState {
        switch milestone.status {
        case "completed": .done
        case "in_progress": .current
        case "paused": .paused
        default: .upcoming
        }
    }
    @State private var pop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Waypoint with a path down to the next one.
            VStack(spacing: 0) {
                WaypointMarker(state: markerState, size: 24)
                    .scaleEffect(pop ? 1.3 : 1)
                    .padding(.top, 3)
                if !isLast {
                    Rectangle()
                        .fill(done ? NaviqColor.forest : NaviqColor.rule)
                        .frame(width: done ? 2 : 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 10) {
                Button(action: toggle) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(String(format: "%02d", index)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(NaviqColor.accent)
                            Text(statusLabel).eyebrowStyle(statusColor)
                            Text("· \(milestone.priority.capitalized) priority").eyebrowStyle(NaviqColor.inkTertiary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(NaviqColor.inkTertiary)
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        Text(milestone.title)
                            .sectionTitleStyle()
                            .foregroundStyle(done ? NaviqColor.inkSecondary : NaviqColor.ink)
                            .multilineTextAlignment(.leading)
                        if let purpose = milestone.purpose, !expanded {
                            Text(purpose).font(.subheadline).foregroundStyle(NaviqColor.inkSecondary).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        if let t = milestone.targetDate {
                            Label("Target \(Dates.short(t))", systemImage: "flag").font(.footnote).foregroundStyle(NaviqColor.inkSecondary)
                        }
                        if let effort = milestone.effortEstimate {
                            Text("Estimate: \(effort)").font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
                        }
                        if !done, let next = milestone.steps.first, !expanded {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("Next").eyebrowStyle(NaviqColor.accent)
                                Text(next).font(.system(.subheadline, design: .serif).italic()).foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Milestone \(index): \(milestone.title), \(statusLabel)")
                .accessibilityHint(expanded ? "Collapse" : "Expand details")

                if expanded { details }

                HStack(spacing: 10) {
                    if !done {
                        Button(milestone.status == "in_progress" ? "Mark complete" : "Start") {
                            Task {
                                let completing = milestone.status == "in_progress"
                                await model.update(milestone, ["status": completing ? "completed" : "in_progress"])
                                Haptics.success()
                                if completing, !reduceMotion {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.6)) { pop = true }
                                    try? await Task.sleep(for: .milliseconds(320))
                                    withAnimation(.spring) { pop = false }
                                }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(width: 168)
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
                        HStack(spacing: 6) { Image(systemName: "ellipsis"); Text("Options") }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(NaviqColor.inkSecondary)
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("More actions for \(milestone.title)")
                }
            }
            .padding(.bottom, isLast ? 4 : 30)
        }
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
