import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmSignOut = false
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(user.name).font(NaviqFont.title).foregroundStyle(NaviqColor.ink)
                            Text(user.email).font(.subheadline).foregroundStyle(NaviqColor.inkSecondary)
                            if user.isAdmin {
                                Label(user.role == "platform_admin" ? "Platform administrator" : "Campus administrator", systemImage: "building.columns")
                                    .font(.caption.weight(.semibold)).foregroundStyle(NaviqColor.coral)
                            }
                        }
                        .padding(.vertical, 6)
                        summaryRows(user.profile)
                        Button { showEdit = true } label: { Label("Edit profile", systemImage: "pencil") }
                    }

                    if user.isAdmin {
                        Section {
                            NavigationLink { AdminHomeView() } label: { Label("Campus admin", systemImage: "megaphone") }
                        } footer: { Text("Publish verified campus notices and listings for your college.") }
                    }

                    NotificationSettingsSection(user: user)

                    Section("Privacy") {
                        NavigationLink("How Naviq uses your data") { PrivacyView() }
                    }

                    DeveloperSection()

                    Section {
                        Button("Sign out") { confirmSignOut = true }
                        Button("Delete account", role: .destructive) { showDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .naviqPage()
            .tint(NaviqColor.forest)
            .listRowSeparatorTint(NaviqColor.rule)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showEdit) { if let u = session.user { EditProfileView(user: u) } }
            .sheet(isPresented: $showDelete) { DeleteAccountView() }
            .confirmationDialog("Sign out of Naviq?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            } message: { Text("This signs you out on all devices. Local reminders are removed.") }
        }
    }

    @ViewBuilder private func summaryRows(_ p: Profile) -> some View {
        LabeledContent("College", value: p.collegeName ?? "Not added")
        LabeledContent("Course", value: [p.degree?.nilIfEmpty, p.branch?.nilIfEmpty].compactMap { $0 }.joined(separator: ", ").nilIfEmpty ?? "Not added")
        LabeledContent("Year", value: p.currentYear.map { "Year \($0)" } ?? "Not added")
        LabeledContent("Skills", value: (p.skills ?? []).isEmpty ? "None yet" : (p.skills ?? []).joined(separator: ", "))
        LabeledContent("Interests", value: (p.interests ?? []).isEmpty ? "None yet" : (p.interests ?? []).joined(separator: ", "))
    }
}

private struct NotificationSettingsSection: View {
    let user: User
    @Environment(SessionStore.self) private var session
    @State private var reminders: Bool
    @State private var days: Int
    @State private var campus: Bool
    @State private var status: String = ""
    @State private var error: String?

    init(user: User) {
        self.user = user
        self.reminders = user.notificationPrefs.deadlineReminders
        self.days = user.notificationPrefs.reminderDaysBefore
        self.campus = user.notificationPrefs.campusAnnouncements
    }

    var body: some View {
        Section {
            Toggle("Deadline reminders", isOn: $reminders)
            if reminders {
                Stepper("Remind me \(days) day\(days == 1 ? "" : "s") before", value: $days, in: 0...14)
            }
            Toggle("Show campus announcements", isOn: $campus)
            if let error { Text(error).foregroundStyle(NaviqColor.coral).font(.footnote) }
        } header: { Text("Notifications") } footer: {
            Text(status.isEmpty ? "Reminders are scheduled on this device for tracked applications." : status)
        }
        .onChange(of: reminders) { save(askPermission: reminders) }
        .onChange(of: days) { save(askPermission: false) }
        .onChange(of: campus) { save(askPermission: false) }
        .task { await refreshStatus() }
    }

    private func save(askPermission: Bool) {
        Task {
            do {
                let updated = try await NaviqAPI.updateProfile(JSONBody.object([
                    "notificationPrefs": ["deadlineReminders": reminders, "reminderDaysBefore": days, "campusAnnouncements": campus] as [String: Any?],
                ]))
                session.update(updated)
                error = nil
                await ReminderCoordinator.syncAfterChange(requestPermission: askPermission)
                await refreshStatus()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func refreshStatus() async {
        switch await NotificationScheduler.shared.authorizationStatus() {
        case .denied: status = "Notifications are turned off for Naviq in iOS Settings, so reminders can't appear."
        case .notDetermined: status = "Naviq will ask for permission when you first track something with a date."
        default: status = ""
        }
    }
}

private struct DeveloperSection: View {
    @State private var url: String = AppConfig.baseURL.absoluteString
    @State private var saved = false

    var body: some View {
        Section {
            TextField("Server URL", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(saved ? "Saved" : "Use this server") {
                AppConfig.setBaseURL(url.trimmed == AppConfig.defaultBaseURL ? nil : url.trimmed)
                saved = true
            }
            .disabled(URL(string: url.trimmed)?.scheme == nil)
        } header: { Text("Developer") } footer: {
            Text("The simulator reaches your Mac at http://localhost:4000. On a physical iPhone, use your Mac's local IP or an HTTPS deployment.")
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NaviqSpacing.l) {
                item("What we store", "Your name, email, a hashed password, and the profile details you choose to add. Applications, saved items, drafts, and your roadmap are private to you.")
                item("Sensitive details", "Income and home state are optional. They're used only for eligibility checks, never shown to administrators, and never sent to Saathi AI. Naviq never asks for Aadhaar, bank details, or portal passwords, and never infers gender, caste, religion, or disability.")
                item("Saathi AI", "When you use Saathi, the minimum needed — your course, skills, interests, projects, and the relevant listing — is sent to the AI provider through Naviq's server. Saathi can't change anything without your confirmation.")
                item("Administrators", "Campus admins see only aggregate counts for their own listings (counts under 3 are hidden). They never see your profile or applications.")
                item("Your control", "Edit your profile any time. Deleting your account permanently removes your profile, applications, saved items, drafts, and roadmap.")
                Text("This summary describes how the app is built. It isn't a legal compliance certification.")
                    .font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
            }
            .padding(NaviqSpacing.page)
        }
        .naviqPage()
        .navigationTitle("Privacy")
    }

    private func item(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(NaviqFont.cardTitle).foregroundStyle(NaviqColor.ink)
            Text(body).foregroundStyle(NaviqColor.inkSecondary)
        }
    }
}

struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes your Naviq account, profile, tracked applications, saved opportunities, drafts, and roadmap. It can't be undone.")
                }
                Section("Confirm with your password") {
                    SecureField("Password", text: $password).textContentType(.password)
                }
                if let error { Section { Text(error).foregroundStyle(NaviqColor.coral) } }
                Section {
                    Button(role: .destructive) { delete() } label: {
                        if working { ProgressView() } else { Text("Delete my account") }
                    }
                    .disabled(password.isEmpty || working)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func delete() {
        working = true
        Task {
            do {
                try await NaviqAPI.deleteAccount(password: password)
                await session.accountDeleted()
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProfileDraft
    @State private var saving = false
    @State private var error: String?
    @State private var newProjectTitle: String = ""
    @State private var newProjectDesc: String = ""

    init(user: User) {
        self.draft = ProfileDraft(user: user)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NaviqSpacing.xxl) {
                    LabeledField(label: "Name") { TextField("Full name", text: $draft.name) }
                    LabeledField(label: "Headline (optional)", hint: "One line about you, used in resume drafts.") {
                        TextField("e.g. Second-year CSE student learning web security", text: $draft.headline)
                    }
                    group("College") { CollegeStep(draft: $draft) }
                    group("Course") { AcademicsStep(draft: $draft) }
                    group("Skills & goals") { SkillsStep(draft: $draft) }
                    group("Projects") { projects }
                    group("Achievements") {
                        TokenEditor(title: "Achievements", tokens: $draft.achievements, placeholder: "Add an achievement and press return")
                    }
                    group("Links") {
                        VStack(spacing: NaviqSpacing.m) {
                            linkField("GitHub", $draft.github)
                            linkField("LinkedIn", $draft.linkedin)
                            linkField("Portfolio", $draft.portfolio)
                        }
                    }
                    group("Preferences") { PreferencesStep(draft: $draft) }
                    if let error { NoticeBanner(text: error) }
                }
                .padding(NaviqSpacing.page)
            }
            .scrollDismissesKeyboard(.interactively)
            .naviqPage()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Save") { save() }.fontWeight(.semibold).disabled(draft.cgpaInvalid)
                    }
                }
            }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.l) {
            SectionHeader(kicker: title)
            content()
        }
    }

    private func linkField(_ label: String, _ binding: Binding<String>) -> some View {
        LabeledField(label: label) {
            TextField("https://", text: binding)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            ForEach(draft.projects) { p in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.headline).foregroundStyle(NaviqColor.ink)
                        if let d = p.description, !d.isEmpty { Text(d).font(.footnote).foregroundStyle(NaviqColor.inkSecondary) }
                    }
                    Spacer()
                    Button { draft.projects.removeAll { $0.id == p.id } } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Remove \(p.title)")
                }
                Hairline()
            }
            LabeledField(label: "New project") {
                VStack(spacing: 8) {
                    TextField("Title", text: $newProjectTitle)
                    TextField("What you built and what you used", text: $newProjectDesc, axis: .vertical).lineLimit(2...4)
                }
            }
            Button("Add project") {
                draft.projects.append(Project(_id: UUID().uuidString, title: newProjectTitle.trimmed, description: newProjectDesc.trimmed, skills: [], url: nil))
                newProjectTitle = ""; newProjectDesc = ""
            }
            .disabled(newProjectTitle.trimmed.isEmpty)
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                let user = try await NaviqAPI.updateProfile(draft.body())
                session.update(user)
                Haptics.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
