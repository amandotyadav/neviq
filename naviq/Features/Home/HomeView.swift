import SwiftUI

/// Navigation values shared across tabs.
struct OpportunityLink: Hashable { let id: String }

@Observable
final class HomeModel {
    var moves: LoadState<[NextMove]> = .idle
    var matches: LoadState<[Opportunity]> = .idle
    var deadlines: [DeadlineItem] = []
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
                VStack(alignment: .leading, spacing: NaviqSpacing.xxl) {
                    masthead
                    nextMoveSection
                    if !model.deadlines.isEmpty { deadlinesSection }
                    matchesSection
                    roadmapSection
                    campusSection
                    saathiEntry
                    ForEach(model.partialErrors, id: \.self) { NoticeBanner(text: $0) }
                }
                .padding(.horizontal, NaviqSpacing.page)
                .padding(.bottom, NaviqSpacing.xxl)
            }
            .naviqPage()
            .refreshable { await model.load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NaviqMark(size: 24) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: {
                        Image(systemName: "person.crop.circle").font(.title3)
                    }
                    .accessibilityLabel("Profile and settings")
                }
            }
            .navigationDestination(for: OpportunityLink.self) { OpportunityDetailView(opportunityId: $0.id) }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .task(id: router.applicationsVersion + router.roadmapVersion + router.savedVersion) { await model.load() }
        }
    }

    // MARK: Sections

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).kickerStyle(NaviqColor.coral)
            Text("\(greeting), \(session.user?.firstName ?? "there").")
                .font(NaviqFont.display)
                .foregroundStyle(NaviqColor.ink)
                .accessibilityAddTraits(.isHeader)
            if let p = session.user?.profile, let degree = p.degree?.nilIfEmpty {
                Text([degree, p.branch?.nilIfEmpty, p.currentYear.map { "Year \($0)" }, p.collegeName].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(NaviqColor.inkSecondary)
            }
        }
        .padding(.top, NaviqSpacing.s)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    @ViewBuilder private var nextMoveSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "Your next move")
            switch model.moves {
            case .idle, .loading: SkeletonRows(count: 1)
            case .failed(let m): ErrorStateView(message: m) { Task { await model.load() } }
            case .loaded(let moves) where moves.isEmpty:
                Text("You're all caught up. Explore Discover for new verified opportunities.")
                    .foregroundStyle(NaviqColor.inkSecondary)
            case .loaded(let moves):
                if let lead = moves.first {
                    Button { open(lead) } label: { LeadMoveView(move: lead) }.buttonStyle(.plain)
                }
                ForEach(moves.dropFirst()) { move in
                    Button { open(move) } label: {
                        HStack(alignment: .top, spacing: NaviqSpacing.m) {
                            Image(systemName: symbol(for: move.kind))
                                .frame(width: 22)
                                .foregroundStyle(NaviqColor.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(move.title).font(.headline).foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                                Text(move.detail).font(.subheadline).foregroundStyle(NaviqColor.inkSecondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(NaviqColor.inkTertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
        }
    }

    private var deadlinesSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "Coming up") {
                InlineLink(title: "Tracker") { router.tab = .applications }
            }
            ForEach(model.deadlines.prefix(4)) { item in
                Button {
                    if let id = item.opportunityId, item.kind == "saved_deadline" { path.append(OpportunityLink(id: id)) }
                    else { router.tab = .applications }
                } label: {
                    HStack(spacing: NaviqSpacing.m) {
                        Dateline(date: item.date, tint: item.overdue == true || Dates.daysUntil(item.date) <= 7 ? NaviqColor.coral : NaviqColor.ink)
                        Rectangle().fill(NaviqColor.rule).frame(width: 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kindLabel(item)).kickerStyle()
                            Text(item.title).font(.headline).foregroundStyle(NaviqColor.ink).multilineTextAlignment(.leading)
                            if let org = item.organization { Text(org).font(.footnote).foregroundStyle(NaviqColor.inkSecondary) }
                        }
                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func kindLabel(_ item: DeadlineItem) -> String {
        switch item.kind {
        case "next_action": item.overdue == true ? "Overdue next step" : "Your next step"
        case "saved_deadline": "Saved · deadline"
        default: "Application deadline"
        }
    }

    @ViewBuilder private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(kicker: "Relevant to you") {
                InlineLink(title: "Discover") { router.tab = .discover }
            }
            switch model.matches {
            case .idle, .loading: SkeletonRows(count: 2).padding(.top, NaviqSpacing.m)
            case .failed(let m): ErrorStateView(message: m) { Task { await model.load() } }
            case .loaded(let list) where list.isEmpty:
                EmptyStateView(symbol: "binoculars", title: "No verified matches right now",
                               message: "Naviq only recommends listings verified against an official source that are open and that you aren't ruled out of. Add skills and interests, or browse everything in Discover.",
                               actionTitle: "Browse Discover") { router.tab = .discover }
            case .loaded(let list):
                ForEach(Array(list.prefix(3).enumerated()), id: \.element.id) { i, opp in
                    NavigationLink(value: OpportunityLink(id: opp.id)) { OpportunityRow(opportunity: opp, index: i + 1) }
                        .buttonStyle(.plain)
                    Hairline()
                }
                Text("Ranked by a match heuristic, not a prediction of selection.")
                    .font(.caption)
                    .foregroundStyle(NaviqColor.inkTertiary)
                    .padding(.top, 8)
            }
            if model.restrictedCount > 0, model.matches.value != nil {
                Button { router.tab = .discover } label: {
                    Text("\(model.restrictedCount) more open listing\(model.restrictedCount == 1 ? " is" : "s are") limited to a specific group or field of study (for example, girl students, existing awardees, or agriculture). Naviq doesn't assume who you are — see them in Discover.")
                        .font(.footnote)
                        .foregroundStyle(NaviqColor.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "Your roadmap") {
                InlineLink(title: "Open") { router.tab = .roadmap }
            }
            if let roadmap = model.roadmap, roadmap.progress.total > 0 {
                Text(roadmap.goal).font(NaviqFont.headline).foregroundStyle(NaviqColor.ink)
                ProgressView(value: Double(roadmap.progress.completed), total: Double(roadmap.progress.total))
                    .tint(NaviqColor.jade)
                    .accessibilityLabel("Roadmap progress")
                    .accessibilityValue("\(roadmap.progress.completed) of \(roadmap.progress.total) milestones completed")
                Text("\(roadmap.progress.completed) of \(roadmap.progress.total) milestones marked complete by you")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(NaviqColor.inkSecondary)
                if let next = roadmap.milestones.first(where: { $0.status == "in_progress" }) ?? roadmap.milestones.first(where: { $0.status == "not_started" }) {
                    HStack(alignment: .top) {
                        Text("Next").kickerStyle(NaviqColor.accent)
                        Text(next.title).font(.subheadline.weight(.semibold)).foregroundStyle(NaviqColor.ink)
                    }
                }
            } else {
                Text("Turn your goal into milestones you can track — with Saathi, or by adding your own.")
                    .foregroundStyle(NaviqColor.inkSecondary)
                Button("Start a roadmap") { router.tab = .roadmap }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var campusSection: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.m) {
            SectionHeader(kicker: "From your campus")
            switch model.announcements {
            case .idle, .loading: SkeletonRows(count: 1)
            case .failed(let m): NoticeBanner(text: m)
            case .loaded(let list) where list.isEmpty:
                Text(model.announcementsReason == "no_college"
                     ? "Add your college in Profile to see official notices from your campus."
                     : "No current notices from your campus administrators.")
                    .foregroundStyle(NaviqColor.inkSecondary)
            case .loaded(let list):
                ForEach(list.prefix(3)) { a in
                    AnnouncementRow(announcement: a)
                    Hairline()
                }
            }
        }
    }

    private var saathiEntry: some View {
        Button { router.askSaathi("What should I do next?") } label: {
            HStack(spacing: NaviqSpacing.m) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.title3)
                    .foregroundStyle(NaviqColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Saathi").font(.headline).foregroundStyle(NaviqColor.ink)
                    Text("“What should I do next?”").font(.subheadline).foregroundStyle(NaviqColor.inkSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(NaviqColor.inkTertiary)
            }
            .padding(NaviqSpacing.l)
            .background { RoundedRectangle(cornerRadius: 14).fill(NaviqColor.surface) }
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(NaviqColor.rule) }
        }
        .buttonStyle(.plain)
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

    private func symbol(for kind: String) -> String {
        switch kind {
        case "overdue_action": "exclamationmark.circle"
        case "deadline_soon": "timer"
        case "track_saved": "tray.and.arrow.down"
        case "explore_match": "sparkle.magnifyingglass"
        case "roadmap", "create_roadmap": "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath"
        default: "person.text.rectangle"
        }
    }
}

/// The lead "story" for the top next move.
private struct LeadMoveView: View {
    let move: NextMove

    var body: some View {
        VStack(alignment: .leading, spacing: NaviqSpacing.s) {
            Text(move.title)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(NaviqColor.ink)
                .multilineTextAlignment(.leading)
            Text(move.detail)
                .font(.body)
                .foregroundStyle(NaviqColor.inkSecondary)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text(move.reason)
            }
            .font(.footnote)
            .foregroundStyle(NaviqColor.inkTertiary)
            HStack {
                Text("Go").font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(NaviqColor.accent)
            .padding(.top, 4)
        }
        .padding(NaviqSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(NaviqColor.surface)
        }
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(NaviqColor.coral)
                .frame(width: 4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the related screen")
    }
}

struct AnnouncementRow: View {
    let announcement: Announcement
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(announcement.category.capitalized).kickerStyle(NaviqColor.coral)
                Text("· Official campus notice").kickerStyle()
            }
            Text(announcement.title).font(NaviqFont.cardTitle).foregroundStyle(NaviqColor.ink)
            Text(announcement.body)
                .font(.subheadline)
                .foregroundStyle(NaviqColor.inkSecondary)
                .lineLimit(expanded ? nil : 3)
            HStack(spacing: NaviqSpacing.m) {
                if let published = announcement.publishedAt {
                    Text("\(announcement.publisherName ?? "Campus admin") · \(published.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption)
                        .foregroundStyle(NaviqColor.inkTertiary)
                }
                Spacer()
                if let url = announcement.sourceUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) { Label("Source", systemImage: "arrow.up.right.square") }
                        .font(.caption.weight(.semibold))
                }
                Button(expanded ? "Less" : "More") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
    }
}
