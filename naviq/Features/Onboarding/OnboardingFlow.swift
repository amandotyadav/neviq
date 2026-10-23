import SwiftUI

struct OnboardingFlow: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .college
    @State private var draft: ProfileDraft = ProfileDraft()
    @State private var isSaving = false
    @State private var error: String?

    enum Step: Int, CaseIterable {
        case college, academics, skills, preferences
        var title: String {
            switch self {
            case .college: "Where do you study?"
            case .academics: "Your course"
            case .skills: "What you know, and where you're headed"
            case .preferences: "A few preferences"
            }
        }
        var subtitle: String {
            switch self {
            case .college: "We use this to show verified notices and listings from your campus."
            case .academics: "Eligibility checks compare these against each opportunity's published criteria."
            case .skills: "Matches explain themselves using what you add here. Only add what's true."
            case .preferences: "All optional. You can change these any time."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: NaviqSpacing.xl) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.title)
                            .font(NaviqFont.title)
                            .foregroundStyle(NaviqColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(step.subtitle).foregroundStyle(NaviqColor.inkSecondary)
                    }
                    Group {
                        switch step {
                        case .college: CollegeStep(draft: $draft)
                        case .academics: AcademicsStep(draft: $draft)
                        case .skills: SkillsStep(draft: $draft)
                        case .preferences: PreferencesStep(draft: $draft)
                        }
                    }
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    if let error { NoticeBanner(text: error) }
                }
                .padding(NaviqSpacing.page)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .naviqPage()
        .onAppear { if let user = session.user { draft.name = user.name } }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                NaviqWordmark(markSize: 22)
                Spacer()
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .eyebrowStyle()
            }
            // Four waypoints joined by a path; completed legs are solid.
            HStack(spacing: 0) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    WaypointMarker(state: s.rawValue < step.rawValue ? .done : s == step ? .current : .upcoming, size: 18)
                    if s != Step.allCases.last {
                        Rectangle()
                            .fill(s.rawValue < step.rawValue ? NaviqColor.forest : NaviqColor.rule)
                            .frame(height: s.rawValue < step.rawValue ? 2 : 1.5)
                    }
                }
            }
            .animation(.smooth, value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
        }
        .padding(.horizontal, NaviqSpacing.page)
        .padding(.top, NaviqSpacing.m)
        .padding(.bottom, NaviqSpacing.l)
    }

    private var footer: some View {
        VStack(spacing: NaviqSpacing.s) {
            Hairline()
            HStack(spacing: NaviqSpacing.m) {
                if step != .college {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 50, height: 50) }
                        .buttonStyle(.plain)
                        .foregroundStyle(NaviqColor.ink)
                        .overlay { Circle().strokeBorder(NaviqColor.rule) }
                        .accessibilityLabel("Back")
                }
                Button {
                    if step == .preferences { finish() } else { move(1) }
                } label: {
                    if isSaving { ProgressView().tint(NaviqColor.onAccent) } else { Text(step == .preferences ? "Finish" : "Continue") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || draft.cgpaInvalid)
            }
            Button("Skip for now — finish later in Profile") { finish() }
                .font(.footnote)
                .foregroundStyle(NaviqColor.inkSecondary)
                .disabled(isSaving)
        }
        .padding(.horizontal, NaviqSpacing.page)
        .padding(.bottom, NaviqSpacing.s)
        .background { NaviqColor.paper.ignoresSafeArea() }
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(reduceMotion ? .none : .smooth(duration: 0.3)) { step = next }
    }

    private func finish() {
        isSaving = true
        error = nil
        Task {
            do {
                let user = try await NaviqAPI.updateProfile(draft.body(completeOnboarding: true))
                Haptics.success()
                session.update(user)
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Steps

struct CollegeStep: View {
    @Binding var draft: ProfileDraft
    @State private var query: String = ""
    @State private var results: LoadState<[College]> = .idle
    @State private var showCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            if let college = draft.college {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected").kickerStyle()
                        Text(college.name).font(.headline).foregroundStyle(NaviqColor.ink)
                    }
                    Spacer()
                    Button("Change") { draft.college = nil; draft.collegeChanged = true }
                }
                .padding(14)
                .background { RoundedRectangle(cornerRadius: 12).fill(NaviqColor.jadeSoft) }
            } else if showCustom {
                LabeledField(label: "Institution name", hint: "We'll add it as an unlisted institution. Campus notices appear once your college joins Naviq.") {
                    TextField("Full official name", text: $draft.customCollegeName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: draft.customCollegeName) { draft.collegeChanged = true }
                }
                Button("Search the list instead") { showCustom = false; draft.customCollegeName = "" }
                    .font(.subheadline)
            } else {
                LabeledField(label: "Search") {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(NaviqColor.inkTertiary)
                        TextField("College or university", text: $query)
                            .autocorrectionDisabled()
                    }
                }
                switch results {
                case .loading: ProgressView().frame(maxWidth: .infinity)
                case .failed(let m): NoticeBanner(text: m)
                case .loaded(let list) where list.isEmpty:
                    Text("No listed institution matches “\(query)”.").foregroundStyle(NaviqColor.inkSecondary)
                case .loaded(let list):
                    VStack(spacing: 0) {
                        ForEach(list) { c in
                            Button {
                                draft.college = c
                                draft.collegeChanged = true
                                Haptics.tap()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).foregroundStyle(NaviqColor.ink)
                                        if let place = [c.city, c.state].compactMap({ $0 }).joined(separator: ", ").nilIfEmpty {
                                            Text(place).font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(NaviqColor.accent)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }
                case .idle: EmptyView()
                }
                Button("My institution isn't listed") { showCustom = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .task(id: query) {
            guard draft.college == nil, !showCustom else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = .loading
            do { results = .loaded(try await NaviqAPI.colleges(query: query.trimmed)) }
            catch is CancellationError {}
            catch { results = .failed(error.localizedDescription) }
        }
    }
}

struct AcademicsStep: View {
    @Binding var draft: ProfileDraft
    private var gradYears: [Int] { let y = Calendar.current.component(.year, from: .now); return Array((y - 1)...(y + 6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.l) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Degree").kickerStyle()
                FlowLayout {
                    ForEach(ProfileDraft.degrees, id: \.self) { d in
                        Button { draft.degree = draft.degree == d ? "" : d } label: { Chip(text: d, selected: draft.degree == d) }
                            .buttonStyle(.plain)
                    }
                }
            }
            LabeledField(label: "Branch or major") {
                TextField("e.g. Computer Science and Engineering", text: $draft.branch)
                    .textInputAutocapitalization(.words)
            }
            if draft.branch.isEmpty {
                FlowLayout {
                    ForEach(ProfileDraft.branchSuggestions, id: \.self) { b in
                        Button { draft.branch = b } label: { Chip(text: b) }.buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Current year of study").kickerStyle()
                Picker("Current year", selection: $draft.currentYear) {
                    Text("—").tag(Int?.none)
                    ForEach(1...5, id: \.self) { Text("Year \($0)").tag(Int?.some($0)) }
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Expected graduation").kickerStyle()
                Picker("Graduation year", selection: $draft.graduationYear) {
                    Text("Not sure").tag(Int?.none)
                    ForEach(gradYears, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                }
                .pickerStyle(.menu)
                .tint(NaviqColor.ink)
            }
            LabeledField(label: "CGPA (optional)", hint: "On a 10-point scale. Used only for criteria that state a minimum.", error: draft.cgpaInvalid ? "Enter a number between 0 and 10." : nil) {
                TextField("e.g. 8.2", text: $draft.cgpaText).keyboardType(.decimalPad)
            }
        }
    }
}

struct SkillsStep: View {
    @Binding var draft: ProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.xl) {
            TokenEditor(title: "Skills", tokens: $draft.skills, suggestions: ProfileDraft.skillSuggestions)
            TokenEditor(title: "Interests", tokens: $draft.interests, suggestions: ProfileDraft.interestSuggestions)
            LabeledField(label: "Career goal (optional)", hint: "e.g. “Security analyst at a product company”") {
                TextField("Where do you want to be in 2–3 years?", text: $draft.careerGoal, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
}

struct PreferencesStep: View {
    @Binding var draft: ProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.xl) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Work mode").kickerStyle()
                HStack {
                    ForEach([("remote", "Remote"), ("hybrid", "Hybrid"), ("onsite", "On-site")], id: \.0) { value, label in
                        Button {
                            if draft.workModes.contains(value) { draft.workModes.remove(value) } else { draft.workModes.insert(value) }
                        } label: { Chip(text: label, selected: draft.workModes.contains(value)) }
                            .buttonStyle(.plain)
                    }
                }
            }
            TokenEditor(title: "Preferred locations", tokens: $draft.locations, suggestions: ["Delhi NCR", "Bengaluru", "Mumbai", "Hyderabad", "Pune", "Chennai"], placeholder: "Add a city")

            VStack(alignment: .leading, spacing: NaviqSpacing.m) {
                Text("Scholarship details (optional, private)").kickerStyle()
                Text("Some scholarships have income or state limits. If you add these, Naviq checks them for you. They're never shown to administrators or sent to Saathi AI.")
                    .font(.footnote)
                    .foregroundStyle(NaviqColor.inkSecondary)
                Picker("Home state", selection: $draft.homeState) {
                    Text("Prefer not to say").tag("")
                    ForEach(ProfileDraft.states, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(NaviqColor.ink)
                LabeledField(label: "Annual family income (₹)") {
                    TextField("e.g. 450000", text: $draft.incomeText).keyboardType(.numberPad)
                }
            }
        }
    }
}
