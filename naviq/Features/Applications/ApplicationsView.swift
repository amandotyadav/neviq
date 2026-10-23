import SwiftUI
import UserNotifications

@Observable
final class ApplicationsModel {
    var state: LoadState<[TrackedApplication]> = .idle
    var showArchived = false
    var notificationStatus: UNAuthorizationStatus = .notDetermined

    func load() async {
        if state.value == nil { state = .loading }
        do { state = .loaded(try await NaviqAPI.applications(archived: showArchived)) }
        catch { state = .failed(error.localizedDescription) }
        notificationStatus = await NotificationScheduler.shared.authorizationStatus()
    }

    func replace(_ app: TrackedApplication) {
        guard var list = state.value else { return }
        if let i = list.firstIndex(where: { $0.id == app.id }) {
            if app.archived != showArchived { list.remove(at: i) } else { list[i] = app }
        } else if app.archived == showArchived {
            list.insert(app, at: 0)
        }
        state = .loaded(list)
    }

    func remove(_ id: String) {
        guard var list = state.value else { return }
        list.removeAll { $0.id == id }
        state = .loaded(list)
    }
}

struct ApplicationsView: View {
    @Environment(AppRouter.self) private var router
    @State private var model = ApplicationsModel()
    @State private var showAdd = false
    @State private var selected: TrackedApplication?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NaviqSpacing.xl) {
                    Text("Applications").font(NaviqFont.display).foregroundStyle(NaviqColor.ink)
                    Picker("Show", selection: $model.showArchived) {
                        Text("Active").tag(false)
                        Text("Archived").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if model.notificationStatus == .denied {
                        NoticeBanner(text: "Notifications are off for Naviq, so deadline reminders won't appear. Turn them on in iOS Settings ▸ Naviq ▸ Notifications.", tone: .info)
                    }

                    switch model.state {
                    case .idle, .loading: SkeletonRows(count: 3)
                    case .failed(let m): ErrorStateView(message: m) { Task { await model.load() } }
                    case .loaded(let list) where list.isEmpty:
                        EmptyStateView(symbol: "tray",
                                       title: model.showArchived ? "Nothing archived" : "Nothing tracked yet",
                                       message: model.showArchived ? "Archived applications appear here." : "Track an opportunity from its detail page, or add one you found elsewhere.",
                                       actionTitle: model.showArchived ? nil : "Find opportunities") { router.tab = .discover }
                    case .loaded(let list):
                        grouped(list)
                    }
                }
                .padding(.horizontal, NaviqSpacing.page)
                .padding(.bottom, NaviqSpacing.xxl)
            }
            .naviqPage()
            .refreshable { await model.load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { DraftsListView() } label: { Label("Drafts", systemImage: "doc.on.doc").labelStyle(.titleAndIcon) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add an application")
                }
            }
            .task(id: "\(model.showArchived)-\(router.applicationsVersion)") { await model.load() }
            .sheet(isPresented: $showAdd) {
                AddApplicationSheet { app in model.replace(app) }
                    .presentationDetents([.large])
            }
            .sheet(item: $selected) { app in
                ApplicationDetailView(application: app) { updated in
                    model.replace(updated)
                    router.applicationsVersion += 1
                } onDelete: { id in
                    model.remove(id)
                }
            }
            .navigationDestination(for: OpportunityLink.self) { OpportunityDetailView(opportunityId: $0.id) }
        }
    }

    @ViewBuilder private func grouped(_ list: [TrackedApplication]) -> some View {
        let preparing = list.filter { $0.status.isPreApply }.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        let active = list.filter { !$0.status.isPreApply && !$0.status.isClosed }
        let closed = list.filter { $0.status.isClosed }
        if !preparing.isEmpty { section("Before you apply", preparing) }
        if !active.isEmpty { section("Submitted & in progress", active) }
        if !closed.isEmpty { section("Outcomes", closed) }
    }

    private func section(_ title: String, _ apps: [TrackedApplication]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(kicker: title) { Text("\(apps.count)").font(.caption.monospacedDigit()).foregroundStyle(NaviqColor.inkTertiary) }
            ForEach(apps) { app in
                Button { selected = app } label: { ApplicationRow(app: app) }.buttonStyle(.plain)
                    .padding(.top, NaviqSpacing.m)
            }
        }
    }
}

private struct ApplicationRow: View {
    let app: TrackedApplication

    var body: some View {
        HStack(alignment: .top, spacing: NaviqSpacing.m) {
            if let d = app.deadline, app.status.isPreApply {
                Dateline(date: d, tint: Dates.daysUntil(d) <= 7 ? NaviqColor.coral : NaviqColor.ink)
            } else {
                IconBadge(systemImage: app.status.symbol, fill: app.status == .offer ? NaviqColor.mint : NaviqColor.lilac, size: 50)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.title).font(NaviqFont.cardTitle).foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                if let org = app.organization { Text(org).font(.subheadline).foregroundStyle(NaviqColor.inkSecondary) }
                StatusBadge(status: app.status)
                if let next = app.nextAction {
                    let overdue = app.nextActionDue.map { $0 < .now } ?? false
                    Label {
                        Text(next + (app.nextActionDue.map { " · \(overdue ? "was due" : "due") \(Dates.short($0))" } ?? ""))
                    } icon: { Image(systemName: overdue ? "exclamationmark.circle" : "arrow.turn.down.right") }
                        .font(.footnote)
                        .foregroundStyle(overdue ? NaviqColor.coral : NaviqColor.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(NaviqColor.inkTertiary)
        }
        .naviqCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ApplicationDetailView: View {
    let onSave: (TrackedApplication) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var app: TrackedApplication
    @State private var hasDeadline: Bool
    @State private var hasDue: Bool
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDelete = false

    init(application: TrackedApplication, onSave: @escaping (TrackedApplication) -> Void, onDelete: @escaping (String) -> Void) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.app = application
        self.hasDeadline = application.deadline != nil
        self.hasDue = application.nextActionDue != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(app.title).font(.headline)
                    if let org = app.organization { Text(org).foregroundStyle(.secondary) }
                    if let s = app.applicationUrl, let url = URL(string: s) {
                        Link(destination: url) { Label("Open official page", systemImage: "arrow.up.right.square") }
                    }
                } footer: {
                    Text("Opening the official page doesn't change your status. Mark it Applied only once you've submitted.")
                }
                Section("Status") {
                    Picker("Status", selection: $app.status) {
                        ForEach(ApplicationStatus.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    if app.status == .applied || app.appliedAt != nil {
                        DatePicker("Applied on", selection: Binding(get: { app.appliedAt ?? .now }, set: { app.appliedAt = $0 }), in: ...Date.now, displayedComponents: .date)
                    }
                }
                Section("Dates") {
                    Toggle("Deadline", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Deadline", selection: Binding(get: { app.deadline ?? .now }, set: { app.deadline = $0 }), displayedComponents: .date)
                    }
                }
                Section {
                    TextField("e.g. Upload mark sheets", text: Binding(get: { app.nextAction ?? "" }, set: { app.nextAction = $0 }), axis: .vertical)
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Due", selection: Binding(get: { app.nextActionDue ?? .now }, set: { app.nextActionDue = $0 }), displayedComponents: .date)
                    }
                } header: { Text("Next action") }
                Section("Notes") {
                    TextEditor(text: $app.notes).frame(minHeight: 100)
                }
                if app.statusHistory.count > 1 {
                    Section("History") {
                        ForEach(app.statusHistory.reversed(), id: \.self) { h in
                            LabeledContent(ApplicationStatus(rawValue: h.status)?.label ?? h.status, value: h.at.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
                Section {
                    Button(app.archived ? "Move back to active" : "Archive") {
                        app.archived.toggle()
                        save()
                    }
                    Button("Remove from tracker", role: .destructive) { confirmDelete = true }
                }
                if let error { Section { Text(error).foregroundStyle(NaviqColor.coral) } }
            }
            .naviqForm()
            .navigationTitle("Application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save") { save() }.fontWeight(.semibold) }
                }
            }
            .confirmationDialog("Remove this application?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { delete() }
            } message: { Text("Its notes and history will be deleted.") }
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                let next = app.nextAction?.nilIfEmpty
                let updated = try await NaviqAPI.updateApplication(app.id, JSONBody.object([
                    "status": app.status.rawValue,
                    "notes": app.notes,
                    "deadline": hasDeadline ? app.deadline ?? Date.now : NSNull(),
                    "nextAction": next ?? NSNull(),
                    "nextActionDue": hasDue && next != nil ? app.nextActionDue ?? Date.now : NSNull(),
                    "appliedAt": app.appliedAt,
                    "archived": app.archived,
                ]))
                Haptics.success()
                onSave(updated)
                await ReminderCoordinator.syncAfterChange(requestPermission: hasDue || hasDeadline)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }

    private func delete() {
        Task {
            do {
                try await NaviqAPI.deleteApplication(app.id)
                onDelete(app.id)
                await ReminderCoordinator.syncAfterChange()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct AddApplicationSheet: View {
    let onCreated: (TrackedApplication) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var organization: String = ""
    @State private var url: String = ""
    @State private var status: ApplicationStatus = .interested
    @State private var hasDeadline = false
    @State private var deadline: Date = .now.addingTimeInterval(14 * 86400)
    @State private var nextAction: String = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Organisation", text: $organization)
                    TextField("Official link (optional)", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: { Text("For opportunities you found outside Naviq. These stay private to you.") }
                Section("Status") {
                    Picker("Status", selection: $status) { ForEach(ApplicationStatus.allCases) { Text($0.label).tag($0) } }
                }
                Section {
                    Toggle("Deadline", isOn: $hasDeadline.animation())
                    if hasDeadline { DatePicker("Deadline", selection: $deadline, displayedComponents: .date) }
                    TextField("Next action (optional)", text: $nextAction)
                }
                if let error { Section { Text(error).foregroundStyle(NaviqColor.coral) } }
            }
            .naviqForm()
            .navigationTitle("Add application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(title.trimmed.isEmpty || saving).fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                let app = try await NaviqAPI.createApplication(JSONBody.object([
                    "title": title.trimmed,
                    "organization": organization.nilIfEmpty,
                    "applicationUrl": url.nilIfEmpty,
                    "status": status.rawValue,
                    "deadline": hasDeadline ? deadline : nil,
                    "nextAction": nextAction.nilIfEmpty,
                ]))
                Haptics.success()
                onCreated(app)
                await ReminderCoordinator.syncAfterChange(requestPermission: hasDeadline)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

struct DraftsListView: View {
    @State private var state: LoadState<[Draft]> = .idle
    @State private var opened: Draft?
    @State private var composer: DraftComposerView.Kind?

    var body: some View {
        List {
            Section {
                Button { composer = .resume } label: { Label("Generate a resume from my profile", systemImage: "doc.text") }
                Button { composer = .resumeSummary } label: { Label("Generate a resume summary", systemImage: "text.alignleft") }
            } footer: { Text("Built only from your verified profile details. Add projects and experience in Profile for better results.") }
            switch state {
            case .idle, .loading: ProgressView()
            case .failed(let m): Text(m).foregroundStyle(NaviqColor.coral)
            case .loaded(let drafts) where drafts.isEmpty:
                Text("No drafts yet. Create one from an opportunity's detail page.").foregroundStyle(.secondary)
            case .loaded(let drafts):
                Section("Your drafts") {
                    ForEach(drafts) { d in
                        Button { opened = d } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.title ?? d.kindLabel).foregroundStyle(NaviqColor.ink)
                                Text("\(d.kindLabel) · \(d.reviewedAt == nil ? "Not reviewed" : "Reviewed") · \(d.updatedAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Drafts")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $opened) { d in
            DraftEditorView(draft: d) { _ in Task { await load() } } onDelete: { _ in Task { await load() } }
        }
        .sheet(item: $composer) { kind in
            DraftComposerView(kind: kind, opportunity: nil) { _ in Task { await load() } }
        }
    }

    private func load() async {
        do { state = .loaded(try await NaviqAPI.drafts()) } catch { state = .failed(error.localizedDescription) }
    }
}
