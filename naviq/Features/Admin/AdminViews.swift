import SwiftUI

/// Campus administrator workspace. Every action is authorised again by the
/// server; this UI only shows what the server allows.
struct AdminHomeView: View {
    enum Section: String, CaseIterable { case announcements = "Notices", listings = "Listings", metrics = "Engagement" }
    @State private var section: Section = .announcements
    @State private var colleges: [College] = []
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(NaviqSpacing.page)

            if let loadError { NoticeBanner(text: loadError).padding(.horizontal) }
            switch section {
            case .announcements: AdminAnnouncementsList(colleges: colleges)
            case .listings: AdminListingsList(colleges: colleges)
            case .metrics: AdminMetricsView()
            }
        }
        .naviqPage()
        .navigationTitle("Campus admin")
        .task {
            do { colleges = try await NaviqAPI.adminColleges() }
            catch { loadError = error.localizedDescription }
        }
    }
}

// MARK: - Announcements

private struct AdminAnnouncementsList: View {
    let colleges: [College]
    @State private var state: LoadState<[Announcement]> = .idle
    @State private var editing: Announcement?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                Button { creating = true } label: { Label("New announcement", systemImage: "square.and.pencil") }
                    .disabled(colleges.isEmpty)
            } footer: {
                Text("Published notices appear on the Home screen of students who selected your college.")
            }
            switch state {
            case .idle, .loading: ProgressView()
            case .failed(let m): Text(m).foregroundStyle(NaviqColor.coral)
            case .loaded(let items) where items.isEmpty: Text("No announcements yet.").foregroundStyle(.secondary)
            case .loaded(let items):
                ForEach(items) { a in
                    Button { editing = a } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(a.status.capitalized).font(.caption.weight(.semibold))
                                    .foregroundStyle(a.status == "published" ? NaviqColor.jade : a.status == "draft" ? NaviqColor.amber : NaviqColor.inkTertiary)
                                Text("· \(a.collegeName ?? "")").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(a.title).foregroundStyle(NaviqColor.ink)
                            Text(a.body).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating) { AnnouncementEditor(colleges: colleges, existing: nil) { _ in Task { await load() } } }
        .sheet(item: $editing) { a in AnnouncementEditor(colleges: colleges, existing: a) { _ in Task { await load() } } }
    }

    private func load() async {
        do { state = .loaded(try await NaviqAPI.adminAnnouncements()) } catch { state = .failed(error.localizedDescription) }
    }
}

private struct AnnouncementEditor: View {
    let colleges: [College]
    let existing: Announcement?
    let onSaved: (Announcement) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var collegeId: String = ""
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var category = "general"
    @State private var sourceUrl: String = ""
    @State private var hasExpiry = false
    @State private var expiresAt: Date = .now.addingTimeInterval(30 * 86400)
    @State private var saving = false
    @State private var error: String?

    private let categories = ["general", "placement", "scholarship", "internship", "event", "academic"]

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Picker("College", selection: $collegeId) {
                        ForEach(colleges) { Text($0.name).tag($0.id) }
                    }
                }
                Section("Notice") {
                    TextField("Title", text: $title)
                    TextField("Message", text: $bodyText, axis: .vertical).lineLimit(4...12)
                    Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Text($0.capitalized).tag($0) } }
                }
                Section {
                    TextField("Official link (optional)", text: $sourceUrl)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Expires", isOn: $hasExpiry.animation())
                    if hasExpiry { DatePicker("Expires on", selection: $expiresAt, in: Date.now..., displayedComponents: .date) }
                } footer: { Text("Link to the original circular or official page so students can verify it.") }
                if let error { Section { Text(error).foregroundStyle(NaviqColor.coral) } }
                Section {
                    Button("Save as draft") { save(status: "draft") }.disabled(!valid || saving)
                    Button("Publish to students") { save(status: "published") }.fontWeight(.semibold).disabled(!valid || saving)
                    if existing?.status == "published" {
                        Button("Archive", role: .destructive) { save(status: "archived") }.disabled(saving)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New announcement" : "Edit announcement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear(perform: prefill)
        }
    }

    private var valid: Bool { title.trimmed.count >= 3 && bodyText.trimmed.count >= 3 && (existing != nil || !collegeId.isEmpty) }

    private func prefill() {
        if let a = existing {
            title = a.title; bodyText = a.body; category = a.category; sourceUrl = a.sourceUrl ?? ""
            if let e = a.expiresAt { hasExpiry = true; expiresAt = e }
        } else if collegeId.isEmpty {
            collegeId = colleges.first?.id ?? ""
        }
    }

    private func save(status: String) {
        saving = true
        error = nil
        Task {
            do {
                var fields: [String: Any?] = [
                    "title": title.trimmed, "body": bodyText.trimmed, "category": category,
                    "sourceUrl": sourceUrl.trimmed, "status": status,
                    "expiresAt": hasExpiry ? expiresAt : NSNull(),
                ]
                let saved: Announcement
                if let existing {
                    saved = try await NaviqAPI.adminUpdateAnnouncement(existing.id, JSONBody.object(fields))
                } else {
                    fields["collegeId"] = collegeId
                    saved = try await NaviqAPI.adminCreateAnnouncement(JSONBody.object(fields))
                }
                Haptics.success()
                onSaved(saved)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - Listings

private struct AdminListingsList: View {
    let colleges: [College]
    @State private var state: LoadState<[Opportunity]> = .idle
    @State private var editing: Opportunity?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                Button { creating = true } label: { Label("New campus listing", systemImage: "plus.rectangle.on.rectangle") }
                    .disabled(colleges.isEmpty)
            } footer: {
                Text("New listings start as “Pending verification”. Verify after checking the official source; editing key facts sends it back to pending.")
            }
            switch state {
            case .idle, .loading: ProgressView()
            case .failed(let m): Text(m).foregroundStyle(NaviqColor.coral)
            case .loaded(let items) where items.isEmpty: Text("No listings yet.").foregroundStyle(.secondary)
            case .loaded(let items):
                ForEach(items) { o in
                    Button { editing = o } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(o.status.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                VerificationLabel(status: o.verificationStatus, lastVerifiedAt: o.lastVerifiedAt, isStale: o.isStale, compact: true)
                            }
                            Text(o.title).foregroundStyle(NaviqColor.ink)
                            DeadlineLabel(availability: o.availability, deadline: o.deadline)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating) { ListingEditor(colleges: colleges, existing: nil) { Task { await load() } } }
        .sheet(item: $editing) { o in ListingEditor(colleges: colleges, existing: o) { Task { await load() } } }
    }

    private func load() async {
        do { state = .loaded(try await NaviqAPI.adminOpportunities()) } catch { state = .failed(error.localizedDescription) }
    }
}

private struct ListingEditor: View {
    let colleges: [College]
    let existing: Opportunity?
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var collegeId: String = ""
    @State private var title: String = ""
    @State private var organization: String = ""
    @State private var type: OpportunityType = .job
    @State private var description: String = ""
    @State private var sourceUrl: String = ""
    @State private var applicationUrl: String = ""
    @State private var hasDeadline = false
    @State private var deadline: Date = .now.addingTimeInterval(14 * 86400)
    @State private var declaredStatus = "open"
    @State private var years: Set<Int> = []
    @State private var degrees: [String] = []
    @State private var branches: [String] = []
    @State private var skills: [String] = []
    @State private var minCGPA: String = ""
    @State private var workMode = "unknown"
    @State private var documents: [String] = []
    @State private var publish = true
    @State private var verifyConfirmed = false
    @State private var verifyNotes: String = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Picker("College", selection: $collegeId) { ForEach(colleges) { Text($0.name).tag($0.id) } }
                }
                Section("Listing") {
                    TextField("Title", text: $title)
                    TextField("Organisation", text: $organization)
                    Picker("Type", selection: $type) { ForEach(OpportunityType.allCases) { Text($0.label).tag($0) } }
                    TextField("Description from the official notice", text: $description, axis: .vertical).lineLimit(3...10)
                }
                Section {
                    TextField("Official source URL (required)", text: $sourceUrl)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Application URL (optional)", text: $applicationUrl)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Source evidence") }
                Section("Dates") {
                    Picker("Status on source", selection: $declaredStatus) {
                        Text("Open").tag("open"); Text("Upcoming").tag("upcoming"); Text("Closed").tag("closed"); Text("Unknown").tag("unknown")
                    }
                    Toggle("Deadline published", isOn: $hasDeadline.animation())
                    if hasDeadline { DatePicker("Deadline", selection: $deadline, displayedComponents: [.date, .hourAndMinute]) }
                }
                Section {
                    HStack {
                        Text("Years")
                        Spacer()
                        ForEach(1...5, id: \.self) { y in
                            Button("\(y)") { if years.contains(y) { years.remove(y) } else { years.insert(y) } }
                                .buttonStyle(.bordered)
                                .tint(years.contains(y) ? NaviqColor.accent : .gray)
                        }
                    }
                    TokenEditor(title: "Degrees", tokens: $degrees, suggestions: ["B.Tech", "B.E.", "BCA", "MCA", "M.Tech"])
                    TokenEditor(title: "Branches", tokens: $branches)
                    TokenEditor(title: "Required skills", tokens: $skills)
                    TextField("Minimum CGPA (optional)", text: $minCGPA).keyboardType(.decimalPad)
                    Picker("Work mode", selection: $workMode) {
                        Text("Unknown").tag("unknown"); Text("On-site").tag("onsite"); Text("Hybrid").tag("hybrid"); Text("Remote").tag("remote"); Text("Not applicable").tag("not_applicable")
                    }
                    TokenEditor(title: "Required documents", tokens: $documents)
                } header: { Text("Eligibility (only what the source states)") } footer: {
                    Text("Leave fields empty when the source doesn't state them — they'll show as unknown to students.")
                }
                Section { Toggle("Published to students", isOn: $publish) }

                if let existing, existing.verificationStatus != "verified" {
                    Section {
                        Toggle("I checked these details against the official source", isOn: $verifyConfirmed)
                        TextField("Verification notes (optional)", text: $verifyNotes)
                        Button("Mark as verified") { verify(existing) }.disabled(!verifyConfirmed || saving)
                    } header: { Text("Verification") }
                }
                if let error { Section { Text(error).foregroundStyle(NaviqColor.coral) } }
            }
            .navigationTitle(existing == nil ? "New listing" : "Edit listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save") { save() }.fontWeight(.semibold).disabled(!valid) }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var valid: Bool {
        title.trimmed.count >= 3 && organization.trimmed.count >= 2 && URL(string: sourceUrl.trimmed)?.scheme?.hasPrefix("http") == true
            && (existing != nil || !collegeId.isEmpty)
    }

    private func prefill() {
        guard let o = existing else { if collegeId.isEmpty { collegeId = colleges.first?.id ?? "" }; return }
        title = o.title; organization = o.organization; type = OpportunityType(rawValue: o.opportunityType) ?? .job
        description = o.officialDescription ?? ""; sourceUrl = o.sourceUrl; applicationUrl = o.applicationUrl ?? ""
        if let d = o.deadline { hasDeadline = true; deadline = d }
        years = Set(o.eligibleYears); degrees = o.eligibleDegrees; branches = o.eligibleBranches; skills = o.requiredSkills
        minCGPA = o.minimumCGPA.map { String($0) } ?? ""; workMode = o.workMode; documents = o.requiredDocuments
        publish = o.status == "published"
        declaredStatus = o.availability == "closed" && o.deadline != nil ? "open" : o.availability
    }

    private func fields() -> [String: Any?] {
        [
            "title": title.trimmed, "organization": organization.trimmed, "opportunityType": type.rawValue,
            "officialDescription": description.trimmed, "sourceUrl": sourceUrl.trimmed, "applicationUrl": applicationUrl.trimmed,
            "declaredStatus": declaredStatus, "deadline": hasDeadline ? deadline : NSNull(),
            "eligibleYears": years.sorted(), "eligibleDegrees": degrees, "eligibleBranches": branches, "requiredSkills": skills,
            "minimumCGPA": Double(minCGPA).map { $0 as Any } ?? NSNull(), "workMode": workMode, "requiredDocuments": documents,
            "status": publish ? "published" : "draft",
        ]
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                if let existing {
                    _ = try await NaviqAPI.adminUpdateOpportunity(existing.id, JSONBody.object(fields()))
                } else {
                    var f = fields()
                    f["collegeId"] = collegeId
                    f["sourceType"] = "college_admin"
                    _ = try await NaviqAPI.adminCreateOpportunity(JSONBody.object(f))
                }
                Haptics.success()
                onChanged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }

    private func verify(_ o: Opportunity) {
        saving = true
        Task {
            do {
                _ = try await NaviqAPI.adminVerify(o.id, notes: verifyNotes)
                Haptics.success()
                onChanged()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - Metrics

private struct AdminMetricsView: View {
    @State private var state: LoadState<AdminMetrics> = .idle

    var body: some View {
        List {
            switch state {
            case .idle, .loading: ProgressView()
            case .failed(let m): Text(m).foregroundStyle(NaviqColor.coral)
            case .loaded(let m):
                Section {
                    LabeledContent("Students on Naviq", value: m.studentsOnNaviq.display)
                    LabeledContent("Published notices", value: "\(m.announcements["published"] ?? 0)")
                    LabeledContent("Draft notices", value: "\(m.announcements["draft"] ?? 0)")
                } footer: { Text(m.note) }
                Section("Listings") {
                    if m.listings.isEmpty { Text("No campus listings yet.").foregroundStyle(.secondary) }
                    ForEach(m.listings) { l in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.title)
                            HStack {
                                Text("Saved: \(l.saves.display)")
                                Text("·")
                                Text("Tracked: \(l.tracked.display)")
                            }
                            .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { state = .loaded(try await NaviqAPI.adminMetrics()) } catch { state = .failed(error.localizedDescription) }
    }
}
