import SwiftUI

/// Navigation values shared across tabs.
struct OpportunityLink: Hashable { let id: String }

@Observable
final class HomeModel {
    var moves: LoadState<[NextMove]> = .idle
    var matches: LoadState<[Opportunity]> = .idle
    var deadlines: [DeadlineItem] = []
    var applications: [TrackedApplication] = []
    var announcements: LoadState<[Announcement]> = .idle
    var announcementsReason: String?
    var restrictedCount = 0
    var roadmap: Roadmap?
    var partialErrors: [String] = []

    func load() async {
        if moves.value == nil { moves = .loading }
        if matches.value == nil { matches = .loading }
        partialErrors = []
        async let m = NaviqAPI.nextMoves()
        async let r = NaviqAPI.matches()
        async let d = NaviqAPI.deadlines()
        async let a = NaviqAPI.announcements()
        async let rm = NaviqAPI.roadmap()
        async let apps = NaviqAPI.applications()

        do { moves = .loaded(try await m) } catch { moves = .failed(error.localizedDescription) }
        do {
            let env = try await r
            matches = .loaded(env.data)
            restrictedCount = env.meta?.excludedRestricted ?? 0
        } catch { matches = .failed(error.localizedDescription) }
        do { deadlines = try await d } catch { partialErrors.append("Deadlines: \(error.localizedDescription)") }
        do {
            let env = try await a
            announcements = .loaded(env.data)
            announcementsReason = env.meta?.reason
        } catch { announcements = .failed(error.localizedDescription) }
        do { roadmap = try await rm } catch { partialErrors.append("Roadmap: \(error.localizedDescription)") }
        do { applications = try await apps } catch { partialErrors.append("Applications: \(error.localizedDescription)") }
    }
}

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = HomeModel()
    @State private var path = NavigationPath()
    @State private var showProfile = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    hero
                    VStack(alignment: .leading, spacing: 36) {
                        recommended
                        if !model.deadlines.isEmpty { upcoming }
                        if otherMoves.count > 0 { nextSteps }
                        if !model.applications.filter({ !$0.archived }).isEmpty { applicationsSnapshot }
                        roadmapSection
                        campusSection
                        saathiEntry
                        ForEach(model.partialErrors, id: \.self) { NoticeBanner(text: $0) }
                    }
                    .padding(.top, 40)
                }
                .padding(.horizontal, NaviqSpacing.page)
                .padding(.bottom, 48)
            }
            .naviqPage()
            .refreshable { await model.load() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: OpportunityLink.self) { OpportunityDetailView(opportunityId: $0.id) }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .task(id: router.applicationsVersion + router.roadmapVersion + router.savedVersion) { await model.load() }
        }
    }

    // MARK: Top bar & hero

    private var topBar: some View {
        HStack {
            NaviqWordmark(markSize: 24)
            Spacer()
            Button { showProfile = true } label: {
                Text(String(session.user?.firstName.prefix(1) ?? "N").uppercased())
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(NaviqColor.forest)
                    .frame(width: 36, height: 36)
                    .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(NaviqColor.forest.opacity(0.6), lineWidth: 1) }
            }
            .accessibilityLabel("Profile and settings")
            .accessibilityIdentifier("home.profile")
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private var greetingLine: String {
        let name = session.user?.firstName ?? ""
        let part: String = switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(greetingLine) · \(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                .eyebrowStyle(NaviqColor.accent)
            switch model.moves {
            case .idle, .loading:
                SkeletonRows(count: 1)
            case .failed(let m):
                ErrorStateView(message: m) { Task { await model.load() } }
            case .loaded(let moves):
                if let lead = moves.first {
                    Text(lead.title).heroStyle().foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                    Text(lead.detail).font(.body).foregroundStyle(NaviqColor.inkSecondary).multilineTextAlignment(.leading)
                    routeGraphic
                    PrimaryAction(title: actionTitle(for: lead)) { open(lead) }
                    Text(lead.reason).font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
                } else {
                    Text("You're all caught up.").heroStyle().foregroundStyle(NaviqColor.ink)
                    Text("Nothing needs your attention right now. Explore verified opportunities in Discover.")
                        .font(.body).foregroundStyle(NaviqColor.inkSecondary)
                    routeGraphic
                    PrimaryAction(title: "Explore opportunities") { router.tab = .discover }
                }
            }
        }
    }

    /// Route with real roadmap progress when a roadmap exists; a neutral route otherwise.
    private var routeGraphic: some View {
        let total = model.roadmap?.progress.total ?? 0
        let done = model.roadmap?.progress.completed ?? 0
        return RouteGraphic(waypoints: total >= 2 ? total : 4, completed: total >= 2 ? done : 0)
            .frame(height: 92)
            .padding(.vertical, 6)
    }

    private func actionTitle(for move: NextMove) -> String {
        switch move.target.type {
        case "profile": "Complete your profile"
        case "opportunity": "View opportunity"
        case "application": "Open tracker"
        case "milestone", "roadmap": "Open roadmap"
        default: "Continue"
        }
    }

    private var otherMoves: [NextMove] {
        guard case .loaded(let moves) = model.moves else { return [] }
        return Array(moves.dropFirst())
    }

    // MARK: Numbering

    private var sectionOrder: [String] {
        var keys = ["recommended"]
        if !model.deadlines.isEmpty { keys.append("upcoming") }
        if !otherMoves.isEmpty { keys.append("steps") }
        if !model.applications.filter({ !$0.archived }).isEmpty { keys.append("applications") }
        keys += ["roadmap", "campus"]
        return keys
    }
    private func num(_ key: String) -> String {
        String(format: "%02d", (sectionOrder.firstIndex(of: key) ?? 0) + 1)
    }

    // MARK: Sections

    @ViewBuilder private var recommended: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.l) {
            SectionEyebrow(number: num("recommended"), title: "Recommended") {
                InlineLink(title: "See all") { router.tab = .discover }
            }
            switch model.matches {
            case .idle, .loading: SkeletonRows(count: 2)
            case .failed(let m): ErrorStateView(message: m) { Task { await model.load() } }
            case .loaded(let list) where list.isEmpty:
                EmptyStateView(symbol: "magnifyingglass", title: "No confirmed matches yet",
                               message: "Naviq only recommends verified, open listings where something in your profile is confirmed. Add skills and interests, or browse everything in Discover.",
                               actionTitle: "Browse Discover") { router.tab = .discover }
            case .loaded(let list):
                if let first = list.first {
                    NavigationLink(value: OpportunityLink(id: first.id)) { OpportunityFeature(opportunity: first, eyebrow: "Best match") }
                        .buttonStyle(.plain)
                }
                let rest = Array(list.dropFirst().prefix(2))
                if !rest.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { i, opp in
                            if i > 0 { Hairline() }
                            NavigationLink(value: OpportunityLink(id: opp.id)) { OpportunityRow(opportunity: opp, index: i + 2) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                Text("Ranked by a match heuristic, not a prediction of selection.")
                    .font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
            }
            if model.restrictedCount > 0, model.matches.value != nil {
                Button { router.tab = .discover } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(NaviqColor.accent)
                        Text("\(model.restrictedCount) more open listing\(model.restrictedCount == 1 ? " is" : "s are") limited to a specific group or field of study (for example, girl students, existing awardees, or agriculture). Naviq doesn't assume who you are — see them in Discover.")
                            .font(.footnote).foregroundStyle(NaviqColor.inkSecondary).multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Hairline() }
                    .overlay(alignment: .bottom) { Hairline() }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            SectionEyebrow(number: num("upcoming"), title: "Upcoming") {
                InlineLink(title: "Tracker") { router.tab = .applications }
            }
            VStack(spacing: 0) {
                ForEach(Array(model.deadlines.prefix(4).enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Hairline() }
                    Button {
                        if let id = item.opportunityId, item.kind == "saved_deadline" { path.append(OpportunityLink(id: id)) }
                        else { router.tab = .applications }
                    } label: {
                        HStack(spacing: 16) {
                            Dateline(date: item.date, tint: item.overdue == true || Dates.daysUntil(item.date) <= 7 ? NaviqColor.coral : NaviqColor.ink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).itemTitleStyle().foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                                Text(kindLabel(item)).font(.footnote).foregroundStyle(NaviqColor.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(NaviqColor.inkTertiary)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func kindLabel(_ item: DeadlineItem) -> String {
        switch item.kind {
        case "next_action": item.overdue == true ? "Next step · overdue" : "Your next step"
        case "saved_deadline": "Saved · application deadline"
        default: "Application deadline"
        }
    }

    private var nextSteps: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            SectionEyebrow(number: num("steps"), title: "Also worth doing")
            VStack(spacing: 0) {
                ForEach(Array(otherMoves.enumerated()), id: \.element.id) { i, move in
                    if i > 0 { Hairline() }
                    Button { open(move) } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(format: "%02d", i + 1)).font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(NaviqColor.inkTertiary).frame(width: 22, alignment: .leading).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(move.title).itemTitleStyle().foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                                Text(move.detail).font(.footnote).foregroundStyle(NaviqColor.inkSecondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right").font(.footnote.weight(.semibold)).foregroundStyle(NaviqColor.accent).padding(.top, 5)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var applicationsSnapshot: some View {
        let apps = model.applications.filter { !$0.archived }
        let stages: [(ApplicationStatus, String)] = [(.interested, "Interest"), (.preparing, "Prep"), (.ready_to_apply, "Ready"), (.applied, "Applied"), (.assessment, "Test"), (.interview, "Interview"), (.offer, "Offer")]
        return VStack(alignment: .leading, spacing: NaviqSpacing.l) {
            SectionEyebrow(number: num("applications"), title: "Applications") {
                InlineLink(title: "Open") { router.tab = .applications }
            }
            ProgressPath(stages: stages.map { s in .init(id: s.0.rawValue, label: s.1, count: apps.filter { $0.status == s.0 }.count) })
            Text("\(apps.count) tracked · only what you've recorded in Naviq")
                .font(.footnote).foregroundStyle(NaviqColor.inkSecondary)
        }
    }

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionEyebrow(number: num("roadmap"), title: "Roadmap") {
                InlineLink(title: "Open") { router.tab = .roadmap }
            }
            if let roadmap = model.roadmap, roadmap.progress.total > 0 {
                Text(roadmap.goal).sectionTitleStyle().foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                Text("\(roadmap.progress.completed) of \(roadmap.progress.total) milestones marked complete by you")
                    .font(.footnote.monospacedDigit()).foregroundStyle(NaviqColor.inkSecondary)
                if let next = roadmap.milestones.first(where: { $0.status == "in_progress" }) ?? roadmap.milestones.first(where: { $0.status == "not_started" }) {
                    HStack(spacing: 8) {
                        Text("Next").eyebrowStyle(NaviqColor.accent)
                        Text(next.title).font(.subheadline.weight(.medium)).foregroundStyle(NaviqColor.ink)
                    }
                    .padding(.top, 2)
                }
            } else {
                Text("Turn your goal into a route.").sectionTitleStyle().foregroundStyle(NaviqColor.ink)
                Text("Build milestones you can track — with Saathi, or by adding your own.")
                    .font(.subheadline).foregroundStyle(NaviqColor.inkSecondary)
                Button("Start a roadmap") { router.tab = .roadmap }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var campusSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            SectionEyebrow(number: num("campus"), title: "Campus notices")
            switch model.announcements {
            case .idle, .loading: SkeletonRows(count: 1)
            case .failed(let m): NoticeBanner(text: m)
            case .loaded(let list) where list.isEmpty:
                Text(model.announcementsReason == "no_college"
                     ? "Add your college in Profile to see official notices from your campus."
                     : "No current notices from your campus administrators.")
                    .font(.subheadline).foregroundStyle(NaviqColor.inkSecondary)
                    .padding(.vertical, 6)
            case .loaded(let list):
                VStack(spacing: 0) {
                    ForEach(Array(list.prefix(3).enumerated()), id: \.element.id) { i, a in
                        if i > 0 { Hairline() }
                        AnnouncementRow(announcement: a)
                    }
                }
            }
        }
    }

    private var saathiEntry: some View {
        Button { router.askSaathi("What should I do next?") } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ask Saathi").eyebrowStyle(NaviqColor.accent)
                HStack(alignment: .firstTextBaseline) {
                    Text("“What should I do next?”")
                        .font(.system(.title3, design: .serif).italic())
                        .foregroundStyle(NaviqColor.ink)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(NaviqColor.accent)
                }
                Text("Your assistant reads your profile and verified listings. It can suggest actions — you confirm each one.")
                    .font(.footnote).foregroundStyle(NaviqColor.inkSecondary).multilineTextAlignment(.leading)
            }
            .padding(.vertical, 18)
            .overlay(alignment: .top) { Rectangle().fill(NaviqColor.forest).frame(height: 1.5) }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Saathi assistant")
    }

    // MARK: Actions

    private func open(_ move: NextMove) {
        Haptics.tap()
        switch move.target.type {
        case "opportunity": if let id = move.target.id { path.append(OpportunityLink(id: id)) }
        case "application": router.tab = .applications
        case "milestone", "roadmap": router.tab = .roadmap
        case "profile": showProfile = true
        default: break
        }
    }
}

struct AnnouncementRow: View {
    let announcement: Announcement
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "megaphone").font(.caption)
                Text(announcement.category).eyebrowStyle()
                Text("· Official campus notice").eyebrowStyle()
            }
            .foregroundStyle(NaviqColor.inkSecondary)
            Text(announcement.title).itemTitleStyle().foregroundStyle(NaviqColor.ink)
            Text(announcement.body)
                .font(.subheadline)
                .foregroundStyle(NaviqColor.inkSecondary)
                .lineLimit(expanded ? nil : 3)
            HStack(spacing: NaviqSpacing.m) {
                if let published = announcement.publishedAt {
                    Text("\(announcement.publisherName ?? "Campus admin") · \(published.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
                }
                Spacer()
                if let url = announcement.sourceUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) { Label("Source", systemImage: "arrow.up.right") }
                        .font(.footnote.weight(.semibold)).foregroundStyle(NaviqColor.accent)
                }
                Button(expanded ? "Less" : "More") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(.footnote.weight(.semibold)).foregroundStyle(NaviqColor.accent)
            }
        }
        .padding(.vertical, 14)
    }
}

/// Circular progress used outside Home (kept for existing call sites).
struct ProgressRing: View {
    let completed: Int
    let total: Int
    var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    var body: some View {
        ZStack {
            Circle().stroke(NaviqColor.rule, lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(NaviqColor.forest, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth, value: fraction)
            Text("\(completed)/\(total)").font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(NaviqColor.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roadmap progress")
        .accessibilityValue("\(completed) of \(total) milestones completed")
    }
}
